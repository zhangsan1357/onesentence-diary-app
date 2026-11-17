// 天卡头像·IO 实现（晨 18 §2.7 v4 建；晨 19 §5.12 本地化 v5）：
// 池文件存在 → Image.file 本地直读（零网络零等待）；缺失 → 默认人像占位
//（本地绘制，零网络零等待——渲染路径不再有任何网络头像）。
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/theme/tokens.dart';

class DayCardAvatar extends StatelessWidget {
  final String? poolPath; // 池文件绝对路径（null/空 = 池未就绪或该格未下载）
  final double size;

  const DayCardAvatar({
    super.key,
    required this.poolPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final p = poolPath;
    if (p == null || p.isEmpty) return _placeholder(b);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(p),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(), // s=184 源图 1:1 解码
          errorBuilder: (_, _, _) => _placeholder(b), // 文件异常本地兜底
        ),
      ),
    );
  }

  /// 默认人像占位（视觉与 NetAvatar 占位一致：灰圆 + person）。
  Widget _placeholder(Brightness b) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: Tokens.fill(b)),
        child: Icon(Icons.person, size: size * .5, color: Tokens.label3(b)),
      );
}
