// lib/services/notification_service.dart

import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/task.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    await _plugin.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _ready = true;
  }

  Future<void> scheduleReminders(Task task) async {
    if (!_ready) await init();
    await cancelReminders(task);

    final now = DateTime.now();
    final dl  = task.deadline;

    final slots = [
      (dl.subtract(const Duration(days: 1)),
      '📋 ${task.name}', 'Due tomorrow — get started!', 1),
      (dl.subtract(const Duration(hours: 2)),
      '⚡ ${task.name}', '2 hours left. Wrap it up!', 2),
      (dl, '⏰ ${task.name}', 'Deadline is now!', 3),
    ];

    for (final s in slots) {
      if (s.$1.isAfter(now)) {
        await _schedule(
          id: task.id! * 10 + s.$4,
          title: s.$2,
          body: s.$3,
          when: s.$1,
          urgent: s.$4 >= 2,
          payload: 'task_${task.id}',
        );
      }
    }
  }

  Future<void> cancelReminders(Task task) async {
    if (task.id == null) return;
    for (final slot in [1, 2, 3]) {
      await _plugin.cancel(task.id! * 10 + slot);
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> showInstant({required String title, required String body}) async {
    if (!_ready) await init();
    await _plugin.show(0, title, body, _details(urgent: false));
  }

  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required bool urgent,
    String? payload,
  }) async {
    await _plugin.zonedSchedule(
      id, title, body,
      tz.TZDateTime.from(when, tz.local),
      _details(urgent: urgent),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  NotificationDetails _details({required bool urgent}) => NotificationDetails(
    android: AndroidNotificationDetails(
      urgent ? 'nudge_urgent' : 'nudge_reminders',
      urgent ? 'Urgent reminders' : 'Task reminders',
      channelDescription: urgent
          ? 'High-priority deadline alerts'
          : 'Scheduled task reminders',
      importance: urgent ? Importance.max : Importance.high,
      priority: urgent ? Priority.max : Priority.high,
      color: urgent ? const Color(0xFFD85A30) : const Color(0xFF6C63FF),
      enableVibration: true,
      autoCancel: true,
    ),
  );
}