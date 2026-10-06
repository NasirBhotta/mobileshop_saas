export 'local_database_executor_unsupported.dart'
    if (dart.library.io) 'local_database_executor_native.dart'
    if (dart.library.js_interop) 'local_database_executor_web.dart';
