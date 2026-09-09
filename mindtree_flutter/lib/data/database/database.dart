import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'mindtree_db.dart';

/// Opens the MindTree SQLite database in the platform data directory.
Future<MindtreeDb> openDatabase() async {
  final dir = await getApplicationSupportDirectory();
  final file = File(p.join(dir.path, 'mindtree.db'));
  return MindtreeDb(NativeDatabase.createInBackground(file));
}
