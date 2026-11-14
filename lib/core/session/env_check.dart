// 平台环境检测（条件导入：web 不依赖 dart:io）。
export 'env_check_io.dart' if (dart.library.js_interop) 'env_check_web.dart';
