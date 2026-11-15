// 第三方随机头像（2026-11-15 用户拍板：不要本地预制表情，用 cravatar 第三方头像）。
// 源站直连 cn.cravatar.com（access-control-allow-origin:*，浏览器 fetch 实测通过；
// cravatar.cn 入口 301 不带 CORS 头导致 web 预览两次灰掉，详见 core/util/avatar.dart）。
// seed 确定性 → 同一条目/评论永远同一张；加载中/失败回落中性人形占位（不显示文字）。
import 'package:flutter/material.dart';

import '../core/util/avatar.dart';
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
          avatarUrl(seed),
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
