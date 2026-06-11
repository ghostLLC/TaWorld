import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/notification_service.dart';
import 'services/local/local_user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  // 单机版：打开应用即自动创建默认用户，无需登录
  if (!await LocalUserService.hasUser()) {
    await LocalUserService.createUser(nickname: '我');
  }
  runApp(TaWorldApp());
}
