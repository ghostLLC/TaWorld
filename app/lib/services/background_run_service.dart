import '../data/local/database_helper.dart';

abstract final class BackgroundRunService {
  static Future<String> start(String task) async {
    final db = await DatabaseHelper.database;
    final id = DatabaseHelper.newId();
    await db.insert('background_runs', {
      'id': id,
      'task': task,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'outcome': 'running',
    });
    return id;
  }

  static Future<void> finish(
    String id,
    String outcome, {
    String? detail,
  }) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'background_runs',
      {
        'outcome': outcome,
        'detail': detail,
        'finished_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete(
      'background_runs',
      where: 'started_at < ?',
      whereArgs: [
        DateTime.now()
            .subtract(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
      ],
    );
  }
}
