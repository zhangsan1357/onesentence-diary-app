// 评论长按菜单（晨 19 §5.2）：评论内嵌载荷 → 编辑/删除 = 重建载荷走既有冲正。
// 会话级（FakeApi+MemoryLocalStore 全链路：载荷重建/标记重排/冲正推云）+
// widget 级（菜单差异/复制/行内编辑/删除确认）。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/e2ee/envelope.dart';
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/crypto_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:diary_app/features/feed/feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 API：online=false 模拟云端不可达（与 offline_sync_test 同型，最小面）。
class FakeApi extends ApiClient {
  bool online = true;
  int nextId = 101;
  final replaces = <({int id, Map<String, dynamic> body})>[];
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
    serverList = [for (final e in serverList) if (e.id != id) e];
  }

  @override
  Future<SyncResult> sync(String sinceIso) async {
    if (!online) throw _net();
    return SyncResult(cursor: 'c', list: serverList);
  }
}

/// FakeApi.replace 记录体（三字段分离）→ Envelope JSON（解密用）。
Map<String, dynamic> _cipherJson(({int id, Map<String, dynamic> body}) r) => {
      'ciphertext': r.body['ciphertext'],
      'nonce_content': r.body['nonce_content'],
      'encrypted_cek': r.body['encrypted_cek'],
    };

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
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  tearDown(() => container.dispose());

  /// 发布一条并冲正到云（serverId 回填），返回最新内存条目。
  Future<DiaryEntry> pubAndSync() async {
    await session.publish(text: '正文一句', mood: null, tags: [], media: []);
    await session.syncNow();
    return container.read(appSessionProvider).entries.first;
  }

  /// 解出服务端（replace 推上去）载荷。
  Future<EntryPayload> serverPayload() async {
    final kv = await store.kvAll();
    final s = sessionFromPlain(readKeystore((k) => kv[k])!);
    final bytes = await Envelope.decrypt(
        jsonEncode(_cipherJson(fake.replaces.single)), s.privateKey);
    return EntryPayload.decode(utf8.decode(bytes));
  }

  test('编辑评论 → 载荷重建 + 标记并入去重 + 冲正推云后新文本在密文内', () async {
    await bootstrap();
    final e = await pubAndSync();
    await session.addComment(e, '第一版');
    final timeBefore =
        container.read(appSessionProvider).entries.first.payload.comments.single.time;
    // 标记：addComment 已并入 0；edit 再并入 0 → 去重不重复
    expect(
        parsePendingMeta((await store.allEntries()).single.pendingMeta)
            .comments,
        [0]);
    await session.editComment(
        container.read(appSessionProvider).entries.first, 0, '第二版');
    final st = container.read(appSessionProvider);
    expect(st.entries.first.payload.comments.single.text, '第二版');
    expect(st.entries.first.payload.comments.single.time, timeBefore,
        reason: '编辑保留原评论时间');
    expect(parsePendingMeta((await store.allEntries()).single.pendingMeta).comments,
        [0], reason: '编辑并入去重');
    await session.syncNow();
    expect(fake.replaces.length, 1, reason: 'serverId 已回填 → replace 路径');
    expect((await serverPayload()).comments.single.text, '第二版');
    expect((await store.allEntries()).single.pendingMeta, '',
        reason: '冲正成功标记清零');
    expect(container.read(appSessionProvider).entries.first.pendingComments,
        isEmpty);
  });

  test('删除评论 → 标记索引重排（其后 -1）+ 冲正后服务端载荷少一条', () async {
    await bootstrap();
    final e = await pubAndSync();
    await session.addComment(e, '第一条');
    await session.addComment(
        container.read(appSessionProvider).entries.first, '第二条');
    await session.addComment(
        container.read(appSessionProvider).entries.first, '第三条');
    expect(parsePendingMeta((await store.allEntries()).single.pendingMeta).comments,
        [0, 1, 2]);
    await session.deleteComment(
        container.read(appSessionProvider).entries.first, 1); // 删中间
    final st = container.read(appSessionProvider);
    expect(st.entries.first.payload.comments.map((c) => c.text).toList(),
        ['第一条', '第三条']);
    // 删除后行号前移：标记 [0,2] → [0,1]（整体 -1），删除本身不加标
    expect(parsePendingMeta((await store.allEntries()).single.pendingMeta).comments,
        [0, 1]);
    await session.syncNow();
    expect((await serverPayload()).comments.map((c) => c.text).toList(),
        ['第一条', '第三条']);
  });

  test('删除未冲正的新评论 → 标记随内容消失，载荷回落与云端一致', () async {
    await bootstrap();
    final e = await pubAndSync();
    await session.addComment(e, '新评论'); // 标记 [0]，未冲正
    await session.deleteComment(
        container.read(appSessionProvider).entries.first, 0);
    final st = container.read(appSessionProvider);
    expect(st.entries.first.payload.comments, isEmpty);
    expect(parsePendingMeta((await store.allEntries()).single.pendingMeta).comments,
        isEmpty, reason: '被删的下标 0 从标记移除（云端从未见过该评论）');
    expect(st.pendingCount, 1, reason: '载荷仍变过 → 待替换留队（幂等冲正）');
    await session.syncNow();
    expect(fake.replaces.length, 1);
    expect((await serverPayload()).comments, isEmpty);
  });

  // ---------- widget 级（菜单交互） ----------

  DiaryEntry entry({List<EntryComment> comments = const []}) => DiaryEntry(
        localId: 'e1',
        serverId: 1,
        date: '2026-11-17',
        payload: EntryPayload(
            text: '正文', time: '09:30', mood: null, comments: comments),
        cipherJson: null,
        updatedAt: DateTime(2026),
      );

  Future<(ProviderContainer, db.MemoryLocalStore)> wBootstrap(
      WidgetTester tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final session = c.read(appSessionProvider.notifier);
    final st = db.MemoryLocalStore();
    await session.debugUseStore(st);
    session.debugHoldFlush = true;
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    await tester.pump(const Duration(milliseconds: 50));
    // 放掉 _loadHolidays 资产加载的 2s timeout Timer（否则测试收尾判 pending timer）
    await tester.pump(const Duration(seconds: 3));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return (c, st);
  }

  Future<void> wPumpEntry(WidgetTester tester, ProviderContainer c,
      DiaryEntry e) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            EntryView(entry: e, isFirstOfDay: true, weekday: '日'),
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> wOpenComments(
      WidgetTester tester, ProviderContainer c, DiaryEntry e) async {
    await wPumpEntry(tester, c, e);
    await tester.tap(find.text('${e.payload.comments.length}'));
    await tester.pumpAndSettle();
  }

  testWidgets('长按自己评论 → 菜单（复制/编辑/删除）；他人评论仅复制', (tester) async {
    final (c, _) = await wBootstrap(tester);
    final e = entry(comments: [
      const EntryComment(who: '我', text: '我的评论', time: '2026-11-17 09:35'),
      const EntryComment(who: '她', text: '她人的评论', time: '2026-11-17 09:40'),
    ]);
    await wOpenComments(tester, c, e);
    await tester.longPress(find.text('我的评论'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsNothing, reason: '取消后菜单关闭');
    // 他人评论：只有复制
    await tester.longPress(find.text('她人的评论'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('复制评论 → 系统剪贴板收到原文 + 提示已复制', (tester) async {
    final (c, _) = await wBootstrap(tester);
    String? copied;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestWidgetsFlutterBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final e = entry(comments: [
      const EntryComment(who: '我', text: '要复制的句子', time: '2026-11-17 09:35'),
    ]);
    await wOpenComments(tester, c, e);
    await tester.longPress(find.text('要复制的句子'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, '要复制的句子');
    expect(find.text('已复制'), findsOneWidget);
  });

  testWidgets('编辑行内：预填原文 → 改文本保存 → 会话层落库载荷更新', (tester) async {
    final (c, st) = await wBootstrap(tester);
    final e = entry(comments: [
      const EntryComment(who: '我', text: '第一版', time: '2026-11-17 09:35'),
    ]);
    await wOpenComments(tester, c, e);
    await tester.longPress(find.text('第一版'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2),
        reason: '行内编辑框（预填）+ 底部输入框');
    expect(find.text('第一版'), findsOneWidget, reason: '编辑框预填原文');
    await tester.enterText(find.byType(TextField).first, '第二版');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget, reason: '保存后编辑框收起');
    // 会话层落库断言：store 行密文解出评论新文本
    final row = (await st.allEntries()).single;
    final kv = await st.kvAll();
    final s = sessionFromPlain(readKeystore((k) => kv[k])!);
    final payload = EntryPayload.decode(
        utf8.decode(await Envelope.decrypt(row.cipherJson!, s.privateKey)));
    expect(payload.comments.single.text, '第二版');
  });

  testWidgets('删除评论：确认弹窗 → 确认 → 载荷移除该评论', (tester) async {
    final (c, st) = await wBootstrap(tester);
    final e = entry(comments: [
      const EntryComment(who: '我', text: '待删评论', time: '2026-11-17 09:35'),
    ]);
    await wOpenComments(tester, c, e);
    await tester.longPress(find.text('待删评论'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除后不可恢复，确定删除？'), findsOneWidget,
        reason: '二次确认弹窗');
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    final row = (await st.allEntries()).single;
    final kv = await st.kvAll();
    final s = sessionFromPlain(readKeystore((k) => kv[k])!);
    final payload = EntryPayload.decode(
        utf8.decode(await Envelope.decrypt(row.cipherJson!, s.privateKey)));
    expect(payload.comments, isEmpty);
    // 注：测试以静态 entry 泵入 EntryView（不随 state 重建），UI 消失由真实
    // feed 的 provider 重建负责；这里断言落库载荷即编辑语义。
  });
}
