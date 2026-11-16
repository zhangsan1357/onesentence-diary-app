// 天卡头像·IO 实现（晨 18 §2.7 v4）：池优先、接口链路回落。
import 'dart:io';

import 'package:flutter/material.dart';

import 'net_avatar.dart';

class DayCardAvatar extends StatelessWidget {
  final String? poolPath; // 池文件绝对路径（null/空 = 池未就绪或该格未下载）
  final String? url; // 后端 EntryVO.avatar（回落链路）
  final double size;

  const DayCardAvatar({
    super.key,
    required this.poolPath,
    required this.url,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final p = poolPath;
    if (p == null || p.isEmpty) return NetAvatar(url: url, size: size);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(p),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(), // s=184 源图 1:1 解码
        ),
      ),
    );
  }
}
