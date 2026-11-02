import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'offline_pack.dart';

/// Status-bar notice while ATLAS is saving exams on the phone.
class OfflineSaveAlerts {
  OfflineSaveAlerts._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _id = 4101;
  static bool _ready = false;
  static bool _asked = false;
  static bool _showing = false;
  static int _lastPercent = -1;

  static Future<void> start() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: android),
      );
      _ready = true;
      OfflinePack.progress.addListener(_handle);
    } catch (e) {
      debugPrint('Save notification unavailable: $e');
    }
  }

  static void _handle() {
    final progress = OfflinePack.progress.value;
    if (progress.active && !progress.finished) {
      if (_showing && _lastPercent == progress.percent) return;
      _lastPercent = progress.percent;
      _showing = true;
      unawaited(_show(progress));
      return;
    }
    if (!_showing) return;
    _showing = false;
    _lastPercent = -1;
    unawaited(_hide());
  }

  static Future<void> _show(OfflineSaveProgress progress) async {
    if (!_ready) return;
    try {
      if (!_asked) {
        _asked = true;
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      final body = progress.known
          ? 'Saving your exams and class lists so you can scan without internet. ${progress.percent}% saved.'
          : 'Saving your exams and class lists so you can scan without internet.';
      await _plugin.show(
        _id,
        'ATLAS',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'atlas_offline_save',
            'Saving exams',
            channelDescription:
                'Shown while ATLAS saves your exams and class lists on this phone.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
            showProgress: true,
            maxProgress: 100,
            progress: progress.percent,
            indeterminate: !progress.known,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Save notification failed: $e');
    }
  }

  static Future<void> _hide() async {
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }
}
