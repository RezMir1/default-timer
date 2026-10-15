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
  var initializationFails = false;
  var schedulingFails = false;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    exact = true;
    allowed = true;
    initializationFails = false;
    schedulingFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize' && initializationFails) {
            throw PlatformException(
              code: 'invalid_icon',
              message: 'Missing ic_notification',
            );
          }
          if (call.method == 'zonedSchedule' && schedulingFails) {
            throw PlatformException(
              code: 'schedule_failed',
              message: 'Android rejected alarm',
            );
          }
          return switch (call.method) {
            'initialize' => true,
            'areNotificationsEnabled' => allowed,
            'canScheduleExactNotifications' => exact,
            'requestNotificationsPermission' => allowed,
            _ => null,
          };
        });
  });

  test(
    'Ошибка инициализации сохраняется и допускает повторную попытку',
    () async {
      final service = AndroidNotifications();
      initializationFails = true;
      expect(await service.requestPermissions(), 'error');
      expect(service.lastError, contains('invalid_icon'));
      expect(service.lastError, contains('Missing ic_notification'));
      initializationFails = false;
      expect(await service.requestPermissions(), 'granted');
      expect(service.lastError, isNull);
      expect(calls.where((call) => call.method == 'initialize'), hasLength(2));
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
    },
  );

  test('Ошибка планирования содержит код и сообщение Android', () async {
    schedulingFails = true;
    final service = AndroidNotifications();
    expect(
      await service.schedule(
        1,
        'Задача',
        DateTime.now().add(const Duration(minutes: 1)),
      ),
      'error',
    );
    expect(service.lastError, 'schedule_failed: Android rejected alarm');
    schedulingFails = false;
    expect(
      await service.schedule(
        1,
        'Задача',
        DateTime.now().add(const Duration(minutes: 1)),
      ),
      'scheduled',
    );
    expect(service.lastError, isNull);
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
