// 标签/心情显示配置：增删改查 + KV 持久化 + 重载（debugLoadCfg）。
// MemoryLocalStore 注入（debugUseStore），无网络依赖；静态表在 setUp/tearDown 复位。
import 'dart:convert';

import 'package:diary_app/core/config/app_defaults.dart';
import 'package:diary_app/core/db/database.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _resetDefaults() {
  AppDefaults.tagColorOverrides = {};
  AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
  AppDefaults.serverMoods = const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late AppSession session;
  late MemoryLocalStore store;

  setUp(() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    session = container.read(appSessionProvider.notifier);
    store = MemoryLocalStore();
    await session.debugUseStore(store);
    _resetDefaults();
  });
  tearDown(_resetDefaults);

  test('标签库：新增预设（初始含默认三项）→ KV 持久化 → 重载恢复 → 删除生效', () async {
    await session.addTagPreset('加班');
    expect(AppDefaults.tagPresets, containsAll(['吐槽', '趣事', '加班']));
    expect(await store.kvGet('cfg.tagPreset'), contains('加班'));
    // 模拟重启：清静态 → 同库重载
    AppDefaults.tagPresets = const [];
    await session.debugLoadCfg();
    expect(AppDefaults.tagPresets, containsAll(['吐槽', '加班']));
    // 删除预设（默认三项也在库内，可删）
    await session.removeTagPreset('吐槽');
    expect(AppDefaults.tagPresets, isNot(contains('吐槽')));
    // 显式空库：删光后 KV 为 '[]'，重载保持空（区别于键缺失回默认）
    for (final t in List.of(AppDefaults.tagPresets)) {
      await session.removeTagPreset(t);
    }
    expect(AppDefaults.tagPresets, isEmpty);
    AppDefaults.tagPresets = List.of(AppDefaults.defaultTags);
    await session.debugLoadCfg();
    expect(AppDefaults.tagPresets, isEmpty, reason: "cfg.tagPreset='[]' 应保持空库");
    // 新增校验：空/超长拒绝
    await expectLater(session.addTagPreset('  '), throwsFormatException);
    await expectLater(session.addTagPreset('长' * 17), throwsFormatException);
  });

  test('标签调色板：覆盖生效 → 恢复自动 → 非法色名重载时忽略', () async {
    final auto = AppDefaults.tagColor('工作');
    await session.setTagColor('工作', 'pink');
    expect(AppDefaults.tagColor('工作'), const Color(0xFFFF2D55));
    expect(await store.kvGet('cfg.tagColor'), contains('"工作":"pink"'));
    // 「自动」：清覆盖 → 回稳定哈希
    await session.setTagColor('工作', null);
    expect(AppDefaults.tagColor('工作'), auto);
    // 重载路径的坏数据按缺失处理
    await store.kvSet('cfg.tagColor', '{"工作":"nope"}');
    await session.debugLoadCfg();
    expect(AppDefaults.tagColor('工作'), auto, reason: '非法色名不入覆盖表');
  });

  test('心情快照（§5.14 服务端唯一事实源）：KV 重载恢复 serverMoods + 名称回落 + moodOf 语义', () async {
    // 未拉取/快照缺失 → allMoods 回落静态种子（首启与 demo 语义不变）
    expect(AppDefaults.allMoods.length, 6);
    expect(AppDefaults.moodOf('happy').name, '开心');
    // 写入服务端快照（_pullMoods 成功后的落盘形态）→ 重载恢复
    await store.kvSet('cfg.moodServer', jsonEncode([
      {'key': 'happy', 'emoji': '😄', 'name': '超开心', 'colorHex': 0xFF34C759},
      {'key': 'm1', 'emoji': '🚀', 'name': '冲', 'colorHex': 0xFF007AFF},
    ]));
    await session.debugLoadCfg();
    expect(AppDefaults.allMoods.length, 2, reason: '服务端列表=唯一事实源（覆盖式）');
    expect(AppDefaults.moodOf('happy').name, '超开心');
    expect(AppDefaults.moodOf('happy').emoji, '😄');
    expect(AppDefaults.moodOf('m1').name, '冲');
    // 种子名回落：服务端 name 缺失（缺口 #9 落地前）→ 静态表中文名
    expect(AppDefaults.moodNameOf('happy'), '开心');
    expect(AppDefaults.moodNameOf('happy', serverName: ''), '开心');
    expect(AppDefaults.moodNameOf('happy', serverName: '超开心'), '超开心');
    expect(AppDefaults.moodNameOf('m9'), 'm9', reason: '非种子 key 回落 key 本身');
    // 清空静态 → 重载仍恢复（快照是重启恢复路径）
    AppDefaults.serverMoods = const [];
    await session.debugLoadCfg();
    expect(AppDefaults.allMoods.length, 2);
    // 坏快照 → 按缺失处理 → 回落种子
    await store.kvSet('cfg.moodServer', 'not-json');
    AppDefaults.serverMoods = const [];
    await session.debugLoadCfg();
    expect(AppDefaults.serverMoods, isEmpty);
    expect(AppDefaults.allMoods.length, 6);
    // 未知 key 兜底（原 moodOf orElse 行为不变）
    expect(AppDefaults.moodOf('nope').key, 'tired');
  });

  test('cfgVersion：每次配置变更自增（驱动观察 AppState 的 UI 重建）', () async {
    final v0 = container.read(appSessionProvider).cfgVersion;
    await session.setTagColor('x', 'red');
    expect(container.read(appSessionProvider).cfgVersion, v0 + 1);
    await session.addTagPreset('y');
    expect(container.read(appSessionProvider).cfgVersion, v0 + 2);
  });
}
