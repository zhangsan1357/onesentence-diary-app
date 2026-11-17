// 头像预下载池·平台无关核心（晨 18 §2.7 v4）。
// 枚举逻辑与后端 AvatarUtil.ofRandomQQ 完全一致（用户拍板：不要自定义种子）：
// 随机 QQ 号（双闭区间）→ "%s@qq.com" → md5 → cravatar URL——同一邮箱空间，
// 池图像与接口图像同源同分布，不存在「池里有接口永远不会出的图」。
// 黄金向量：md5('798969707@qq.com') = dedf817b2bf150463aca1693856ad6e8
//（后端 AvatarUtil.main 示例号）。
import '../../widgets/animal_avatar.dart' show stableHash;
import 'avatar.dart';

/// 池容量（用户拍板 1w 张；s=184 约 5KB/张 ≈ 50MB 磁盘）。
const int kAvatarPoolSize = 10000;

/// 池图像下载尺寸参数（56pt 天卡 @3x 1:1 像素）。
const String kAvatarPoolSizeParam = '184';

/// 与后端 RandomUtil.randomInt(123456789, 987654321, true, true) 一致的双闭区间。
const int kQqMin = 123456789;
const int kQqMax = 987654321;

/// 池索引：key = 盐|dateKey → stableHash（与评论头像/标签色同源哈希）→
/// 非负取模——同 key 同格（同一刷新周期稳定），盐重掷即随机换格。
int avatarPoolIndex(String key) =>
    (stableHash(key) & 0x7fffffff) % kAvatarPoolSize;

/// 池图像 URL：md5(email) → cn.cravatar.com 直连（免 301，客户端既定 host）+ s=184。
String avatarPoolUrl(String email) =>
    '${avatarUrl(email)}?s=$kAvatarPoolSizeParam';

/// 池进度快照（晨 19 §5.12 设置页查看）：filled=已就绪张数，total=池容量，
/// enabled=本平台池是否启用（web 无 dart:io → false）。纯值类，const 相等
/// 判断供 ValueNotifier 去重。
class PoolProgress {
  final int filled;
  final int total;
  final bool enabled;
  const PoolProgress({
    required this.filled,
    required this.total,
    this.enabled = true,
  });

  @override
  bool operator ==(Object other) =>
      other is PoolProgress &&
      other.filled == filled &&
      other.total == total &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(filled, total, enabled);
}
