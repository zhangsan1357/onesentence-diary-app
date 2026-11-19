// 晨 19 §5.11 测试映射：setServerBase 健壮化（全角冒号/空格规范化 → 持久化、
// 非法地址不动现有配置、不可达地址不抛且横幅友好）+ unlock/unlockBiometric
// 服务端不可达不抛（解锁不被可达性阻断，转友好同步横幅）。
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:diary_app/features/compose/compose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可控注册失败的后端替身（其余全通）。
class ControllableApi extends ApiClient {
  bool failRegister = false;

  @override
  Future<DeviceRegResult> registerDevice({
    required String userId,
    required String deviceNo,
    required String name,
    required String userKeyHex,
    String? passKey,
  }) async {
    if (failRegister) throw Exception('boom-raw-english');
    return DeviceRegResult(token: 't-fake', deviceId: 1);
  }

  @override
  Future<SyncResult> sync(String sinceIso) async =>
      SyncResult(cursor: 'c', list: const []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late db.MemoryLocalStore store;
  late ControllableApi api;

  Future<void> bootstrap() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    api = ControllableApi();
    session = container.read(appSessionProvider.notifier);
    store = db.MemoryLocalStore();
    await session.debugUseStore(store);
    session.debugUseApi(api);
    session.debugHoldFlush = true;
  }

  test('setServerBase：全角冒号/空格规范化 → 合法地址持久化', () async {
    await bootstrap();
    // 中文输入法常见误输入：全角冒号 + 夹空格
    await session.setServerBase('192.168.1.8：9060');
    expect(await store.kvGet('api.base'), 'http://192.168.1.8:9060');
    final st = container.read(appSessionProvider);
    expect(st.serverBase, 'http://192.168.1.8:9060');
    expect(st.toast, '服务端地址已保存');
  });

  test('setServerBase：非法地址（端口含字母）→ 不动现有配置 + 中文提示', () async {
    await bootstrap();
    await session.setServerBase('127.0.0.1:9060'); // 先落一个合法地址
    expect(await store.kvGet('api.base'), 'http://127.0.0.1:9060');
    await session.setServerBase('http://192.168.1.8:9o60'); // Uri.parse 抛
    expect(await store.kvGet('api.base'), 'http://127.0.0.1:9060',
        reason: '非法地址不得覆盖现有配置');
    expect(container.read(appSessionProvider).serverStatus, '地址格式不对，请检查后重新输入');
    // 空输入 → 明确提示，不静默
    await session.setServerBase('');
    expect(container.read(appSessionProvider).serverStatus, '请输入服务端地址');
  });

  test('setServerBase：服务端不可达 → 不抛 + 横幅友好（无原始异常文本）', () async {
    await bootstrap();
    await session.createIdentity(RecoveryWords.generate(), '地址测试');
    api.failRegister = true;
    await session.setServerBase('127.0.0.1:59999');
    expect(await store.kvGet('api.base'), 'http://127.0.0.1:59999',
        reason: '探测失败不回滚：地址已持久化');
    final st = container.read(appSessionProvider);
    expect(st.toast, '服务端地址已保存');
    expect(st.serverStatus, '服务端已保存 · 暂时连不上，稍后可重试同步');
    expect(st.serverStatus!.contains('boom'), isFalse, reason: '原始异常不上屏');
  });

  test('setServerBase：可达（注册成功）→ 横幅「服务端已连接」', () async {
    await bootstrap();
    await session.createIdentity(RecoveryWords.generate(), '连接测试');
    await session.setServerBase('127.0.0.1:9060');
    expect(container.read(appSessionProvider).serverStatus, '服务端已连接 · http://127.0.0.1:9060');
  });

  test('unlock：服务端不可达 → 不抛、锁定解除、同步横幅友好', () async {
    await bootstrap();
    api.failRegister = true; // 全程未注册成功 → 无缓存 token，解锁走注册失败路径
    await session.createIdentity(RecoveryWords.generate(), '离线解锁');
    await Future<void>.delayed(const Duration(milliseconds: 50)); // 后台自举失败落定
    await session.setLockEnabled(true, passcode: '123456');
    session.lock();
    expect(container.read(appSessionProvider).locked, isTrue);
    await session.unlock('123456'); // §5.11：不再抛出
    final st = container.read(appSessionProvider);
    expect(st.locked, isFalse);
    expect(st.syncError, '服务端暂时连不上 · 内容已本地解密，稍后可手动刷新同步');
    expect(st.syncError!.contains('boom'), isFalse);
  });

  testWidgets('compose：自动锁触发 → 发布页自动 pop 露出锁屏（竞态兜底）', (tester) async {
    // 真实会话（绕过 demo）：内存库 + 假 API；compose 是全屏路由浮于锁屏
    // 覆盖层之上（HomeShell 内部），锁定后此前仍可点发布 → "Bad state: locked"
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = container.read(appSessionProvider.notifier);
    await session.debugUseStore(db.MemoryLocalStore());
    session.debugUseApi(ControllableApi());
    session.debugHoldFlush = true;
    await session.createIdentity(RecoveryWords.generate(), '锁竞态');
    await session.setLockEnabled(true, passcode: '123456');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(builder: (ctx) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(ctx).push(ComposeRoute());
          });
          return const Scaffold(body: Text('底层'));
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ComposePage), findsOneWidget);

    // 自动锁（退后台等价触发）：锁定即 pop 发布页
    session.lock();
    await tester.pumpAndSettle();
    expect(find.byType(ComposePage), findsNothing,
        reason: '锁定后发布页自动关闭，露出其下的锁屏覆盖层');
    expect(container.read(appSessionProvider).locked, isTrue);
    // 冲掉 createIdentity → _loadHolidays 的 2s asset timeout 定时器
    //（FakeAsync 收尾不允许挂起定时器）
    await tester.pump(const Duration(seconds: 3));
  });
}
