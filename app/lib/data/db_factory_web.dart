import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// In a browser the database is SQLite compiled to WebAssembly, kept in the
/// browser's own storage (web/sqlite3.wasm and web/sqflite_sw.js).
DatabaseFactory? get webDatabaseFactory => databaseFactoryFfiWeb;
