// 第三方随机头像（2026-11-15 用户拍板：不要本地预制表情，用第三方随机头像）。
// 服务选 DiceBear bottts——本网络实测 200 可达且带 access-control-allow-origin:*：
// cravatar 不带 CORS 头（web 预览两次灰掉的根因）、gravatar 本网络超时、pravatar 403。
// seed 确定性 → 同一条目/评论永远同一张；加载中/失败回落中性人形占位（不显示文字）。
import 'package:flutter/material.dart';

import '../features/theme/tokens.dart';

class NetAvatar extends StatelessWidget {
  final String seed;
  final double size;

  const NetAvatar({super.key, required this.seed, required this.size});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          'https://api.dicebear.com/9.x/bottts/png'
          '?seed=${Uri.encodeComponent(seed)}&size=80',
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) =>
              progress == null ? child : _placeholder(b),
          errorBuilder: (_, _, _) => _placeholder(b),
        ),
      ),
    );
  }

  Widget _placeholder(Brightness b) => Container(
        color: Tokens.fill(b),
        child: Icon(Icons.person, size: size * .5, color: Tokens.label3(b)),
      );
}
