import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:taworld/data/local/database_helper.dart';

Future<void> openTestDatabase({String path = inMemoryDatabasePath}) async {
  sqfliteFfiInit();
  await DatabaseHelper.configureForTesting(
    factory: databaseFactoryFfi,
    path: path,
  );
  await DatabaseHelper.database;
}

Future<void> closeTestDatabase() async {
  await DatabaseHelper.resetForTesting();
}
