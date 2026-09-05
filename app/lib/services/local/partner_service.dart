/// TaWorld 关心的人 — 本地服务
///
/// 管理用户关心的人（单机版替代关系模块）。
library;

import 'package:flutter/foundation.dart';

import '../../data/local/database_helper.dart';
import '../../data/models/partner.dart';
import '../person_location_service.dart';

abstract final class PartnerService {
  /// 关心的人列表变更通知器（跨 Tab 刷新用）
  static final refreshCounter = ValueNotifier<int>(0);

  /// 通知所有监听方刷新关心的人列表
  static void notifyRefresh() {
    refreshCounter.value++;
  }

  /// 获取所有活跃的关注人
  static Future<List<Partner>> getAll({bool includeDissolved = false}) async {
    final db = await DatabaseHelper.database;
    final where = includeDissolved ? null : "status = 'active'";
    final rows = await db.query(
      'partners',
      where: where,
      orderBy: 'created_at DESC',
    );
    return rows.map(Partner.fromMap).toList();
  }

  /// 获取单个
  static Future<Partner?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('partners', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Partner.fromMap(rows.first);
  }

  /// 添加关心的人
  static Future<Partner> add({
    required String nickname,
    required String type,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? district,
    String? country,
    String? timezoneId,
    String? timezoneSource,
    bool timezoneConfirmed = false,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final location = PersonLocationService.resolve(city, country: country);
    final partner = Partner(
      id: DatabaseHelper.newId(),
      nickname: nickname,
      type: type,
      note: note,
      latitude: location != null ? location.latitude : latitude,
      longitude: location != null ? location.longitude : longitude,
      city: location?.city ?? city,
      district: district ?? location?.province,
      country: country ?? location?.country,
      timezoneId: timezoneId ?? location?.timezoneId,
      timezoneSource:
          timezoneSource ?? (location == null ? null : 'city_selection'),
      timezoneConfirmed: timezoneId != null
          ? timezoneConfirmed
          : location != null,
      status: 'active',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('partners', partner.toMap());
    notifyRefresh();
    return partner;
  }

  /// 更新信息
  static Future<void> update(
    String id, {
    String? nickname,
    String? avatarPath,
    String? type,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? district,
    String? country,
    String? timezoneId,
    String? timezoneSource,
    bool? timezoneConfirmed,
    bool clearTimezone = false,
    bool clearNote = false,
    bool clearAvatar = false,
    bool clearLocation = false,
    DateTime? expectedUpdatedAt,
  }) async {
    if (clearTimezone && timezoneId != null) {
      throw ArgumentError(
        'timezoneId cannot be supplied when clearTimezone is true',
      );
    }

    final db = await DatabaseHelper.database;
    Map<String, Object?>? current;
    if (city != null || timezoneId != null || clearTimezone) {
      final rows = await db.query(
        'partners',
        columns: const ['city', 'timezone_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) current = rows.first;
    }

    final currentCity = current?['city'] as String?;
    final cityChanged = city != null && !_sameLabel(city, currentCity);
    final currentTimezoneId = current?['timezone_id'] as String?;
    final timezoneChanged =
        timezoneId != null && timezoneId != currentTimezoneId;
    final location = cityChanged && !clearLocation
        ? PersonLocationService.resolve(city, country: country)
        : null;
    final resolvedTimezone = timezoneId ?? location?.timezoneId;
    final shouldInvalidateTimezone =
        clearLocation ||
        clearTimezone ||
        (cityChanged && resolvedTimezone == null);

    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (nickname != null) data['nickname'] = nickname;
    if (avatarPath != null) data['avatar_path'] = avatarPath;
    if (type != null) data['type'] = type;
    if (clearNote || note != null) {
      data['note'] = clearNote || note!.isEmpty ? null : note;
    }
    if (clearAvatar) data['avatar_path'] = null;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (city != null) data['city'] = city;
    if (district != null) data['district'] = district;
    if (country != null) data['country'] = country;
    if (cityChanged) {
      data['latitude'] = location?.latitude ?? latitude;
      data['longitude'] = location?.longitude ?? longitude;
      data['district'] = district ?? location?.province;
      data['country'] = country ?? location?.country;
    }
    if (clearLocation) {
      for (final key in [
        'city',
        'country',
        'district',
        'latitude',
        'longitude',
      ]) {
        data[key] = null;
      }
    }
    if (shouldInvalidateTimezone) {
      data['timezone_id'] = null;
      data['timezone_source'] = null;
      data['timezone_confirmed'] = 0;
    } else if (resolvedTimezone != null) {
      data['timezone_id'] = resolvedTimezone;
      if (location != null && timezoneId == null) {
        data['timezone_source'] = 'city_selection';
        data['timezone_confirmed'] = 1;
      }
      if (timezoneSource != null) {
        data['timezone_source'] = timezoneSource;
      } else if (timezoneChanged) {
        data['timezone_source'] = null;
      }
      if (timezoneConfirmed != null) {
        data['timezone_confirmed'] = timezoneConfirmed ? 1 : 0;
      } else if (timezoneChanged) {
        data['timezone_confirmed'] = 0;
      }
    } else {
      if (timezoneSource != null) data['timezone_source'] = timezoneSource;
      if (timezoneConfirmed != null) {
        data['timezone_confirmed'] = timezoneConfirmed ? 1 : 0;
      }
    }
    final changed = await db.update(
      'partners',
      data,
      where: expectedUpdatedAt == null ? 'id = ?' : 'id = ? AND updated_at = ?',
      whereArgs: [
        id,
        if (expectedUpdatedAt != null) expectedUpdatedAt.toIso8601String(),
      ],
    );
    if (changed != 1) throw StateError('资料已改变，请重新加载后再保存');
    notifyRefresh();
  }

  static bool _sameLabel(String left, String? right) {
    return left.trim().toLowerCase() == (right ?? '').trim().toLowerCase();
  }

  /// Hard-deletes a provisional row when the operation that created it fails
  /// post-write verification. Normal user removal remains a soft delete via
  /// [dissolve], so this compensation API must only receive a newly-created ID.
  static Future<void> deleteCreated(String id) async {
    final db = await DatabaseHelper.database;
    final deleted = await db.delete(
      'partners',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted != 1) {
      throw StateError('Provisional partner row could not be rolled back');
    }
    notifyRefresh();
  }

  /// Restores a pre-write snapshot after an update fails post-write
  /// verification. This is intentionally separate from [update], whose null
  /// parameters mean "leave unchanged" and therefore cannot restore nullable
  /// fields exactly.
  static Future<void> restoreSnapshot(Partner snapshot) async {
    final db = await DatabaseHelper.database;
    final restored = await db.update(
      'partners',
      snapshot.toMap(),
      where: 'id = ?',
      whereArgs: [snapshot.id],
    );
    if (restored != 1) {
      throw StateError('Partner snapshot could not be restored');
    }
    notifyRefresh();
  }

  /// 解除关系（软删除）
  static Future<void> dissolve(String id) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'partners',
      {'status': 'dissolved', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyRefresh();
  }

  /// 获取关系天数
  static Future<void> restore(String id) async {
    final db = await DatabaseHelper.database;
    final changed = await db.update(
      'partners',
      {'status': 'active', 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND status != ?',
      whereArgs: [id, 'active'],
    );
    if (changed != 1) throw StateError('人物状态已改变，请刷新后重试');
    notifyRefresh();
  }

  /// 获取添加到 App 的天数，不代表相识时长。
  static int daysSince(DateTime createdAt) {
    return DateTime.now().difference(createdAt).inDays;
  }
}
