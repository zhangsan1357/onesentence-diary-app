// Widget 数据快照契约（晨 19 §5.5）：Flutter 侧把「今日已写/连续天数/最近一句」
// 写成 App Group 键值，WidgetKit（等 Mac 后实现）只读本契约渲染。本文件=纯函数
// 唯一事实源；平台写入收敛在条件导入门面（原生翻译友好约束 #3，env_check/
// avatar_pool/media_save 同款）。
import 'dates.dart';
import '../model/diary_entry.dart';

/// 快照键（Widget 端按此读取；改键=改契约，需同步 Swift 侧注释）。
const kWsWrittenToday = 'writtenToday';
const kWsTodayCount = 'todayCount';
const kWsStreak = 'streak';
const kWsLastText = 'lastText';
const kWsLastTime = 'lastTime';
const kWsTotal = 'total';
const kWsUpdatedAt = 'updatedAtIso';

/// 构建快照键值。与 computeStreak 同语义（从今天或昨天回数，今天未写不断签）；
/// 最近一句 = 日期+日内时间最大者。lastText 截断 60 字（Widget 展示预算）。
Map<String, String> buildWidgetSnapshot(List<DiaryEntry> entries, DateTime now) {
  final live = entries.where((e) => !e.deleted).toList();
  final today = Dates.date(now);
  final todays = live.where((e) => e.date == today).toList();
  final dates = {...live.map((e) => e.date)}.toSet();
  var day = DateTime(now.year, now.month, now.day);
  if (!dates.contains(Dates.date(day))) {
    day = day.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (dates.contains(Dates.date(day))) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  DiaryEntry? latest;
  for (final e in live) {
    if (latest == null ||
        e.date.compareTo(latest.date) > 0 ||
        (e.date == latest.date &&
            e.payload.time.compareTo(latest.payload.time) > 0)) {
      latest = e;
    }
  }
  final text = latest?.payload.text ?? '';
  final truncated = text.length <= 60 ? text : text.substring(0, 60);
  return {
    kWsWrittenToday: todays.isNotEmpty ? '1' : '0',
    kWsTodayCount: '${todays.length}',
    kWsStreak: '$streak',
    kWsLastText: truncated,
    kWsLastTime: latest == null ? '' : '${latest.date} ${latest.payload.time}',
    kWsTotal: '${live.length}',
    kWsUpdatedAt: now.toIso8601String(),
  };
}
