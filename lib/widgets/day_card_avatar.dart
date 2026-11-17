// 天卡头像（晨 18 §2.7 v4 建；晨 19 §5.12 本地化 v5）：池文件存在 → Image.file
// 本地直读（零网络零等待）；缺失 → 默认人像占位（本地绘制，零网络）。
export 'day_card_avatar_io.dart' if (dart.library.js_interop) 'day_card_avatar_web.dart';
