// 信封加密组装：随机 CEK → AES-GCM 加正文 → ECIES 包裹 CEK → 92B EncryptedCEK。
// 字节布局与序列化字段名（ciphertext/nonce_content/encrypted_cek，snake_case）由
// 02 手册 §7 黄金向量钉死，golden 测试常绿是合入前提。
import 'dart:convert';
import 'dart:typed_data';

import 'bytes.dart';
import 'kdf.dart';

const _cekWrapInfo = 'e2ee-cek-encryption'; // HKDF info，02 §7 固定值
const _ephemeralPubLen = 32;
const _wrapNonceLen = 12;

/// CEK 包裹（ECIES）：
/// 临时 X25519 密钥对 → ECDH(recipientPub) → HKDF-SHA256(salt=nil,
/// info="e2ee-cek-encryption", L=32) → encKey → AES-GCM 加密 CEK →
/// EncryptedCEK(92B) = ephemeralPub[0:32] || wrapNonce[32:44] || cipher[44:92]。
/// [ephemeralSeed]/[nonce] 仅测试注入用（黄金向量确定性复现），生产传 null。
Future<Uint8List> wrapCek(
  List<int> cek,
  List<int> recipientPub, {
  List<int>? ephemeralSeed,
  List<int>? nonce,
}) async {
  final ephemeralPriv = ephemeralSeed ?? randomBytes(32);
  final ephemeralPub = await x25519PublicKey(ephemeralPriv);
  final wrapNonce = nonce ?? randomBytes(_wrapNonceLen);
  final shared = await x25519SharedSecret(ephemeralPriv, recipientPub);
  final encKey = await hkdfSha256(shared, info: utf8.encode(_cekWrapInfo));
  final cipher = await aesGcmEncrypt(encKey, wrapNonce, cek);
  return concat([ephemeralPub, wrapNonce, cipher]);
}

/// 解包 EncryptedCEK（unwrapCek 是 wrapCek 的逆）。
Future<Uint8List> unwrapCek(List<int> encryptedCek, List<int> priv) async {
  assert(encryptedCek.length == 92, 'EncryptedCEK 必须 92 字节');
  final ephemeralPub = slice(encryptedCek, 0, _ephemeralPubLen);
  final wrapNonce = slice(encryptedCek, _ephemeralPubLen,
      _ephemeralPubLen + _wrapNonceLen);
  final cipher = slice(encryptedCek, _ephemeralPubLen + _wrapNonceLen);
  final shared = await x25519SharedSecret(priv, ephemeralPub);
  final encKey = await hkdfSha256(shared, info: utf8.encode(_cekWrapInfo));
  return aesGcmDecrypt(encKey, wrapNonce, cipher);
}

class Envelope {
  Envelope._();

  /// 加密为序列化 JSON：
  /// {"ciphertext": b64, "nonce_content": b64, "encrypted_cek": b64}
  static Future<String> encryptJson(
    List<int> plaintext,
    List<int> recipientPub, {
    List<int>? cek,
    List<int>? contentNonce,
    List<int>? ephemeralSeed,
    List<int>? wrapNonce,
  }) async {
    final cekBytes = cek ?? randomBytes(32);
    final nonceBytes = contentNonce ?? randomBytes(12);
    final cipher = await aesGcmEncrypt(cekBytes, nonceBytes, plaintext);
    final encryptedCek = await wrapCek(
      cekBytes,
      recipientPub,
      ephemeralSeed: ephemeralSeed,
      nonce: wrapNonce,
    );
    return jsonEncode({
      'ciphertext': b64Encode(cipher),
      'nonce_content': b64Encode(nonceBytes),
      'encrypted_cek': b64Encode(encryptedCek),
    });
  }

  /// 解密序列化 JSON，返回明文字节。
  static Future<Uint8List> decrypt(String json, List<int> priv) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final cipher = b64Decode(map['ciphertext'] as String);
    final nonce = b64Decode(map['nonce_content'] as String);
    final encryptedCek = b64Decode(map['encrypted_cek'] as String);
    final cek = await unwrapCek(encryptedCek, priv);
    return aesGcmDecrypt(cek, nonce, cipher);
  }
}
