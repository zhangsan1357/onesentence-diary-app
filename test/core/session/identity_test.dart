// 身份模型（2026-11-14 恢复词版）：12 词短语或派生密钥 hex → 确定性身份；
// deviceNo 每设备随机（不复用旧设备号）；userId=注册名随 keystore 携带。
import 'package:diary_app/core/e2ee/bytes.dart';
import 'package:diary_app/core/session/crypto_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_test/flutter_test.dart';

const _phrase = '的 的 的 的 的 的 的 的 的 的 的 在'; // BIP39 向量（熵全 0，见 recovery_words_test）

void main() {
  test('同一恢复词短语 → 同公钥同私钥（跨设备等价）', () async {
    final a = await sessionFromIdentity(_phrase, userId: '阿明');
    final b = await sessionFromIdentity(_phrase);
    expect(hexEncode(a.publicKey), hexEncode(b.publicKey));
    expect(a.keystore.wrappedPrivB64, b.keystore.wrappedPrivB64);
    expect(a.keystore.userId, '阿明'); // 注册名随 keystore 携带
    expect(b.keystore.userId, '');
  });

  test('不同恢复词 → 不同身份', () async {
    final a = await sessionFromIdentity(RecoveryWords.generate());
    final b = await sessionFromIdentity(RecoveryWords.generate());
    expect(hexEncode(a.publicKey), isNot(hexEncode(b.publicKey)));
  });

  test('派生密钥 hex 导入 = 短语导入（往返一致，②「或其派生密钥」）', () async {
    final phrase = RecoveryWords.generate();
    final s1 = await sessionFromIdentity(phrase);
    final seedHex = hexEncode(RecoveryWords.phraseToSeed(phrase));
    final s2 = await sessionFromIdentity(seedHex);
    expect(hexEncode(s1.publicKey), hexEncode(s2.publicKey));
    expect(s1.keystore.wrappedPrivB64, s2.keystore.wrappedPrivB64);
  });

  test('空白归一化：短语前后空格/多余空白不影响身份', () async {
    final a = await sessionFromIdentity('  $_phrase  ');
    final b = await sessionFromIdentity(_phrase);
    expect(hexEncode(a.publicKey), hexEncode(b.publicKey));
  });

  test('deviceNo 每设备随机 UUID v4（不复用旧设备号）', () async {
    final a = await sessionFromIdentity(_phrase);
    final b = await sessionFromIdentity(_phrase);
    final r = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(r.hasMatch(a.keystore.deviceNo), isTrue,
        reason: 'deviceNo=${a.keystore.deviceNo}');
    expect(r.hasMatch(b.keystore.deviceNo), isTrue,
        reason: 'deviceNo=${b.keystore.deviceNo}');
    expect(a.keystore.deviceNo, isNot(b.keystore.deviceNo),
        reason: '每次生成都应是全新设备号');
    expect(a.keystore.wrapNonceB64, ''); // 明文模式标志
  });

  test('非法输入拒绝：词数不足 / 词表外 / 校验和不过', () async {
    await expectLater(
        sessionFromIdentity('hello world'), throwsFormatException);
    await expectLater(sessionFromIdentity('的 的 的'), throwsFormatException);
    await expectLater(sessionFromIdentity('的 一 是 在 不 了 有 和 人 这 中 大'),
        throwsFormatException); // 12 个真词但校验和不匹配
  });
}
