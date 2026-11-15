// 头像 URL 助手：md5(seed) → 与后端定稿格式一字不差的头像链接。
// 用途边界（2026-11-15 用户拍板：头像 URL 事实源在后端，条目头像直接消费
// EntryVO.avatar，客户端不拼装）：本助手仅用于 demo 数据与评论头像——评论在
// 端上密文内、后端不可见，只能客户端按评论身份（who|time|text）确定性拼装。
// 后端调整 URL 规则时，同步改此一处模板。
// 技术注记：cravatar.cn 入口 301 不带 CORS 头（web 预览灰掉的根因），模板直连
// cn.cravatar.com（access-control-allow-origin:*，浏览器 fetch 实测通过）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/md5.dart';

import '../e2ee/bytes.dart';

String avatarUrl(String seed) {
  final digest =
      MD5Digest().process(Uint8List.fromList(utf8.encode(seed)));
  return 'https://cn.cravatar.com/avatar/${hexEncode(digest)}.png';
}
