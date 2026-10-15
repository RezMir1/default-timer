import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'android_notifications.dart';
import 'task.dart';
import 'task_storage.dart';

import 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart'
    as browser_notifications;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: TaskScreen()),
  );
}

class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController pulseController;
  final TaskStorage storage = TaskStorage();
  final AndroidNotifications androidNotifications = AndroidNotifications();
  bool isLoading = true;
  bool isEnablingNotifications = false;
  String? loadError;
  int nextTaskId = 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    pulseController.repeat(reverse: true);
    unawaited(loadTasks());
  }

  void showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> loadTasks() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      final saved = await storage.load();
      if (!mounted) return;
      final restored =
          saved ??
          [
            Task(id: 1, title: 'Послеобеденный сон', duration: 7200),
            Task(id: 2, title: 'Вечерняя уборка', duration: 1800),
            Task(id: 3, title: 'Чтение книги', duration: 3600),
          ];
      final now = DateTime.now();
      for (final task in restored) {
        task.updateRemaining(now);
      }
      setState(() {
        tasks = restored;
        nextTaskId =
            tasks.fold<int>(0, (max, task) => task.id > max ? task.id : max) +
            1;
        isLoading = false;
      });
      for (final task in tasks) {
        if (task.isRunning) startTimer(task);
      }
      await saveTasks();
      // Планирование в Android выполняется независимо от UI-таймера.
      for (final task in tasks.toList()) {
        if (task.isRunning && androidNotifications.supported) {
          if (!await scheduleNotification(task)) break;
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        loadError =
            'Не удалось загрузить задачи. Сохранённые данные не перезаписаны.';
      });
    }
  }

  Future<void> saveTasks() async {
    try {
      await storage.save(tasks);
    } catch (_) {
      showMessage('Не удалось сохранить задачи в локальное хранилище');
    }
  }

  Future<bool> scheduleNotification(Task task) async {
    final endsAt = task.endsAt;
    if (endsAt == null) return true;
    final result = await androidNotifications.schedule(
      task.id,
      task.title,
      endsAt,
    );
    if (result == 'denied') {
      showMessage(
        'Для уведомлений Android нажмите колокольчик и разрешите уведомления',
      );
      return false;
    } else if (result == 'inexact') {
      showMessage(
        'Уведомление запланировано. Для точного времени разрешите будильники через колокольчик',
      );
    } else if (result == 'error') {
      showMessage(
        'Не удалось запланировать уведомление Android: '
        '${androidNotifications.lastError ?? 'неизвестная ошибка'}',
      );
      return false;
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !isLoading && loadError == null) {
      for (final task in tasks) {
        if (task.isRunning) updateTimer(task);
      }
    }
  }

  Future<void> enableNotifications() async {
    if (isEnablingNotifications) return;
    setState(() => isEnablingNotifications = true);
    try {
      await _enableNotifications();
    } finally {
      if (mounted) setState(() => isEnablingNotifications = false);
    }
  }

  Future<void> _enableNotifications() async {
    if (androidNotifications.supported) {
      final result = await androidNotifications.requestPermissions();
      if (!mounted) return;
      showMessage(switch (result) {
        'granted' =>
          'Уведомления и точные таймеры разрешены. Пробное уведомление создано',
        'inexact' => 'Уведомления разрешены, но без точных будильников они могут запаздывать',
        'denied' => 'Разрешите уведомления в настройках приложения Android',
        _ =>
          'Не удалось включить уведомления Android: '
              '${androidNotifications.lastError ?? 'неизвестная ошибка'}',
      });
      if (result != 'granted' && result != 'inexact') return;
      for (final task in tasks.toList()) {
        if (task.isRunning && !await scheduleNotification(task)) break;
      }
      return;
    }
    final permission = await browser_notifications.requestPermission();
    if (!mounted) return;

    var message = switch (permission) {
      'granted' => 'Уведомления разрешены',
      'denied' => 'Уведомления заблокированы. Разрешите их в настройках сайта',
      'default' => 'Разрешение на уведомления не получено',
      'unsupported' => 'Этот браузер не поддерживает уведомления',
      'insecure' => 'Для уведомлений откройте сайт через HTTPS или localhost',
      _ => 'Не удалось запросить разрешение на уведомления',
    };
    if (permission == 'granted') {
      final created = browser_notifications.showNotification('', isTest: true);
      message = created
          ? 'Пробное уведомление создано. Если его не видно, проверьте уведомления Windows (Win + N)'
          : 'Разрешение есть, но браузер не смог создать уведомление';
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void startTimer(Task task) {
    task.timer?.cancel();
    task.timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      updateTimer(task);
    });
  }

  void updateTimer(Task task) {
    if (!mounted || !task.isRunning) return;
    setState(() => task.updateRemaining(DateTime.now()));
    if (task.isFinished) {
      task.timer?.cancel();
      unawaited(saveTasks());
      // В Android уведомление уже запланировано системой: второй раз не показываем.
      if (kIsWeb) {
        final created = browser_notifications.showNotification(task.title);
        if (kIsWeb && !created) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Уведомление не создано. Нажмите колокольчик для проверки разрешения',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> toggleTimer(Task task) async {
    if (task.isBusy || task.isFinished) return;
    setState(() => task.isBusy = true);
    try {
      if (task.isRunning) {
        await androidNotifications.cancel(task.id);
        if (!mounted) return;
        task.timer?.cancel();
        setState(() {
          task.updateRemaining(DateTime.now());
          task.isRunning = false;
          task.endsAt = null;
        });
        await saveTasks();
      } else {
        setState(() {
          task.isRunning = true;
          task.endsAt = DateTime.now().add(
            Duration(seconds: task.remainingSeconds),
          );
        });
        startTimer(task);
        final notification = androidNotifications.supported
            ? scheduleNotification(task)
            : Future<bool>.value(true);
        await saveTasks();
        await notification;
      }
    } catch (_) {
      showMessage(
        'Не удалось изменить уведомление Android. Попробуйте ещё раз',
      );
    } finally {
      if (mounted) setState(() => task.isBusy = false);
    }
  }

  final TextEditingController titleController = TextEditingController();
  final hoursController = TextEditingController();
  final minutesController = TextEditingController();
  final secondsController = TextEditingController();
  Future<void> resetTimer(Task task) async {
    if (task.isBusy) return;
    setState(() => task.isBusy = true);
    try {
      await androidNotifications.cancel(task.id);
      if (!mounted) return;
      task.timer?.cancel();
      setState(() {
        task.remainingSeconds = task.initialSeconds;
        task.isRunning = false;
        task.isFinished = false;
        task.endsAt = null;
      });
      await saveTasks();
    } catch (_) {
      showMessage('Не удалось отменить уведомление Android');
    } finally {
      if (mounted) setState(() => task.isBusy = false);
    }
  }

  void addTask(String title, int duration) {
    setState(() {
      tasks.add(Task(id: nextTaskId++, title: title, duration: duration));
    });
    unawaited(saveTasks());
  }

  Future<void> deleteTask(Task task) async {
    if (task.isBusy) return;
    setState(() => task.isBusy = true);
    try {
      await androidNotifications.cancel(task.id);
      if (!mounted) return;
      task.timer?.cancel();
      setState(() => tasks.remove(task));
      await saveTasks();
    } catch (_) {
      showMessage('Не удалось отменить уведомление Android');
    } finally {
      if (mounted) setState(() => task.isBusy = false);
    }
  }

  String formatTime(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    int seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  List<Task> tasks = [];
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (Task task in tasks) {
      task.timer?.cancel();
    }
    titleController.dispose();
    hoursController.dispose();
    minutesController.dispose();
    secondsController.dispose();
    pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Default Timer'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          if (kIsWeb || androidNotifications.supported)
            IconButton(
              tooltip: 'Разрешить и проверить уведомления',
              icon: const Icon(Icons.notifications_outlined),
              onPressed:
                  isLoading || loadError != null || isEnablingNotifications
                  ? null
                  : enableNotifications,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isLoading || loadError != null
            ? null
            : () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text('Новая задача'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: titleController,
                            decoration: const InputDecoration(
                              labelText: 'Название задачи',
                              hintText: 'Например, чтение книги',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('Часы'),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: hoursController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: '00',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('Минуты'),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: minutesController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: '00',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text('Секунды'),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: secondsController,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: '00',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            String title = titleController.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Заполните название задачи'),
                                ),
                              );
                              return;
                            }
                            String hoursText = hoursController.text.trim();

                            int? hours = hoursText.isEmpty
                                ? 0
                                : int.tryParse(hoursText);
                            if (hours == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Часы должны быть числом'),
                                ),
                              );
                              return;
                            }
                            String minutesText = minutesController.text.trim();

                            int? minutes = minutesText.isEmpty
                                ? 0
                                : int.tryParse(minutesText);
                            if (minutes == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Минуты должны быть числом'),
                                ),
                              );
                              return;
                            }
                            String secondsText = secondsController.text.trim();

                            int? seconds = secondsText.isEmpty
                                ? 0
                                : int.tryParse(secondsText);
                            if (seconds == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Секунды должны быть числом'),
                                ),
                              );
                              return;
                            }
                            int duration =
                                hours * 3600 + minutes * 60 + seconds;
                            if (duration <= 0 ||
                                hours < 0 ||
                                minutes < 0 ||
                                minutes > 59 ||
                                seconds < 0 ||
                                seconds > 59) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Проверьте правильность введённого времени',
                                  ),
                                ),
                              );
                              return;
                            }
                            addTask(title, duration);
                            hoursController.clear();
                            minutesController.clear();
                            secondsController.clear();
                            titleController.clear();
                            Navigator.pop(context);
                          },
                          child: const Text('Добавить'),
                        ),
                      ],
                    );
                  },
                );
              },
        child: const Icon(Icons.add),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loadError!, textAlign: TextAlign.center),
                  TextButton(
                    onPressed: loadTasks,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                Task task = tasks[index];

                return AnimatedBuilder(
                  animation: pulseController,
                  builder: (context, child) {
                    return Container(
                      color: task.isFinished
                          ? Color.lerp(
                              Colors.red.shade50,
                              Colors.red.shade300,
                              pulseController.value,
                            )
                          : Colors.transparent,
                      child: ListTile(
                        title: Text(task.title),
                        subtitle: Text(formatTime(task.remainingSeconds)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                task.isRunning ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: task.isFinished || task.isBusy
                                  ? null
                                  : () => toggleTimer(task),
                            ),
                            IconButton(
                              onPressed: task.isBusy
                                  ? null
                                  : () => resetTimer(task),
                              icon: Icon(Icons.restart_alt),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: task.isBusy
                                  ? null
                                  : () => deleteTask(task),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
