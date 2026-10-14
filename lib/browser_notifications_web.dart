import 'dart:js_interop';

@JS('Notification')
external JSFunction? get _notificationConstructor;

@JS('isSecureContext')
external bool get _isSecureContext;

@JS('Notification')
extension type _BrowserNotification._(JSObject _) implements JSObject {
  external factory _BrowserNotification(
    String title,
    _NotificationOptions options,
  );

  external static String get permission;
  external static JSPromise<JSString> requestPermission();
}

extension type _NotificationOptions._(JSObject _) implements JSObject {
  external factory _NotificationOptions({String body});
}

Future<String> requestPermission() async {
  if (_notificationConstructor == null) return 'unsupported';
  if (!_isSecureContext) return 'insecure';

  try {
    final permission = _BrowserNotification.permission;
    if (permission != 'default') return permission;

    final result = await _BrowserNotification.requestPermission().toDart;
    return result.toDart;
  } catch (_) {
    return 'error';
  }
}

bool showNotification(String taskTitle, {bool isTest = false}) {
  if (_notificationConstructor == null || !_isSecureContext) return false;

  try {
    if (_BrowserNotification.permission != 'granted') return false;

    _BrowserNotification(
      isTest ? 'Проверка уведомлений' : 'Таймер завершён',
      _NotificationOptions(
        body: isTest
            ? 'Уведомления Default Timer работают'
            : 'Задача «$taskTitle» завершена',
      ),
    );
    return true;
  } catch (_) {
    return false;
  }
}
