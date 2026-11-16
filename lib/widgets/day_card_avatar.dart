// 天卡头像（晨 18 §2.7 v4）：池文件存在 → Image.file 本地直读（零网络零等待，
// ClipOval 与 NetAvatar 同视觉）；缺失 → 回退 NetAvatar（EntryVO.avatar + 方案 D）。
export 'day_card_avatar_io.dart' if (dart.library.js_interop) 'day_card_avatar_web.dart';
