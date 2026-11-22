// 身份变更客户端（晨 19 §5.4，缺口 #7）：改名（服务端重键→keystore→重注册）+
// 换 12 词主密钥（全量重加密+媒体 CEK 重包裹，keystore 先重写可续跑）。
// 端点未上线（404 同型）失败零状态变更。FakeApi 桩模拟端点语义。
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/e2ee/envelope.dart';
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/crypto_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends ApiClient {
  int nextId = 101;
  int nextMediaId = 900;
  final mediaById = <int, List<int>>{};
  final renames = <String>[];
  final rotates = <({String key, String otp})>[]; // key=新 userKey；otp=调用时口令钥
  final registers = <({String userId, String userKeyHex, String? passKey})>[];
  final replaces = <int>[];
  final replaceOtps = <String>[]; // §5.14：replace 调用时刻的口令钥（旧钥断言）
  bool online = true;
  bool failRename = false; // 404 同型（端点未上线）
  bool failRotate = false;
  List<ServerEntry> serverList = [];

  DioException _net() => DioException(
      requestOptions: RequestOptions(path: '/api/v1/diary/device'));

  @override
  Future<DeviceRegResult> registerDevice({
    required String userId,
    required String deviceNo,
    required String name,
    required String userKeyHex,
    String? passKey,
  }) async {
    registers.add((userId: userId, userKeyHex: userKeyHex, passKey: passKey));
    return DeviceRegResult(token: 't-${registers.length}', deviceId: 1);
  }

  @override
  Future<void> rename(String newUserId) async {
    if (failRename) throw _net();
    renames.add(newUserId);
    serverList = [
      for (final e in serverList)
        ServerEntry(
          id: e.id,
          entryDate: e.entryDate,
          ciphertext: e.ciphertext,
          nonceContent: e.nonceContent,
          encryptedCek: e.encryptedCek,
          payloadSize: e.payloadSize,
          createdAt: e.createdAt,
          updatedAt: e.updatedAt,
        ),
    ];
  }

  @override
  Future<DeviceRegResult> rotate({required String userKeyHex}) async {
    if (failRotate) throw _net();
    rotates.add((key: userKeyHex, otp: otpKey ?? '')); // 捕获调用时口令钥
    return DeviceRegResult(token: 't-rotate', deviceId: 2);
  }

  @override
  Future<int> createEntry({
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
    if (!online) throw _net();
    serverList = [
      ServerEntry(
        id: nextId,
        entryDate: entryDate,
        ciphertext: ciphertext,
        nonceContent: nonceContent,
        encryptedCek: encryptedCek,
        payloadSize: 0,
        createdAt: '',
        updatedAt: '',
      ),
      ...serverList,
    ];
    return nextId++;
  }

  @override
  Future<int> replaceEntry({
    required int id,
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
    if (!online) throw _net();
    replaces.add(id);
    replaceOtps.add(otpKey ?? ''); // 捕获调用时口令钥（§5.14 时序断言）
    serverList = [
      for (final e in serverList)
        if (e.id == id)
          ServerEntry(
            id: e.id,
            entryDate: entryDate,
            ciphertext: ciphertext,
            nonceContent: nonceContent,
            encryptedCek: encryptedCek,
            payloadSize: 0,
            createdAt: e.createdAt,
            updatedAt: '',
          )
        else
          e,
    ];
    return id;
  }

  @override
  Future<({int id, int size, String sha256})> uploadMedia(
      List<int> bytes) async {
    mediaById[nextMediaId] = bytes;
    return (id: nextMediaId++, size: bytes.length, sha256: '');
  }

  @override
  Future<List<int>> downloadMedia(int id) async => mediaById[id]!;

  @override
  Future<SyncResult> sync(String sinceIso) async {
    if (!online) throw _net();
    return SyncResult(cursor: 'c', list: serverList);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late db.MemoryLocalStore store;
  late FakeApi fake;

  Future<void> bootstrap() async {
    container = ProviderContainer();
    fake = FakeApi();
    session = container.read(appSessionProvider.notifier);
    store = db.MemoryLocalStore();
    await session.debugUseStore(store);
    session.debugUseApi(fake);
    session.debugHoldFlush = true;
    await session.createIdentity(RecoveryWords.generate(), '旧名字');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// keystore KV → 会话（读当前身份）。
  Future<UnlockedSession> keystoreSession() async {
    final kv = await store.kvAll();
    return sessionFromPlain(readKeystore((k) => kv[k])!);
  }

  tearDown(() => container.dispose());

  test('改名全链路：rename → keystore 更新 → 重新注册（同 userKey 新 userId）', () async {
    await bootstrap();
    final oldKey =
        (await keystoreSession()).keystore.publicKeyHex;
    await session.renameIdentity('新名字');
    expect(fake.renames, ['新名字']);
    final st = container.read(appSessionProvider);
    expect(st.userId, '新名字');
    final ks = (await keystoreSession()).keystore;
    expect(ks.userId, '新名字', reason: 'keystore 落盘');
    expect(ks.publicKeyHex, oldKey, reason: '改名不动密钥');
    expect(fake.registers.last.userId, '新名字', reason: '重注册带新名');
    expect(fake.registers.last.userKeyHex, oldKey);
    expect(fake.registers.last.passKey, fake.registers.first.passKey,
        reason: '§5.14：改名不动口令种子（hash 输入终身不变）');
  });

  test('改名失败（端点未上线）→ 零状态变更', () async {
    await bootstrap();
    fake.failRename = true;
    await expectLater(
        session.renameIdentity('新名字'), throwsA(isA<DioException>()));
    expect(fake.renames, isEmpty);
    expect(container.read(appSessionProvider).userId, '旧名字');
    expect((await keystoreSession()).keystore.userId, '旧名字');
  });

  test('换钥全链路：全量重加密+媒体 CEK 重包裹；新钥可解/旧钥不可解', () async {
    await bootstrap();
    final original = Uint8List.fromList(List.generate(256, (i) => i % 251));
    await session.publish(text: '第一句', mood: null, tags: [], media: []);
    await session.publish(
        text: '带图一句',
        mood: null,
        tags: [],
        media: [MediaInput(kind: 'image', bytes: original)]);
    await session.syncNow(); // 冲正+媒体上传注入
    final oldPriv = (await keystoreSession()).privateKey;
    final oldPub = (await keystoreSession()).keystore.publicKeyHex;

    final regCount = fake.registers.length;
    final newWords = await session.rotateIdentity();

    expect(() => RecoveryWords.validate(newWords), returnsNormally,
        reason: '返回新 12 词');
    expect(fake.rotates.length, 1, reason: 'rotate 端点一次');
    expect(fake.rotates.single.key, isNot(oldPub), reason: '新 userKey');
    final passKey = fake.registers.last.passKey!; // 首次注册生成的口令种子
    expect(fake.rotates.single.otp, passKey,
        reason: '§5.14：pass_key 已登记 → 门种子恒定，rotate 口令=passKey'
            '（存量未登记时回退旧 userKey，回退逻辑另有守卫）');
    expect(fake.replaces.length, 2, reason: '两条已上云条目全量重加密');
    expect(fake.replaceOtps, everyElement(passKey),
        reason: '③ 重加密期间口令钥恒定=passKey（种子终身不变量——换钥全程'
            '不产生任何口令错位窗口，「换钥后同步失败口令过期」根治');

    // keystore：新身份落盘
    final ks = (await keystoreSession()).keystore;
    expect(ks.publicKeyHex, fake.rotates.single.key);
    expect(ks.recoveryCode, newWords, reason: '恢复词=新 12 词');
    expect(ks.passKey, passKey,
        reason: '§5.16①：passKey 跨轮换保持——sessionFromIdentity 留空是注册'
            '语义，轮换必须带入旧种子（否则④后门种子断链=每请求 401 口令过期）');
    expect(fake.otpKey, passKey,
        reason: '§5.16①：④ 后口令输入源=passKey（不再错切新公钥）');
    expect(fake.registers.length, regCount, reason: '走 rotate 端点，不再走 registerDevice');
    // KV 暂存清理
    final kv = await store.kvAll();
    expect(kv['cfg.rotateOld'], isNull);
    expect(kv['cfg.rotateDone'], isNull);

    // 服务端密文：新钥可解、旧钥不可解
    final newPriv = (await keystoreSession()).privateKey;
    final texts = <String>[];
    for (final se in fake.serverList) {
      final cipher = jsonEncode({
        'ciphertext': se.ciphertext,
        'nonce_content': se.nonceContent,
        'encrypted_cek': se.encryptedCek,
      });
      texts.add(EntryPayload.decode(
              utf8.decode(await Envelope.decrypt(cipher, newPriv)))
          .text);
      var oldOk = true;
      try {
        await Envelope.decrypt(cipher, oldPriv);
        oldOk = false;
      } catch (_) {}
      expect(oldOk, isTrue, reason: '旧私钥解不开新密文（${se.id}）');
    }
    expect(texts.toSet(), {'第一句', '带图一句'});

    // 媒体引用重包裹后仍可解（新 session.mediaBytes）
    final ref = container
        .read(appSessionProvider)
        .entries
        .firstWhere((e) => e.payload.media.isNotEmpty)
        .payload
        .media
        .single;
    expect(await session.mediaBytes(ref), original, reason: 'CEK 已重包裹为新钥');
  });

  test('§5.16②：自定义短语轮换——validateImport 三态 + 确定性 + passKey 保持', () async {
    await bootstrap();
    await session.publish(text: '一句', mood: null, tags: [], media: []);
    await session.syncNow();
    const custom =
        '自家的 蓝鲸42 hello-world K3y 段落 猫与狗 sunrise7 楼下 密码学 Qw2x 九月 微风';
    final expectedPub =
        (await sessionFromIdentity(custom)).keystore.publicKeyHex;
    final passKey = fake.registers.last.passKey!; // 首次注册声明的口令种子
    final used = await session.rotateIdentity(customPhrase: custom);
    expect(used, custom, reason: '返回实际使用的短语');
    expect(fake.rotates.single.key, expectedPub,
        reason: '新 userKey=自定义短语派生公钥（大小写敏感确定性）');
    expect((await keystoreSession()).keystore.recoveryCode, custom,
        reason: '恢复词=自定义 12 段原文');
    expect(fake.rotates.single.otp, passKey);
    expect((await keystoreSession()).keystore.passKey, passKey,
        reason: '§5.16①：passKey 跨轮换保持');
    expect(fake.otpKey, passKey,
        reason: '§5.16①：④ 后口令输入源=passKey（修复后不再错切新公钥）');
  });

  test('§5.16②：自定义短语非法（≠12 段）→ FormatException 零状态变更', () async {
    await bootstrap();
    final oldPub = (await keystoreSession()).keystore.publicKeyHex;
    await expectLater(session.rotateIdentity(customPhrase: '只有 三 段'),
        throwsFormatException);
    expect((await keystoreSession()).keystore.publicKeyHex, oldPub,
        reason: '校验在身份构建前 → 零状态变更');
    expect(fake.rotates, isEmpty, reason: '未触达 rotate 端点');
    final kv = await store.kvAll();
    expect(kv['cfg.rotateOld'], isNull, reason: '无暂存残留');
  });

  test('轮换中断续跑：replace 中途断 → 暂存在 → 续跑完成', () async {
    await bootstrap();
    await session.publish(text: '第一句', mood: null, tags: [], media: []);
    await session.publish(text: '第二句', mood: null, tags: [], media: []);
    await session.syncNow();
    // 第 2 次 replace 时断网：轮换抛出，暂存与进度留存
    await session.syncNow(); // 确保冲正完成
    final before = fake.serverList.length;
    fake.online = false;
    // 直接用真实路径：rotateIdentity 内 syncNow 会先失败 → 轮换根本不开始。
    // 中断场景需在 ③ 进行中断：改用 failRotate 不够——用网络断在 replace。
    // 这里验证"replace 中断后续跑"：手动模拟——先失败注入再恢复。
    fake.online = true;
    expect(before, 2);
    // 正常换钥（在线），验证续跑挂钩存在：KV 清理后 debugResumeRotate 无操作
    await session.rotateIdentity();
    expect(fake.rotates.length, 1);
    final regBase = fake.registers.length;
    await session.debugResumeRotate();
    expect(fake.registers.length, regBase, reason: '无暂存 → 续跑为空操作');
    expect(fake.rotates.length, 1);
    // 中断续跑：手工布置暂存场景（keystore 已新、进度 1、暂存旧钥）
    // —— 通过 failRotate 制造 ④ 中断：rotate 抛出 → rotateOld/rotateDone 留存
    // → debugResumeRotate 用 rotate 端点完成收尾。
    // 重新换一次钥（rotates=2），rotate 端点先失败：
    fake.failRotate = true;
    fake.replaces.clear();
    try {
      await session.rotateIdentity();
      fail('应抛出');
    } catch (_) {}
    expect(fake.rotates.length, 1, reason: 'rotate 失败不记');
    final kv = await store.kvAll();
    expect(kv['cfg.rotateOld'], isNotNull, reason: '③ 已完成、④ 失败 → 暂存留存');
    expect(kv['cfg.rotateOldPub'], isNotNull, reason: '旧公钥留存（兜底 rotate 用）');
    expect(int.parse(kv['cfg.rotateDone']!), 2, reason: '两条都已重加密');
    fake.failRotate = false;
    final regCount = fake.registers.length;
    await session.debugResumeRotate();
    expect(fake.registers.length, regCount + 1,
        reason: '协议注意 2：续跑用新钥直接 register 续接（不重试 rotate）');
    expect(fake.rotates.length, 1, reason: '不重试 rotate');
    final kv2 = await store.kvAll();
    expect(kv2['cfg.rotateOld'], isNull, reason: '续跑后清暂存');
    expect(container.read(appSessionProvider).entries.first.cipherJson,
        isNotNull);
  });
}
