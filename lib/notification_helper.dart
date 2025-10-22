import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  // Icons (place a small png in android/app/src/main/res/drawable/)
  const AndroidInitializationSettings android =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings ios =
      DarwinInitializationSettings(requestAlertPermission: true);
  const InitializationSettings settings =
      InitializationSettings(android: android, iOS: ios);
  await _notif.initialize(settings);
}

Future<void> showTextNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  const AndroidNotificationDetails android = AndroidNotificationDetails(
    'chat_channel', 'Chat messages',
    channelDescription: 'Incoming chat messages',
    importance: Importance.high,
    priority: Priority.high,
    ticker: 'ticker',
  );
  const DarwinNotificationDetails ios =
      DarwinNotificationDetails(presentAlert: true, presentBadge: true);
  const NotificationDetails details =
      NotificationDetails(android: android, iOS: ios);
  await _notif.show(id, title, body, details, payload: payload);
}