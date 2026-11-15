// 网络头像（2026-11-15 用户拍板：URL 事实源在后端，客户端只消费不拼装、
// 不改 host——301 由网络栈自动跟随，iOS 无 CORS 概念完全正常；
// 后端保证返回有效图片）。尺寸适配：s= 参数按显示尺寸规范化（3x 屏 1:1，
// 省流量且清晰；同 hash 不同 s 是同一张图的不同分辨率，图案不变），
// 圆形裁剪 + cover 按 size（天卡 40 / 评论 24）适配；
// url 缺失或加载中/失败回落中性人形占位（不显示文字）。
// demo 与评论（密文内、后端不可见）用 core/util/avatar.dart 同款模板本地拼。
// 注：web 预览受浏览器 CORS 限制，cravatar 系 CDN 的 ACAO 头随缓存状态漂移，
// 预览可用性见 PROGRESS（真机不受影响）。
import 'package:flutter/material.dart';

import '../features/theme/tokens.dart';

class NetAvatar extends StatelessWidget {
  final String? url;
  final double size;

  const NetAvatar({super.key, required this.url, required this.size});

  /// 按显示尺寸规范化 s= 参数（已有则覆盖、没有则追加）：3x 屏 1:1 像素。
  static String sized(String u, double size) {
    final px = (size * 3).round();
    final uri = Uri.parse(u);
    final q = Map<String, String>.from(uri.queryParameters);
    q['s'] = '$px';
    return uri.replace(queryParameters: q).toString();
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    if (url == null || url!.isEmpty) return _placeholder(b);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          sized(url!, size),
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) =>
              progress == null ? child : _placeholder(b),
          errorBuilder: (_, _, _) => _placeholder(b),
        ),
      ),
    );
  }

  Widget _placeholder(Brightness b) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Tokens.fill(b)),
        child: Icon(Icons.person, size: size * .5, color: Tokens.label3(b)),
      );
}
