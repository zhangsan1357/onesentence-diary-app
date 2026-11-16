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
  final moodSaves = <({String moodKey, String emoji, String color})>[];
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
  }) async {
    if (failMoodWrite) throw Exception('端点未上线（404 同型）');
    moodSaves.add((moodKey: moodKey, emoji: emoji, color: color));
    final existing = serverMoods.indexWhere((m) => m.moodKey == moodKey);
    if (existing >= 0) {
      final old = serverMoods[existing];
      serverMoods[existing] = MoodCfgServer(
          moodKey: moodKey, emoji: emoji, color: color, sort: old.sort);
      return old.sort;
    }
    serverMoods = [
      ...serverMoods,
      MoodCfgServer(
          moodKey: moodKey, emoji: emoji, color: color, sort: nextMoodId),
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
    AppDefaults.moodOverrides = {};
    AppDefaults.customMoods = const [];
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

  test('心情补缺：服务器种子仅填充本地没有的 key，已有 key 不动', () async {
    await bootstrap();
    AppDefaults.customMoods = [
      const MoodCfg(key: 'm1', emoji: '🚀', name: '冲', colorHex: 0xFF123456),
    ];
    fake.serverMoods = [
      MoodCfgServer(moodKey: 'happy', emoji: '😊', color: 'green', sort: 0),
      MoodCfgServer(moodKey: 'm9', emoji: '🧘', color: 'blue', sort: 9),
    ];
    await session.syncNow();
    final keys = AppDefaults.customMoods.map((m) => m.key);
    expect(keys, contains('m9'), reason: '本地没有 → 补缺并入自定义列表');
    expect(keys, isNot(contains('happy')), reason: '默认 6 心情本地已有 → 不动');
    expect(AppDefaults.customMoods
        .where((m) => m.key == 'm1')
        .single.emoji, '🚀', reason: '本地自定义优先');
  });

  test('双写·推·心情（§5.9/§5.10）：自定义增/改 → saveMood（colorHex→#RRGGBB），默认覆盖不推', () async {
    await bootstrap();
    final m = await session.addMood('冲', '🚀', AppDefaults.tagColorHex['blue']!);
    expect(fake.moodSaves.single.moodKey, m.key);
    expect(fake.moodSaves.single.emoji, '🚀');
    expect(fake.moodSaves.single.color,
        matches(RegExp(r'^#[0-9A-Fa-f]{6}$')), reason: 'colorHex → #RRGGBB（服务端契约）');
    expect(fake.moodSaves.single.color,
        '#${(AppDefaults.tagColorHex['blue']! & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}');
    expect(fake.serverMoods.where((x) => x.moodKey == m.key).single.emoji, '🚀',
        reason: '同 moodKey=更新幂等');
    await session.updateMood(m.key, '🌟', '冲鸭', AppDefaults.tagColorHex['red']!);
    expect(fake.moodSaves.length, 2);
    expect(
        fake.moodSaves.last.moodKey, m.key, reason: '同 moodKey 幂等更新');
    expect(fake.moodSaves.last.emoji, '🌟');
    final n = fake.moodSaves.length;
    await session.updateMood('happy', '😄', '开心改', AppDefaults.tagColorHex['blue']!);
    expect(fake.moodSaves.length, n, reason: '默认心情显示覆盖不推送（设备本地）');
    expect(AppDefaults.moodOverrides['happy']!.name, '开心改');
  });

  test('心情删除名单防复活（§5.9）：删除服务端来源心情 → 拉取不再并入 + 名单持久化', () async {
    await bootstrap();
    fake.serverMoods = [
      MoodCfgServer(moodKey: 'm77', emoji: '🧘', color: 'blue', sort: 7),
    ];
    await session.syncNow();
    expect(AppDefaults.customMoods.map((m) => m.key), contains('m77'),
        reason: '先补缺并入');
    await session.removeMood('m77');
    expect(AppDefaults.customMoods.map((m) => m.key), isNot(contains('m77')));
    expect(fake.moodDeletes, ['m77'], reason: '删除推 deleteMood（静默）');
    final kv = await store.kvAll();
    expect(jsonDecode(kv['cfg.moodDeleted']!), contains('m77'));
    await session.syncNow();
    expect(AppDefaults.customMoods.map((m) => m.key), isNot(contains('m77')),
        reason: '拉取补缺过滤名单 → 不复活');
  });

  test('心情推送失败静默（§5.9）：端点未上线不冒泡、本地照常生效', () async {
    await bootstrap();
    fake.failMoodWrite = true;
    final m = await session.addMood('冲', '🚀', AppDefaults.tagColorHex['blue']!);
    expect(AppDefaults.customMoods.map((x) => x.key), contains(m.key),
        reason: '本地照常落（推送先行模式）');
    expect(fake.moodSaves, isEmpty, reason: '失败不记桩');
    await session.removeMood(m.key);
    expect(fake.moodDeletes, isEmpty, reason: '删除推失败同样静默');
    expect(AppDefaults.customMoods.map((x) => x.key), isNot(contains(m.key)));
    final kv = await store.kvAll();
    expect(jsonDecode(kv['cfg.moodDeleted']!), contains(m.key),
        reason: '名单仍持久化（复活防护不依赖端点）');
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
