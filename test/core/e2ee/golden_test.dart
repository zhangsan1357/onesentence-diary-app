// 黄金向量测试（02 手册 §7 固化向量，Go 参考实现 2026-11-13 实测输出）。
// golden 常绿是合入前提（03 手册 §2.3）。向量与参数勿改，只读。
import 'dart:convert';
import 'dart:typed_data';

import 'package:diary_app/core/e2ee/bytes.dart';
import 'package:diary_app/core/e2ee/envelope.dart';
import 'package:diary_app/core/e2ee/kdf.dart';
import 'package:flutter_test/flutter_test.dart';

const _privRecipientHex =
    '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20';
const _pubRecipientHex =
    '07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c';
const _privEphemeralHex =
    '3132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f50';
const _pubEphemeralHex =
    '5f09b7f97a40b50220697064b43b27411b07a4aa1fe05370b27519826983d30d';
const _sharedSecretHex =
    'aeada1b0fa3ff2de8dec36f400b01ef9ba6f0bc8e9421c4bae6b0ff17d990e74';
const _encKeyHex =
    'e27fd60fbe19d72565e0682f53096830e1cb8f7698f22c8fde22c7b5f2c22000';

const _cekHex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _wrapNonceHex = 'a0a1a2a3a4a5a6a7a8a9aaab';
// EncryptedCEK(92B) = ephemeralPub[0:32] || wrapNonce[32:44] || cipher[44:92]
const _encryptedCekHex =
    '5f09b7f97a40b50220697064b43b27411b07a4aa1fe05370b27519826983d30d'
    'a0a1a2a3a4a5a6a7a8a9aaab'
    '0bb19157ce9157edba2b7dc5bbc96f46f52689d40c71d2d44febb492a4ea00c3'
    '12b269e90ce730fa306a617453716b6f';

const _bodyNonceHex = 'c0c1c2c3c4c5c6c7c8c9cacb';
const _plain = '一句话日记 golden vector：服务端只见密文。';
const _ciphertextHex =
    'e4f0a782f8dd7ef1053f6a07da0258762b1c8f5b598c3fcc4fa03f654592c32c'
    '5a0a1a42f87aa2a867a8dbb31163e46c22e339ec552e209bab8db917fdbe88'
    '50efbe220c94fb57d3';

const _masterKeyHex =
    '7eacc8ef1c20b5d90580132601e1aaad53a2d88a84460a1835c5d09ffa80e952';

// 完整 JSON fixture（base64 StdEncoding，03 手册 §2.3 原文）
const _goldenJson =
    '{"ciphertext":"5PCngvjdfvEFP2oH2gJYdiscj1tZjD/MT6A/ZUWSwyxaChpC+HqiqGeo27MRY+RsIuM57FUuIJurjbkX/b6IUO++IgyU+1fT","nonce_content":"wMHCw8TFxsfIycrL","encrypted_cek":"Xwm3+XpAtQIgaXBktDsnQRsHpKof4FNwsnUZgmmD0w2goaKjpKWmp6ipqqsLsZFXzpFX7borfcW7yW9G9SaJ1Axx0tRP67SSpOoAwxKyaekM5zD6MGphdFNxa28="}';
const _privB64 = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=';

Uint8List _hex(String s) => hexDecode(s);
String _hexOf(List<int> b) => hexEncode(b);

void main() {
  test('argon2id golden：password/salt → masterKey', () async {
    final key = await argon2idKey('hello-diary', utf8.encode('diary-salt-2026!'));
    expect(_hexOf(key), _masterKeyHex);
  });

  test('x25519 公钥推导（RFC7748 clamp）', () async {
    expect(_hexOf(await x25519PublicKey(_hex(_privRecipientHex))),
        _pubRecipientHex);
    expect(_hexOf(await x25519PublicKey(_hex(_privEphemeralHex))),
        _pubEphemeralHex);
  });

  test('x25519 sharedSecret = aeada1b0…', () async {
    final shared = await x25519SharedSecret(_hex(_privEphemeralHex),
        _hex(_pubRecipientHex));
    expect(_hexOf(shared), _sharedSecretHex);
  });

  test('hkdf-sha256 encKey（salt=nil, info=e2ee-cek-encryption, L=32）', () async {
    final encKey = await hkdfSha256(_hex(_sharedSecretHex),
        info: utf8.encode('e2ee-cek-encryption'));
    expect(_hexOf(encKey), _encKeyHex);
  });

  test('CEK 包裹（ECIES）：EncryptedCEK 92B 字节布局', () async {
    final wrapped = await wrapCek(
      _hex(_cekHex),
      _hex(_pubRecipientHex),
      ephemeralSeed: _hex(_privEphemeralHex),
      nonce: _hex(_wrapNonceHex),
    );
    expect(wrapped.length, 92);
    expect(_hexOf(wrapped), _encryptedCekHex);
  });

  test('正文 AES-256-GCM：cipher+tag 拼接布局（同 Go gcm.Seal）', () async {
    final ct = await aesGcmEncrypt(
        _hex(_cekHex), _hex(_bodyNonceHex), utf8.encode(_plain));
    expect(_hexOf(ct), _ciphertextHex);
  });

  test('golden envelope decrypt（03 §2.3 fixture 原文）', () async {
    final plain = await Envelope.decrypt(_goldenJson, base64Decode(_privB64));
    expect(utf8.decode(plain), _plain);
  });

  test('deterministic encrypt 复现完整 golden JSON', () async {
    final json = await Envelope.encryptJson(
      utf8.encode(_plain),
      _hex(_pubRecipientHex),
      cek: _hex(_cekHex),
      contentNonce: _hex(_bodyNonceHex),
      ephemeralSeed: _hex(_privEphemeralHex),
      wrapNonce: _hex(_wrapNonceHex),
    );
    expect(json, _goldenJson);
  });

  test('encrypt→decrypt 随机往返（随机临时密钥/CEK 路径）', () async {
    final pair = await x25519KeyPair();
    final pub = (await pair.extractPublicKey()).bytes;
    final priv = await pair.extractPrivateKeyBytes();

    final json = await Envelope.encryptJson(utf8.encode('往返测试 $_plain'), pub);
    final back = await Envelope.decrypt(json, priv);
    expect(utf8.decode(back), '往返测试 $_plain');
  });
}
