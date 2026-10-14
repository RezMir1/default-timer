import 'package:default_timer/android_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var exact = true;
  var allowed = true;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    exact = true;
    allowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' => allowed,
            'canScheduleExactNotifications' => exact,
            _ => null,
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Планирование и отмена идут по порядку с одним ID', () async {
    final service = AndroidNotifications();
    final schedule = service.schedule(
      7,
      'Чтение',
      DateTime.now().add(const Duration(minutes: 1)),
    );
    final cancel = service.cancel(7);
    expect(await schedule, 'scheduled');
    await cancel;
    final operations = calls
        .where((call) => ['zonedSchedule', 'cancel'].contains(call.method))
        .toList();
    expect(operations.map((call) => call.method), ['zonedSchedule', 'cancel']);
    expect(operations.first.arguments['id'], 7);
    expect(operations.last.arguments['id'], 7);
  });

  test('Отказ в разрешении не планирует уведомление', () async {
    allowed = false;
    expect(
      await AndroidNotifications().schedule(
        1,
        'Задача',
        DateTime.now().add(const Duration(minutes: 1)),
      ),
      'denied',
    );
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });

  test('Без точных будильников выбирается неточный режим', () async {
    exact = false;
    expect(
      await AndroidNotifications().schedule(
        1,
        'Задача',
        DateTime.now().add(const Duration(minutes: 1)),
      ),
      'inexact',
    );
    final call = calls.singleWhere((call) => call.method == 'zonedSchedule');
    expect(
      call.arguments['platformSpecifics']['scheduleMode'],
      'inexactAllowWhileIdle',
    );
  });
}
