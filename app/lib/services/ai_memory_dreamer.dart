/// TaWorld AI 记忆整合器（Dreaming）
///
/// 灵感来自 ChatGPT 的 "Dreaming" 机制：
/// 在后台定期对记忆进行整合、去重、衰减和摘要，
/// 使 AI 的记忆保持精简、准确、有条理。
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local/database_helper.dart';
import '../data/models/ai_wiki_fact.dart';
import 'ai_service.dart';

/// 记忆衰减配置
class _DecayConfig {
  /// 不同类别的半衰期（天）
  static const Map<String, double> halfLives = {
    'user_identity': double.infinity, // 核心身份信息永不衰减
    'user_pref': 180, // 偏好：6 个月半衰期
    'partner_fact': 365, // 关于关心的人的事实：1 年
    'relationship': 365, // 关系信息：1 年
    'event': 90, // 事件：3 个月
    'conversation_detail': 30, // 对话细节：1 个月
  };

  /// 最低强度阈值，低于此值将被归档
  static const double archiveThreshold = 0.08;
}

abstract final class AiMemoryDreamer {
  /// 执行完整的记忆整合流程
  ///
  /// 应在后台任务中定期调用（如每天一次）。
  static Future<DreamResult> dream() async {
    final result = DreamResult();
    final db = await DatabaseHelper.database;

    try {
      // Step 1: 记忆衰减
      result.decayed = await _applyDecay(db);

      // Step 2: 清理过期记忆
      result.archived = await _archiveWeakFacts(db);

      // Step 3: LLM 整合（去重、合并、提升）
      final consolidationResult = await _llmConsolidation(db);
      result.merged = consolidationResult.merged;
      result.promoted = consolidationResult.promoted;

      // Step 4: 生成对话摘要（如果有足够的未摘要对话）
      result.summarized = await _summarizeOldConversations(db);

      // Step 5: 清理旧 chunks（保留最近 30 天）
      result.cleanedChunks = await _cleanOldChunks(db);

      // 记录最后 dreaming 时间
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'last_dream_time', DateTime.now().millisecondsSinceEpoch);

      dev.log(
        'Dreaming 完成: 衰减=${result.decayed}, 归档=${result.archived}, '
        '合并=${result.merged}, 提升=${result.promoted}, '
        '摘要=${result.summarized}, 清理chunks=${result.cleanedChunks}',
        name: 'AiMemoryDreamer',
      );
    } catch (e) {
      dev.log('Dreaming 失败: $e', name: 'AiMemoryDreamer');
      result.error = e.toString();
    }

    return result;
  }

  /// 获取上次 dreaming 的时间
  static Future<DateTime?> getLastDreamTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('last_dream_time');
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  /// 获取记忆统计信息
  static Future<MemoryStats> getStats() async {
    final db = await DatabaseHelper.database;

    final factCount = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ai_wiki_facts WHERE strength > ?',
        [_DecayConfig.archiveThreshold]);
    final totalFacts = factCount.first['cnt'] as int? ?? 0;

    final categoryStats = await db.rawQuery('''
      SELECT category, COUNT(*) as cnt, AVG(importance) as avg_importance
      FROM ai_wiki_facts
      WHERE strength > ?
      GROUP BY category
    ''', [_DecayConfig.archiveThreshold]);

    final summaryCount = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM ai_conversation_summaries');
    final totalSummaries = summaryCount.first['cnt'] as int? ?? 0;

    final chunkCount = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM conversation_chunks');
    final totalChunks = chunkCount.first['cnt'] as int? ?? 0;

    return MemoryStats(
      totalFacts: totalFacts,
      categoryBreakdown: {
        for (final row in categoryStats)
          row['category'] as String: row['cnt'] as int? ?? 0,
      },
      averageImportance: categoryStats.isEmpty
          ? 0
          : categoryStats
                  .map((r) => (r['avg_importance'] as num?)?.toDouble() ?? 0)
                  .reduce((a, b) => a + b) /
              categoryStats.length,
      totalSummaries: totalSummaries,
      totalChunks: totalChunks,
    );
  }

  // ==================== 内部方法 ====================

  /// 对所有活跃记忆应用时间衰减
  static Future<int> _applyDecay(Database db) async {
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'strength > ?',
      whereArgs: [_DecayConfig.archiveThreshold],
    );

    int decayedCount = 0;
    final now = DateTime.now();

    for (final row in rows) {
      final category = row['category'] as String;
      final halfLife = _DecayConfig.halfLives[category] ?? 90;

      // 核心身份不衰减
      if (halfLife == double.infinity) continue;

      final lastAccessed = row['last_accessed'] != null
          ? DateTime.parse(row['last_accessed'] as String)
          : DateTime.parse(row['created_at'] as String);

      final daysSinceAccess = now.difference(lastAccessed).inDays;
      if (daysSinceAccess <= 1) continue; // 1天内不衰减

      // Ebbinghaus 衰减公式: S = e^(-0.693 * t / H)
      final currentStrength = (row['strength'] as num?)?.toDouble() ?? 1.0;
      final accessCount = row['access_count'] as int? ?? 0;

      // 访问频率加成（被访问越多，衰减越慢）
      final accessBoost = math.min(1.0, math.log(1 + accessCount) / 5);
      final effectiveHalfLife = halfLife * (1 + accessBoost);

      final newStrength =
          math.exp(-0.693 * daysSinceAccess / effectiveHalfLife);
      final clampedStrength = math.max(0.0, math.min(1.0, newStrength));

      if ((currentStrength - clampedStrength).abs() > 0.01) {
        await db.update(
          'ai_wiki_facts',
          {'strength': clampedStrength},
          where: 'id = ?',
          whereArgs: [row['id'] as String],
        );
        decayedCount++;
      }
    }

    return decayedCount;
  }

  /// 归档强度过低的记忆
  static Future<int> _archiveWeakFacts(Database db) async {
    // 查找低强度记忆
    final weak = await db.query(
      'ai_wiki_facts',
      where: 'strength <= ? AND category != ?',
      whereArgs: [_DecayConfig.archiveThreshold, 'user_identity'],
    );

    if (weak.isEmpty) return 0;

    // 软删除：将 strength 设为 0
    for (final row in weak) {
      await db.update(
        'ai_wiki_facts',
        {'strength': 0.0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [row['id'] as String],
      );
    }

    return weak.length;
  }

  /// 使用 LLM 进行记忆整合：去重、合并矛盾、提升高频记忆
  static Future<_ConsolidationResult> _llmConsolidation(Database db) async {
    final result = _ConsolidationResult();

    // 获取所有活跃事实
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'strength > ?',
      whereArgs: [_DecayConfig.archiveThreshold],
      orderBy: 'category, importance DESC',
    );

    if (rows.length < 5) return result; // 太少，不需要整合

    final facts = rows.map(AiWikiFact.fromMap).toList();

    // 按类别分组
    final byCategory = <String, List<AiWikiFact>>{};
    for (final f in facts) {
      byCategory.putIfAbsent(f.category, () => []).add(f);
    }

    // 指令部分作为 system message（跨类别调用可被 DeepSeek 缓存）
    const consolidationSystemPrompt =
        '你是一个记忆整合助手。请对以下记忆进行整合：\n\n'
        '请执行以下操作：\n'
        '1. 找出重复或高度重复的记忆，指出应该保留哪一条（返回要删除的 ID 列表）\n'
        '2. 找出相互矛盾的记忆，指出应该保留最新的哪一条（返回要删除的 ID 列表）\n'
        '3. 如果多条记忆可以合并为一条更好的总结，给出合并建议\n\n'
        '返回 JSON 格式：\n'
        '{\n'
        '  "delete_ids": ["id1", "id2"],\n'
        '  "merge_suggestions": [\n'
        '    {"source_ids": ["id3", "id4"], "merged_content": "合并后的内容", "importance": 0.7}\n'
        '  ]\n'
        '}\n\n'
        '如果没有需要操作的，返回：{"delete_ids": [], "merge_suggestions": []}';

    for (final entry in byCategory.entries) {
      final category = entry.key;
      final categoryFacts = entry.value;
      if (categoryFacts.length < 3) continue; // 太少，跳过

      final factList =
          categoryFacts.map((f) => '[${f.id}] ${f.content}').join('\n');

      // 可变数据（类别 + 事实列表）作为 user message
      final userPrompt = '类别: $category\n记忆列表:\n$factList';

      final response = await AiService.callProModel(
        systemPrompt: consolidationSystemPrompt,
        prompt: userPrompt,
        temperature: 0.1,
        maxTokens: 1500,
      );

      if (response == null) continue;

      try {
        Map<String, dynamic>? data;
        try {
          data = jsonDecode(response.trim()) as Map<String, dynamic>;
        } catch (_) {
          final match = RegExp(r'\{[\s\S]*\}').firstMatch(response);
          if (match != null) {
            data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
          }
        }
        if (data == null) continue;

        // 处理删除
        final deleteIds = (data['delete_ids'] as List?)?.cast<String>() ?? [];
        for (final id in deleteIds) {
          await db.update(
            'ai_wiki_facts',
            {'strength': 0.0, 'updated_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );
          result.merged++;
        }

        // 处理合并
        final merges = data['merge_suggestions'] as List? ?? [];
        for (final merge in merges) {
          final mergeData = merge as Map<String, dynamic>;
          final sourceIds =
              (mergeData['source_ids'] as List?)?.cast<String>() ?? [];
          final mergedContent = mergeData['merged_content'] as String? ?? '';
          final importance =
              (mergeData['importance'] as num?)?.toDouble() ?? 0.6;

          if (sourceIds.isEmpty || mergedContent.isEmpty) continue;

          // 用第一条作为合并后的记录
          final keepId = sourceIds.first;
          await db.update(
            'ai_wiki_facts',
            {
              'content': mergedContent,
              'importance': importance,
              'strength': 1.0,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [keepId],
          );

          // 其余的归档
          for (int i = 1; i < sourceIds.length; i++) {
            await db.update(
              'ai_wiki_facts',
              {
                'strength': 0.0,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [sourceIds[i]],
            );
          }
          result.merged += sourceIds.length - 1;
          result.promoted++;
        }
      } catch (e) {
        dev.log('整合解析失败 ($category): $e', name: 'AiMemoryDreamer');
      }
    }

    return result;
  }

  /// 对旧的对话进行摘要（超过 20 条且未摘要的对话）
  static Future<int> _summarizeOldConversations(Database db) async {
    // 查找最近未摘要的对话
    final lastSummary = await db.query(
      'ai_conversation_summaries',
      orderBy: 'created_at DESC',
      limit: 1,
    );

    final sinceTime = lastSummary.isNotEmpty
        ? lastSummary.first['created_at'] as String
        : '1970-01-01T00:00:00';

    final messages = await db.query(
      'chat_history',
      where: 'created_at > ?',
      whereArgs: [sinceTime],
      orderBy: 'created_at ASC',
    );

    if (messages.length < 10) return 0; // 不够多，暂不摘要

    // 格式化对话
    final conversationText = messages.map((m) {
      final role = m['role'] == 'user' ? '用户' : 'AI';
      return '$role: ${m['content']}';
    }).join('\n');

    // 指令部分作为 system message（可被 DeepSeek 缓存）
    const summarizeSystemPrompt =
        '请对以下对话进行简洁的摘要，保留关键信息。\n\n'
        '要求：\n'
        '1. 摘要不超过 100 字\n'
        '2. 保留关键话题和结论\n'
        '3. 提取涉及的主要话题标签\n\n'
        '返回 JSON 格式：\n'
        '{"summary": "摘要内容", "topics": ["话题1", "话题2"]}';

    // 可变数据（对话内容）作为 user message
    final userPrompt = '对话内容：\n$conversationText';

    final response = await AiService.callProModel(
      systemPrompt: summarizeSystemPrompt,
      prompt: userPrompt,
      temperature: 0.3,
      maxTokens: 500,
    );

    if (response == null) return 0;

    try {
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.trim()) as Map<String, dynamic>;
      } catch (_) {
        final match = RegExp(r'\{[\s\S]*\}').firstMatch(response);
        if (match != null) {
          data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        }
      }
      if (data == null) return 0;

      final summary = data['summary'] as String? ?? '';
      final topics = (data['topics'] as List?)?.cast<String>() ?? [];

      if (summary.isNotEmpty) {
        final now = DateTime.now();
        await db.insert('ai_conversation_summaries', {
          'id': DatabaseHelper.newId(),
          'summary': summary,
          'message_count': messages.length,
          'date':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          'topics': jsonEncode(topics),
          'created_at': now.toIso8601String(),
        });
        return 1;
      }
    } catch (e) {
      dev.log('对话摘要失败: $e', name: 'AiMemoryDreamer');
    }

    return 0;
  }

  /// 清理 30 天前的对话 chunks
  static Future<int> _cleanOldChunks(Database db) async {
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    return db.delete(
      'conversation_chunks',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
  }
}

/// Dreaming 执行结果
class DreamResult {
  int decayed = 0;
  int archived = 0;
  int merged = 0;
  int promoted = 0;
  int summarized = 0;
  int cleanedChunks = 0;
  String? error;

  bool get hasError => error != null;
}

/// 记忆统计
class MemoryStats {
  final int totalFacts;
  final Map<String, int> categoryBreakdown;
  final double averageImportance;
  final int totalSummaries;
  final int totalChunks;

  const MemoryStats({
    required this.totalFacts,
    required this.categoryBreakdown,
    required this.averageImportance,
    required this.totalSummaries,
    required this.totalChunks,
  });
}

class _ConsolidationResult {
  int merged = 0;
  int promoted = 0;
}
