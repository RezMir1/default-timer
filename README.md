# default_timer

Таймер задач с сохранением состояния и уведомлениями.

## Запуск

После добавления плагинов полностью остановите старый запуск приложения.

```powershell
flutter pub get
flutter run -d chrome --web-port=8080
```

В браузере задачи сохраняются в localStorage текущего сайта. Используйте тот же
браузер, hostname и порт при повторном запуске. Очистка данных сайта удаляет задачи.
Пустой список тоже сохраняется: удалённые примеры не появляются снова.

На Android задачи сохраняются локально на устройстве. Для сборки нужен Android SDK:

```powershell
flutter build apk --debug
```

## Уведомления и таймеры

Нажмите колокольчик, чтобы разрешить и проверить уведомления. На Android также
разрешите точные будильники; без этого используется неточное планирование.
Уведомление планируется при запуске таймера и отменяется при паузе, сбросе или
удалении задачи. Android доставляет его самостоятельно, без работающего
Dart-таймера. Принудительная остановка приложения и ограничения производителя
телефона могут препятствовать доставке.

В браузере уведомления создаются только пока страница выполняет код. При закрытой
вкладке уведомление не создаётся. При повторном открытии состояние таймера
восстанавливается по сохранённому времени окончания. Завершённые во время закрытия
задачи отображаются завершёнными без повторного уведомления.

## Проверка

```powershell
flutter analyze
flutter test
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
