// 恢复词：BIP39 中文简体生成/校验/派生 + 黄金向量。
// 向量来源：tool/gen_wordlist.js 运行时由 Node crypto 独立计算（与 Dart 实现互证）；
// 动态口令向量来自后端调试台公式 + curl 对活后端实测（2026-11-14）。
import 'package:diary_app/core/e2ee/bytes.dart';
import 'package:diary_app/core/e2ee/kdf.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('黄金向量：熵全 0 → 「的×11 在」→ seed（Node 端独立计算）', () {
    const phrase = '的 的 的 的 的 的 的 的 的 的 的 在';
    expect(RecoveryWords.canonicalPhrase(phrase), phrase);
    RecoveryWords.validate(phrase); // 不抛
    expect(hexEncode(RecoveryWords.phraseToSeed(phrase)),
        '7571379a07dc7c0f699665f43477353c89aa80036f9b66a33e79cbce612cd1e2');
  });

  test('generate：12 词、全在词表、可过校验（多轮）', () {
    for (var i = 0; i < 8; i++) {
      final p = RecoveryWords.generate();
      final ws = p.split(' ');
      expect(ws.length, 12);
      for (final w in ws) {
        expect(RecoveryWords.wordlist.contains(w), isTrue, reason: w);
      }
      RecoveryWords.validate(p);
    }
  });

  test('抄写错误被校验和拒绝：换词 / 缺词 / 词表外 / 错序', () {
    // 换词：末词「在」→「不」（校验位 3 → 4，必不匹配）
    expect(() => RecoveryWords.validate('的 的 的 的 的 的 的 的 的 的 的 不'),
        throwsFormatException);
    // 缺词（11 个）
    expect(() => RecoveryWords.validate('的 的 的 的 的 的 的 的 的 的 的'),
        throwsFormatException);
    // 词表外
    expect(
        () => RecoveryWords.validate(
            'hello world foo bar baz qux quux corge grault garply waldo fred'),
        throwsFormatException);
    // 错序（1↔2 互换 → 熵变化 → 校验和 13≠3，确定性拒绝）
    expect(() => RecoveryWords.validate('一 的 的 的 的 的 的 的 的 的 的 在'),
        throwsFormatException);
  });

  test('canonicalPhrase：换行/多空格归一化；非 12 词 → null', () {
    const messy = '  的   的\n的 的 的 的 的 的 的 的 的  在'; // 11 的 + 在
    expect(RecoveryWords.canonicalPhrase(messy),
        '的 的 的 的 的 的 的 的 的 的 的 在');
    expect(RecoveryWords.canonicalPhrase('的 一'), isNull);
  });

  test('looksLikeHexKey：64 位 hex 判定（导入二选一路径）', () {
    expect(RecoveryWords.looksLikeHexKey('ab' * 32), isTrue);
    expect(RecoveryWords.looksLikeHexKey('AB' * 32), isTrue);
    expect(RecoveryWords.looksLikeHexKey('ab' * 31), isFalse);
    expect(RecoveryWords.looksLikeHexKey(RecoveryWords.generate()), isFalse);
  });

  test('diaryPass 黄金向量（公式已对活后端 curl 实测）', () {
    const key =
        '2bdb0e19c144b01c7214407b7ce8f9c15f40705bcb04184b1917730e4f0bea4d';
    expect(diaryPass(key, epochSec: 5982143 * 300), '23b15233');
    // 窗口边界：窗内任意时刻同值；跨窗（+300s）变化
    expect(diaryPass(key, epochSec: 5982143 * 300 + 299), '23b15233');
    expect(diaryPass(key, epochSec: 5982143 * 300 + 300),
        isNot('23b15233'));
    // 大写密钥归一化小写参与运算（与后端/调试台一致）
    expect(
        diaryPass(
            '2BDB0E19C144B01C7214407B7CE8F9C15F40705BCB04184B1917730E4F0BEA4D',
            epochSec: 5982143 * 300),
        '23b15233');
    // 口令固定 8 位 hex
    expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(diaryPass(key)), isTrue);
  });
}
