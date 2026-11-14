// 每日 21:30 本地提醒（03 §6：flutter_local_notifications + timezone）。
// 本工程仅面向 iOS；web/其他平台直接跳过。
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static const _dailyId = 2130;
  static const _hour = 21;
  static const _minute = 30;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> _ensureInit() async {
    if (_initialized || !supported) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(iOS: DarwinInitializationSettings());
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  /// 开启每日 21:30 提醒。
  static Future<void> enableDaily() async {
    if (!supported) return;
    await _ensureInit();
    final now = DateTime.now();
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, _hour, _minute);
    if (next.isBefore(now)) {
      next = next.add(const Duration(days: 1));
    }
    const details = NotificationDetails(iOS: DarwinNotificationDetails());
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: '一句话日记',
      body: '今天还没写点什么？',
      scheduledDate: next,
      notificationDetails: details,
      matchDateTimeComponents: DateTimeComponents.time, // 每日重复
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 关闭提醒。
  static Future<void> disableDaily() async {
    if (!supported || !_initialized) return;
    await _plugin.cancel(id: _dailyId);
  }
}
