// 标签/心情云端双写（晨 17 §4.1）+ 输入草稿（§4.12）。
// 双写契约能力（02 手册只读）：POST /config/tags 同 device 同名=更新；
// GET /config/moods 只读种子。拉取=补缺合并（同名本地优先），删除名单防复活。
import 'dart:convert';

import 'package:diary_app/core/api/api_client.dart';
import 'package:diary_app/core/config/app_defaults.dart';
import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class CfgFakeApi extends ApiClient {
  int nextTagId = 10;
  int nextMoodId = 100;
  final tagSaves = <({String name, String color})>[];
  final moodSaves = <({String moodKey, String emoji, String color, String? name})>[];
  final moodDeletes = <String>[];
  bool failMoodWrite = false; // 推送失败静默验证
  List<TagCfg> serverTags = [];
  List<MoodCfgServer> serverMoods = [];

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
  Future<SyncResult> sync(String sinceIso) async =>
      SyncResult(cursor: 'c', list: const []);

  @override
  Future<List<TagCfg>> configTags() async => serverTags;

  @override
  Future<int> saveTag({required String name, required String color}) async {
    tagSaves.add((name: name, color: color));
    final existing = serverTags.indexWhere((t) => t.name == name);
    if (existing >= 0) {
      final old = serverTags[existing];
      serverTags[existing] =
          TagCfg(id: old.id, name: name, color: color, sort: old.sort);
      return old.id;
    }
    serverTags = [
      ...serverTags,
      TagCfg(id: nextTagId, name: name, color: color, sort: nextTagId),
    ];
    return nextTagId++;
  }

  @override
  Future<List<MoodCfgServer>> configMoods() async => serverMoods;

  @override
  Future<int> saveMood({
    required String moodKey,
    required String emoji,
    required String color,
    String? name,
  }) async {
    if (failMoodWrite) throw Exception('端点未上线（404 同型）');
    moodSaves.add((moodKey: moodKey, emoji: emoji, color: color, name: name));
    final existing = serverMoods.indexWhere((m) => m.moodKey == moodKey);
    if (existing >= 0) {
      final old = serverMoods[existing];
      serverMoods[existing] = MoodCfgServer(
          moodKey: moodKey,
          emoji: emoji,
          color: color,
          sort: old.sort,
          name: name ?? old.name);
      return old.sort;
    }
    serverMoods = [
      ...serverMoods,
      MoodCfgServer(
          moodKey: moodKey,
          emoji: emoji,
          color: color,
          sort: nextMoodId,
          name: name),
    ];
    return nextMoodId++;
  }

  @override
  Future<void> deleteMood(String moodKey) async {
    if (failMoodWrite) throw Exception('端点未上线（404 同型）');
    moodDeletes.add(moodKey);
    serverMoods =
        [for (final m in serverMoods) if (m.moodKey != moodKey) m];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late db.MemoryLocalStore store;
  late CfgFakeApi fake;

  Future<void> bootstrap() async {
    container = ProviderContainer();
    fake = CfgFakeApi();
    session = container.read(appSessionProvider.notifier);
    store = db.MemoryLocalStore();
    await session.debugUseStore(store);
    session.debugUseApi(fake);
    session.debugHoldFlush = true;
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  tearDown(() {
    container.dispose();
    AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    AppDefaults.tagColorOverrides = {};
    AppDefaults.serverMoods = const [];
  });

  test('双写·推：新增预设/改色 → saveTag 推当前生效色（同名=更新）', () async {
    await bootstrap();
    await session.addTagPreset('美食');
    expect(fake.tagSaves.length, 1);
    expect(fake.tagSaves.single.name, '美食');
    expect(fake.tagSaves.single.color,
        AppDefaults.tagColorName('美食'), reason: '自动哈希色物化为显式色');
    final n = fake.tagSaves.length;
    await session.setTagColor('美食', 'pink');
    expect(fake.tagSaves.length, n + 1);
    expect(fake.tagSaves.last, (name: '美食', color: 'pink'));
    expect(fake.serverTags.where((t) => t.name == '美食').single.color, 'pink',
        reason: '同名=更新，不重复建行');
  });

  test('双写·拉：服务器独有预设并入（色随预设），同名本地优先不覆盖', () async {
    await bootstrap();
    fake.serverTags = [
      TagCfg(id: 1, name: '旅行', color: 'orange', sort: 1),
      TagCfg(id: 2, name: '吐槽', color: 'red', sort: 2), // 本地已有同名
    ];
    AppDefaults.tagColorOverrides['吐槽'] = 'pink'; // 本地自定义优先
    await session.syncNow();
    expect(AppDefaults.tagPresets, contains('旅行'));
    expect(AppDefaults.tagColorOverrides['旅行'], 'orange');
    expect(AppDefaults.tagColorOverrides['吐槽'], 'pink',
        reason: '同名本地优先（契约无时间戳）');
    expect(AppDefaults.tagPresets, isNot(contains('red')), reason: '不改名只补缺');
  });

  test('删除名单防复活：本地删掉的预设，拉取不再并入', () async {
    await bootstrap();
    await session.removeTagPreset('趣事'); // 默认预设之一
    fake.serverTags = [TagCfg(id: 3, name: '趣事', color: 'blue', sort: 3)];
    await session.syncNow();
    expect(AppDefaults.tagPresets, isNot(contains('趣事')));
    final kv = await store.kvAll();
    expect(jsonDecode(kv['cfg.tagDeleted']!), contains('趣事'));
  });

  test('心情全量覆盖拉取（§5.14 服务端唯一事实源）：serverMoods 替换 + 名称回落 + 快照落盘', () async {
    await bootstrap();
    fake.serverMoods = [
      const MoodCfgServer(moodKey: 'happy', emoji: '😄', color: '#34C759', sort: 0, name: '超开心'),
      const MoodCfgServer(moodKey: 'm9', emoji: '🧘', color: 'blue', sort: 9),
    ];
    await session.syncNow();
    expect(AppDefaults.allMoods.length, 2, reason: '服务端列表整体覆盖（不再补缺合并）');
    expect(AppDefaults.moodOf('happy').name, '超开心', reason: '服务端 name 优先（缺口 #9）');
    expect(AppDefaults.moodOf('happy').emoji, '😄');
    expect(AppDefaults.moodOf('m9').name, 'm9', reason: '服务端 name 缺失 + 非种子 → key 本身');
    expect(AppDefaults.moodOf('m9').colorHex, 0xFF007AFF,
        reason: '非 #RRGGBB hex → 色名反查（blue 在 8 色板内）');
    final kv = await store.kvAll();
    expect(kv['cfg.moodServer'], contains('m9'), reason: '快照落盘（离线显示上次数据）');
    // 空表（异常/清库瞬间）→ 空表守卫不覆盖：保留上次快照（only 未拉取过才回落种子）
    fake.serverMoods = [];
    await session.syncNow();
    expect(AppDefaults.allMoods.length, 2, reason: '空表不覆盖，快照保留');
    AppDefaults.serverMoods = const []; // 模拟快照缺失（首次启动）
    expect(AppDefaults.allMoods.length, 6, reason: '无快照 → allMoods 回落静态种子');
  });

  test('心情增/改即推（§5.14 唯一写路径）：推送成功后重拉覆盖，默认心情同路径', () async {
    await bootstrap();
    final m = await session.addMood('冲', '🚀', AppDefaults.tagColorHex['blue']!);
    expect(fake.moodSaves.single.moodKey, m.key);
    expect(fake.moodSaves.single.emoji, '🚀');
    expect(fake.moodSaves.single.color,
        matches(RegExp(r'^#[0-9A-Fa-f]{6}$')), reason: 'colorHex → #RRGGBB（服务端契约）');
    expect(fake.moodSaves.single.name, '冲', reason: 'name 随写请求（缺口 #9 落地即生效）');
    expect(AppDefaults.serverMoods.map((x) => x.key), contains(m.key),
        reason: '推送成功 → 重拉服务端列表覆盖本地');
    expect(AppDefaults.moodOf(m.key).name, '冲');
    await session.updateMood(m.key, '🌟', '冲鸭', AppDefaults.tagColorHex['red']!);
    expect(fake.moodSaves.length, 2);
    expect(fake.moodSaves.last.moodKey, m.key, reason: '同 moodKey 幂等更新');
    expect(fake.moodSaves.last.emoji, '🌟');
    expect(AppDefaults.moodOf(m.key).emoji, '🌟');
    // 默认心情同路径推送（§5.9「本地覆盖不推」语义废除——服务端=唯一事实源）
    await session.updateMood('happy', '😀', '超开心', AppDefaults.tagColorHex['blue']!);
    expect(fake.moodSaves.last.moodKey, 'happy');
    expect(AppDefaults.moodOf('happy').name, '超开心');
    expect(AppDefaults.moodOf('happy').emoji, '😀');
  });

  test('心情删除（§5.14）：推 deleteMood + 重拉；默认心情不可删（全局表保护）', () async {
    await bootstrap();
    await session.addMood('临时', '🧪', AppDefaults.tagColorHex['blue']!);
    final key = fake.moodSaves.single.moodKey;
    await session.removeMood(key);
    expect(fake.moodDeletes, [key]);
    expect(AppDefaults.serverMoods.map((x) => x.key), isNot(contains(key)),
        reason: '删除成功 → 重拉后本地消失（无删除名单，服务端物理删）');
    // 默认种子心情拒绝删除（服务端是全局表，删种子影响所有设备）
    await expectLater(session.removeMood('happy'), throwsFormatException);
    expect(fake.moodDeletes, [key]);
  });

  test('心情推送失败不落本地（§5.14 严格云一致）：addMood/updateMood/removeMood 上抛', () async {
    await bootstrap();
    fake.failMoodWrite = true;
    await expectLater(
        session.addMood('冲', '🚀', AppDefaults.tagColorHex['blue']!), throwsA(anything));
    expect(AppDefaults.serverMoods.map((x) => x.key), isNot(contains('m')),
        reason: '失败不落本地（离线不可改，下次联网重试）');
    await expectLater(
        session.updateMood('happy', '😀', '超开心', 0), throwsA(anything));
    expect(AppDefaults.moodOf('happy').emoji, '😊', reason: '改失败 → 服务端值不动');
    await expectLater(session.removeMood('happy'), throwsFormatException);
  });

  test('草稿：保存→读取往返；防抖合并写；清除后为空', () async {
    await bootstrap();
    session.saveDraft('new', jsonEncode({'text': '没写完的一句'}));
    // loadDraft 先落防抖中的值 → 立即读也能拿到最新
    expect(await session.loadDraft('new'),
        jsonEncode({'text': '没写完的一句'}));
    session.saveDraft('cmt.1', '评论草稿');
    await session.clearDraft('new');
    expect(await session.loadDraft('new'), isNull);
    expect(await session.loadDraft('cmt.1'), '评论草稿', reason: '多键互不影响');
    final kv = await store.kvAll();
    expect(kv['draft.new'], isNull);
    expect(kv['draft.cmt.1'], '评论草稿');
  });

  test('注销清草稿与删除名单（KV 一并清除）', () async {
    await bootstrap();
    session.saveDraft('new', '草稿');
    await session.removeTagPreset('趣事');
    await session.logout();
    final kv = await store.kvAll();
    expect(kv['draft.new'], isNull);
    expect(kv['cfg.tagDeleted'], isNull);
  });
}
