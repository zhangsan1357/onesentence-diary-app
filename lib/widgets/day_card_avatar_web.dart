// 天卡头像·Web 实现：池禁用（无 dart:io），恒走 NetAvatar 网络链路。
import 'package:flutter/material.dart';

import 'net_avatar.dart';

class DayCardAvatar extends StatelessWidget {
  final String? poolPath;
  final String? url;
  final double size;

  const DayCardAvatar({
    super.key,
    required this.poolPath,
    required this.url,
    required this.size,
  });

  @override
  Widget build(BuildContext context) => NetAvatar(url: url, size: size);
}
