// IO 平台：NativeDatabase 落盘到应用文档目录。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'database.dart';

Future<LocalStore> openLocalStore() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}diary.sqlite');
  return DriftLocalStore(AppDb(NativeDatabase(file)));
}
