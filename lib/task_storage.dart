import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'task.dart';

class TaskStorage {
  static const key = 'default_timer_tasks_v1';
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  Future<void> _pendingWrite = Future<void>.value();

  Future<List<Task>?> load() async {
    final saved = await _preferences.getString(key);
    if (saved == null) return null;
    final data = jsonDecode(saved) as List<dynamic>;
    final tasks = data
        .map((item) => Task.fromJson(item as Map<String, dynamic>))
        .toList();
    if (tasks.map((task) => task.id).toSet().length != tasks.length) {
      throw const FormatException('Повторяющиеся номера задач');
    }
    return tasks;
  }

  Future<void> save(List<Task> tasks) {
    // Снимок делаем сразу; записи выполняем по порядку.
    final saved = jsonEncode(tasks.map((task) => task.toJson()).toList());
    final write = _pendingWrite.then((_) => _preferences.setString(key, saved));
    _pendingWrite = write.catchError((Object error) {});
    return write;
  }
}
