import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taworld/services/data_reset_service.dart';
import 'package:taworld/services/local/local_user_service.dart';
import 'package:taworld/services/local/partner_service.dart';

import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('taworld_reset_test_');
    for (final name in ['avatars', 'chat_images']) {
      final directory = Directory('${root.path}/$name');
      await directory.create(recursive: true);
      await File('${directory.path}/sample.txt').writeAsString('private');
    }
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'deepseek_api_key': 'legacy-key',
      'custom_preference': 'private',
    });
    await openTestDatabase();
    await LocalUserService.createUser(nickname: '测试用户');
    await PartnerService.add(nickname: '小乐', type: 'family');
  });

  tearDown(() async {
    await closeTestDatabase();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reset removes identity, preferences and managed attachments', () async {
    var cancelBackground = 0;
    var registerBackground = 0;
    var cancelNotifications = 0;
    var clearKeys = 0;
    final dependencies = DataResetDependencies(
      documentsDirectory: root,
      cancelBackgroundTasks: () async => cancelBackground++,
      registerBackgroundTasks: () async => registerBackground++,
      cancelNotifications: () async => cancelNotifications++,
      clearApiKey: () async => clearKeys++,
    );

    await DataResetService.reset(dependencies: dependencies);

    expect(await LocalUserService.hasUser(), isFalse);
    expect(await PartnerService.getAll(), isEmpty);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('custom_preference'), isNull);
    expect(preferences.getString('deepseek_api_key'), isNull);
    expect(await Directory('${root.path}/avatars').exists(), isFalse);
    expect(await Directory('${root.path}/chat_images').exists(), isFalse);
    expect(cancelBackground, 1);
    expect(registerBackground, 1);
    expect(cancelNotifications, 1);
    expect(clearKeys, 1);
  });
}
