// 头像 URL 助手：md5(seed) → https://cn.cravatar.com/avatar/<hex>.png
// （沿用 linkBoy CravatarUtil → 后端 AvatarUtil 的同源做法，任意 MD5 hex 都有头像）。
// 域名注意（2026-11-15 实测）：cravatar.cn 入口会 301 → cn.cravatar.com，而 301
// 那一跳不带 CORS 头，Flutter web（CanvasKit 必须过 CORS）两轮灰掉；直连源站
// cn.cravatar.com 200 + access-control-allow-origin:*，浏览器 fetch 实测通过。
// iOS 无 CORS 概念，直连同样更快（省一次跳转）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/md5.dart';

import '../e2ee/bytes.dart';

String avatarUrl(String seed) {
  final digest =
      MD5Digest().process(Uint8List.fromList(utf8.encode(seed)));
  return 'https://cn.cravatar.com/avatar/${hexEncode(digest)}.png';
}
