// 面容 ID 解锁全流程（假 BioVault 注入）：启用存私钥 → 锁定 → 面容取私钥直接解锁
// （无需口令）→ 关闭清除；无存档回退口令的信号（bio-missing）；注销一并清除。
import 'package:diary_app/core/db/database.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/bio_vault.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBio implements BioVault {
  bool avail = true;
  bool authOk = true;
  String? stored;

  @override
  Future<bool> available() async => avail;

  @override
  Future<bool> authenticate(String reason) async => authOk;

  @override
  Future<void> savePriv(String privB64) async => stored = privB64;

  @override
  Future<String?> readPriv() async => stored;

  @override
  Future<void> deletePriv() async => stored = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late MemoryLocalStore store;
  late FakeBio bio;

  setUp(() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    session = container.read(appSessionProvider.notifier);
    store = MemoryLocalStore();
    await session.debugUseStore(store);
    bio = FakeBio();
    session.bio = bio;
  });

  test('启用：生物识别确认 → 私钥入库 + ui.bio=1；锁定后面容解锁免口令', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '面容测试');
    expect(container.read(appSessionProvider).bioUnlock, isFalse);
    // 开启锁定保护（keystore 转口令包裹）——锁定态下面容解锁才有意义
    await session.setLockEnabled(true, passcode: '123456');
    await session.enableBioUnlock();
    expect(bio.stored, isNotNull);
    expect(container.read(appSessionProvider).bioUnlock, isTrue);
    expect(await store.kvGet('ui.bio'), '1');

    session.lock();
    expect(container.read(appSessionProvider).locked, isTrue);
    // 面容识别（假实现恒通过）→ 钥匙串私钥直取 → 无需口令；
    // 本地解锁完成后的联网注册/同步在测试环境无后端 → 异常照抛（真机进横幅），不影响解锁态
    await expectLater(session.unlockBiometric(), throwsA(anything));
    final st = container.read(appSessionProvider);
    expect(st.locked, isFalse);
    expect(st.userId, '面容测试');
    expect(st.needsOnboarding, isFalse);
    expect(session.state.entries, isEmpty);
  });

  test('钥匙串无存档 → StateError(bio-missing)，UI 回退口令路径', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '回退测试');
    await session.setLockEnabled(true, passcode: '123456');
    session.lock();
    bio.stored = null; // 未启用面容解锁（或生物特征集变更失效）
    await expectLater(session.unlockBiometric(),
        throwsA(predicate((e) => e.toString().contains('bio-missing'))));
    expect(container.read(appSessionProvider).locked, isTrue);
    // 口令回退路径仍可用（本地解锁完成；联网部分测试环境抛错不阻断解锁态）
    await expectLater(session.unlock('123456'), throwsA(anything));
    expect(container.read(appSessionProvider).locked, isFalse);
  });

  test('生物识别未通过 / 设备不可用 / 未解锁会话 → 拒绝启用', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '拒绝测试');
    bio.authOk = false;
    await expectLater(session.enableBioUnlock(), throwsFormatException);
    expect(bio.stored, isNull);
    bio.authOk = true;
    bio.avail = false;
    await expectLater(session.enableBioUnlock(), throwsFormatException);
    bio.avail = true;
    // 正常启用后再关闭 → 清空
    await session.enableBioUnlock();
    expect(bio.stored, isNotNull);
    await session.disableBioUnlock();
    expect(bio.stored, isNull);
    expect(await store.kvGet('ui.bio'), '0');
    expect(container.read(appSessionProvider).bioUnlock, isFalse);
  });

  test('注销账号：钥匙串存档与 ui.bio 一并清除', () async {
    final phrase = RecoveryWords.generate();
    await session.createIdentity(phrase, '注销测试');
    await session.enableBioUnlock();
    expect(bio.stored, isNotNull);
    await session.logout();
    expect(bio.stored, isNull);
    expect(await store.kvGet('ui.bio'), isNull);
    expect(container.read(appSessionProvider).bioUnlock, isFalse);
  });
}
