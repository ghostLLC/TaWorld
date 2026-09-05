import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/local/database_helper.dart';

abstract final class ToolOperationJournal {
  static const mutations = {
    'create_partner',
    'update_partner',
    'create_reminder',
    'update_reminder',
    'delete_reminder',
  };
  static Object? _canonical(Object? value) => value is Map
      ? {
          for (final key in value.keys.cast<String>().toList()..sort())
            key: _canonical(value[key]),
        }
      : value is List
      ? value.map(_canonical).toList()
      : value;

  static Future<String> execute({
    required String requestId,
    required String tool,
    required Map<String, dynamic> arguments,
    required Future<String> Function() action,
  }) async {
    if (!mutations.contains(tool)) return action();
    final id = sha256
        .convert(
          utf8.encode('$requestId|$tool|${jsonEncode(_canonical(arguments))}'),
        )
        .toString();
    final db = await DatabaseHelper.database;
    final existing = await db.query(
      'tool_operations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (existing.isNotEmpty) {
      final result = existing.single['result'];
      if (result is String) return result;
      return jsonEncode({
        'status': 'failure',
        'verified': false,
        'message': '上一次相同操作被中断，结果尚未确认。请先读取人物或提醒记录核对，不能直接重复创建。',
      });
    }
    await db.insert('tool_operations', {
      'id': id,
      'request_id': requestId,
      'tool': tool,
      'state': 'started',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    final result = await action();
    final decoded = jsonDecode(result);
    if (decoded is Map &&
        decoded['status'] == 'failure' &&
        decoded['verified'] == true) {
      await db.delete('tool_operations', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.update(
        'tool_operations',
        {'state': 'completed', 'result': result},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return result;
  }
}
