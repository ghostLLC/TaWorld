/// TaWorld AI 记忆提取器
///
/// 对话结束后异步调用，使用 DeepSeek V4 Pro 从对话中提取
/// 有价值的事实，写入 Wiki 层（ai_wiki_facts 表）。
library;

import 'dart:convert';
import 'dart:developer' as dev;

import '../data/local/database_helper.dart';
import '../data/models/ai_wiki_fact.dart';
import 'ai_service.dart';

/// 从对话中提取的结构化事实
class _ExtractedFact {
  final String content;
  final String category; // user_pref / partner_fact / event / relationship
  final String? entityName;
  final String status; // NEW / UPDATE / SAME
  final double importance;

  const _ExtractedFact({
    required this.content,
    required this.category,
    this.entityName,
    required this.status,
    required this.importance,
  });
}

abstract final class AiMemoryExtractor {
  /// 从最近一轮对话中提取记忆，写入 Wiki 事实表
  ///
  /// 应在对话完成后异步调用，不阻塞 UI。
  static Future<void> extractFromConversation({
    required String userMessage,
    required String assistantReply,
  }) async {
    try {
      // 读取当前已有事实，避免重复
      final existingFacts = await _getExistingFactsSummary();

      // 指令部分作为 system message（跨调用可被 DeepSeek 缓存）
      const systemPrompt = '''你是一个记忆提取助手。请从以下对话中提取值得长期记住的事实。

提取规则：
1. 只提取有持久价值的信息（用户偏好、关于关心的人的信息、重要事件、关系动态）
2. 忽略日常闲聊、临时状态、已经在已有记忆中包含的信息
3. 如果新信息与已有记忆矛盾，标记为 UPDATE
4. 如果信息已存在且一致，标记为 SAME（不会重复写入）
5. 每条事实用简短的一句话概括，不超过40字
6. category 只能是: user_pref / partner_fact / event / relationship
7. entity_name 填相关的人名（如"小红"），没有则填 null

严格返回 JSON 格式，不要包含任何其他文字：
{"facts": [
  {"content": "事实内容", "category": "user_pref", "entity_name": null, "status": "NEW", "importance": 0.7}
]}

如果没有值得记住的新信息，返回：{"facts": []}''';

      // 可变数据作为 user message
      final userPrompt = '''已有的记忆：
$existingFacts

--- 本轮对话 ---
用户: $userMessage
AI: $assistantReply''';

      final response = await AiService.callProModel(
        systemPrompt: systemPrompt,
        prompt: userPrompt,
        temperature: 0.2,
        maxTokens: 1500,
      );

      if (response == null || response.isEmpty) return;

      final facts = _parseFacts(response);
      if (facts.isEmpty) return;

      await _mergeFacts(facts);

      dev.log('记忆提取完成: 提取 ${facts.length} 条, 写入 ${facts.where((f) => f.status != 'SAME').length} 条',
          name: 'AiMemoryExtractor');
    } catch (e) {
      dev.log('记忆提取失败: $e', name: 'AiMemoryExtractor');
    }
  }

  /// 从一批历史消息中提取记忆（用于初始化或批量处理）
  static Future<void> extractFromHistory({int messageLimit = 50}) async {
    try {
      final history = await AiService.getChatHistory(limit: messageLimit);
      if (history.length < 2) return;

      // 将历史消息格式化为对话文本
      final conversationBuffer = StringBuffer();
      for (final msg in history) {
        final role = msg['role'] == 'user' ? '用户' : 'AI';
        conversationBuffer.writeln('$role: ${msg['content']}');
      }

      final existingFacts = await _getExistingFactsSummary();

      // 指令部分作为 system message（跨调用可被 DeepSeek 缓存）
      const systemPrompt = '''你是一个记忆提取助手。请从以下完整对话历史中提取值得长期记住的重要事实。

提取规则：
1. 只提取有持久价值的信息（用户偏好、关于关心的人的信息、重要事件、关系动态）
2. 忽略日常闲聊和临时状态
3. 如果新信息与已有记忆矛盾，标记为 UPDATE
4. 每条事实用简短的一句话概括，不超过40字
5. category 只能是: user_pref / partner_fact / event / relationship
6. entity_name 填相关的人名（如"小红"），没有则填 null
7. importance 评分: 核心身份信息0.9+, 偏好0.6-0.8, 一般事件0.3-0.5

严格返回 JSON 格式：
{"facts": [
  {"content": "事实内容", "category": "user_pref", "entity_name": null, "status": "NEW", "importance": 0.7}
]}

如果没有值得记住的信息，返回：{"facts": []}''';

      // 可变数据作为 user message
      final userPrompt = '''已有的记忆：
${existingFacts.isEmpty ? '（暂无）' : existingFacts}

--- 对话历史 ---
$conversationBuffer''';

      final response = await AiService.callProModel(
        systemPrompt: systemPrompt,
        prompt: userPrompt,
        temperature: 0.2,
        maxTokens: 2000,
      );

      if (response == null || response.isEmpty) return;

      final facts = _parseFacts(response);
      await _mergeFacts(facts);

      dev.log('历史记忆提取完成: 处理 ${history.length} 条消息, 提取 ${facts.length} 条事实',
          name: 'AiMemoryExtractor');
    } catch (e) {
      dev.log('历史记忆提取失败: $e', name: 'AiMemoryExtractor');
    }
  }

  // ==================== 内部方法 ====================

  /// 获取现有事实的摘要文本（给 LLM 参考用）
  static Future<String> _getExistingFactsSummary() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'strength > ?',
      whereArgs: [0.1],
      orderBy: 'importance DESC',
      limit: 50,
    );
    if (rows.isEmpty) return '（暂无）';
    return rows.map((r) => '- [${r['category']}] ${r['content']}').join('\n');
  }

  /// 解析 LLM 返回的 JSON 为事实列表
  static List<_ExtractedFact> _parseFacts(String response) {
    try {
      // 尝试直接解析
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.trim()) as Map<String, dynamic>;
      } catch (_) {
        // 尝试提取 JSON 块
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(response);
        if (match != null) {
          data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        }
      }

      if (data == null) return [];

      final factsList = data['facts'] as List?;
      if (factsList == null) return [];

      return factsList.map((f) {
        final fact = f as Map<String, dynamic>;
        return _ExtractedFact(
          content: fact['content'] as String? ?? '',
          category: fact['category'] as String? ?? 'user_pref',
          entityName: fact['entity_name'] as String?,
          status: (fact['status'] as String? ?? 'NEW').toUpperCase(),
          importance: (fact['importance'] as num?)?.toDouble() ?? 0.5,
        );
      }).where((f) => f.content.isNotEmpty).toList();
    } catch (e) {
      dev.log('解析事实失败: $e', name: 'AiMemoryExtractor');
      return [];
    }
  }

  /// 将提取的事实合并到 Wiki 表中
  static Future<void> _mergeFacts(List<_ExtractedFact> facts) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();

    for (final fact in facts) {
      if (fact.status == 'SAME') continue; // 已存在且一致，跳过

      if (fact.status == 'UPDATE') {
        // 查找需要更新的旧事实
        final existing = await _findSimilarFact(fact);
        if (existing != null) {
          await db.update(
            'ai_wiki_facts',
            {
              'content': fact.content,
              'importance': fact.importance,
              'strength': 1.0, // 更新后重置强度
              'updated_at': now.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [existing.id],
          );
          continue;
        }
      }

      // NEW 或找不到匹配的 UPDATE → 插入新事实
      // 先检查是否已有高度相似的事实
      final similar = await _findSimilarFact(fact);
      if (similar == null) {
        await db.insert('ai_wiki_facts', {
          'id': DatabaseHelper.newId(),
          'category': fact.category,
          'entity_id': fact.entityName, // 简化：用名字作为 entity_id
          'content': fact.content,
          'source': 'chat',
          'importance': fact.importance,
          'strength': 1.0,
          'access_count': 0,
          'last_accessed': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    }
  }

  /// 查找相似的事实（简单的文本匹配，避免重复）
  static Future<AiWikiFact?> _findSimilarFact(_ExtractedFact fact) async {
    final db = await DatabaseHelper.database;
    // 精确内容匹配
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'content = ?',
      whereArgs: [fact.content],
      limit: 1,
    );
    if (rows.isNotEmpty) return AiWikiFact.fromMap(rows.first);

    // 同类别 + 同实体的事实（用于 UPDATE 场景）
    if (fact.entityName != null) {
      final entityRows = await db.query(
        'ai_wiki_facts',
        where: 'category = ? AND entity_id = ? AND strength > 0.1',
        whereArgs: [fact.category, fact.entityName],
        orderBy: 'importance DESC',
        limit: 5,
      );
      // 简单关键词匹配：如果新事实和旧事实有较多共同字符
      for (final row in entityRows) {
        final existingContent = row['content'] as String;
        if (_similarity(existingContent, fact.content) > 0.6) {
          return AiWikiFact.fromMap(row);
        }
      }
    }

    return null;
  }

  /// 简单的字符串相似度（Jaccard 系数基于字符 bigram）
  static double _similarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    Set<String> bigrams(String s) {
      final result = <String>{};
      for (int i = 0; i < s.length - 1; i++) {
        result.add(s.substring(i, i + 2));
      }
      return result;
    }

    final setA = bigrams(a);
    final setB = bigrams(b);
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : intersection / union;
  }
}
