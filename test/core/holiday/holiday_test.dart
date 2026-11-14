// 调休合并逻辑测试（内置 + 服务端覆盖）。
import 'package:diary_app/core/holiday/holiday.dart';
import 'package:flutter_test/flutter_test.dart';

Holiday _h(String d, String type, [String name = '']) {
  final p = d.split('-').map(int.parse).toList();
  return Holiday(date: DateTime(p[0], p[1], p[2]), type: type, name: name);
}

void main() {
  test('merge：服务端覆盖同日内置，其余保留并升序', () {
    final builtin = [_h('2026-10-01', 'off', '国庆节'), _h('2026-10-10', 'ban', '国庆调休')];
    final server = [_h('2026-09-25', 'off', '中秋节'), _h('2026-10-01', 'off', '国庆节(更新)')];
    final merged = mergeHolidays(builtin, server);
    expect(merged.map((h) => _d(h)).toList(),
        ['2026-09-25', '2026-10-01', '2026-10-10']);
    expect(merged[1].name, '国庆节(更新)');
  });

  test('noteFor：十月显示国庆+调休班日', () {
    final mh = MonthHolidays([
      _h('2026-10-01', 'off', '国庆节'),
      _h('2026-10-02', 'off', '国庆节'),
      _h('2026-10-10', 'ban', '国庆调休'),
    ]);
    expect(mh.noteFor(2026, 10), contains('国庆节'));
    expect(mh.noteFor(2026, 10), contains('10.10(班)'));
    expect(mh.noteFor(2026, 11), isNull);
  });

  test('of：命中/未命中', () {
    final mh = MonthHolidays([_h('2026-09-25', 'off', '中秋节')]);
    expect(mh.of(DateTime(2026, 9, 25))?.type, 'off');
    expect(mh.of(DateTime(2026, 9, 26)), isNull);
  });
}

String _d(Holiday h) =>
    '${h.date.year}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')}';
