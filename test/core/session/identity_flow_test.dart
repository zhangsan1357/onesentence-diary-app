// 身份流程（会话层）：生成身份 ① / 新设备登录 ② / 补设注册名。
// MemoryLocalStore 注入（debugUseStore），无网络依赖——注册失败进 syncError，不影响本地状态断言。
import 'dart:convert';

import 'package:diary_app/core/db/database.dart' as db;
import 'package:drift/drift.dart' as drift;
import 'package:diary_app/core/e2ee/envelope.dart';
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/crypto_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late db.MemoryLocalStore store;

  setUp(() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    session = container.read(appSessionProvider.notifier);
    store = db.MemoryLocalStore();
    await session.debugUseStore(store);
  });

  test('① createIdentity：keystore/身份文本落盘 + 解锁 + 注册名携带', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '测试者');
    final st = container.read(appSessionProvider);
    expect(st.unlocked, isTrue);
    expect(st.needsOnboarding, isFalse);
    expect(st.userId, '测试者');
    final kv = await store.kvAll();
    final ks = readKeystore((k) => kv[k]);
    expect(ks, isNotNull);
    expect(ks!.userId, '测试者');
    expect(kv['ks.recovery'], phrase); // 身份文本随 keystore 落盘（用户自行保管）
    expect(ks.deviceNo,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')));
  });

  test('① createIdentity：校验和不过 → FormatException，不留 keystore', () async {
    await expectLater(
        session.createIdentity('的 一 是 在 不 了 有 和 人 这 中 大', 'x'),
        throwsFormatException);
    final kv = await store.kvAll();
    expect(readKeystore((k) => kv[k]), isNull);
  });

  test('① createIdentity：注册名为空/超长拒绝', () async {
    final phrase = RecoveryWords.generate();
    await expectLater(
        session.createIdentity(phrase, '  '), throwsFormatException);
    await expectLater(
        session.createIdentity(phrase, '长' * 65), throwsFormatException);
  });

  test('② loginIdentity：同词同注册名 → 同公钥（新设备重建等价）', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '用户A');
    final kv1 = await store.kvAll();
    final pub1 = readKeystore((k) => kv1[k])!.publicKeyHex;
    // loginIdentity 末尾要联网注册+同步（测试无后端）→ 本地落盘先行完成后抛网络错
    await expectLater(
        session.loginIdentity('用户A', phrase), throwsA(anything));
    final kv2 = await store.kvAll();
    expect(readKeystore((k) => kv2[k])!.publicKeyHex, pub1,
        reason: '同词同注册名在「新设备」重建出同一身份');
    final st = container.read(appSessionProvider);
    expect(st.userId, '用户A');
    expect(st.needsOnboarding, isFalse);
    expect(st.needsName, isFalse);
  });

  test('② loginIdentity：恢复词校验失败直接抛 FormatException', () async {
    await expectLater(
        session.loginIdentity('用户A', '的 一 是 在 不 了 有 和 人 这 中 大'),
        throwsFormatException);
  });

  test('注销账号：keystore/令牌/游标清空 → 回到生成身份引导，原词可重新登录', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '注销测试');
    expect(container.read(appSessionProvider).needsOnboarding, isFalse);
    await session.logout();
    final kv = await store.kvAll();
    expect(kv.keys.any((k) => k.startsWith('ks.')), isFalse, reason: 'keystore KV 全清');
    expect(kv.containsKey('api.token'), isFalse);
    expect(kv.containsKey('sync.cursor'), isFalse);
    final st = container.read(appSessionProvider);
    expect(st.needsOnboarding, isTrue);
    expect(st.hasKeystore, isFalse);
    expect(st.userId, isEmpty);
    expect(st.lockEnabled, isFalse);
    // 原词重新登录 → 同一身份重建（服务端密文仍可解）
    await expectLater(
        session.loginIdentity('注销测试', phrase), throwsA(anything));
    expect(container.read(appSessionProvider).userId, '注销测试');
    expect(container.read(appSessionProvider).needsOnboarding, isFalse);
  });

  test('存量身份补设注册名：needsName 清除、keystore 更新、旧设备号保留', () async {
    // 模拟旧版 keystore（无 userId，deviceNo 固定）
    final s = await sessionFromIdentity('ab' * 32, deviceNo: 'legacy-device');
    final legacy = KeystoreData(
      saltB64: s.keystore.saltB64,
      wrappedPrivB64: s.keystore.wrappedPrivB64,
      wrapNonceB64: s.keystore.wrapNonceB64,
      publicKeyHex: s.keystore.publicKeyHex,
      deviceNo: s.keystore.deviceNo,
      userId: '',
      recoveryCode: 'ab' * 32,
    );
    for (final e in keystoreToKv(legacy).entries) {
      await store.kvSet(e.key, e.value);
    }
    await session.debugRestorePlainSession();
    expect(container.read(appSessionProvider).needsName, isTrue);
    await session.setName('老用户'); // 联网部分 unawaited，不阻塞
    final st = container.read(appSessionProvider);
    expect(st.needsName, isFalse);
    expect(st.userId, '老用户');
    final kv = await store.kvAll();
    final ks = readKeystore((k) => kv[k])!;
    expect(ks.userId, '老用户');
    expect(ks.deviceNo, 'legacy-device', reason: '同一设备不更换设备号');
  });

  test('P1-3 落盘零明文：库行只有密文，读取时解密重建内存', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '安全测试');
    // 手动落一条密文行（模拟同步后的库状态；publish 依赖网络上传不在此测）
    const text = '磁盘上不该有这句明文';
    final payload = EntryPayload(text: text, time: '10:00', mood: null);
    final s2 = await sessionFromIdentity(phrase, userId: '安全测试');
    final cipher =
        await Envelope.encryptJson(utf8.encode(payload.encode()), s2.publicKey);
    await store.upsertEntry(db.EntriesCompanion.insert(
      localId: 'e-cipher-1',
      serverId: const drift.Value(1),
      entryDate: '2026-11-15',
      payloadJson: '',
      cipherJson: const drift.Value(null),
      updatedAtMs: 0,
      deleted: const drift.Value(false),
    ));
    // 上面的占位行没有密文：真正校验用密文行
    await store.upsertEntry(db.EntriesCompanion.insert(
      localId: 'e-cipher-2',
      serverId: const drift.Value(2),
      entryDate: '2026-11-15',
      payloadJson: cipher, // 列复用存密文（P1-3）
      cipherJson: drift.Value(cipher),
      updatedAtMs: 0,
      deleted: const drift.Value(false),
    ));
    final rows = await store.allEntries();
    final withCipher = rows.where((r) => r.cipherJson != null);
    expect(withCipher, isNotEmpty);
    for (final r in withCipher) {
      expect(r.payloadJson, isNot(contains('"text"')),
          reason: '本地库不得落明文载荷');
      expect(r.payloadJson, contains('ciphertext'),
          reason: 'payloadJson 列复用存密文');
    }
    // 读取路径：解密重建内存索引
    await session.debugReloadEntries();
    final st = container.read(appSessionProvider);
    final hit = st.entries.where((e) => e.localId == 'e-cipher-2');
    expect(hit, isNotEmpty);
    expect(hit.first.payload.text, text, reason: '密文解密回原文');
    // 旧明文行（占位行 payloadJson 空、无密文）→ 不渲染但也不崩溃
    expect(st.entries.where((e) => e.localId == 'e-cipher-1'), isEmpty);
  });

  test('P0-2 needsPass 引导：身份建立置位 → finishPassSetup 清除 → logout 复位', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '引导测试');
    expect(container.read(appSessionProvider).needsPass, isTrue);
    session.finishPassSetup();
    expect(container.read(appSessionProvider).needsPass, isFalse);
    await session.logout();
    expect(container.read(appSessionProvider).needsPass, isFalse);
  });

  test('P1-4 lock 清空内存明文（解锁后 debugReloadEntries 从密文重建）', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '锁定测试');
    const text = '锁定后内存要清掉';
    final payload = EntryPayload(text: text, time: '10:00', mood: null);
    final s2 = await sessionFromIdentity(phrase, userId: '锁定测试');
    final cipher =
        await Envelope.encryptJson(utf8.encode(payload.encode()), s2.publicKey);
    await store.upsertEntry(db.EntriesCompanion.insert(
      localId: 'e-lock-1',
      serverId: const drift.Value(1),
      entryDate: '2026-11-15',
      payloadJson: cipher,
      cipherJson: drift.Value(cipher),
      updatedAtMs: 0,
      deleted: const drift.Value(false),
    ));
    await session.setLockEnabled(true, passcode: '123456');
    await session.debugReloadEntries();
    expect(container.read(appSessionProvider).entries, isNotEmpty);
    session.lock();
    final locked = container.read(appSessionProvider);
    expect(locked.locked, isTrue);
    expect(locked.entries, isEmpty, reason: '锁定后内存不得驻留明文条目');
    // 解锁（口令解包）→ 重建内存索引；联网部分失败不抛出、不阻断解锁
    // （晨 19 §5.11：服务端不可达只转同步横幅）
    await session.unlock('123456');
    final st = container.read(appSessionProvider);
    expect(st.locked, isFalse);
    expect(st.entries.firstWhere((e) => e.localId == 'e-lock-1').payload.text,
        text, reason: '解锁后从密文重建内存索引');
  });

  test('unlockKeystore：口令错误 → StateError(bad-passcode) 哨兵（§5.13 E2E 抓到的真 bug）',
      () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '哨兵测试');
    await session.setLockEnabled(true, passcode: '123456');
    session.lock();
    // 错误口令 → GCM 认证失败被 unlockKeystore 归一为文档哨兵
    // （此前实抛 SecretBoxAuthenticationError，『口令不正确』分支恒不命中）
    await expectLater(session.unlock('999999'),
        throwsA(predicate((e) => e.toString().contains('bad-passcode'))));
    expect(container.read(appSessionProvider).locked, isTrue,
        reason: '口令错误不解锁');
  });
}
