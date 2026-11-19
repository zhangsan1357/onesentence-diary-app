// 天卡头像·Web 实现（§5.12 本地化 v5；§5.14 签名对齐）：web 无 dart:io 池禁用
//（cravatar 也无 CORS 头）→ 恒默认人像占位（Chrome 预览语义=「本地无图」；
// 真机 iOS 走 IO 实现池命中本地图 / 未命中网络回落）。url/ensure 参数仅签名
// 对齐，web 不消费。
import 'package:flutter/material.dart';

import '../features/theme/tokens.dart';

class DayCardAvatar extends StatelessWidget {
  final String? poolPath;
  final String? url;
  final void Function()? ensure;
  final double size;

  const DayCardAvatar({
    super.key,
    required this.poolPath,
    this.url,
    this.ensure,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(shape: BoxShape.circle, color: Tokens.fill(b)),
      child: Icon(Icons.person, size: size * .5, color: Tokens.label3(b)),
    );
  }
}
