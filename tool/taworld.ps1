[CmdletBinding()]
param(
    [switch]$Gradle,
    [switch]$UseProxy,
    [string]$ProxyUri = 'http://127.0.0.1:7897',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ToolArgs
)

# PowerShell assigns otherwise-unqualified string parameters positional
# binding precedence. Preserve the public parameter list above while making
# ordinary calls such as `taworld.ps1 pub get` reach the child tool: a ProxyUri
# is considered supplied only when its parameter name appears in the call.
$proxyUriWasNamed = $MyInvocation.Line -match '(?i)(?:^|\s)-ProxyUri(?:\s|=|:)'
if (-not $proxyUriWasNamed -and $PSBoundParameters.ContainsKey('ProxyUri')) {
    $ToolArgs = @($ProxyUri) + @($ToolArgs)
    $ProxyUri = 'http://127.0.0.1:7897'
}

$ErrorActionPreference = 'Stop'

function Get-ConfiguredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfiguredPath,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    if ([System.IO.Path]::IsPathRooted($ConfiguredPath)) {
        return [System.IO.Path]::GetFullPath($ConfiguredPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $RepositoryRoot -ChildPath $ConfiguredPath))
}

function Get-ProcessEnvironmentState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $processEnvironment = [System.Environment]::GetEnvironmentVariables('Process')
    $present = $processEnvironment.ContainsKey($Name)
    $value = if ($present) { [string]$processEnvironment[$Name] } else { $null }

    return [pscustomobject]@{
        Present = $present
        Value = $value
    }
}

function Restore-ProcessEnvironmentState {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Snapshot
    )

    foreach ($name in $Snapshot.Keys) {
        $state = $Snapshot[$name]
        if ($state.Present) {
            [System.Environment]::SetEnvironmentVariable($name, $state.Value, 'Process')
        } else {
            [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
    }
}

function Get-ProxyEndpoint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UriText
    )

    $proxyUriValue = $null
    if (-not [System.Uri]::TryCreate($UriText, [System.UriKind]::Absolute, [ref]$proxyUriValue)) {
        throw "ProxyUri must be an absolute URI with an explicit host and port: $UriText"
    }

    if ([string]::IsNullOrWhiteSpace($proxyUriValue.Host)) {
        throw "ProxyUri must include an explicit host: $UriText"
    }

    # Uri.IsDefaultPort cannot distinguish an omitted default port from an
    # explicitly written one, so inspect the authority text as well.
    $authority = $proxyUriValue.Authority
    $hasExplicitPort = $authority -match ':(?<port>\d+)$'
    if (-not $hasExplicitPort) {
        throw "ProxyUri must include an explicit port: $UriText"
    }

    $proxyPort = 0
    if (-not [int]::TryParse($Matches['port'], [ref]$proxyPort) -or $proxyPort -lt 1 -or $proxyPort -gt 65535) {
        throw "ProxyUri contains an invalid port: $UriText"
    }

    return [pscustomobject]@{
        Uri = $UriText
        Host = $proxyUriValue.Host
        Port = $proxyPort
    }
}

$repositoryRoot = $null
$locationPushed = $false
$childExitCode = 1
$environmentNames = @(
    'JAVA_HOME',
    'Path',
    'PUB_CACHE',
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'ALL_PROXY',
    'GRADLE_OPTS'
)
$environmentSnapshot = @{}
foreach ($environmentName in $environmentNames) {
    $environmentSnapshot[$environmentName] = Get-ProcessEnvironmentState -Name $environmentName
}

try {
    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
    if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
        throw "Repository root does not exist: $repositoryRoot"
    }

    $jdkHomeSetting = if ([string]::IsNullOrWhiteSpace($env:TAWORLD_JDK_HOME)) {
        'D:\AndroidStudio\jbr'
    } else {
        $env:TAWORLD_JDK_HOME
    }
    $flutterHomeSetting = if ([string]::IsNullOrWhiteSpace($env:TAWORLD_FLUTTER_HOME)) {
        'C:\flutter'
    } else {
        $env:TAWORLD_FLUTTER_HOME
    }
    $pubCacheSetting = if ([string]::IsNullOrWhiteSpace($env:TAWORLD_PUB_CACHE)) {
        Join-Path -Path $repositoryRoot -ChildPath '.pub-cache'
    } else {
        $env:TAWORLD_PUB_CACHE
    }

    $jdkHome = Get-ConfiguredPath -ConfiguredPath $jdkHomeSetting -RepositoryRoot $repositoryRoot
    $flutterHome = Get-ConfiguredPath -ConfiguredPath $flutterHomeSetting -RepositoryRoot $repositoryRoot
    $pubCache = Get-ConfiguredPath -ConfiguredPath $pubCacheSetting -RepositoryRoot $repositoryRoot

    $javaExe = Join-Path -Path $jdkHome -ChildPath 'bin\java.exe'
    $flutterBat = Join-Path -Path $flutterHome -ChildPath 'bin\flutter.bat'
    $pubspecPath = Join-Path -Path $repositoryRoot -ChildPath 'app\pubspec.yaml'
    $gradleBat = Join-Path -Path $repositoryRoot -ChildPath 'app\android\gradlew.bat'

    # Validate every required executable/file before changing directory or
    # changing the process environment used by the child command.
    foreach ($requiredPath in @(
        [pscustomobject]@{ Path = $javaExe; Kind = 'Leaf' },
        [pscustomobject]@{ Path = $flutterBat; Kind = 'Leaf' },
        [pscustomobject]@{ Path = $pubspecPath; Kind = 'Leaf' },
        [pscustomobject]@{ Path = $gradleBat; Kind = 'Leaf' }
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath.Path -PathType $requiredPath.Kind)) {
            throw "Required TaWorld tool path does not exist: $($requiredPath.Path)"
        }
    }

    # Windows PowerShell 5 represents native stderr as an ErrorRecord. Keep
    # java -version's expected stderr output in the captured version text
    # without allowing it to trip the wrapper's terminating-error policy.
    $javaVersionErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $javaVersionOutput = @(& $javaExe -version 2>&1)
        $javaVersionExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $javaVersionErrorActionPreference
    }
    if ($javaVersionExitCode -ne 0) {
        throw "Unable to execute the configured JDK at $javaExe. java -version exited with code $javaVersionExitCode."
    }

    $javaVersionText = $javaVersionOutput -join [Environment]::NewLine
    $javaVersionMatch = [System.Text.RegularExpressions.Regex]::Match(
        $javaVersionText,
        'version\s+"(?<major>\d+)'
    )
    if (-not $javaVersionMatch.Success) {
        throw "Could not determine the configured JDK major version from java -version output. Expected JDK 21 at $javaExe."
    }

    $javaMajorVersion = [int]$javaVersionMatch.Groups['major'].Value
    if ($javaMajorVersion -ne 21) {
        throw "TaWorld requires JDK 21, but java -version reported major version $javaMajorVersion at $javaExe."
    }

    $proxyEndpoint = $null
    if ($UseProxy) {
        $proxyEndpoint = Get-ProxyEndpoint -UriText $ProxyUri
        $proxyPortOpen = $false
        try {
            $proxyTestParameters = @{
                ComputerName = $proxyEndpoint.Host
                Port = $proxyEndpoint.Port
                InformationLevel = 'Quiet'
                WarningAction = 'SilentlyContinue'
            }
            $proxyPortOpen = [bool](Test-NetConnection @proxyTestParameters)
        } catch {
            throw "Could not verify proxy $($proxyEndpoint.Host):$($proxyEndpoint.Port): $($_.Exception.Message)"
        }

        if (-not $proxyPortOpen) {
            throw "Proxy port is closed: $($proxyEndpoint.Host):$($proxyEndpoint.Port). Aborting before the child command."
        }
    }

    $env:JAVA_HOME = $jdkHome
    $jdkBin = Join-Path -Path $jdkHome -ChildPath 'bin'
    $env:Path = "$jdkBin$([System.IO.Path]::PathSeparator)$($environmentSnapshot['Path'].Value)"
    $env:PUB_CACHE = $pubCache

    if ($UseProxy) {
        $env:HTTP_PROXY = $proxyEndpoint.Uri
        $env:HTTPS_PROXY = $proxyEndpoint.Uri
        $env:ALL_PROXY = $proxyEndpoint.Uri
        $env:GRADLE_OPTS = @(
            '-Djava.net.useSystemProxies=false',
            "-Dhttp.proxyHost=$($proxyEndpoint.Host)",
            "-Dhttp.proxyPort=$($proxyEndpoint.Port)",
            "-Dhttps.proxyHost=$($proxyEndpoint.Host)",
            "-Dhttps.proxyPort=$($proxyEndpoint.Port)"
        ) -join ' '
    } else {
        $env:HTTP_PROXY = $null
        $env:HTTPS_PROXY = $null
        $env:ALL_PROXY = $null
        $env:GRADLE_OPTS = '-Djava.net.useSystemProxies=false'
    }

    if (-not (Test-Path -LiteralPath $pubCache -PathType Container)) {
        New-Item -ItemType Directory -Path $pubCache -Force | Out-Null
    }

    if ($Gradle) {
        Push-Location -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath 'app\android')
        $locationPushed = $true
        & $gradleBat @ToolArgs
    } else {
        Push-Location -LiteralPath (Join-Path -Path $repositoryRoot -ChildPath 'app')
        $locationPushed = $true
        & $flutterBat @ToolArgs
    }

    $childExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
} catch {
    Write-Error $_
    $childExitCode = 1
} finally {
    if ($locationPushed) {
        try {
            Pop-Location -ErrorAction Stop
        } catch {
            Write-Warning "Unable to restore the caller's location: $($_.Exception.Message)"
        }
    }

    try {
        Restore-ProcessEnvironmentState -Snapshot $environmentSnapshot
    } catch {
        Write-Warning "Unable to restore one or more process environment variables: $($_.Exception.Message)"
    }
}

exit $childExitCode
