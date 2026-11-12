import 'package:sqflite/sqflite.dart';

/// Phones use sqflite's own database; see db_factory_web.dart for browsers.
DatabaseFactory? get webDatabaseFactory => null;
