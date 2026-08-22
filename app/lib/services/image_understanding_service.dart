import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/local/database_helper.dart';
import 'ai_model_catalog.dart';
import 'ai_service.dart';

class ImageUnderstandingException implements Exception {
  const ImageUnderstandingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageUnderstanding {
  const ImageUnderstanding({required this.summary, required this.facts});

  final String summary;
  final List<String> facts;
}

class ImageMemoryReceipt {
  const ImageMemoryReceipt({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is ImageMemoryReceipt &&
      other.title == title &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(title, detail);
}

class StoredImageAttachment {
  const StoredImageAttachment({
    required this.localPath,
    required this.mimeType,
    required this.sha256Digest,
    required this.sizeBytes,
  });

  final String localPath;
  final String mimeType;
  final String sha256Digest;
  final int sizeBytes;
}

/// Local-first image input pipeline.
///
/// Images are copied into the app documents directory before analysis, then
/// referenced from the typed chat attachment table. Only the extracted facts
/// enter long-term memory; graph presentation deliberately ignores images.
abstract final class ImageUnderstandingService {
  static const int maxInlineImageBytes = 32 * 1024 * 1024;
  static const _endpoint = 'https://api.deepseek.com/chat/completions';

  static const _analysisPrompt = '''你是 TaWorld 的温暖关怀助手小念。请理解图片，并只返回 JSON：
{"summary":"一句简洁、客观的图片概述","facts":["可长期记住且对关心他人有用的明确事实"]}
规则：
1. facts 只写图片中可直接确认的事实，不猜测身份、关系或敏感属性；没有适合长期记忆的事实时返回空数组。
2. 每条事实独立、简短，最多 8 条；不要输出 Markdown 或 JSON 以外的内容。
3. 语气温和，但 summary 不夸张。''';

  static ImageMemoryReceipt? memoryReceipt(ImageUnderstanding understanding) {
    final count = understanding.facts.length;
    if (count == 0) return null;
    return ImageMemoryReceipt(
      title: '已记住图片里的信息',
      detail: '已保存 $count 条可用于后续关怀的事实',
    );
  }

  static Map<String, Object?> buildInlinePayload({
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (bytes.isEmpty || bytes.length > maxInlineImageBytes) {
      throw const ImageUnderstandingException('图片为空或超过 32 MiB 限制');
    }
    return {
      'model': AiModelCatalog.vision,
      'temperature': 0.2,
      'max_tokens': 1200,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _analysisPrompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
              },
            },
          ],
        },
      ],
    };
  }

  static ImageUnderstanding parseResponse(Map<String, Object?> response) {
    final choices = response['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final raw = message is Map ? message['content']?.toString().trim() : null;
    if (raw == null || raw.isEmpty) {
      throw const ImageUnderstandingException('图片理解服务没有返回内容');
    }

    final normalized = raw
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) throw const FormatException('not an object');
      final summary = decoded['summary']?.toString().trim() ?? '';
      if (summary.isEmpty) {
        throw const ImageUnderstandingException('图片概述为空');
      }
      final rawFacts = decoded['facts'];
      final facts = rawFacts is List
          ? rawFacts
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .take(8)
                .toList(growable: false)
          : const <String>[];
      return ImageUnderstanding(summary: summary, facts: facts);
    } on ImageUnderstandingException {
      rethrow;
    } catch (_) {
      throw const ImageUnderstandingException('图片理解结果格式无效，请重试');
    }
  }

  static Future<ImageUnderstanding> analyze(
    File file, {
    Dio? client,
    String? apiKey,
  }) async {
    final bytes = await file.readAsBytes();
    final mimeType = detectMimeType(bytes);
    final key = apiKey ?? await AiService.getApiKey();
    if (key == null || key.isEmpty) {
      throw const ImageUnderstandingException('请先在设置中配置 DeepSeek API Key');
    }

    try {
      final response = await (client ?? Dio()).post<Map<String, Object?>>(
        _endpoint,
        data: buildInlinePayload(bytes: bytes, mimeType: mimeType),
        options: Options(
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final data = response.data;
      if (data == null) {
        throw const ImageUnderstandingException('图片理解服务没有返回内容');
      }
      return parseResponse(data);
    } on ImageUnderstandingException {
      rethrow;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw ImageUnderstandingException(
        status == null ? '图片理解网络连接失败，请重试' : '图片理解请求失败（$status）',
      );
    } catch (_) {
      throw const ImageUnderstandingException('图片理解失败，请重试');
    }
  }

  static Future<StoredImageAttachment> storeLocalCopy(
    File source, {
    Directory? documentsDirectory,
  }) async {
    final bytes = await source.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxInlineImageBytes) {
      throw const ImageUnderstandingException('图片为空或超过 32 MiB 限制');
    }
    final mimeType = detectMimeType(bytes);
    final extension = switch (mimeType) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      _ => throw const ImageUnderstandingException('不支持的图片格式'),
    };
    final documents =
        documentsDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'chat_images'));
    await directory.create(recursive: true);
    final name = '${DatabaseHelper.newId()}$extension';
    final destination = File(p.join(directory.path, name));
    await destination.writeAsBytes(bytes, flush: true);
    return StoredImageAttachment(
      localPath: destination.path,
      mimeType: mimeType,
      sha256Digest: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
    );
  }

  static Future<String> persistUnderstanding({
    required StoredImageAttachment attachment,
    required ImageUnderstanding understanding,
  }) async {
    final db = await DatabaseHelper.database;
    final messageId = DatabaseHelper.newId();
    final attachmentId = DatabaseHelper.newId();
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert('chat_history', {
        'id': messageId,
        'role': 'user',
        'content': understanding.summary,
        'message_type': 'image',
        'metadata_json': jsonEncode({
          'attachment_id': attachmentId,
          'summary': understanding.summary,
        }),
        'request_id': 'image:$messageId',
        'hidden_at': null,
        'created_at': now,
      });
      await txn.insert('chat_attachments', {
        'id': attachmentId,
        'chat_message_id': messageId,
        'local_path': attachment.localPath,
        'mime_type': attachment.mimeType,
        'sha256': attachment.sha256Digest,
        'width': null,
        'height': null,
        'model_summary': understanding.summary,
        'extracted_facts_json': jsonEncode(understanding.facts),
        'status': 'local',
        'created_at': now,
      });
      for (final fact in understanding.facts) {
        await txn.insert('ai_wiki_facts', {
          'id': DatabaseHelper.newId(),
          'category': 'image_observation',
          'entity_id': null,
          'content': fact,
          'source': 'image',
          'importance': 0.65,
          'strength': 1.0,
          'access_count': 0,
          'last_accessed': null,
          'created_at': now,
          'updated_at': now,
        });
      }
    });
    return messageId;
  }

  static String detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 6) {
      final header = ascii.decode(bytes.sublist(0, 6), allowInvalid: true);
      if (header == 'GIF87a' || header == 'GIF89a') return 'image/gif';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    throw const ImageUnderstandingException('仅支持 JPEG、PNG、GIF 或 WebP 图片');
  }
}
