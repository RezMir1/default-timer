import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class AndroidNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _pendingOperation = Future<void>.value();

  Future<T> _inOrder<T>(Future<T> Function() operation) {
    final result = _pendingOperation.then((_) => operation());
    _pendingOperation = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()!;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'task_timers',
      'Таймеры задач',
      channelDescription: 'Уведомления о завершении задач',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
    ),
  );

  Future<String> requestPermissions() async {
    if (!supported) return 'unsupported';
    try {
      await initialize();
      final allowed = await _android.requestNotificationsPermission() ?? false;
      if (!allowed) return 'denied';
      if (await _android.canScheduleExactNotifications() != true) {
        await _android.requestExactAlarmsPermission();
      }
      await _plugin.show(
        id: 0,
        title: 'Проверка уведомлений',
        body: 'Уведомления Default Timer работают',
        notificationDetails: _details,
      );
      return await _android.canScheduleExactNotifications() == true
          ? 'granted'
          : 'inexact';
    } catch (_) {
      return 'error';
    }
  }

  Future<String> schedule(int id, String title, DateTime endsAt) async {
    return _inOrder(() => _schedule(id, title, endsAt));
  }

  Future<String> _schedule(int id, String title, DateTime endsAt) async {
    if (!supported) return 'unsupported';
    try {
      await initialize();
      if (await _android.areNotificationsEnabled() != true) return 'denied';
      final exact = await _android.canScheduleExactNotifications() == true;
      if (!endsAt.isAfter(DateTime.now())) {
        await _plugin.show(
          id: id,
          title: 'Таймер завершён',
          body: 'Задача «$title» завершена',
          notificationDetails: _details,
        );
        return 'scheduled';
      }
      await _plugin.zonedSchedule(
        id: id,
        title: 'Таймер завершён',
        body: 'Задача «$title» завершена',
        scheduledDate: tz.TZDateTime.from(endsAt, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return exact ? 'scheduled' : 'inexact';
    } catch (_) {
      return 'error';
    }
  }

  Future<void> cancel(int id) async {
    return _inOrder(() => _cancel(id));
  }

  Future<void> _cancel(int id) async {
    if (!supported) return;
    await initialize();
    await _plugin.cancel(id: id);
  }
}
