// Widget 数据快照·门面（晨 19 §5.5）：纯函数契约（本文件）+ 条件导出平台写入
// （原生 = home_widget / web = 空操作）。原生翻译友好约束 #3 同款模式。
export 'widget_snapshot_core.dart';
export 'widget_snapshot_io.dart' if (dart.library.js_interop) 'widget_snapshot_web.dart';
