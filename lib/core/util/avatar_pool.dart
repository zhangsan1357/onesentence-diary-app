// 头像预下载池·门面（晨 18 §2.7 v4）：平台无关核心 + IO/Web 条件实现。
// 池枚举与后端 AvatarUtil.ofRandomQQ 同款（随机 QQ 号 → email → md5 → cravatar），
// 后台静默分批下载，渲染按 stableHash(盐|dateKey) 随机取格、缺失回落接口链路。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'avatar_pool_io.dart' if (dart.library.js_interop) 'avatar_pool_web.dart';
export 'avatar_pool_io.dart' if (dart.library.js_interop) 'avatar_pool_web.dart';

export 'avatar_pool_core.dart';

/// 全局单例（会话 init 启动一次；feed 渲染同步查格）。
final avatarPoolProvider = Provider<AvatarPool>((ref) {
  final pool = createAvatarPool();
  ref.onDispose(pool.stop);
  return pool;
});
