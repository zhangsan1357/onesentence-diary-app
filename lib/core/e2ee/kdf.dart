// 密码学原语组装层：只用公开库（cryptography + pointycastle），不手搓算法。
// 参数与字节布局由 02 手册 §7 黄金向量钉死（test/core/e2ee/golden_test.dart）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';

import 'bytes.dart';

/// SHA-256（恢复词派生 / 动态口令等通用摘要）。
Uint8List sha256Bytes(List<int> data) =>
    SHA256Digest().process(Uint8List.fromList(data));

/// 动态口令（2026-11-14 后端 v4，AuthGateFilter 同式，已对活后端实测验证）：
/// X-Diary-Pass = SHA-256(userKey + ':' + 窗号) 前 8 位 hex，窗号 = epoch秒/300（5 分钟窗）。
/// userKey 一律以小写参与运算（与后端/调试台一致）。[epochSec] 仅供测试注入。
String diaryPass(String userKeyHex, {int? epochSec}) {
  final sec = epochSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final w = sec ~/ 300;
  return hexEncode(sha256Bytes(utf8.encode('${userKeyHex.toLowerCase()}:$w')))
      .substring(0, 8);
}

/// Argon2id 主密钥派生：memory=64MiB(65536KiB), iterations=3, parallelism=4, keyLen=32。
Future<Uint8List> argon2idKey(
  String password,
  List<int> salt, {
  int memoryKiB = 65536,
  int iterations = 3,
  int parallelism = 4,
  int keyLen = 32,
}) async {
  final generator = Argon2BytesGenerator()
    ..init(Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      Uint8List.fromList(salt),
      desiredKeyLength: keyLen,
      iterations: iterations,
      memory: memoryKiB,
      lanes: parallelism,
    ));
  final out = Uint8List(keyLen);
  generator.deriveKey(utf8.encode(password), 0, out, 0);
  return out;
}

/// HKDF-SHA256（RFC5869）。salt 为空 → 按 RFC 默认（等价 HashLen 零填充）。
Future<Uint8List> hkdfSha256(
  List<int> ikm, {
  List<int> salt = const [],
  List<int> info = const [],
  int length = 32,
}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
  final key = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: salt,
    info: info,
  );
  return Uint8List.fromList(await key.extractBytes());
}

final _x25519 = X25519();

/// X25519 密钥对（32B 原始字节，非 PEM）。
Future<SimpleKeyPair> x25519KeyPair() => _x25519.newKeyPair();

Future<SimpleKeyPair> x25519KeyPairFromSeed(List<int> seed) =>
    _x25519.newKeyPairFromSeed(seed);

/// 由私钥推导公钥（库内按 RFC7748 clamp）。
Future<Uint8List> x25519PublicKey(List<int> priv) async {
  final pair = await _x25519.newKeyPairFromSeed(priv);
  return Uint8List.fromList((await pair.extractPublicKey()).bytes);
}

/// ECDH 共享密钥（与 Go curve25519.X25519 一致）。
Future<Uint8List> x25519SharedSecret(List<int> priv, List<int> peerPub) async {
  final pair = await _x25519.newKeyPairFromSeed(priv);
  final secret = await _x25519.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(peerPub, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await secret.extractBytes());
}

final _aesGcm = AesGcm.with256bits();

/// AES-256-GCM 加密；返回 cipher+tag 拼接（与 Go gcm.Seal 布局一致）。nonce 12B。
Future<Uint8List> aesGcmEncrypt(
  List<int> key,
  List<int> nonce,
  List<int> plaintext,
) async {
  final box = await _aesGcm.encrypt(
    plaintext,
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
  out.setAll(0, box.cipherText);
  out.setAll(box.cipherText.length, box.mac.bytes);
  return out;
}

/// AES-256-GCM 解密（输入为 cipher+tag 拼接）。nonce 12B。
Future<Uint8List> aesGcmDecrypt(
  List<int> key,
  List<int> nonce,
  List<int> cipherAndTag,
) async {
  const tagLen = 16;
  final cipher = cipherAndTag.sublist(0, cipherAndTag.length - tagLen);
  final tag = cipherAndTag.sublist(cipherAndTag.length - tagLen);
  return Uint8List.fromList(await _aesGcm.decrypt(
    SecretBox(cipher, nonce: nonce, mac: Mac(tag)),
    secretKey: SecretKey(key),
  ));
}
