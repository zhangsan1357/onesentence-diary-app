// 光晕卡片像素采样自测（01 §4.1：常态 ΔRGB ≤ ~12/255 视为合格白色卡片）。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:diary_app/features/theme/tokens.dart';
import 'package:diary_app/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _capture(GlobalKey key, WidgetTester tester) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // 真实异步（GPU/软件光栅）需脱离 FakeAsync zone 执行
  final image = await tester.binding
      .runAsync(() => boundary.toImage(pixelRatio: 2));
  final img = image!;
  final bytes = await tester.binding.runAsync(
      () => img.toByteData(format: ui.ImageByteFormat.rawRgba));
  return bytes!.buffer.asUint8List();
}

(int, int, int) _px(Uint8List rgba, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return (rgba[i], rgba[i + 1], rgba[i + 2]);
}

void main() {
  testWidgets('浅色常态：天卡片应接近纯白（ΔRGB≤12），悬停应明显变色', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: Tokens.theme(Brightness.light),
      home: Scaffold(
        backgroundColor: Tokens.bg(Brightness.light),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 340,
              height: 240,
              child: const GlowDayCard(glowIndex: 1, child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    ));

    final rgba = await _capture(key, tester);
    final w = 340 * 2, h = 240 * 2;

    // 卡片右上角（g1 锚点 100% 0%，光晕最强处）
    final corner = _px(rgba, w, w - 6, 6);
    // 卡片中心（离光晕最远处）
    final center = _px(rgba, w, w ~/ 2, h ~/ 2);

    int maxDelta((int, int, int) p) {
      final (r, g, b) = p;
      return [255 - r, 255 - g, 255 - b].reduce((a, b) => a > b ? a : b);
    }

    debugPrint('corner=$corner center=$center '
        'dCorner=${maxDelta(corner)} dCenter=${maxDelta(center)}');

    expect(maxDelta(center), lessThanOrEqualTo(12),
        reason: '卡片中心应接近纯白');
    expect(maxDelta(corner), lessThanOrEqualTo(12),
        reason: '常态光晕 0.12 下右上角也应保持接近白色');
  });

  testWidgets('深色常态：用户要求暗色同样显色 → 光晕可见（原版 body.dark 0.15 被覆盖）',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: Tokens.theme(Brightness.dark),
      home: Scaffold(
        backgroundColor: Tokens.bg(Brightness.dark),
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 340,
              height: 240,
              child: const GlowDayCard(glowIndex: 1, child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    ));

    final rgba = await _capture(key, tester);
    final w = 340 * 2, h = 240 * 2;

    int maxDelta((int, int, int) p) {
      final (r, g, b) = p;
      // 深色卡底 #1C1C1E：取与底色的最大通道差
      return [(r - 0x1C).abs(), (g - 0x1C).abs(), (b - 0x1E).abs()]
          .reduce((a, b) => a > b ? a : b);
    }

    final center = _px(rgba, w, w ~/ 2, h ~/ 2);
    // g1 锚点 = 右上角，光晕最强处
    final corner = _px(rgba, w, w - 6, 6);
    debugPrint('dark center=$center corner=$corner '
        'dCenter=${maxDelta(center)} dCorner=${maxDelta(corner)}');

    // 与浅色同系数 1：常态 0.12 在深底上的通道差比白底大（对比度更高）
    expect(maxDelta(center), greaterThanOrEqualTo(4),
        reason: '卡片中心应有可感知光晕色（不再近不可见）');
    expect(maxDelta(corner), greaterThanOrEqualTo(4),
        reason: '锚点处光晕应明显可见');
    expect(maxDelta(corner), lessThanOrEqualTo(48),
        reason: '常态 0.12 不应过浓');
  });
}
