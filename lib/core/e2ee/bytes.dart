// 字节工具：hex/base64/utf8 与拼装（加密胶水的一部分，无算法逻辑）。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

Uint8List hexDecode(String hex) {
  assert(hex.length % 2 == 0);
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List concat(List<List<int>> parts) {
  final total = parts.fold<int>(0, (n, p) => n + p.length);
  final out = Uint8List(total);
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}

Uint8List slice(List<int> bytes, int start, [int? end]) {
  final e = end ?? bytes.length;
  return Uint8List.fromList(bytes.sublist(start, e));
}

Uint8List randomBytes(int n) {
  final out = Uint8List(n);
  // Random.secure() 为加密级随机源。
  for (var i = 0; i < n; i++) {
    out[i] = Random.secure().nextInt(256);
  }
  return out;
}

final _b64 = base64;
String b64Encode(List<int> bytes) => _b64.encode(bytes);
Uint8List b64Decode(String s) => base64Decode(s);
