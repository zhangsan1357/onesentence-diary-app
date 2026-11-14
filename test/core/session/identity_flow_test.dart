// 身份流程（会话层）：生成身份 ① / 新设备登录 ② / 补设注册名。
// MemoryLocalStore 注入（debugUseStore），无网络依赖——注册失败进 syncError，不影响本地状态断言。
import 'package:diary_app/core/db/database.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/crypto_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late MemoryLocalStore store;

  setUp(() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    session = container.read(appSessionProvider.notifier);
    store = MemoryLocalStore();
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
}
