import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

Future<QueryExecutor> openLocalDatabaseExecutor() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(path.join(directory.path, 'mobileshop_saas.sqlite'));
  return NativeDatabase.createInBackground(file);
}
