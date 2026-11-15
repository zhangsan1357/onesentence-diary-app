// 头像 URL 助手：md5(seed) → https://cravatar.cn/avatar/<hex>.png
// （沿用 linkBoy CravatarUtil → 后端 AvatarUtil 的同源做法，任意 MD5 hex 都有头像）。
// 用途边界：后端条目头像是响应时随机生成（EntryVO.avatar，不落库、每次请求不同，
// 树洞匿名风）；客户端此助手仅用于 demo 数据展示与评论装饰（评论在密文载荷内，
// 用评论身份做确定性种子——同一条评论头像稳定且互不相同，不破坏「云端只见密文」）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/md5.dart';

import '../e2ee/bytes.dart';

String avatarUrl(String seed) {
  final digest =
      MD5Digest().process(Uint8List.fromList(utf8.encode(seed)));
  return 'https://cravatar.cn/avatar/${hexEncode(digest)}.png';
}
