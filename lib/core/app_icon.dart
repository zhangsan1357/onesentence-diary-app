// App 图标切换（2026-11-16，iOS 备用图标机制）：真机生效，iOS 系统会弹确认框。
// 入口仅 iOS 显示（me_page 用 supported 门控）；get 通道异常静默降级为 null
// （web 预览 / 热重载期原生侧未注册等边界）。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppIcon {
  static const _channel = MethodChannel('app.icon');

  /// 备用图标（名字与 Assets.xcassets 的 appiconset 一致）：id + 显示名 + 预览资产。
  static const choices = <(String, String, String)>[
    ('AppIconNight', '暗夜少女', 'assets/appicon/night.png'),
    ('AppIconPatrick', '派大星', 'assets/appicon/patrick.png'),
    ('AppIconSponge', '海绵宝宝', 'assets/appicon/sponge.png'),
  ];

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 当前备用图标名（从未换过 / 默认 → null）。
  static Future<String?> current() async {
    try {
      return await _channel.invokeMethod<String>('get');
    } on Exception {
      return null;
    }
  }

  /// [name] null = 恢复默认（原生侧映射 setAlternateIconName(nil)）。
  static Future<void> set(String? name) async {
    await _channel.invokeMethod('set', {'name': name ?? ''});
  }
}
