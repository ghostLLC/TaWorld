/// TaWorld AI 记忆服务 — 动态上下文构建
///
/// 核心职责：
/// 1. 从现有数据表收集上下文，构建动态系统提示词
/// 2. Wiki 事实的 CRUD 操作
/// 3. 对话摘要管理
library;

import '../data/local/database_helper.dart';
import '../data/models/ai_wiki_fact.dart';
import 'local/local_user_service.dart';
import 'local/partner_service.dart';
import 'local/local_reminder_service.dart';
import 'ai_rag_service.dart';

/// AI 记忆服务
abstract final class AiMemoryService {

  // ==================== 动态系统提示词构建 ====================

  /// 构建完整的动态系统提示词
  ///
  /// 将用户身份、关心的人、活跃提醒、时间感知、Wiki 事实、
  /// 以及 RAG 相关回忆注入到系统提示中。
  static Future<String> buildSystemPrompt({
    String? userMessage,
  }) async {
    final sections = <String>[];

    // 1. 基础指令（格式规则 + 行为规则）
    sections.add(_baseInstructions);

    // 2. 用户身份
    final user = await LocalUserService.getUser();
    if (user != null && user.nickname.isNotEmpty) {
      sections.add('【用户信息】\n用户叫${user.nickname}');
    }

    // 3. 关心的人列表
    final partners = await PartnerService.getAll();
    if (partners.isNotEmpty) {
      final lines = <String>[];
      for (final p in partners) {
        final days = DateTime.now().difference(p.createdAt).inDays;
        final parts = <String>['${p.nickname}（${p.typeLabel}，认识 $days 天'];
        if (p.city != null && p.city!.isNotEmpty) {
          parts.add('城市: ${p.city}');
        }
        if (p.note != null && p.note!.isNotEmpty) {
          parts.add('备注: ${p.note}');
        }
        lines.add('- ${parts.first}${parts.length > 1 ? '，${parts.skip(1).join('，')}' : ''}）');
      }
      sections.add('【关心的人】\n${lines.join('\n')}');
    }

    // 4. 活跃提醒配置
    if (partners.isNotEmpty) {
      final reminderLines = <String>[];
      for (final p in partners) {
        final configs = await LocalReminderService.getConfigs(p.id);
        final enabled = configs.where((c) => c.enabled).toList();
        if (enabled.isNotEmpty) {
          final categories = enabled.map((c) {
            switch (c.category) {
              case 'sleep':
                final time = c.config['target_sleep_time'] ?? '';
                return '睡觉提醒${time.isNotEmpty ? "($time)" : ""}';
              case 'meal':
                final meals = c.config['meals'] as List?;
                final time = meals != null && meals.isNotEmpty
                    ? meals[0]['target_time'] ?? ''
                    : '';
                return '吃饭提醒${time.isNotEmpty ? "($time)" : ""}';
              case 'weather':
                return '天气提醒';
              default:
                return c.category;
            }
          }).join('、');
          reminderLines.add('- ${p.nickname}: $categories');
        }
      }
      if (reminderLines.isNotEmpty) {
        sections.add('【活跃提醒】\n${reminderLines.join('\n')}');
      }
    }

    // 5. Wiki 事实（从数据库读取）
    // 注意：Wiki 和摘要放在时间之前，因为时间每 3-6 小时变一次，
    // 放后面可以让更多稳定区块命中 DeepSeek 上下文缓存。
    final facts = await getTopFacts(limit: 20);
    if (facts.isNotEmpty) {
      final factLines = facts.map((f) => '- ${f.content}').toList();
      sections.add('【你了解的信息】\n${factLines.join('\n')}');
    }

    // 6. 最近对话摘要
    final summaries = await getRecentSummaries(limit: 3);
    if (summaries.isNotEmpty) {
      final summaryLines = summaries.map((s) => '- ${s['summary']}').toList();
      sections.add('【近期对话概要】\n${summaryLines.join('\n')}');
    }

    // 7. 时间感知（粗化到时段，每 3-6 小时变一次，不精确到分钟）
    // 放在半静态内容之后、动态 RAG 之前，最大化 DeepSeek 缓存前缀。
    final now = DateTime.now();
    final hour = now.hour;
    String timeDesc;
    if (hour < 6) {
      timeDesc = '凌晨';
    } else if (hour < 9) {
      timeDesc = '早上';
    } else if (hour < 12) {
      timeDesc = '上午';
    } else if (hour < 14) {
      timeDesc = '中午';
    } else if (hour < 18) {
      timeDesc = '下午';
    } else if (hour < 22) {
      timeDesc = '晚上';
    } else {
      timeDesc = '深夜';
    }
    sections.add('【当前时间】\n${now.year}年${now.month}月${now.day}日 $timeDesc');

    // 8. RAG 检索：根据用户当前消息召回相关历史对话
    // 最易变的内容放最后，避免破坏前面区块的缓存。
    if (userMessage != null && userMessage.isNotEmpty) {
      try {
        final ragResults = await AiRagService.search(
          query: userMessage,
          topK: 3,
          maxAge: 60,
        );
        if (ragResults.isNotEmpty) {
          sections.add(AiRagService.formatForPrompt(ragResults));
        }
      } catch (_) {
        // RAG 检索失败不影响主流程
      }
    }

    return sections.join('\n\n');
  }

  // ==================== Wiki 事实 CRUD ====================

  /// 添加一条 Wiki 事实
  static Future<void> addFact({
    required String category,
    required String content,
    String? entityId,
    String source = 'chat',
    double importance = 0.5,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    await db.insert('ai_wiki_facts', {
      'id': DatabaseHelper.newId(),
      'category': category,
      'entity_id': entityId,
      'content': content,
      'source': source,
      'importance': importance,
      'strength': 1.0,
      'access_count': 0,
      'last_accessed': null,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  /// 更新一条 Wiki 事实
  static Future<void> updateFact(String id, {
    String? content,
    double? importance,
    double? strength,
  }) async {
    final db = await DatabaseHelper.database;
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (content != null) data['content'] = content;
    if (importance != null) data['importance'] = importance;
    if (strength != null) data['strength'] = strength;
    await db.update('ai_wiki_facts', data, where: 'id = ?', whereArgs: [id]);
  }

  /// 删除一条 Wiki 事实
  static Future<void> deleteFact(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_wiki_facts', where: 'id = ?', whereArgs: [id]);
  }

  /// 获取所有 Wiki 事实
  static Future<List<AiWikiFact>> getAllFacts() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('ai_wiki_facts', orderBy: 'importance DESC');
    return rows.map(AiWikiFact.fromMap).toList();
  }

  /// 获取 top-N 事实（按综合得分排序）
  static Future<List<AiWikiFact>> getTopFacts({int limit = 20}) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'strength > 0.1',
      orderBy: 'importance * strength DESC',
      limit: limit,
    );
    final facts = rows.map(AiWikiFact.fromMap).toList();

    // 更新访问计数（异步，不阻塞）
    _bumpAccessCount(facts.map((f) => f.id).toList());

    return facts;
  }

  /// 按 entity 获取事实
  static Future<List<AiWikiFact>> getFactsByEntity(String entityId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'entity_id = ? AND strength > 0.1',
      whereArgs: [entityId],
      orderBy: 'importance DESC',
    );
    return rows.map(AiWikiFact.fromMap).toList();
  }

  /// 按类别获取事实
  static Future<List<AiWikiFact>> getFactsByCategory(String category) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'ai_wiki_facts',
      where: 'category = ? AND strength > 0.1',
      whereArgs: [category],
      orderBy: 'importance DESC',
    );
    return rows.map(AiWikiFact.fromMap).toList();
  }

  /// 清空所有 Wiki 事实
  static Future<void> clearAllFacts() async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_wiki_facts');
  }

  /// 获取事实总数
  static Future<int> getFactCount() async {
    final db = await DatabaseHelper.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM ai_wiki_facts WHERE strength > 0.1",
    );
    return result.first['cnt'] as int? ?? 0;
  }

  /// 清除所有 AI 记忆数据（Wiki 事实 + 摘要 + chunks）
  static Future<void> clearAllMemory() async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_wiki_facts');
    await db.delete('ai_conversation_summaries');
    await db.delete('conversation_chunks');
  }

  // ==================== 对话摘要 ====================

  /// 保存对话摘要
  static Future<void> saveSummary({
    required String summary,
    required int messageCount,
    String? topics,
  }) async {
    final db = await DatabaseHelper.database;
    final now = DateTime.now();
    await db.insert('ai_conversation_summaries', {
      'id': DatabaseHelper.newId(),
      'summary': summary,
      'message_count': messageCount,
      'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'topics': topics,
      'created_at': now.toIso8601String(),
    });
  }

  /// 获取最近的对话摘要
  static Future<List<Map<String, dynamic>>> getRecentSummaries({int limit = 3}) async {
    final db = await DatabaseHelper.database;
    return db.query(
      'ai_conversation_summaries',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }

  /// 清空所有对话摘要
  static Future<void> clearAllSummaries() async {
    final db = await DatabaseHelper.database;
    await db.delete('ai_conversation_summaries');
  }

  // ==================== 内部辅助 ====================

  /// 异步更新访问计数
  static Future<void> _bumpAccessCount(List<String> factIds) async {
    if (factIds.isEmpty) return;
    try {
      final db = await DatabaseHelper.database;
      final now = DateTime.now().toIso8601String();
      for (final id in factIds) {
        await db.rawUpdate(
          'UPDATE ai_wiki_facts SET access_count = access_count + 1, '
          'last_accessed = ? WHERE id = ?',
          [now, id],
        );
      }
    } catch (_) {
      // 静默处理
    }
  }

  /// 基础指令（保留现有的格式规则）
  static const _baseInstructions = '''你正在用「Ta的世界」APP跟用户聊天，就像朋友之间发微信一样。

回复规则：
- 像真人发微信，每次回复拆成2~4条短句，用 ||| 分隔
- 每条短句10~30个字，简短口语化
- 绝对不要使用emoji、表情、颜文字
- 绝对不要使用markdown格式（不要用**加粗**、*斜体*、#标题、- 列表、1. 编号）
- 不要使用任何特殊符号或格式标记
- 语气自然亲切，像朋友聊天
- 你只聊跟关心对方有关的话题，不聊其他
- 每条短句之间要有自然的停顿感，不要像写文章
- 利用下方提供的用户信息、关心的人、你了解的信息来个性化你的回复
- 当提到你了解的信息时，要自然融入，不要生硬引用

示例回复（用户问"帮我写句早安语"）：
早安呀|||今天天气不错呢|||记得吃早餐哦

示例回复（用户问"怎么关心对方"）：
其实不用太复杂|||有时候一句在干嘛就很暖|||关键是让他感觉到你在想他''';
}
