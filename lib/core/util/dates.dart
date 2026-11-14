// 日期工具：全部使用本地时区的 yyyy-MM-dd / HH:mm 文本协议（与服务端 DATE 一致）。
class Dates {
  Dates._();

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  static String hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 解析 yyyy-MM-dd；失败返回 null。
  static DateTime? tryParseDate(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// 解析 yyyy-MM 或 yyyy-MM-dd 为该月任意一天的引用。
  static String monthOf(String date) => date.substring(0, 7);

  /// 该月天数。
  static int daysInMonth(int year, int month) {
    if (month == 12) return 31;
    return DateTime(year, month + 1, 0).day;
  }

  static const weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static const weekdayShort = ['一', '二', '三', '四', '五', '六', '日'];

  /// 1=周一…7=周日（ISO）。
  static int weekdayIso(DateTime d) => d.weekday;
}
