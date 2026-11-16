// Widget 快照写入·IO 实现（晨 19 §5.5）：home_widget 桥 iOS App Group 键值。
// 纯增强模式（同头像池 §2.7）：无 App Group entitlement/插件不可用 → 静默失败，
// 绝不影响主流程。entitlements 与 WidgetKit extension 等 Mac 后实现（Windows
// 无法编译 Swift）；Dart 侧先上无副作用。
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 注入点（测试预留）：write 逐键写、update 触发 Widget 刷新。
Future<void> saveWidgetSnapshot(
  Map<String, String> values, {
  Future<bool> Function(String key, String? value)? write,
  Future<bool> Function()? update,
}) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return; // 仅 iOS；测试注入可绕过
  try {
    final w = write ??
        (k, v) async {
          final ok = await HomeWidget.saveWidgetData<String>(k, v);
          return ok ?? false;
        };
    final u = update ??
        () async {
          final ok = await HomeWidget.updateWidget(name: 'DiaryWidget');
          return ok ?? false;
        };
    for (final e in values.entries) {
      await w(e.key, e.value);
    }
    await u();
  } catch (_) {
    // 无 entitlement/插件异常：静默（纯增强）
  }
}
