// 头像预下载池·Web 实现：无 dart:io，池禁用——渲染恒默认人像占位
//（§5.12 本地化语义：本地无图 → 默认人像，Chrome 预览不再走网络头像）。
import 'package:flutter/foundation.dart';

import 'avatar_pool_core.dart';

class AvatarPool {
  Future<void> start() async {}
  void stop() {}

  /// 池禁用（enabled=false）：设置页显示「未启用」，渲染走默认人像。
  final ValueNotifier<PoolProgress> progress =
      ValueNotifier<PoolProgress>(const PoolProgress(
          filled: 0, total: kAvatarPoolSize, enabled: false));

  String? pathFor(int index) => null;

  // §5.14：web 无种子清单（cravatar 也无 CORS 头，CanvasKit 加载必失败）→
  // URL 恒 null、ensureIndex no-op——渲染恒默认人像占位。
  String? urlForIndex(int index) => null;

  Future<void> ensureIndex(int index) async {}
}

AvatarPool createAvatarPool() => AvatarPool();
