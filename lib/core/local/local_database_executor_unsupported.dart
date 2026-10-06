import 'package:drift/drift.dart';

Future<QueryExecutor> openLocalDatabaseExecutor() =>
    Future.error(UnsupportedError('Local database is not supported here.'));
