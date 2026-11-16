// 媒体全屏查看器（晨 19 §5.3）：查看管线（下载→解 CEK 包裹→AES-GCM 解密）
// 会话级往返 + 查看器 UI（翻页/重试/保存）+ ImageGrid 门控（无密钥引用不可点）。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:diary_app/widgets/common.dart';
import 'package:diary_app/widgets/media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 API：记录上传媒体按 id 供 downloadMedia 取回（其余最小面）。
class FakeApi extends ApiClient {
  int nextId = 101;
  int nextMediaId = 900;
  final mediaById = <int, List<int>>{};
  int downloadCalls = 0;
  List<ServerEntry> serverList = [];

  @override
  Future<DeviceRegResult> registerDevice({
    required String userId,
    required String deviceNo,
    required String name,
    required String userKeyHex,
  }) async =>
      DeviceRegResult(token: 't-fake', deviceId: 1);

  @override
  Future<int> createEntry({
    required String entryDate,
    required String ciphertext,
    required String nonceContent,
    required String encryptedCek,
  }) async {
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
  Future<({int id, int size, String sha256})> uploadMedia(
      List<int> bytes) async {
    mediaById[nextMediaId] = bytes;
    return (id: nextMediaId++, size: bytes.length, sha256: '');
  }

  @override
  Future<List<int>> downloadMedia(int id) async {
    downloadCalls++;
    final b = mediaById[id];
    if (b == null) {
      throw DioException(
          requestOptions: RequestOptions(path: '/media/$id'));
    }
    return b;
  }

  @override
  Future<SyncResult> sync(String sinceIso) async =>
      SyncResult(cursor: 'c', list: serverList);
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
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  tearDown(() {
    try {
      container.dispose();
    } catch (_) {
      // widget 级用例不走 bootstrap（late 未赋值）→ 跳过
    }
  });

  test('查看管线往返：加密上传 → 下载解密逐字节相等（§5.3）', () async {
    await bootstrap();
    final original = Uint8List.fromList(List.generate(512, (i) => i % 251));
    await session.publish(
        text: '带图一句',
        mood: null,
        tags: [],
        media: [MediaInput(kind: 'image', bytes: original)]);
    await session.syncNow(); // 冲正：媒体上传 + 引用注入 + create
    final ref = container.read(appSessionProvider).entries.first.payload.media.single;
    expect(ref.cekB64, isNotEmpty, reason: '冲正后引用带密钥包裹');
    final bytes = await session.mediaBytes(ref);
    expect(bytes, original, reason: '下载密文 → 解 CEK → AES-GCM 解密还原原文');
  });

  test('查看管线缓存：同引用二次取不再下载', () async {
    await bootstrap();
    final original = Uint8List.fromList([1, 2, 3, 4]);
    await session.publish(
        text: '带图一句', mood: null, tags: [], media: [MediaInput(kind: 'image', bytes: original)]);
    await session.syncNow();
    final ref = container.read(appSessionProvider).entries.first.payload.media.single;
    await session.mediaBytes(ref);
    expect(fake.downloadCalls, 1);
    await session.mediaBytes(ref);
    expect(fake.downloadCalls, 1, reason: '会话级缓存命中');
  });

  test('空密钥引用拒绝（demo/未冲正）+ 未知媒体 id 报错', () async {
    await bootstrap();
    expect(
        () async => session.mediaBytes(const MediaRef(id: 1, kind: 'image', cekB64: '')),
        throwsA(isA<FormatException>()));
    final original = Uint8List.fromList([1, 2, 3]);
    await session.publish(
        text: '带图一句', mood: null, tags: [], media: [MediaInput(kind: 'image', bytes: original)]);
    await session.syncNow();
    final ref = container.read(appSessionProvider).entries.first.payload.media.single;
    // 服务器从未见过该 id（FakeApi 只存 uploadMedia 收到的）
    expect(() async => session.mediaBytes(MediaRef(id: 9999, kind: 'image', cekB64: ref.cekB64)),
        throwsA(isA<DioException>()));
  });

  // ---------- widget 级 ----------

  testWidgets('查看器：暗底显示 + 索引标题 + 关闭返回', (tester) async {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')); // 1x1 PNG
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return Center(
            child: TextButton(
              onPressed: () => MediaViewer.show(
                context,
                images: [
                  const MediaRef(id: 1, kind: 'image', cekB64: 'a'),
                  const MediaRef(id: 2, kind: 'image', cekB64: 'b'),
                ],
                initialIndex: 1,
                fetchBytes: (_) async => png,
              ),
              child: const Text('open'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget, reason: '字节渲染');
    expect(find.text('2/2'), findsOneWidget, reason: '索引标题');
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget, reason: '关闭返回');
  });

  testWidgets('查看器：加载失败 → 页内重试成功', (tester) async {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')); // 1x1 PNG
    var fail = true;
    await tester.pumpWidget(MaterialApp(
      home: MediaViewer(
        images: const [MediaRef(id: 1, kind: 'image', cekB64: 'a')],
        initialIndex: 0,
        fetchBytes: (_) async {
          if (fail) throw Exception('网络断');
          return png;
        },
      ),
    ));
    await tester.pump();
    expect(find.text('加载失败'), findsOneWidget);
    fail = false; // 网络恢复
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget, reason: '重试成功渲染');
  });

  testWidgets('查看器：保存按钮加载后启用，注入 saveBytes 被调 + 提示', (tester) async {
    final png = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')); // 1x1 PNG
    Uint8List? saved;
    final gate = Completer<Uint8List>(); // 门控：加载未完成时按钮应禁用
    await tester.pumpWidget(MaterialApp(
      home: MediaViewer(
        images: const [MediaRef(id: 1, kind: 'image', cekB64: 'a')],
        initialIndex: 0,
        fetchBytes: (_) => gate.future,
        saveBytes: (b) async => saved = b,
      ),
    ));
    await tester.pump();
    final saveBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.save_alt));
    expect(saveBtn.onPressed, isNull, reason: '未加载完禁用');
    gate.complete(png);
    await tester.pumpAndSettle();
    final saveBtn2 = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.save_alt));
    expect(saveBtn2.onPressed, isNotNull, reason: '加载完启用');
    await tester.tap(find.byIcon(Icons.save_alt));
    await tester.pump();
    expect(saved, png);
    expect(find.text('已保存到相册 ✓'), findsOneWidget);
  });

  testWidgets('ImageGrid 门控：无密钥引用不响应点按，真实媒体回调', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ImageGrid(
          images: const [
            MediaRef(id: 5, kind: 'image', cekB64: ''), // demo/未冲正占位
            MediaRef(id: 6, kind: 'image', cekB64: 'x'),
          ],
          onOpen: (_) => opened++,
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(opened, 0, reason: '占位不响应（demo 不可点）');
    await tester.tap(find.byType(GestureDetector).at(1));
    await tester.pump();
    expect(opened, 1, reason: '真实媒体回调');
  });
}
