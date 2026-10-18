# TaWorld development environment

Supported versions:

- Flutter 3.41.9
- Dart 3.11.5
- JDK 21
- Gradle 8.14
- Android Gradle Plugin (AGP) 8.11.1
- Kotlin 2.2.20

## One entry point

Use `tool/taworld.ps1` from any working directory. The script resolves the
repository from its own location, selects JDK 21, Flutter, and the repository
local Pub cache, and restores the caller's process environment when the child
command finishes. It does not change global or system settings.

Raw `java` and `gradlew` commands are unsafe on this machine because the
system `JAVA_HOME` points to Zulu Java 8. The wrapper invokes the Android
Studio JBR directly and rejects any configured JDK whose major version is not
21.

The wrapper places `PUB_CACHE` at `D:\TaWorld\.pub-cache` by default. Keeping
the Pub cache on the same `D:` drive as the Gradle build outputs keeps plugin
Kotlin sources on one filesystem root and avoids Kotlin incremental-cache
errors such as “different roots”. Set `TAWORLD_PUB_CACHE` only when an
equivalent same-drive cache is intentional.

## Default direct-network workflow

Direct networking is the default. The supported commands are:

```powershell
Set-Location D:\TaWorld
.\tool\taworld.ps1 clean
.\tool\taworld.ps1 pub get
.\tool\taworld.ps1 analyze
.\tool\taworld.ps1 test
.\tool\taworld.ps1 build apk --release
.\tool\taworld.ps1 -Gradle --version

# Only when direct access is unavailable and the local proxy is confirmed healthy
.\tool\taworld.ps1 -UseProxy -ProxyUri http://127.0.0.1:7897 pub get
```

The local proxy at `127.0.0.1:7897` is optional. It previously caused Java and
Gradle TLS handshake failures, so direct mode remains the default. When direct
access is unavailable, opt in with `-UseProxy`; the wrapper checks that the
specified host and port are reachable before starting Flutter or Gradle.

## Optional local overrides

The wrapper accepts process-scoped overrides without changing machine-wide
configuration:

```powershell
$env:TAWORLD_JDK_HOME = 'D:\AndroidStudio\jbr'
$env:TAWORLD_FLUTTER_HOME = 'C:\flutter'
$env:TAWORLD_PUB_CACHE = 'D:\TaWorld\.pub-cache'
```

These variables affect only the PowerShell process running the wrapper. Clear
them after an ad-hoc session if desired; do not write them to system settings.
