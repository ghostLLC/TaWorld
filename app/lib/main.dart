import 'dart:async';
import 'package:flutter/material.dart';
import 'app/app.dart';
import 'services/app_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaWorldApp());
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(AppRuntime.start()),
  );
}
