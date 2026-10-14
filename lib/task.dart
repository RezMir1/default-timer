import 'dart:async';

class Task {
  final int id;
  String title;
  int remainingSeconds;
  final int initialSeconds;
  bool isRunning;
  bool isFinished;
  DateTime? endsAt;
  Timer? timer;
  bool isBusy = false;

  Task({
    required this.id,
    required this.title,
    required int duration,
    int? remainingSeconds,
    this.isRunning = false,
    this.isFinished = false,
    this.endsAt,
  }) : initialSeconds = duration,
       remainingSeconds = remainingSeconds ?? duration;

  // Округляем вверх, чтобы 2.8 секунды отображались как 3, а не как 2.
  void updateRemaining(DateTime now) {
    if (!isRunning || endsAt == null) return;
    final milliseconds = endsAt!.difference(now).inMilliseconds;
    remainingSeconds = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
    if (remainingSeconds == 0) {
      isRunning = false;
      isFinished = true;
      endsAt = null;
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'initialSeconds': initialSeconds,
    'remainingSeconds': remainingSeconds,
    'isRunning': isRunning,
    'isFinished': isFinished,
    'endsAt': endsAt?.toUtc().toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final title = json['title'] as String;
    final duration = json['initialSeconds'] as int;
    final remaining = json['remainingSeconds'] as int;
    final running = json['isRunning'] as bool;
    final finished = json['isFinished'] as bool;
    final endsAt = json['endsAt'] == null
        ? null
        : DateTime.parse(json['endsAt'] as String);
    if (id <= 0 ||
        id >= 2147483647 ||
        title.trim().isEmpty ||
        duration <= 0 ||
        remaining < 0 ||
        remaining > duration ||
        (running && (endsAt == null || finished)) ||
        (finished && remaining != 0)) {
      throw const FormatException('Некорректные данные задачи');
    }
    return Task(
      id: id,
      title: title,
      duration: duration,
      remainingSeconds: remaining,
      isRunning: running,
      isFinished: finished,
      endsAt: endsAt,
    );
  }
}
