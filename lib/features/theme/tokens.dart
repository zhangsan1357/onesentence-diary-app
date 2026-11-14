// 设计 token：mockup v2 CSS 变量 1:1 映射（01 手册 §4 视觉规格）。
// ⚠️ 光晕透明度用 Theme.brightness 判定取值，不用数字上下文的动态技巧（01 §4.1 教训）。
import 'package:flutter/material.dart';

class Tokens {
  Tokens._();

  // 表面色（light-dark）
  static const bgLight = Color(0xFFF2F2F7);
  static const bgDark = Color(0xFF000000);
  static const cardLight = Color(0xFFFFFFFF);
  static const cardDark = Color(0xFF1C1C1E);
  static const fillLight = Color(0x1F767680); // rgba(118,118,128,.12)
  static const fillDark = Color(0x3E787880); // rgba(120,120,128,.24)
  static const labelLight = Color(0xFF000000);
  static const labelDark = Color(0xFFF2F2F7);
  static final label2Light = const Color(0xFF3C3C43).withValues(alpha: .62);
  static final label2Dark = const Color(0xFFEBEBF5).withValues(alpha: .62);
  static final label3Light = const Color(0xFF3C3C43).withValues(alpha: .34);
  static final label3Dark = const Color(0xFFEBEBF5).withValues(alpha: .34);
  static final sepLight = const Color(0xFF3C3C43).withValues(alpha: .29);
  static final sepDark = const Color(0xFF545458).withValues(alpha: .65);

  static const blueLight = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0A84FF);
  static const redLight = Color(0xFFFF3B30);
  static const redDark = Color(0xFFFF453A);
  static const orangeLight = Color(0xFFFF9500);
  static const orangeDark = Color(0xFFFF9F0A);
  static const green = Color(0xFF34C759);

  // ---------- 语义化（按 brightness 取值） ----------
  static Color bg(Brightness b) =>
      b == Brightness.light ? bgLight : bgDark;
  static Color card(Brightness b) =>
      b == Brightness.light ? cardLight : cardDark;
  static Color fill(Brightness b) =>
      b == Brightness.light ? fillLight : fillDark;
  static Color label(Brightness b) =>
      b == Brightness.light ? labelLight : labelDark;
  static Color label2(Brightness b) =>
      b == Brightness.light ? label2Light : label2Dark;
  static Color label3(Brightness b) =>
      b == Brightness.light ? label3Light : label3Dark;
  static Color sep(Brightness b) =>
      b == Brightness.light ? sepLight : sepDark;
  static Color blue(Brightness b) =>
      b == Brightness.light ? blueLight : blueDark;
  static Color red(Brightness b) =>
      b == Brightness.light ? redLight : redDark;
  static Color orange(Brightness b) =>
      b == Brightness.light ? orangeLight : orangeDark;

  /// 光晕透明度（常态/悬停）。浅色 0.12/0.30（01 §4.1 原版）；
  /// 深色按用户要求单独放大（原版 body.dark ×0.15 在深底上近不可见——
  /// 光晕色距深底更近，同系数实测 ΔRGB 仅 2~4，2026-11-14 放开为 0.40/0.55）。
  static double glowBaseOpacity(Brightness b) =>
      b == Brightness.light ? 0.12 : 0.40;
  static double glowHotOpacity(Brightness b) =>
      b == Brightness.light ? 0.30 : 0.55;

  // ---------- 8 组光晕（mockup .od2-daycard.gN::before 1:1） ----------
  static const glowAnchors = [
    (Alignment.topRight, Color(0xFF60A5FA), Color(0xFF3B82F6)), // g1
    (Alignment.bottomLeft, Color(0xFF34D399), Color(0xFF10B981)), // g2
    (Alignment.topLeft, Color(0xFFF472B6), Color(0xFFEC4899)), // g3
    (Alignment.bottomRight, Color(0xFFA78BFA), Color(0xFF8B5CF6)), // g4
    (Alignment.centerRight, Color(0xFFFBBF24), Color(0xFFF59E0B)), // g5
    (Alignment(0.6, -0.8), Color(0xFFEF4444), Color(0xFFEF4444)), // g6 80% 10%
    (Alignment.bottomCenter, Color(0xFFEC4899), Color(0xFFEC4899)), // g7
    (Alignment.centerLeft, Color(0xFF06B6D4), Color(0xFF06B6D4)), // g8
  ];

  /// 休/班徽章底色。
  static Color badgeOffBg(Brightness b) => (b == Brightness.light
          ? const Color(0xFFFF3B30)
          : const Color(0xFFFF453A))
      .withValues(alpha: b == Brightness.light ? .13 : .22);
  static Color badgeBanBg(Brightness b) => (b == Brightness.light
          ? const Color(0xFFFF9500)
          : const Color(0xFFFF9F0A))
      .withValues(alpha: b == Brightness.light ? .15 : .22);

  static ThemeData theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: b == Brightness.light ? blueLight : blueDark,
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg(b),
      brightness: b,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI'],
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? green
              : (b == Brightness.light
                  ? const Color(0x52BCBCC2) // rgba(120,120,128,.32)
                  : const Color(0x58787880)),
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      dividerTheme: DividerThemeData(color: sep(b), thickness: .5),
    );
  }
}
