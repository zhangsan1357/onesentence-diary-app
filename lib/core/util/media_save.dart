// 保存图片到系统相册·门面（晨 19 §5.3）：条件导入（原生 = gal 插件 / web 桩），
// 平台差异收敛单文件（AGENTS 原生翻译友好约束 #3，env_check/avatar_pool 同款）。
export 'media_save_io.dart' if (dart.library.js_interop) 'media_save_web.dart';
