/// TaWorld 关心的人 — 本地服务
///
/// 管理用户关心的人（单机版替代关系模块）。
library;

import '../../data/local/database_helper.dart';
import '../../data/models/partner.dart';

abstract final class PartnerService {
  /// 获取所有活跃的关注人
  static Future<List<Partner>> getAll({bool includeDissolved = false}) async {
    final db = await DatabaseHelper.database;
    final where = includeDissolved ? null : "status = 'active'";
    final rows = await db.query('partners', where: where, orderBy: 'created_at DESC');
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
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final partner = Partner(
      id: DatabaseHelper.newId(),
      nickname: nickname,
      type: type,
      note: note,
      latitude: latitude,
      longitude: longitude,
      city: city,
      district: district,
      status: 'active',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('partners', partner.toMap());
    return partner;
  }

  /// 更新信息
  static Future<void> update(String id, {
    String? nickname,
    String? avatarPath,
    String? type,
    String? note,
    double? latitude,
    double? longitude,
    String? city,
    String? district,
  }) async {
    final db = await DatabaseHelper.database;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (nickname != null) data['nickname'] = nickname;
    if (avatarPath != null) data['avatar_path'] = avatarPath;
    if (type != null) data['type'] = type;
    if (note != null) data['note'] = note;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (city != null) data['city'] = city;
    if (district != null) data['district'] = district;
    await db.update('partners', data, where: 'id = ?', whereArgs: [id]);
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
  }

  /// 获取关系天数
  static int daysSince(DateTime createdAt) {
    return DateTime.now().difference(createdAt).inDays;
  }
}
