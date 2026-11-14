// IO 平台：flutter_test 会注入 FLUTTER_TEST 环境变量（官方约定）。
import 'dart:io';

bool isTestEnv() => Platform.environment.containsKey('FLUTTER_TEST');
