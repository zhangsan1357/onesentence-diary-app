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
  final tagSaves = <({String name, String color})>[];
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
