// 离线队列（2026-11-16）：云端不可达 → 增删改本地暂存（含媒体加密暂存）；
// 手动刷新（syncNow）时按修改顺序一次性冲正。假 API 模拟断网/恢复，
// 断网 = 抛 DioException（网络层错误），恢复 = 正常应答并记录调用。
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

/// 假 API：online=false 模拟云端不可达（DioException，与真实断网同型）。
class FakeApi extends ApiClient {
  bool online = true;
  int nextId = 101;
  int nextMediaId = 900;
  int createCallIdx = 0;
  int? failCreateAt; // 第 N 次 create（0 基）抛 DioException——模拟冲正中途断网
  final creates = <Map<String, dynamic>>[];
  final replaces = <({int id, Map<String, dynamic> body})>[];
  final deletes = <int>[];
  final uploads = <List<int>>[];
  List<ServerEntry> serverList = [];

  DioException _net() => DioException(
      requestOptions: RequestOptions(path: '/api/v1/diary/entries'));

  @override
  Future<DeviceRegResult> registerDevice({
    required String userId,
    required String deviceNo,
    required String name,
    required String userKeyHex,
    String? passKey,
  }) async =>
      DeviceRegResult(token: 't-fake', deviceId: 1);

  @override
  Future<int> createEntry({
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
    if (!online) throw _net();
    final i = createCallIdx++;
    if (failCreateAt == i) throw _net();
    final body = {
      'entryDate': entryDate,
      'ciphertext': ciphertext,
      'nonce_content': nonceContent,
      'encrypted_cek': encryptedCek,
    };
    creates.add(body);
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
    replaces.add((id: id, body: {
      'ciphertext': ciphertext,
      'nonce_content': nonceContent,
      'encrypted_cek': encryptedCek,
    }));
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
  Future<void> deleteEntry(int id) async {
    if (!online) throw _net();
    deletes.add(id);
    serverList = [for (final e in serverList) if (e.id != id) e];
  }

  @override
  Future<({int id, int size, String sha256})> uploadMedia(
      List<int> bytes) async {
    if (!online) throw _net();
    uploads.add(bytes);
    return (id: nextMediaId++, size: bytes.length, sha256: '');
  }

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
    session.debugHoldFlush = true; // 挂起写路径的后台冲正：测试显式 flushNow/syncNow 保持确定性
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    // createIdentity 内部 unawaited 的注册+空同步落地（全假实现，毫秒级）
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  tearDown(() => container.dispose());

  Future<void> pubOffline({List<MediaInput> media = const []}) async {
    fake.online = false;
    await session.publish(text: '离线一句', mood: null, tags: [], media: media);
    fake.online = true;
  }

  test('发布断网 → 本地先行入队（syncState=1、待同步计数），UI 即时返回', () async {
    await bootstrap();
    await pubOffline();
    final st = container.read(appSessionProvider);
    expect(st.entries.length, 1);
    expect(st.entries.first.serverId, isNull);
    expect(st.entries.first.payload.text, '离线一句');
    expect(st.pendingCount, 1);
    expect(st.toast, contains('已加密保存')); // 本地先行：落库即提示；离线告知由后台冲正失败补发
    expect((await store.allEntries()).single.syncState, 1);
  });

  test('离线发布 → 后台冲正失败 → toast 明示云端不可达（§2.3 本地先行补发）', () async {
    await bootstrap();
    session.debugHoldFlush = false; // 本项验证后台冲正路径本身
    fake.online = false;
    await session.publish(text: '离线一句', mood: null, tags: [], media: []);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(container.read(appSessionProvider).toast,
        contains('云端不可达'));
    expect((await store.allEntries()).single.syncState, 1, reason: '留队待续传');
  });

  test('在线发布本地先行 → 后台冲正回填 serverId、清队列与标记', () async {
    await bootstrap();
    session.debugHoldFlush = false;
    await session.publish(text: '在线一句', mood: null, tags: [], media: []);
    // 发布即时返回（不等网络）：内存里 serverId 尚未回填
    expect(container.read(appSessionProvider).entries.single.serverId, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final st = container.read(appSessionProvider);
    expect(st.entries.single.serverId, 101, reason: '后台冲正回填');
    expect(st.pendingCount, 0);
    expect(st.entries.single.textPending, isFalse);
    expect((await store.allEntries()).single.syncState, 0);
  });

  test('手动刷新冲正新建：推云 + serverId 回填 + 队列清零；重复刷新不重放', () async {
    await bootstrap();
    await pubOffline();
    await session.syncNow();
    expect(fake.creates.length, 1);
    final st = container.read(appSessionProvider);
    expect(st.entries.first.serverId, 101);
    expect(st.pendingCount, 0);
    expect((await store.allEntries()).single.syncState, 0);
    await session.syncNow(); // 已清队：幂等
    expect(fake.creates.length, 1);
  });

  test('评论断网 → 待替换（syncState=2）→ 冲正推替换且评论在密文内', () async {
    await bootstrap();
    await pubOffline();
    await session.syncNow();
    final localId =
        container.read(appSessionProvider).entries.first.localId;
    fake.online = false;
    await session.addComment(
        container.read(appSessionProvider).entries.first, '离线评论');
    fake.online = true;
    expect((await store.allEntries()).single.syncState, 2);
    expect(container.read(appSessionProvider).pendingCount, 1);
    await session.syncNow();
    expect(fake.replaces.length, 1);
    expect(container.read(appSessionProvider).pendingCount, 0);
    // 替换推上去的密文解出评论（端上私钥）
    final kv = await store.kvAll();
    final s = sessionFromPlain(readKeystore((k) => kv[k])!);
    final bytes =
        await Envelope.decrypt(jsonEncode(_cipherJson(fake.replaces.single)), s.privateKey);
    final payload = EntryPayload.decode(utf8.decode(bytes));
    expect(payload.comments.single.text, '离线评论');
    expect((await store.allEntries()).single.localId, localId);
  });

  test('删除已同步条目断网 → 待删除（syncState=3）→ 冲正推删除', () async {
    await bootstrap();
    await pubOffline();
    await session.syncNow();
    final serverId =
        container.read(appSessionProvider).entries.first.serverId!;
    fake.online = false;
    await session.deleteEntry(
        container.read(appSessionProvider).entries.first);
    fake.online = true;
    expect((await store.allEntries()).single.syncState, 3);
    expect(container.read(appSessionProvider).pendingCount, 1);
    await session.syncNow();
    expect(fake.deletes, [serverId]);
    final row = (await store.allEntries()).single;
    expect(row.deleted, isTrue);
    expect(row.syncState, 0);
    expect(fake.serverList.where((e) => e.id == serverId), isEmpty);
  });

  test('离线新建再删除 → 本地直接清除（无服务端可删），计数回落', () async {
    await bootstrap();
    await pubOffline();
    await session.deleteEntry(
        container.read(appSessionProvider).entries.first);
    final st = container.read(appSessionProvider);
    expect(st.entries, isEmpty);
    expect(st.pendingCount, 0);
    expect(await store.allEntries(), isEmpty);
  });

  test('冲正中途断网 → 已推的清队、未推的保留队列（下次刷新续传）', () async {
    await bootstrap();
    await pubOffline(); // 条目 A
    fake.online = false;
    await session.publish(text: '第二句', mood: null, tags: [], media: []);
    fake.online = true; // 条目 B
    fake.failCreateAt = 1; // 第 2 次 create 断网（A 成功、B 失败）
    await expectLater(session.syncNow(), throwsA(isA<DioException>()));
    final rows = await store.allEntries();
    final clean = rows.where((r) => r.syncState == 0).toList();
    final dirty = rows.where((r) => r.syncState != 0).toList();
    expect(clean.length, 1, reason: 'A 已推成、清队');
    expect(dirty.length, 1, reason: 'B 保留队列');
    expect(container.read(appSessionProvider).pendingCount, 1);
    fake.failCreateAt = null;
    fake.createCallIdx = 0;
    await session.syncNow(); // 下次手动刷新续传 B
    expect(fake.creates.length, 2);
    expect(container.read(appSessionProvider).pendingCount, 0);
  });

  test('带图发布断网 → 媒体加密暂存 → 冲正时上传并注入引用，暂存清空', () async {
    await bootstrap();
    await pubOffline(media: [
      MediaInput(kind: 'image', bytes: Uint8List.fromList([1, 2, 3, 4])),
    ]);
    final localId =
        container.read(appSessionProvider).entries.first.localId;
    final pm = await store.pendingMediaFor(localId);
    expect(pm.length, 1);
    expect(pm.single.blob.length, greaterThan(4)); // nonce12 ‖ 密文
    expect(pm.single.cekWrappedB64, isNotEmpty);
    await session.syncNow();
    expect(fake.uploads.length, 1);
    expect(fake.creates.length, 1);
    expect(await store.pendingMediaFor(localId), isEmpty);
    // 引用注入：最终密文解出 media[0].id = 上传 id
    final kv = await store.kvAll();
    final s = sessionFromPlain(readKeystore((k) => kv[k])!);
    final cipher = (await store.allEntries()).single.cipherJson!;
    final bytes = await Envelope.decrypt(cipher, s.privateKey);
    final payload = EntryPayload.decode(utf8.decode(bytes));
    expect(payload.media.single.id, 900);
    expect(payload.media.single.cekB64, pm.single.cekWrappedB64);
  });

  test('pendingMeta 编解码往返 + 坏 JSON 容错', () {
    expect(encodePendingMeta(false, const []), '');
    final m0 = parsePendingMeta('');
    expect(m0.text, isFalse);
    expect(m0.comments, isEmpty);
    final m = parsePendingMeta(encodePendingMeta(true, [3, 4]));
    expect(m.text, isTrue);
    expect(m.comments, [3, 4]);
    final g = parsePendingMeta('garbage');
    expect(g.text, isFalse);
    expect(g.comments, isEmpty);
    final n = parsePendingMeta(null);
    expect(n.text, isFalse);
    expect(n.comments, isEmpty);
  });

  test('待同步标记：离线发布整条标 *，冲正后清空', () async {
    await bootstrap();
    await pubOffline();
    var st = container.read(appSessionProvider);
    expect(st.entries.single.textPending, isTrue);
    expect(st.entries.single.pendingComments, isEmpty);
    await session.syncNow();
    st = container.read(appSessionProvider);
    expect(st.entries.single.textPending, isFalse);
  });

  test('待同步标记：干净条目离线加评论只标评论（正文不标），冲正清空', () async {
    await bootstrap();
    await pubOffline();
    await session.syncNow(); // 条目先上云、变干净
    fake.online = false;
    await session.addComment(
        container.read(appSessionProvider).entries.single, '离线评论');
    fake.online = true;
    final st = container.read(appSessionProvider);
    expect(st.entries.single.textPending, isFalse, reason: '正文没改过不标正文');
    expect(st.entries.single.pendingComments, [0]);
    await session.syncNow();
    final st2 = container.read(appSessionProvider);
    expect(st2.entries.single.pendingComments, isEmpty);
    expect(fake.replaces.length, 1, reason: '整条重加密推替换');
  });

  test('待同步标记：离线编辑正文标正文（原有评论不标），冲正清空', () async {
    await bootstrap();
    await pubOffline();
    await session.syncNow();
    fake.online = false;
    await session.updateEntry(
        container.read(appSessionProvider).entries.single,
        text: '改过的正文',
        mood: null,
        tags: []);
    fake.online = true;
    final st = container.read(appSessionProvider);
    expect(st.entries.single.textPending, isTrue);
    expect(st.entries.single.pendingComments, isEmpty);
    await session.syncNow();
    expect(
        container.read(appSessionProvider).entries.single.textPending, isFalse);
  });
}

/// FakeApi.replace 记录体（三字段分离）→ Envelope JSON（解密用）。
Map<String, dynamic> _cipherJson(({int id, Map<String, dynamic> body}) r) => {
      'ciphertext': r.body['ciphertext'],
      'nonce_content': r.body['nonce_content'],
      'encrypted_cek': r.body['encrypted_cek'],
    };
