import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum NotificationPermissionStatus { allowed, denied, unknown }

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/launcher_icon');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.initialize(settings);
      _initialized = true;
      await requestPermissions();
    } catch (_) {
      // Desktop tests and unsupported platforms should still be able to run.
      _initialized = false;
    }
  }

  Future<NotificationPermissionStatus> requestPermissions() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.requestNotificationsPermission();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);

      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      await mac?.requestPermissions(alert: true, badge: true, sound: true);

      return checkPermissionStatus();
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  Future<NotificationPermissionStatus> checkPermissionStatus() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled == true) return NotificationPermissionStatus.allowed;
      if (enabled == false) return NotificationPermissionStatus.denied;
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
    return NotificationPermissionStatus.unknown;
  }

  Future<void> syncReminders(List<Map<String, dynamic>> reminders) async {
    await initialize();
    if (!_initialized) return;
    for (final reminder in reminders) {
      final id = '${reminder['id']}';
      await cancelReminder(id);
      final enabled = _isEnabled(reminder['enabled']);
      if (enabled) {
        await scheduleDailyReminder(
          id: id,
          timeOfDay: '${reminder['time_of_day']}',
          label: '${reminder['label'] ?? '记录一下今天的状态'}',
        );
      }
    }
  }

  Future<void> scheduleDailyReminder({
    required String id,
    required String timeOfDay,
    required String label,
  }) async {
    await initialize();
    if (!_initialized) return;
    final parts = timeOfDay.split(':');
    if (parts.length < 2) return;
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts[1]) ?? 0;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'stable_record_reminders',
        '稳啦记录提醒',
        channelDescription: '提醒用户记录血糖、饮食、运动和状态',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      _notificationId(id),
      '稳啦',
      label,
      _nextDailyTime(hour, minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder(String id) async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId(id));
  }

  bool _isEnabled(Object? value) {
    return value == true || value == 1 || '$value' == '1' || '$value' == 'true';
  }

  int _notificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }

  tz.TZDateTime _nextDailyTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
