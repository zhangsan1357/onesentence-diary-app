// 调休数据：内置年度 JSON（离线可用）+ 服务端 /holidays 合并（01 §10）。
// off=休（红徽章）/ ban=班（橙徽章）；普通周末由日历页红色数字区分（2026-11-14）。
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class Holiday {
  final DateTime date;
  final String type; // off | ban
  final String name;

  const Holiday({required this.date, required this.type, required this.name});

  Map<String, dynamic> toJson() => {'d': _d, 'type': type, 'name': name};

  String get _d =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Holiday fromJson(Map<String, dynamic> j) {
    final p = (j['d'] as String).split('-').map(int.parse).toList();
    return Holiday(
      date: DateTime(p[0], p[1], p[2]),
      type: j['type'] as String,
      name: (j['name'] as String?) ?? '',
    );
  }
}

/// 合并：服务端数据优先覆盖内置（按日期去重），返回按日期升序。
List<Holiday> mergeHolidays(List<Holiday> builtin, List<Holiday> server) {
  final map = <String, Holiday>{
    for (final h in builtin) _key(h.date): h,
  };
  for (final h in server) {
    map[_key(h.date)] = h;
  }
  final list = map.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return list;
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 月视图汇总：该月的 off/ban 集合 + 节日名。
class MonthHolidays {
  final List<Holiday> all; // 已合并、全年
  final Map<String, Holiday> _byDate;

  MonthHolidays(this.all) : _byDate = {for (final h in all) _key(h.date): h};

  Holiday? of(DateTime d) => _byDate[_key(d)];

  /// 节假日说明行（mockup cnote）：名称 + 班日列表，如「国庆节 10.1-10.7 休 · 10.10(班)」。
  String? noteFor(int year, int month) {
    final inMonth =
        all.where((h) => h.date.year == year && h.date.month == month).toList();
    if (inMonth.isEmpty) return null;
    final title = inMonth
        .map((h) => h.name)
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(' ');
    final bans = inMonth
        .where((h) => h.type == 'ban')
        .map((h) => '$month.${h.date.day}(班)')
        .join(' · ');
    return bans.isEmpty ? title : '$title · $bans';
  }
}

/// 内置年度数据（assets/holidays_`<year>`.json）。
Future<List<Holiday>> loadBuiltinHolidays(int year) async {
  try {
    final s = await rootBundle.loadString('assets/holidays_$year.json');
    final list = (jsonDecode(s) as List)
        .map((e) => Holiday.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  } catch (_) {
    return const [];
  }
}

/// 2026 内置种子（02 §4.2；正式数据以国务院公告为准）。
const builtin2026Seed = [
  {'d': '2026-09-25', 'type': 'off', 'name': '中秋节'},
  {'d': '2026-09-27', 'type': 'ban', 'name': '中秋调休'},
  {'d': '2026-10-01', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-02', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-03', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-04', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-05', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-06', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-07', 'type': 'off', 'name': '国庆节'},
  {'d': '2026-10-10', 'type': 'ban', 'name': '国庆调休'},
];
