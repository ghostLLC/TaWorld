import 'dart:convert';

import '../data/local/database_helper.dart';

class ChatHistoryWriteResult {
  const ChatHistoryWriteResult({required this.id, required this.inserted});

  final String id;
  final bool inserted;
}

/// Typed access to the local conversation timeline.
///
/// Hiding a record only changes its presentation state. The row remains in the
/// database so AI context, memory extraction and backup keep their full audit
/// trail.
abstract final class ChatHistoryService {
  static Future<ChatHistoryWriteResult> append({
    required String role,
    required String content,
    String messageType = 'message',
    Map<String, Object?> metadata = const {},
    String? requestId,
    bool hidden = false,
  }) async {
    final db = await DatabaseHelper.database;
    final id = DatabaseHelper.newId();
    await db.insert('chat_history', {
      'id': id,
      'role': role,
      'content': content,
      'message_type': messageType,
      'metadata_json': jsonEncode(metadata),
      'request_id': requestId,
      'hidden_at': hidden ? DateTime.now().toIso8601String() : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    return ChatHistoryWriteResult(id: id, inserted: true);
  }

  static Future<ChatHistoryWriteResult> appendOnce({
    required String requestId,
    required String role,
    required String content,
    String messageType = 'message',
    Map<String, Object?> metadata = const {},
    bool hidden = false,
  }) async {
    final db = await DatabaseHelper.database;
    final existing = await db.query(
      'chat_history',
      columns: const ['id'],
      where: 'request_id = ?',
      whereArgs: [requestId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return ChatHistoryWriteResult(
        id: existing.single['id'] as String,
        inserted: false,
      );
    }

    final id = DatabaseHelper.newId();
    await db.insert('chat_history', {
      'id': id,
      'role': role,
      'content': content,
      'message_type': messageType,
      'metadata_json': jsonEncode(metadata),
      'request_id': requestId,
      'hidden_at': hidden ? DateTime.now().toIso8601String() : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    return ChatHistoryWriteResult(id: id, inserted: true);
  }

  static Future<void> hide(String id) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'chat_history',
      {'hidden_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, Object?>>> getVisible({int limit = 50}) {
    return getAll(includeHidden: false, limit: limit);
  }

  static Future<List<Map<String, Object?>>> getAll({
    bool includeHidden = true,
    int limit = 50,
  }) async {
    final db = await DatabaseHelper.database;
    return db.query(
      'chat_history',
      where: includeHidden ? null : 'hidden_at IS NULL',
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  static Future<Map<String, Map<String, Object?>>> getAttachmentsByMessageIds(
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await DatabaseHelper.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'chat_attachments',
      where: 'chat_message_id IN ($placeholders)',
      whereArgs: ids,
    );
    return {
      for (final row in rows)
        if (row['chat_message_id'] is String)
          row['chat_message_id']! as String: row,
    };
  }
}
