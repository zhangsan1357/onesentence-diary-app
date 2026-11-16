// Widget 数据快照层（晨 19 §5.5）：契约纯函数（今日已写/streak/lastText 截断/
// 最近一句）+ 会话接线（内存重建汇聚点、内容不变跳过、writer 注入）。
import 'dart:convert';

import 'package:diary_app/core/db/database.dart' as db;
import 'package:diary_app/core/model/diary_entry.dart';
import 'package:diary_app/core/session/app_session.dart';
import 'package:diary_app/core/session/recovery_words.dart';
import 'package:diary_app/core/util/widget_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DiaryEntry _e(String date, String time, String text,
        {DateTime? updatedAt, bool deleted = false}) =>
    DiaryEntry(
      localId: 'id-$date-$time',
      serverId: 1,
      date: date,
      payload: EntryPayload(text: text, time: time, mood: null),
      cipherJson: null,
      updatedAt: updatedAt ?? DateTime(2026),
      deleted: deleted,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('快照构建：今日已写/今日条数/连续天数/总数/最近一句', () {
    final now = DateTime(2026, 11, 17, 21, 30);
    final entries = [
      _e('2026-11-17', '21:00', '今晚这句'),
      _e('2026-11-17', '08:00', '早晨一句'),
      _e('2026-11-16', '09:30', '昨天一句'),
      _e('2026-11-13', '12:00', ' older'), // 断档（14/15 未写）
      _e('2026-11-10', '09:00', '已删', deleted: true),
    ];
    final s = buildWidgetSnapshot(entries, now);
    expect(s[kWsWrittenToday], '1');
    expect(s[kWsTodayCount], '2');
    expect(s[kWsStreak], '2', reason: '17/16 连续两天，13 断档');
    expect(s[kWsTotal], '4', reason: '已删不计');
    expect(s[kWsLastText], '今晚这句', reason: '最近一句=日期+日内时间最大');
    expect(s[kWsLastTime], '2026-11-17 21:00');
    expect(s.containsKey(kWsUpdatedAt), isTrue);
  });

  test('快照构建：今天未写不断签（从昨天回数）+ lastText 60 字截断', () {
    final now = DateTime(2026, 11, 17, 9, 0);
    final long = '一' * 80;
    final entries = [
      _e('2026-11-17', '07:00', long),
      _e('2026-11-16', '22:00', 'x'),
      _e('2026-11-15', '22:00', 'y'),
    ];
    final s = buildWidgetSnapshot(entries, now);
    expect(s[kWsStreak], '3', reason: '今天已写（07:00 一条）→ 17/16/15');
    expect(s[kWsWrittenToday], '1');
    expect(s[kWsLastText], '一' * 60, reason: '60 字截断');
    // 今天未写场景
    final s2 = buildWidgetSnapshot([_e('2026-11-16', '22:00', 'x'),
        _e('2026-11-15', '09:00', 'y')], now);
    expect(s2[kWsWrittenToday], '0');
    expect(s2[kWsStreak], '2', reason: '从昨天回数：16、15');
  });

  test('快照构建：空数据全零', () {
    final s = buildWidgetSnapshot([], DateTime(2026, 11, 17));
    expect(s[kWsWrittenToday], '0');
    expect(s[kWsStreak], '0');
    expect(s[kWsTotal], '0');
    expect(s[kWsLastText], '');
  });

  testWidgets('会话接线：发布后写入；内容不变跳过（writer 注入）', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = container.read(appSessionProvider.notifier);
    final store = db.MemoryLocalStore();
    await session.debugUseStore(store);
    session.debugHoldFlush = true;
    await session.createIdentity(RecoveryWords.generate(), '测试者');
    final writes = <Map<String, String>>[];
    session.debugWidgetWriter = (values) async => writes.add(values);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 3)); // 放 holidays Timer
    // bootstrap 内 _loadLocalEntries（空数据）已写一次；时序无关取基线
    final base = writes.length;
    expect(base, greaterThanOrEqualTo(1), reason: '汇聚点已触发');
    expect(writes.first[kWsTotal], '0');
    await session.refreshWidgetSnapshot();
    expect(writes.length, base, reason: '内容不变跳过（比较排除 updatedAtIso）');
    await session.publish(text: '今天写一句', mood: null, tags: [], media: []);
    await session.refreshWidgetSnapshot();
    expect(writes.length, base + 1);
    expect(writes.last[kWsWrittenToday], '1');
    expect(writes.last[kWsTodayCount], '1');
    expect(writes.last[kWsTotal], '1');
    expect(writes.last[kWsStreak], '1');
    expect(writes.last[kWsLastText], '今天写一句');
    expect(jsonEncode(writes.last), contains('updatedAtIso'));
  });
}
