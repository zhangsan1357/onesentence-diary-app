// 天卡头像·IO 实现（晨 18 §2.7 v4 建；晨 19 §5.12 本地化 v5；§5.14 按需回落）：
// 池文件存在 → Image.file 本地直读（零网络零等待）；缺失且有回落 URL →
// Image.network 即时加载（加载中/失败仍默认人像）+ 挂载时触发一次池补写
//（ensureIndex 原子写回池，下次本地直读）；无 URL（池未启动）→ 默认人像。
import 'dart:io';

import 'package:flutter/material.dart';

import '../features/theme/tokens.dart';

class DayCardAvatar extends StatefulWidget {
  final String? poolPath; // 池文件绝对路径（null/空 = 池未就绪或该格未下载）
  final String? url; // 该格回落 URL（null = 平台无池/种子未就绪）
  final void Function()? ensure; // 挂载时补写池（fire-and-forget，幂等）
  final double size;

  const DayCardAvatar({
    super.key,
    required this.poolPath,
    this.url,
    this.ensure,
    required this.size,
  });

  @override
  State<DayCardAvatar> createState() => _DayCardAvatarState();
}

class _DayCardAvatarState extends State<DayCardAvatar> {
  @override
  void initState() {
    super.initState();
    // 挂载即补池（build 之外的副作用点；ensureIndex 自身幂等+在途去重）
    if (widget.poolPath == null || widget.poolPath!.isEmpty) {
      widget.ensure?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final w = widget;
    final p = w.poolPath;
    if (p != null && p.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: w.size,
          height: w.size,
          child: Image.file(
            File(p),
            fit: BoxFit.cover,
            cacheWidth: (w.size * 3).round(), // s=184 源图 1:1 解码
            errorBuilder: (_, _, _) => _placeholder(b), // 文件异常本地兜底
          ),
        ),
      );
    }
    final url = w.url;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: w.size,
          height: w.size,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(b), // 无网/被墙 → 占位
          ),
        ),
      );
    }
    return _placeholder(b);
  }

  /// 默认人像占位（视觉与 NetAvatar 占位一致：灰圆 + person）。
  Widget _placeholder(Brightness b) => Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(shape: BoxShape.circle, color: Tokens.fill(b)),
        child: Icon(Icons.person, size: widget.size * .5, color: Tokens.label3(b)),
      );
}
