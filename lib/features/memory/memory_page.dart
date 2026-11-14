// 回忆页：连续天数 hero + 那年今天 + 随机翻一条 + 年度热力图（GitHub 风格）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_defaults.dart';
import '../../core/model/diary_entry.dart';
import '../../core/repo/demo_data.dart';
import '../../core/session/app_session.dart';
import '../../core/util/dates.dart';
import '../../features/theme/tokens.dart';

class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  int _randIdx = 0;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final state = ref.watch(appSessionProvider);
    final today = DateTime.now();
    final now = DateTime.now();

    final streak = state.demo
        ? demoStreak
        : computeStreak(state.entries, today);
    final yearAgo = state.demo
        ? DiaryEntry(
            localId: 'demo-year-ago',
            serverId: null,
            date: '${today.year - 1}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}',
            payload: demoYearAgo,
            cipherJson: null,
            updatedAt: today,
          )
        : yearAgoEntry(state.entries, today);
    // 随机翻一条：真实身份翻自己的条目（此前误用演示池，用户会看到不属于自己的随机文案）；
    // 演示模式仍用 mockup POOL 视觉对照。
    final List<({String? mood, String text})> pool = state.demo
        ? [for (final p in demoRandomPool) (mood: p.mood, text: p.text)]
        : [
            for (final e in state.entries)
              if (!e.deleted) (mood: e.payload.mood, text: e.payload.text),
          ];
    final rand = pool.isEmpty ? null : pool[_randIdx % pool.length];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 64, 18, 0),
            child: Text('回忆',
                style: TextStyle(
                    fontSize: 33,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                    color: Tokens.label(b))),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Text('那些被留下的话',
                style: TextStyle(fontSize: 14, color: Tokens.label2(b))),
          ),
          const SizedBox(height: 14),
          // hero
          _card(b, Row(
            children: [
              Text('$streak',
                  style: TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      color: Tokens.orange(b),
                      height: 1)),
              const SizedBox(width: 14),
              Text('天\n连续记录',
                  style: TextStyle(
                      fontSize: 14, height: 1.3, color: Tokens.label2(b))),
              const Spacer(),
              // 最近 7 天圆点
              Row(
                children: [
                  for (var i = 6; i >= 0; i--)
                    Container(
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(left: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.entries.any((e) =>
                                !e.deleted &&
                                e.date ==
                                    Dates.date(now.subtract(Duration(days: i))))
                            ? Tokens.green
                            : Tokens.fill(b),
                      ),
                    ),
                ],
              ),
            ],
          )),
          // 那年今天
          sectionLabel(b, '那年今天 · ${now.year} 年 ${now.month} 月 ${now.day} 日'),
          _card(b, yearAgo == null
              ? Text('去年今天还没有记录',
                  style: TextStyle(fontSize: 13, color: Tokens.label3(b)))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (yearAgo.payload.mood == null
                                ? Tokens.green
                                : AppDefaults
                                    .moodOf(yearAgo.payload.mood!).color)
                            .withValues(alpha: .16),
                      ),
                      child: Text(
                        yearAgo.payload.mood == null
                            ? '📝'
                            : AppDefaults.moodOf(yearAgo.payload.mood!).emoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(yearAgo.payload.text,
                              style: TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                  color: Tokens.label(b))),
                          const SizedBox(height: 6),
                          Text(
                            '${yearAgo.payload.time} · 端到端加密',
                            style: TextStyle(
                                fontSize: 11, color: Tokens.label3(b)),
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
          // 随机翻一条
          sectionLabel(b, '随机翻一条'),
          _card(b, rand == null
              ? Text('还没有可以翻看的日记',
                  style: TextStyle(fontSize: 13, color: Tokens.label3(b)))
              : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (rand.mood == null
                              ? Tokens.green
                              : AppDefaults.moodOf(rand.mood!).color)
                          .withValues(alpha: .16),
                    ),
                    child: Text(
                        rand.mood == null
                            ? '📝'
                            : AppDefaults.moodOf(rand.mood!).emoji,
                        style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(rand.text,
                        style: TextStyle(
                            fontSize: 15, height: 1.55, color: Tokens.label(b))),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: Tokens.fill(b),
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => setState(() => _randIdx++),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh,
                            size: 13, color: Tokens.blue(b)),
                        const SizedBox(width: 5),
                        Text('换一条',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Tokens.blue(b))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          )),
          // 热力图
          sectionLabel(b, '${now.year} 热力图'),
          _card(b, Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heatmap(state, now),
              const SizedBox(height: 10),
              Text(
                '${now.year} 年 · ${state.demo ? 17 : heatmapCounts(state.entries).values.where((c) => c > 0).length} 天有记录 · 密文仅在解锁后可见',
                style: TextStyle(fontSize: 11, color: Tokens.label3(b)),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget sectionLabel(Brightness b, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 9),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Tokens.label2(b))),
      );

  Widget _card(Brightness b, Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Tokens.card(b),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      );

  Widget _heatmap(AppState state, DateTime now) {
    final counts = state.demo ? <String, int>{} : heatmapCounts(state.entries);
    // 26 周 × 7 行（mockup 182 格）
    final start = now.subtract(const Duration(days: 181));
    return SizedBox(
      height: 7 * 9 + 6 * 3,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 26,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          childAspectRatio: 1,
        ),
        itemCount: 182,
        itemBuilder: (context, i) {
          // 列优先映射（mockup grid-auto-flow:column）：i = col*7 + row
          final col = i ~/ 7;
          final row = i % 7;
          final dayIndex = col * 7 + row;
          final day = start.add(Duration(days: dayIndex));
          final level = state.demo
              ? (dayIndex * 13) % 5
              : _level(counts[Dates.date(day)] ?? 0);
          final color = level == 0
              ? Tokens.fill(Theme.of(context).brightness)
              : Tokens.green.withValues(alpha: switch (level) {
                  1 => .35,
                  2 => .65,
                  3 => 1.0,
                  _ => 1.0,
                });
          return Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2.5),
            ),
          );
        },
      ),
    );
  }

  int _level(int count) {
    if (count <= 0) return 0;
    if (count == 1) return 1;
    if (count <= 3) return 2;
    return 3;
  }
}
