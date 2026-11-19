// 服务端统计消费（晨 19 §5.10）：stats 解析 + syncNow 置位/失败保留旧值 +
// computeStreak 边界三类（与服务端 EntryService.stats 定义逐字对齐：锚点=今天
// 有记录?今天:(昨天有记录?昨天:无)→向前逐日连续，今天昨天都无=0）。
import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends ApiClient {
  int nextId = 101;
  bool statsFail = false;
  int statsCalls = 0;
  List<ServerEntry> serverList = [];

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
  Future<SyncResult> sync(String sinceIso) async =>
      SyncResult(cursor: 'c', list: serverList);

  @override
  Future<StatsResult> stats({int days = 365}) async {
    statsCalls++;
    if (statsFail) throw Exception('端点异常');
    final today = DateTime.now();
    final d = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return StatsResult(
      total: serverList.length,
      days: serverList.isEmpty ? 0 : 1,
      streak: serverList.isEmpty ? 0 : 1,
      heatmap: serverList.isEmpty ? [] : [(date: d, count: serverList.length)],
      perMonth: [],
    );
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
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  tearDown(() {
    try {
      container.dispose();
    } catch (_) {
      // 纯解析用例不走 bootstrap（late 未赋值）→ 跳过
    }
  });

  test('stats 解析：total/days/streak/稀疏 heatmap/perMonth', () {
    final r = StatsResult.fromJson({
      'total': 12,
      'days': 5,
      'streak': 2,
      'heatmap': [
        {'date': '2026-11-16', 'count': 3},
        {'date': '2026-11-17', 'count': 9},
      ],
      'perMonth': [
        {'month': '2026-11', 'count': 12},
      ],
    });
    expect(r.total, 12);
    expect(r.days, 5);
    expect(r.streak, 2);
    expect(r.heatmap.length, 2, reason: '稀疏：仅含有记录的日子');
    expect(r.heatmap.first.date, '2026-11-16', reason: 'date ASC');
    expect(r.heatmap.last.count, 9);
    expect(r.perMonth.single.month, '2026-11');
    // 容错：缺字段回零
    final empty = StatsResult.fromJson(const {});
    expect(empty.total, 0);
    expect(empty.heatmap, isEmpty);
  });

  test('syncNow 成功置位 AppState.stats（服务端 total/streak）', () async {
    await bootstrap();
    // 时序无关（CI 反馈）：汇聚点在 bootstrap 内就可能先置位 stats（空快照），
    // 不断「初始为 null」，只断发布+syncNow 后的值。
    await session.publish(text: '今天一句', mood: null, tags: [], media: []);
    await session.syncNow();
    final st = container.read(appSessionProvider);
    expect(st.stats, isNotNull);
    expect(st.stats!.total, 1);
    expect(st.stats!.streak, 1, reason: '今天有记录 → 锚点今天');
    expect(fake.statsCalls, greaterThanOrEqualTo(1));
  });

  test('stats 拉取失败静默保留旧值（离线回落本地计算）', () async {
    await bootstrap();
    await session.publish(text: '今天一句', mood: null, tags: [], media: []);
    await session.syncNow();
    final old = container.read(appSessionProvider).stats;
    expect(old, isNotNull);
    await session.publish(text: '第二句', mood: null, tags: [], media: []);
    fake.statsFail = true;
    await session.syncNow();
    final st = container.read(appSessionProvider);
    expect(st.stats!.total, old!.total, reason: '失败不覆盖（本地兜底显示旧值）');
    expect(st.entries.length, 2, reason: '条目本身照常本地先行/冲正');
  });

  test('computeStreak：今天有记录（长连签）', () {
    final now = DateTime(2026, 11, 17);
    DiaryEntry e(String d) => DiaryEntry(
          localId: 'x$d',
          serverId: 1,
          date: d,
          payload: const EntryPayload(text: 't', time: '09:00', mood: null),
          cipherJson: null,
          updatedAt: now,
        );
    expect(computeStreak(
        [e('2026-11-17'), e('2026-11-16'), e('2026-11-15')], now), 3);
  });

  test('computeStreak：今天未写昨天写（不断签，从昨天回数）', () {
    final now = DateTime(2026, 11, 17);
    DiaryEntry e(String d) => DiaryEntry(
          localId: 'x$d',
          serverId: 1,
          date: d,
          payload: const EntryPayload(text: 't', time: '09:00', mood: null),
          cipherJson: null,
          updatedAt: now,
        );
    expect(computeStreak([e('2026-11-16'), e('2026-11-15')], now), 2);
  });

  test('computeStreak：今天昨天都无 = 0', () {
    final now = DateTime(2026, 11, 17);
    DiaryEntry e(String d) => DiaryEntry(
          localId: 'x$d',
          serverId: 1,
          date: d,
          payload: const EntryPayload(text: 't', time: '09:00', mood: null),
          cipherJson: null,
          updatedAt: now,
        );
    expect(computeStreak([e('2026-11-14'), e('2026-11-15')], now), 0);
    expect(computeStreak(const [], now), 0);
  });
}
