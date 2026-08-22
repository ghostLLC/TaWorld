/// Transactional, testable backup import orchestration.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/database_helper.dart';
import 'backup_archive_codec.dart';

abstract final class BackupImportStages {
  static const validated = 'validated';
  static const databaseReplaced = 'databaseReplaced';
  static const databaseReopened = 'databaseReopened';
  static const attachmentsRestored = 'attachmentsRestored';
  static const preferenceApplied = 'preferenceApplied';
  static const preferencesApplied = 'preferencesApplied';
}

class BackupImportDependencies {
  final String databasePath;
  final Directory temporaryRoot;
  final SharedPreferences preferences;
  final DatabaseFactory databaseFactory;
  final Future<void> Function() closeDatabase;
  final Future<Database> Function() reopenDatabase;
  final Directory? attachmentsDirectory;
  final Future<void> Function(String stage)? afterStage;

  const BackupImportDependencies({
    required this.databasePath,
    required this.temporaryRoot,
    required this.preferences,
    required this.databaseFactory,
    required this.closeDatabase,
    required this.reopenDatabase,
    this.attachmentsDirectory,
    this.afterStage,
  });
}

class BackupImportException implements Exception {
  final String message;
  final Object cause;
  final StackTrace causeStackTrace;
  final Object? rollbackCause;
  final StackTrace? rollbackStackTrace;

  const BackupImportException({
    required this.message,
    required this.cause,
    required this.causeStackTrace,
    this.rollbackCause,
    this.rollbackStackTrace,
  });

  bool get rollbackSucceeded => rollbackCause == null;

  @override
  String toString() => message;
}

class _PreferenceSnapshot {
  final bool existed;
  final Object? value;

  const _PreferenceSnapshot(this.existed, this.value);
}

class BackupImporter {
  const BackupImporter();

  static const restorePreferenceKeys = <String>{
    'theme_mode',
    'palette_id',
    'push_enabled',
    'ai_proactive_enabled',
    'last_dream_time',
    'last_proactive_time',
  };
  static const _cacheKeys = <String>{'cache_hit_tokens', 'cache_miss_tokens'};
  static const _apiKey = 'deepseek_api_key';

  Future<void> importBytes(
    Uint8List zipBytes,
    BackupImportDependencies dependencies,
  ) async {
    // Archive parsing and size/CRC validation happen before any filesystem or
    // database lifecycle mutation.
    final validated = BackupArchiveCodec.decode(zipBytes);

    Directory? stagingDirectory;
    File? incomingFile;
    var databaseClosed = false;
    var mutationStarted = false;
    var originalDatabaseExisted = false;
    Map<String, _PreferenceSnapshot>? preferenceSnapshot;
    Object? apiKeyBefore;
    final createdAttachmentFiles = <File>[];
    var importSucceeded = false;

    try {
      await dependencies.temporaryRoot.create(recursive: true);
      stagingDirectory = await dependencies.temporaryRoot.createTemp(
        'taworld_import_',
      );
      final stagedFile = File(
        '${stagingDirectory.path}${Platform.pathSeparator}database.staged',
      );
      await stagedFile.writeAsBytes(validated.databaseBytes, flush: true);
      await _validateStagedDatabase(
        stagedFile.path,
        dependencies.databaseFactory,
      );

      preferenceSnapshot = _snapshotPreferences(dependencies.preferences);
      apiKeyBefore = dependencies.preferences.get(_apiKey);
      await dependencies.afterStage?.call(BackupImportStages.validated);

      await dependencies.closeDatabase();
      databaseClosed = true;

      final liveFile = File(dependencies.databasePath);
      final backupFile = File('${dependencies.databasePath}.pre_import_backup');
      incomingFile = File('${dependencies.databasePath}.incoming');
      originalDatabaseExisted = await liveFile.exists();
      if (originalDatabaseExisted) {
        await liveFile.copy(backupFile.path);
      } else if (await backupFile.exists()) {
        await backupFile.delete();
      }

      await liveFile.parent.create(recursive: true);
      await stagedFile.copy(incomingFile.path);
      mutationStarted = true;
      await _removeSidecars(dependencies.databasePath);
      if (await liveFile.exists()) await liveFile.delete();
      await incomingFile.rename(liveFile.path);
      incomingFile = File('${dependencies.databasePath}.incoming');
      await dependencies.afterStage?.call(BackupImportStages.databaseReplaced);

      final reopened = await dependencies.reopenDatabase();
      await _validateReopenedDatabase(reopened);
      await dependencies.afterStage?.call(BackupImportStages.databaseReopened);

      await _restoreAttachments(
        validated.attachments,
        reopened,
        dependencies.attachmentsDirectory,
        createdAttachmentFiles,
      );
      await dependencies.afterStage?.call(
        BackupImportStages.attachmentsRestored,
      );

      await _applyPreferences(
        validated.preferences,
        dependencies.preferences,
        dependencies.afterStage,
      );
      final apiKeyAfter = dependencies.preferences.get(_apiKey);
      if (!_preferenceValuesEqual(apiKeyBefore, apiKeyAfter)) {
        throw StateError('API key changed during backup import');
      }
      await dependencies.afterStage?.call(
        BackupImportStages.preferencesApplied,
      );
      importSucceeded = true;
    } catch (error, stackTrace) {
      if (!databaseClosed) rethrow;
      final rollback = mutationStarted
          ? await _rollback(
              dependencies,
              originalDatabaseExisted: originalDatabaseExisted,
              preferenceSnapshot: preferenceSnapshot!,
              apiKeyBefore: apiKeyBefore,
            )
          : await _reopenWithoutRestore(dependencies);
      throw BackupImportException(
        message: rollback.error == null ? '导入失败，原数据已恢复' : '导入及自动恢复均失败',
        cause: error,
        causeStackTrace: stackTrace,
        rollbackCause: rollback.error,
        rollbackStackTrace: rollback.stackTrace,
      );
    } finally {
      if (!importSucceeded) {
        await _bestEffortDeleteFiles(createdAttachmentFiles);
      }
      await _bestEffortDeleteFile(incomingFile);
      await _bestEffortDeleteDirectory(stagingDirectory);
    }
  }

  static Future<void> _restoreAttachments(
    Map<String, Uint8List> attachments,
    Database database,
    Directory? targetDirectory,
    List<File> createdFiles,
  ) async {
    if (attachments.isEmpty) return;
    if (targetDirectory == null) {
      throw StateError('Attachment restore directory is unavailable');
    }
    await targetDirectory.create(recursive: true);
    final restoredPaths = <String, String>{};
    var collisionSequence = 0;

    for (final entry in attachments.entries) {
      var target = File(
        '${targetDirectory.path}${Platform.pathSeparator}${entry.key}',
      );
      if (await target.exists()) {
        final existing = await target.readAsBytes();
        if (_bytesEqual(existing, entry.value)) {
          restoredPaths[entry.key] = target.path;
          continue;
        }
        collisionSequence++;
        target = File(
          '${targetDirectory.path}${Platform.pathSeparator}'
          'import_${DateTime.now().microsecondsSinceEpoch}_$collisionSequence'
          '_${entry.key}',
        );
      }

      final incoming = File('${target.path}.incoming');
      await incoming.writeAsBytes(entry.value, flush: true);
      await incoming.rename(target.path);
      createdFiles.add(target);
      restoredPaths[entry.key] = target.path;
    }

    final rows = await database.query(
      'chat_attachments',
      columns: const ['id', 'local_path'],
    );
    await database.transaction((txn) async {
      for (final row in rows) {
        final path = row['local_path'] as String?;
        if (path == null || path.isEmpty) continue;
        final fileName = path.split(RegExp(r'[\\/]')).last;
        final restored = restoredPaths[fileName];
        if (restored == null) continue;
        await txn.update(
          'chat_attachments',
          {'local_path': restored, 'status': 'local'},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  static bool _bytesEqual(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static Future<void> _validateStagedDatabase(
    String path,
    DatabaseFactory factory,
  ) async {
    Database? database;
    try {
      database = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      await _requireHealthyDatabase(database, requireCurrentVersion: false);
    } finally {
      await database?.close();
    }
  }

  static Future<void> _validateReopenedDatabase(Database database) async {
    await _requireHealthyDatabase(database, requireCurrentVersion: true);
  }

  static Future<void> _requireHealthyDatabase(
    Database database, {
    required bool requireCurrentVersion,
  }) async {
    final checkRows = await database.rawQuery('PRAGMA quick_check');
    final check = checkRows.length == 1 && checkRows.single.values.length == 1
        ? checkRows.single.values.single
        : null;
    if (check != 'ok') throw StateError('SQLite quick_check failed');

    final versionRows = await database.rawQuery('PRAGMA user_version');
    final version = versionRows.single.values.single;
    if (version is! int ||
        version < 1 ||
        version > DatabaseHelper.schemaVersion) {
      throw StateError('Unsupported SQLite schema version');
    }
    if (requireCurrentVersion && version != DatabaseHelper.schemaVersion) {
      throw StateError('SQLite migration did not reach the current schema');
    }
  }

  static Map<String, _PreferenceSnapshot> _snapshotPreferences(
    SharedPreferences preferences,
  ) {
    final snapshot = <String, _PreferenceSnapshot>{};
    for (final key in {...restorePreferenceKeys, ..._cacheKeys}) {
      snapshot[key] = _PreferenceSnapshot(
        preferences.containsKey(key),
        preferences.get(key),
      );
    }
    return snapshot;
  }

  static Future<void> _applyPreferences(
    Map<String, Object?> imported,
    SharedPreferences preferences,
    Future<void> Function(String stage)? afterStage,
  ) async {
    for (final key in restorePreferenceKeys) {
      if (!imported.containsKey(key)) continue;
      await _setPreference(preferences, key, imported[key]);
      await afterStage?.call('${BackupImportStages.preferenceApplied}:$key');
    }
    for (final key in _cacheKeys) {
      await _requirePreferenceWrite(await preferences.setInt(key, 0), key);
      await afterStage?.call('${BackupImportStages.preferenceApplied}:$key');
    }
  }

  static Future<void> _restorePreferences(
    SharedPreferences preferences,
    Map<String, _PreferenceSnapshot> snapshot,
    Object? apiKeyBefore,
  ) async {
    for (final entry in snapshot.entries) {
      if (!entry.value.existed) {
        await _requirePreferenceWrite(
          await preferences.remove(entry.key),
          entry.key,
        );
      } else {
        await _setPreference(preferences, entry.key, entry.value.value);
      }
    }
    if (apiKeyBefore == null) {
      await _requirePreferenceWrite(await preferences.remove(_apiKey), _apiKey);
    } else {
      await _setPreference(preferences, _apiKey, apiKeyBefore);
    }
  }

  static Future<void> _setPreference(
    SharedPreferences preferences,
    String key,
    Object? value,
  ) async {
    final bool written;
    if (value is String) {
      written = await preferences.setString(key, value);
    } else if (value is bool) {
      written = await preferences.setBool(key, value);
    } else if (value is int) {
      written = await preferences.setInt(key, value);
    } else if (value is double) {
      written = await preferences.setDouble(key, value);
    } else if (value is List<String>) {
      written = await preferences.setStringList(key, value);
    } else {
      throw StateError('Unsupported preference type for $key');
    }
    await _requirePreferenceWrite(written, key);
  }

  static Future<void> _requirePreferenceWrite(bool written, String key) async {
    if (!written) throw StateError('Preference write failed for $key');
  }

  static Future<({Object? error, StackTrace? stackTrace})> _rollback(
    BackupImportDependencies dependencies, {
    required bool originalDatabaseExisted,
    required Map<String, _PreferenceSnapshot> preferenceSnapshot,
    required Object? apiKeyBefore,
  }) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await attempt(dependencies.closeDatabase);
    await attempt(() => _removeSidecars(dependencies.databasePath));
    await attempt(() async {
      final liveFile = File(dependencies.databasePath);
      final backupFile = File('${dependencies.databasePath}.pre_import_backup');
      if (await liveFile.exists()) await liveFile.delete();
      if (originalDatabaseExisted) {
        if (!await backupFile.exists()) {
          throw StateError('Pre-import database backup is missing');
        }
        await backupFile.copy(liveFile.path);
      }
    });
    await attempt(
      () => _restorePreferences(
        dependencies.preferences,
        preferenceSnapshot,
        apiKeyBefore,
      ),
    );
    await attempt(() async {
      final database = await dependencies.reopenDatabase();
      await _validateReopenedDatabase(database);
    });
    return (error: firstError, stackTrace: firstStackTrace);
  }

  static Future<({Object? error, StackTrace? stackTrace})>
  _reopenWithoutRestore(BackupImportDependencies dependencies) async {
    try {
      await dependencies.reopenDatabase();
      return (error: null, stackTrace: null);
    } catch (error, stackTrace) {
      return (error: error, stackTrace: stackTrace);
    }
  }

  static Future<void> _removeSidecars(String databasePath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final file = File('$databasePath$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  static bool _preferenceValuesEqual(Object? first, Object? second) {
    if (first is List<String> && second is List<String>) {
      if (first.length != second.length) return false;
      for (var index = 0; index < first.length; index++) {
        if (first[index] != second[index]) return false;
      }
      return true;
    }
    return first == second;
  }

  static Future<void> _bestEffortDeleteFile(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Future<void> _bestEffortDeleteDirectory(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> _bestEffortDeleteFiles(Iterable<File> files) async {
    for (final file in files) {
      await _bestEffortDeleteFile(file);
    }
  }
}
