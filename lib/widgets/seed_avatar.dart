// 本地确定性头像（2026-11-15 用户拍板替代远端 cravatar）：web 预览受 CORS 限制、
// 真机受网络波动，网络头像两次都渲染成灰色占位。改为颜色+表情由种子哈希决定——
// 与标签色同源哈希（AppDefaults.stableHash），同种子稳定、跨端一致、零网络依赖。
import 'package:flutter/material.dart';

import '../core/config/app_defaults.dart';

class SeedAvatar extends StatelessWidget {
  final String seed;
  final double size;

  const SeedAvatar({super.key, required this.seed, required this.size});

  static const _faces = [
    '🐰', '🐱', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷',
    '🐸', '🐵', '🐧', '🦉', '🦄', '🐙', '🐢', '🐳', '🦋', '🐝',
  ];

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final h = AppDefaults.stableHash(seed);
    final color = Color(AppDefaults.tagColorHex[AppDefaults.tagColorNames[h % 8]]!);
    final face = _faces[(h ~/ 8) % _faces.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: b == Brightness.dark ? .30 : .16),
      ),
      child: Text(face, style: TextStyle(fontSize: size * .52, height: 1)),
    );
  }
}
