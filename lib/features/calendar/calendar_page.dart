// 日历页：月历 + 前后月补位灰显可点击切月 + 休/班徽章 + 心情圆点（≤3）+
// 底部统计 + 点日期跳时光并高亮。table_calendar 自定义 dayBuilder（03 §6）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/config/app_defaults.dart';
import '../../core/model/diary_entry.dart';
import '../../core/session/app_session.dart';
import '../../core/util/dates.dart';
import '../../features/shell/home_shell.dart';
import '../../features/theme/tokens.dart';

class CalendarPage extends ConsumerStatefulWidget {
  final void Function(HomeTab) switchTab;

  const CalendarPage({super.key, required this.switchTab});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focused = DateTime(2026, 11, 1);
  final _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _focused = DateTime(_today.year, _today.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);

    final monthEntries = <String, List<DiaryEntry>>{};
    for (final e in state.entries.where((e) => !e.deleted)) {
      monthEntries.putIfAbsent(e.date, () => []).add(e);
    }
    final monthCount = monthEntries.keys
        .where((k) => k.startsWith(Dates.monthKey(_focused)))
        .fold<int>(0, (n, k) => n + monthEntries[k]!.length);

    // 心情分布（前 4）
    final dist = <String, int>{};
    monthEntries.forEach((k, list) {
      if (!k.startsWith(Dates.monthKey(_focused))) return;
      for (final e in list) {
        if (e.payload.mood != null) {
          dist[e.payload.mood!] = (dist[e.payload.mood!] ?? 0) + 1;
        }
      }
    });
    final distTop = (dist.keys.toList()
          ..sort((a, c) => dist[c]!.compareTo(dist[a]!)))
        .take(4);

    final note = state.holidays?.noteFor(_focused.year, _focused.month);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 64, 18, 0),
            child: Text('日历',
                style: TextStyle(
                    fontSize: 33,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                    color: Tokens.label(b))),
          ),
          // 标题行：‹ 年月 › 今
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Row(
              children: [
                _mbtn(b, Icons.chevron_left, () {
                  setState(() {
                    _focused = DateTime(_focused.year, _focused.month - 1, 1);
                  });
                }),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_focused.year}年${_focused.month}月',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Tokens.label(b),
                        fontFeatures: const []),
                  ),
                ),
                _mbtn(b, Icons.chevron_right, () {
                  setState(() {
                    _focused = DateTime(_focused.year, _focused.month + 1, 1);
                  });
                }),
                const SizedBox(width: 8),
                _mbtnText(b, '今', () {
                  setState(() {
                    _focused = DateTime(_today.year, _today.month, 1);
                  });
                }),
              ],
            ),
          ),
          // 节假日说明行
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: SizedBox(
              height: 16,
              child: note == null
                  ? const SizedBox.shrink()
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: note,
                          style: TextStyle(
                              fontSize: 12, color: Tokens.label2(b)),
                        ),
                      ]),
                    ),
            ),
          ),
          // 月历
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TableCalendar(
              firstDay: DateTime(2000, 1, 1),
              lastDay: DateTime(2100, 12, 31),
              focusedDay: _focused,
              currentDay: _today,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              headerVisible: false,
              daysOfWeekVisible: true,
              availableGestures: AvailableGestures.horizontalSwipe,
              onPageChanged: (focused) =>
                  setState(() => _focused = DateTime(focused.year, focused.month, 1)),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle:
                    TextStyle(fontSize: 12, color: Tokens.label3(b)),
                weekendStyle: TextStyle(
                    fontSize: 12,
                    color: Tokens.red(b).withValues(alpha: .75)),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: true,
                canMarkersOverflow: false,
                markersMaxCount: 0,
                cellAlignment: Alignment.topCenter,
              ),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (_, d) => Center(
                  child: Text(
                    '日一二三四五六'[d.weekday % 7],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      // 日/六 表头同样红色，与双休数字呼应
                      color: d.weekday == DateTime.saturday ||
                              d.weekday == DateTime.sunday
                          ? Tokens.red(b).withValues(alpha: .75)
                          : Tokens.label3(b),
                    ),
                  ),
                ),
                defaultBuilder: (ctx, day, _) => _dayCell(ctx, day, outside: false),
                outsideBuilder: (ctx, day, _) =>
                    _dayCell(ctx, day, outside: true),
                todayBuilder: (ctx, day, _) => _dayCell(ctx, day,
                    outside: !_isSameMonth(day, _focused), isToday: true),
                disabledBuilder: (ctx, day, _) => _dayCell(ctx, day, outside: true),
                selectedBuilder: (ctx, day, _) => _dayCell(ctx, day, outside: false),
              ),
            ),
          ),
          // 底部统计
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('本月 $monthCount 条',
                    style:
                        TextStyle(fontSize: 13, color: Tokens.label2(b))),
                Row(
                  children: [
                    for (final mood in distTop)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${AppDefaults.moodOf(mood).emoji}×${dist[mood]}',
                          style: TextStyle(
                              fontSize: 13, color: Tokens.label2(b)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: Text(
                '周末与法定节假日红色 · 班 = 调休上班 · 圆点为心情',
                style: TextStyle(fontSize: 11, color: Tokens.label3(b)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameMonth(DateTime a, DateTime f) =>
      a.year == f.year && a.month == f.month;

  Widget _mbtn(Brightness b, IconData icon, VoidCallback onTap) =>
      Material(
        color: Tokens.fill(b),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 16, color: Tokens.label(b)),
          ),
        ),
      );

  Widget _mbtnText(Brightness b, String t, VoidCallback onTap) =>
      Material(
        color: Tokens.fill(b),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Text(t,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Tokens.label(b))),
            ),
          ),
        ),
      );

  void _jumpToDay(DateTime day) {
    if (!_isSameMonth(day, _focused)) {
      setState(() => _focused = DateTime(day.year, day.month, 1));
    }
    widget.switchTab(HomeTab.feed);
    ref.read(appSessionProvider.notifier).highlight(day);
  }

  Widget _dayCell(BuildContext ctx, DateTime day, {bool outside = false, bool isToday = false}) {
    final b = Theme.of(ctx).brightness;
    final state = ref.read(appSessionProvider);
    // 补位灰显格不显示调休徽章/心情点（对齐 mockup .od2-day.oth）
    final hol = outside ? null : state.holidays?.of(day);
    final isOff = hol?.type == 'off';
    final isBan = hol?.type == 'ban';
    // 双休红色区分（2026-11-14 用户要求）；周末逢调休上班（班）仍是工作日 → 橙
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    final moods = state.entries
        .where((e) => !e.deleted && e.date == Dates.date(day))
        .map((e) => e.payload.mood)
        .whereType<String>()
        .take(3)
        .toList();

    final numColor = outside
        ? Tokens.label3(b).withValues(alpha: .55)
        : isBan
            ? Tokens.orange(b)
            : (isOff || isWeekend)
                ? Tokens.red(b)
                : Tokens.label(b);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _jumpToDay(day),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Container(
            width: 33,
            height: 33,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? Tokens.blue(b) : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 17,
                color: isToday ? Colors.white : numColor,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            height: 10,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isOff || isBan)
                  Text(
                    isOff ? '休' : '班',
                    style: TextStyle(
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: isOff ? Tokens.red(b) : Tokens.orange(b),
                    ),
                  )
                else if (moods.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < moods.length; i++)
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppDefaults.moodOf(moods[i]).color,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
