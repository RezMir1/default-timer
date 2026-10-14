import 'dart:convert';

import 'package:default_timer/task.dart';
import 'package:default_timer/task_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'Быстрые записи сохраняют последний снимок, включая пустой список',
    () async {
      final storage = TaskStorage();
      expect(await storage.load(), isNull);
      final tasks = [Task(id: 1, title: 'Задача', duration: 20)];
      final first = storage.save(tasks);
      tasks.clear();
      final last = storage.save(tasks);
      await Future.wait([first, last]);
      expect(await TaskStorage().load(), isEmpty);
    },
  );

  test('Запущенный таймер восстанавливается по времени окончания', () async {
    final end = DateTime.utc(2026, 10, 14, 20);
    final task = Task(
      id: 1,
      title: 'Таймер',
      duration: 30,
      isRunning: true,
      endsAt: end,
    );
    await TaskStorage().save([task]);
    final restored = (await TaskStorage().load())!.single;
    restored.updateRemaining(end.subtract(const Duration(milliseconds: 2800)));
    expect(restored.remainingSeconds, 3);
    restored.updateRemaining(end.add(const Duration(seconds: 1)));
    expect(restored.remainingSeconds, 0);
    expect(restored.isRunning, isFalse);
    expect(restored.isFinished, isTrue);
  });

  test('Пауза не расходует время при восстановлении', () async {
    final task = Task(
      id: 1,
      title: 'Пауза',
      duration: 30,
      remainingSeconds: 12,
    );
    await TaskStorage().save([task]);
    final restored = (await TaskStorage().load())!.single;
    restored.updateRemaining(DateTime.now().add(const Duration(days: 1)));
    expect(restored.remainingSeconds, 12);
  });

  test('Повреждённые данные не заменяются примерами', () async {
    const corrupt = '[{"id":1}]';
    await SharedPreferencesAsync().setString(TaskStorage.key, corrupt);
    await expectLater(TaskStorage().load(), throwsA(isA<TypeError>()));
    expect(await SharedPreferencesAsync().getString(TaskStorage.key), corrupt);
  });

  test('Дублирующиеся ID отклоняются', () async {
    final json = Task(id: 1, title: 'Задача', duration: 10).toJson();
    await SharedPreferencesAsync().setString(
      TaskStorage.key,
      jsonEncode([json, json]),
    );
    await expectLater(TaskStorage().load(), throwsFormatException);
  });
}
