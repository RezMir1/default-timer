import 'package:default_timer/main.dart';
import 'package:default_timer/task.dart';
import 'package:default_timer/task_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> openScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: TaskScreen()));
  await flush(tester);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets(
    'Ошибка уведомлений не запускает повторные запросы для всех задач',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      var initializations = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initialize') {
              initializations++;
              throw PlatformException(
                code: 'invalid_icon',
                message: 'Missing ic_notification',
              );
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final end = DateTime.now().add(const Duration(minutes: 2));
      await TaskStorage().save([
        Task(
          id: 1,
          title: 'Первая',
          duration: 120,
          isRunning: true,
          endsAt: end,
        ),
        Task(
          id: 2,
          title: 'Вторая',
          duration: 120,
          isRunning: true,
          endsAt: end,
        ),
      ]);
      await openScreen(tester);
      expect(initializations, 1);
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(initializations, 2);
      expect(find.textContaining('invalid_icon'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Отсутствующий плагин показывает ошибку загрузки вместо красного экрана',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance = null;
      await openScreen(tester);
      expect(
        find.text(
          'Не удалось загрузить задачи. Сохранённые данные не перезаписаны.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Сохранённые задачи загружаются вместо примеров', (tester) async {
    await TaskStorage().save([Task(id: 7, title: 'Моя задача', duration: 12)]);
    await openScreen(tester);
    expect(find.text('Моя задача'), findsOneWidget);
    expect(find.text('00:00:12'), findsOneWidget);
    expect(find.text('Послеобеденный сон'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Удаление сохраняется после повторного открытия', (tester) async {
    await TaskStorage().save([
      Task(id: 7, title: 'Удалить меня', duration: 12),
    ]);
    await openScreen(tester);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await flush(tester);
    expect(await TaskStorage().load(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await openScreen(tester);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Послеобеденный сон'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Запуск, пауза и сброс сохраняют состояние', (tester) async {
    await TaskStorage().save([Task(id: 7, title: 'Таймер', duration: 30)]);
    await openScreen(tester);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await flush(tester);
    final running = (await TaskStorage().load())!.single;
    expect(running.isRunning, isTrue);
    expect(running.endsAt, isNotNull);
    await tester.tap(find.byIcon(Icons.pause));
    await flush(tester);
    final paused = (await TaskStorage().load())!.single;
    expect(paused.isRunning, isFalse);
    expect(paused.endsAt, isNull);
    await tester.tap(find.byIcon(Icons.restart_alt));
    await flush(tester);
    expect((await TaskStorage().load())!.single.remainingSeconds, 30);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
