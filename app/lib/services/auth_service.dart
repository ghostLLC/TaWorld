/// TaWorld 认证服务
///
/// 管理 JWT Token 的存储、刷新、清除。
library;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/api_endpoints.dart';

/// 认证服务（Token 管理）
abstract final class AuthService {
  static const _accessTokenKey = 'ta_access_token';
  static const _refreshTokenKey = 'ta_refresh_token';

  /// 保存 Token
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
  }

  /// 获取 Access Token
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// 获取 Refresh Token
  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// 清除所有 Token（登出）
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  /// 是否已登录
  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// 尝试刷新 Token
  ///
  /// 返回 true 表示刷新成功并已更新存储。
  static Future<bool> refreshToken(Dio dio) async {
    try {
      final rt = await getRefreshToken();
      if (rt == null) return false;

      final response = await dio.post(
        ApiEndpoints.refresh,
        data: {'refresh_token': rt},
      );

      if (response.statusCode == 200) {
        final data = response.data['data'];
        await saveTokens(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
        );
        return true;
      }
    } catch (_) {
      // 刷新失败
    }
    return false;
  }
}
