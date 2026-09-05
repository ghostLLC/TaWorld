import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:taworld/data/local/database_helper.dart';
import 'package:taworld/services/local/partner_service.dart';
import 'package:taworld/services/local/local_user_service.dart';
import 'package:taworld/services/data_backup_service.dart';
import 'package:taworld/services/backup/backup_archive_codec.dart';
import 'package:taworld/services/backup/backup_importer.dart';
import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'backup carries both avatars and restores portable paths; key stays local',
    () async {
      final root = await Directory.systemTemp.createTemp('taworld_asset_test_');
      addTearDown(() async {
        await closeTestDatabase();
        await root.delete(recursive: true);
      });
      final dbPath = '${root.path}/taworld.db';
      await openTestDatabase(path: dbPath);
      SharedPreferences.setMockInitialValues({
        'deepseek_api_key': 'local-only-test',
      });
      final avatar = File('${root.path}/avatar.png');
      await avatar.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1]);
      final other = File('${root.path}/other.png');
      await other.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 2]);
      await LocalUserService.createUser(nickname: '测试用户');
      await LocalUserService.updateAvatar(avatar.path);
      final person = await PartnerService.add(nickname: '测试妈妈', type: 'family');
      await PartnerService.update(person.id, avatarPath: other.path);
      final bytes = await DataBackupService.createBackupBytes();
      final archive = BackupArchiveCodec.decode(bytes);
      expect(archive.attachments, hasLength(2));
      expect(archive.assetPaths, hasLength(2));
      expect(archive.preferences.containsKey('deepseek_api_key'), isFalse);
      await avatar.delete();
      await other.delete();
      final prefs = await SharedPreferences.getInstance();
      await const BackupImporter().importBytes(
        bytes,
        BackupImportDependencies(
          databasePath: dbPath,
          temporaryRoot: root,
          preferences: prefs,
          databaseFactory: databaseFactoryFfi,
          closeDatabase: DatabaseHelper.close,
          reopenDatabase: () async {
            await DatabaseHelper.forceReopen();
            return DatabaseHelper.database;
          },
          attachmentsDirectory: Directory('${root.path}/restored'),
        ),
      );
      expect(
        await File(
          (await LocalUserService.getUser())!.avatarPath!,
        ).readAsBytes(),
        [137, 80, 78, 71, 13, 10, 26, 10, 1],
      );
      expect(
        await File(
          (await PartnerService.getById(person.id))!.avatarPath!,
        ).readAsBytes(),
        [137, 80, 78, 71, 13, 10, 26, 10, 2],
      );
      expect(prefs.getString('deepseek_api_key'), 'local-only-test');
    },
  );
  test(
    'maintenance rejects independent readers and releases after failure',
    () async {
      await openTestDatabase();
      addTearDown(closeTestDatabase);
      final entered = Completer<void>(), release = Completer<void>();
      final operation = DatabaseHelper.withMaintenance(() async {
        await DatabaseHelper.database;
        entered.complete();
        await release.future;
        throw StateError('injected');
      });
      final expectation = expectLater(operation, throwsStateError);
      await entered.future;
      await expectLater(DatabaseHelper.database, throwsStateError);
      release.complete();
      await expectation;
      expect((await DatabaseHelper.database).isOpen, isTrue);
    },
  );
}
