// 本地动物头像（2026-11-16 用户拍板：退回原版动物图标设计，评论场景不要底色）：
// 评论在密文内、后端不可见 → 本地绘制。seed 确定性选动物（同一刷新周期内
// 同一条评论稳定）；随机性由调用方传入的刷新盐驱动——每次刷新全部换新。
// 渲染为裸 emoji（无底色圆），沿用 d776648 原版 SeedAvatar 的 20 动物脸表。
import 'package:flutter/material.dart';

/// ★ 配置点：动物头像表（原版 20 种，增删改直接动这张表）。
const animalFaces = <String>[
  '🐰', '🐱', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷',
  '🐸', '🐵', '🐧', '🦉', '🦄', '🐙', '🐢', '🐳', '🦋', '🐝',
];

/// 32 位溢出稳定哈希（Java hashCode 同款，乘数 31）：输入任意文本 → 非负整数。
/// 乘数不能用 djb2 的 33（=3×11）：其值恒为 3 的倍数，对表长取模时
/// 「前缀加盐」会系统性失效（盐前后 mod N 大概率相同）。
int stableHash(String s) {
  var h = 5381;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

class AnimalAvatar extends StatelessWidget {
  final String seed;
  final double size;

  const AnimalAvatar({super.key, required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final face = animalFaces[stableHash(seed) % animalFaces.length];
    return Text(face,
        style: TextStyle(fontSize: size, height: 1),
        overflow: TextOverflow.visible);
  }
}
