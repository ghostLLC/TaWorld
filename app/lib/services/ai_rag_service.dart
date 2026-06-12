/// TaWorld AI RAG 检索服务
///
/// 从历史对话中检索与当前话题相关的片段，
/// 注入到系统提示中，实现"情景记忆"召回。
///
/// 检索策略：
/// 1. 关键词匹配（基于分词和 TF-IDF 思路，纯本地）
/// 2. 时间衰减（越近的对话权重越高）
/// 3. 可选的 embedding 向量搜索（需接入 embedding API）
library;

import 'dart:convert';
import 'dart:math' as math;

import '../data/local/database_helper.dart';

/// RAG 检索结果
class RagResult {
  final String content;
  final String role;
  final DateTime date;
  final double score;

  const RagResult({
    required this.content,
    required this.role,
    required this.date,
    required this.score,
  });

  @override
  String toString() =>
      '[${date.month}/${date.day} ${role == 'user' ? '用户' : 'AI'}] $content';
}

abstract final class AiRagService {
  /// 中文停用词（高频但无意义的词，检索时忽略）
  static const _stopWords = {
    '的', '了', '在', '是', '我', '有', '和', '就', '不', '人',
    '都', '一', '一个', '上', '也', '很', '到', '说', '要', '去',
    '你', '会', '着', '没有', '看', '好', '自己', '这', '他', '她',
    '吗', '呢', '啊', '吧', '哦', '嗯', '那', '这个', '那个',
    '什么', '怎么', '可以', '能', '把', '对', '让', '给', '跟',
    '还', '再', '又', '已经', '正在', '被', '从', '向', '比',
  };

  /// 存储对话片段到 RAG 库
  ///
  /// 应在对话完成后异步调用。
  static Future<void> storeConversationChunks({
    required String userMessage,
    required String assistantReply,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 提取话题标签
    final topics = _extractTopics(userMessage);

    // 存储用户消息
    await db.insert('conversation_chunks', {
      'id': DatabaseHelper.newId(),
      'content': userMessage,
      'role': 'user',
      'conversation_date': dateStr,
      'topics': topics.isNotEmpty ? jsonEncode(topics) : null,
      'embedding': null, // 预留 embedding 字段
      'created_at': now.toIso8601String(),
    });

    // 存储 AI 回复（只存非流式的完整回复）
    if (assistantReply.isNotEmpty) {
      await db.insert('conversation_chunks', {
        'id': DatabaseHelper.newId(),
        'content': assistantReply,
        'role': 'assistant',
        'conversation_date': dateStr,
        'topics': topics.isNotEmpty ? jsonEncode(topics) : null,
        'embedding': null,
        'created_at': now.add(const Duration(seconds: 1)).toIso8601String(),
      });
    }
  }

  /// 检索与查询最相关的历史对话片段
  ///
  /// [query] 用户当前消息
  /// [topK] 返回最多 K 条结果
  /// [maxAge] 最多回溯多少天（默认 90 天）
  static Future<List<RagResult>> search({
    required String query,
    int topK = 5,
    int maxAge = 90,
  }) async {
    final db = await DatabaseHelper.database;
    final cutoff =
        DateTime.now().subtract(Duration(days: maxAge)).toIso8601String();

    // 提取查询关键词
    final queryTopics = _extractTopics(query);
    if (queryTopics.isEmpty) return [];

    // 从数据库获取时间范围内的 chunks
    final rows = await db.query(
      'conversation_chunks',
      where: 'created_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'created_at DESC',
      limit: 500, // 最多扫描 500 条
    );

    if (rows.isEmpty) return [];

    // 对每条 chunk 计算相关性得分
    final results = <RagResult>[];
    for (final row in rows) {
      final content = row['content'] as String? ?? '';
      if (content.isEmpty) continue;

      final role = row['role'] as String? ?? 'user';
      final createdAt = DateTime.parse(row['created_at'] as String);
      final chunkTopics = row['topics'] != null
          ? (jsonDecode(row['topics'] as String) as List?)
                  ?.cast<String>() ??
              []
          : <String>[];

      final score = _calculateRelevance(
        query: query,
        queryTopics: queryTopics,
        content: content,
        chunkTopics: chunkTopics,
        createdAt: createdAt,
      );

      if (score > 0.1) {
        results.add(RagResult(
          content: content,
          role: role,
          date: createdAt,
          score: score,
        ));
      }
    }

    // 按得分排序，取 top-K
    results.sort((a, b) => b.score.compareTo(a.score));
    return results.take(topK).toList();
  }

  /// 将 RAG 结果格式化为系统提示的附加内容
  static String formatForPrompt(List<RagResult> results) {
    if (results.isEmpty) return '';

    final lines = results.map((r) {
      final daysAgo = DateTime.now().difference(r.date).inDays;
      final timeLabel = daysAgo == 0
          ? '今天'
          : daysAgo == 1
              ? '昨天'
              : '$daysAgo 天前';
      final roleLabel = r.role == 'user' ? '用户' : 'AI';
      return '- [$timeLabel] $roleLabel: ${r.content}';
    }).toList();

    return '【可能相关的过往对话】\n${lines.join('\n')}';
  }

  /// 获取 RAG 统计信息
  static Future<Map<String, dynamic>> getStats() async {
    final db = await DatabaseHelper.database;

    final totalResult = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM conversation_chunks');
    final total = totalResult.first['cnt'] as int? ?? 0;

    final dateRange = await db.rawQuery(
      'SELECT MIN(created_at) as earliest, MAX(created_at) as latest '
      'FROM conversation_chunks',
    );

    return {
      'totalChunks': total,
      'earliestChunk': dateRange.first['earliest'],
      'latestChunk': dateRange.first['latest'],
    };
  }

  /// 清空所有 chunks
  static Future<void> clearAll() async {
    final db = await DatabaseHelper.database;
    await db.delete('conversation_chunks');
  }

  // ==================== 内部方法 ====================

  /// 简单的中文分词（基于字符 bigram + 常见词识别）
  ///
  /// 不依赖分词库，适合轻量级场景。
  /// 对于更精确的分词，可以后续接入 jieba 等分词工具。
  static List<String> _extractTopics(String text) {
    final topics = <String>{};

    // 1. 提取 2-4 字的连续片段作为候选词
    for (int len = 2; len <= 4; len++) {
      for (int i = 0; i <= text.length - len; i++) {
        final segment = text.substring(i, i + len);
        // 过滤纯标点或空白
        if (segment.trim().isEmpty) continue;
        if (RegExp(r'^[^\u4e00-\u9fff\w]+$').hasMatch(segment)) continue;
        topics.add(segment);
      }
    }

    // 2. 提取英文单词
    final englishWords = RegExp(r'[a-zA-Z]{3,}').allMatches(text);
    for (final match in englishWords) {
      topics.add(match.group(0)!.toLowerCase());
    }

    // 3. 提取数字（如日期、数量）
    final numbers = RegExp(r'\d+').allMatches(text);
    for (final match in numbers) {
      topics.add(match.group(0)!);
    }

    // 4. 移除停用词
    topics.removeWhere((t) => _stopWords.contains(t));

    return topics.toList();
  }

  /// 计算 chunk 与 query 的相关性得分
  static double _calculateRelevance({
    required String query,
    required List<String> queryTopics,
    required String content,
    required List<String> chunkTopics,
    required DateTime createdAt,
  }) {
    double score = 0.0;

    // 1. 关键词匹配得分
    final contentLower = content.toLowerCase();
    int keywordHits = 0;
    for (final topic in queryTopics) {
      if (contentLower.contains(topic.toLowerCase())) {
        keywordHits++;
      }
    }
    if (queryTopics.isNotEmpty) {
      score += (keywordHits / queryTopics.length) * 0.5;
    }

    // 2. 话题标签匹配
    if (chunkTopics.isNotEmpty && queryTopics.isNotEmpty) {
      final overlap =
          queryTopics.toSet().intersection(chunkTopics.toSet()).length;
      score += (overlap / queryTopics.length) * 0.3;
    }

    // 3. 时间衰减（越近越重要）
    final daysAgo = DateTime.now().difference(createdAt).inDays;
    final timeWeight = math.exp(-0.03 * daysAgo); // ~23 天半衰期
    score *= (0.5 + 0.5 * timeWeight);

    // 4. 精确包含查询词的大片段加分
    if (query.length >= 4 && content.contains(query)) {
      score += 0.3;
    }

    return score.clamp(0.0, 1.0);
  }
}
