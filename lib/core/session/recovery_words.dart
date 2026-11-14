// 12 恢复词（BIP39 中文简体标准词表）：生成 / 规范化 / 校验 / 派生。
// 生成：128 位随机熵 + 4 位校验和（SHA-256(熵) 首字节高 4 位）→ 132 位 → 12×11 位索引 → 12 词。
// 校验：换词/错序等抄写错误约 15/16 概率被校验和拒绝，校验通过才允许派生身份（② 的「校验」前置半场）。
// 派生：seed = SHA-256(规范短语 utf8) → X25519 确定性密钥对（见 crypto_session.sessionFromIdentity）。
// 「或其派生密钥」：64 位 hex 直接作为 seed 导入，与短语等价（往返一致）。
import 'dart:convert';
import 'dart:typed_data';

import '../e2ee/bytes.dart';
import '../e2ee/kdf.dart';
import 'bip39_zh.dart';

class RecoveryWords {
  RecoveryWords._();

  static const wordlist = bip39Zh;
  static final _split = RegExp(r'\s+');
  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// 是否为 64 位 hex 派生密钥（导入时与 12 词短语二选一）。
  static bool looksLikeHexKey(String s) => _hex64.hasMatch(s.trim());

  /// 规范短语：任意空白分隔 → 单空格连接；词数不是 12 返回 null。
  static String? canonicalPhrase(String input) {
    final ws = input.trim().split(_split)..removeWhere((w) => w.isEmpty);
    return ws.length == 12 ? ws.join(' ') : null;
  }

  /// 生成 12 恢复词（单空格连接，可过 validate）。
  static String generate() => _phraseFromEntropy(randomBytes(16));

  /// 校验 12 词：全部在词表内 + 校验和匹配。失败抛 FormatException（消息可直接展示）。
  static void validate(String phrase) {
    final canonical = canonicalPhrase(phrase);
    if (canonical == null) {
      throw const FormatException('恢复词需要 12 个词（用空格分隔）');
    }
    final bits = StringBuffer();
    for (final w in canonical.split(' ')) {
      final i = wordlist.indexOf(w);
      if (i < 0) {
        throw FormatException('恢复词「$w」不在词表内（有错字或用了别处的词）');
      }
      bits.write(_bits(i, 11));
    }
    final all = bits.toString();
    final ent = _bytesFromBits(all.substring(0, 128));
    final expect = _bits(sha256Bytes(ent)[0] >> 4, 4);
    if (all.substring(128) != expect) {
      throw const FormatException('恢复词校验不通过（有抄写错误，请核对顺序）');
    }
  }

  /// 恢复词短语 → 32B seed（SHA-256(规范短语)）。调用前应先 validate。
  static Uint8List phraseToSeed(String phrase) {
    final canonical = canonicalPhrase(phrase) ?? phrase.trim();
    return sha256Bytes(utf8.encode(canonical));
  }

  // ---------- 内部：BIP39 位打包 ----------

  static String _phraseFromEntropy(Uint8List ent) {
    final cs = sha256Bytes(ent)[0] >> 4;
    final bits = _bitsOfBytes(ent) + _bits(cs, 4);
    final words = <String>[];
    for (var i = 0; i < 12; i++) {
      words.add(wordlist[int.parse(bits.substring(i * 11, (i + 1) * 11), radix: 2)]);
    }
    return words.join(' ');
  }

  static String _bitsOfBytes(List<int> b) =>
      [for (final v in b) _bits(v, 8)].join();

  static String _bits(int v, int n) => v.toRadixString(2).padLeft(n, '0');

  static Uint8List _bytesFromBits(String bits) {
    final out = Uint8List(bits.length ~/ 8);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(bits.substring(i * 8, (i + 1) * 8), radix: 2);
    }
    return out;
  }
}
