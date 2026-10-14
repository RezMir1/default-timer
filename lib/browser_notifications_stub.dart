// На других платформах браузерные уведомления не используются.
Future<String> requestPermission() async => 'unsupported';

bool showNotification(String taskTitle, {bool isTest = false}) => false;
