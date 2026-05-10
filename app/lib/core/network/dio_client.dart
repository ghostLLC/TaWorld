/// TaWorld 网络层 — Dio 客户端配置
///
/// 统一的 HTTP 客户端，内置 Token 拦截器和错误处理。
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../services/auth_service.dart';

/// API 基础地址（开发环境）
const String _baseUrl = 'http://10.0.2.2:8000'; // Android 模拟器访问宿主机

/// 创建全局 Dio 实例
Dio createDioClient() {
  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  // Token 拦截器
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await AuthService.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    },
    onError: (error, handler) async {
      if (error.response?.statusCode == 401) {
        // 尝试刷新 Token
        final refreshed = await AuthService.refreshToken(dio);
        if (refreshed) {
          // 重试原始请求
          final retryOptions = error.requestOptions;
          final token = await AuthService.getAccessToken();
          retryOptions.headers['Authorization'] = 'Bearer $token';
          try {
            final response = await dio.fetch(retryOptions);
            handler.resolve(response);
            return;
          } catch (_) {}
        }
        // 刷新失败 → 登出
        await AuthService.clearTokens();
      }
      handler.next(error);
    },
  ));

  // 日志拦截器（仅 Debug 模式）
  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => debugPrint(obj.toString()),
    ));
  }

  return dio;
}
