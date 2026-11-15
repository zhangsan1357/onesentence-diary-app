// 本地动物头像（2026-11-16 用户拍板退回的动物图标设计）：
// 评论在密文内、后端不可见 → 本地绘制。seed 确定性选动物（同一刷新周期内
// 同一条评论稳定）；随机性由调用方传入的刷新盐驱动——每次刷新全部换新。
//
// ★ 配置点：生肖头像表（先上 12 生肖，不好看再增删改——每项 (emoji, 底色)，
//   底色走 Tailwind 100/200 系柔和浅底，DiceBear 风格，深浅色模式通用）。
import 'package:flutter/material.dart';

const animalAvatars = <(String, Color)>[
  ('🐭', Color(0xFFE0E7FF)), // 鼠 indigo-200
  ('🐮', Color(0xFFD1FAE5)), // 牛 emerald-100
  ('🐯', Color(0xFFFED7AA)), // 虎 orange-200
  ('🐰', Color(0xFFFBCFE8)), // 兔 pink-200
  ('🐲', Color(0xFFFDE68A)), // 龙 amber-200
  ('🐍', Color(0xFFBBF7D0)), // 蛇 green-200
  ('🐴', Color(0xFFFEF08A)), // 马 yellow-200
  ('🐑', Color(0xFFE5E7EB)), // 羊 gray-200
  ('🐵', Color(0xFFFECACA)), // 猴 red-200
  ('🐔', Color(0xFFFFE4E6)), // 鸡 rose-100
  ('🐶', Color(0xFFBFDBFE)), // 狗 blue-200
  ('🐷', Color(0xFFF0ABFC)), // 猪 fuchsia-200
];

/// 32 位溢出稳定哈希（Java hashCode 同款，乘数 31）：输入任意文本 → 非负整数。
/// 乘数不能用 djb2 的 33（=3×11）：其值恒为 3 的倍数，对 12 生肖取模时
/// 「前缀加盐」会系统性失效（盐前后 mod 12 大概率相同）。
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
    final (emoji, bg) = animalAvatars[stableHash(seed) % animalAvatars.length];
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bg,
        alignment: Alignment.center,
        child: Text(emoji,
            style: TextStyle(fontSize: size * 0.58, height: 1)),
      ),
    );
  }
}
