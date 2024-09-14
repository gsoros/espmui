import 'dart:async';
//import 'dart:developer' as dev;

//import 'package:flutter/foundation.dart';

import 'package:espmui/debug.dart';
import 'package:mutex/mutex.dart';
//import 'util.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef Plugin = FlutterLocalNotificationsPlugin;
typedef AFLNP = AndroidFlutterLocalNotificationsPlugin;
typedef AndroidSettings = AndroidInitializationSettings;
typedef Settings = InitializationSettings;
typedef AndroidDetails = AndroidNotificationDetails;
typedef Details = NotificationDetails;

class Notifications with Debug {
  static final Notifications _instance = Notifications._construct();
  final _exclusiveAccess = Mutex();
  bool _initDone = false;
  Plugin _plugin = Plugin();

  Future<void> _init() async {
    if (_initDone) return;
    await _exclusiveAccess.protect(() async {
      if (_initDone) return;

      await _plugin.initialize(
        Settings(android: AndroidSettings('@mipmap/ic_launcher')),
        //onDidReceiveBackgroundNotificationResponse: onResponse,
        //onDidReceiveNotificationResponse: onResponse,
      );

      // Android 13+
      _plugin.resolvePlatformSpecificImplementation<AFLNP>()?.requestNotificationsPermission();

      _initDone = true;
    });
  }

  Future<void> notify(
    String title,
    String body, {
    int id = 0,
    String channelId = "channel id",
    String channelName = "channel name",
    String? channelDescription,
    Importance importance = Importance.defaultImportance,
    Priority priority = Priority.defaultPriority,
    String? ticker,
    String? payload,
    bool playSound = true,
    bool enableVibration = true,
    bool showProgress = false,
    int maxProgress = 0,
    int progress = 0,
    bool ongoing = false,
    bool onlyAlertOnce = false,
  }) async {
    await _init();
    await _plugin.show(
        id,
        title,
        body,
        Details(
            android: AndroidDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: importance,
          priority: priority,
          ticker: ticker,
          playSound: playSound,
          enableVibration: enableVibration,
          showProgress: showProgress,
          maxProgress: maxProgress,
          progress: progress,
          ongoing: ongoing,
          onlyAlertOnce: onlyAlertOnce,
        )),
        payload: payload);
  }

  Future<void> cancel(int id) async {
    await _init();
    await _plugin.cancel(id);
  }

  void onResponse(NotificationResponse? response) {
    logD("Notifications::onResponse($response)");
  }

  /// returns a singleton
  factory Notifications() {
    return _instance;
  }

  Notifications._construct() {
    logD('_construct()');
    _init();
  }
}
