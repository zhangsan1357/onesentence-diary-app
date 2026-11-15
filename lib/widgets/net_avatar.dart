// 网络头像（2026-11-15 用户拍板：URL 事实源在后端，客户端只消费不拼装、
// 不改 host——301 由网络栈自动跟随，iOS 无 CORS 概念完全正常；
// 后端保证返回有效图片）。尺寸适配：s= 参数按显示尺寸规范化（3x 屏 1:1，
// 省流量且清晰；同 hash 不同 s 是同一张图的不同分辨率，图案不变）。
// 淡入占位（2026-11-16 晨 15 方案 D，真机反馈头像刷新慢）：占位垫底 +
// 图就绪 250ms 淡入——加载中只见灰色人形、不再「灰圆突跳成图」；
// 预取命中（feed 头像预热）时首帧即 progress==null，无动画直接显示。
// url 缺失或加载失败回落中性人形占位（不显示文字）。
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            _placeholder(b), // 底层占位：加载中/失败都由它兜住，无空窗
            Image.network(
              sized(url!, size),
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => AnimatedOpacity(
                opacity: progress == null ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: child,
              ),
              errorBuilder: (_, _, _) => const SizedBox.shrink(), // 底层占位仍在
            ),
          ],
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
