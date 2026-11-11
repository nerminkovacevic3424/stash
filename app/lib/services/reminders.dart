import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// "Watch this later" nudges, delivered as local notifications. Nothing
/// leaves the phone. Works from both the main app and the share sheet.
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Called with the post id when the user taps a reminder.
  static void Function(String postId)? onOpen;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_stash'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final id = response.payload;
        if (id != null && id.isNotEmpty) onOpen?.call(id);
      },
    );
    _ready = true;
  }

  /// The post whose reminder launched the app, if that is how it was opened.
  static Future<String?> launchPostId() async {
    try {
      await init();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) return details!.notificationResponse?.payload;
    } catch (_) {}
    return null;
  }

  // Notification ids are ints; derive a stable one from the post id.
  static int _id(String postId) => postId.hashCode & 0x7fffffff;

  /// Returns false when the reminder could not be set (permission refused).
  static Future<bool> schedule(String postId, DateTime when, {required String title, String? body}) async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.requestNotificationsPermission() == false) return false;
      await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        sound: true,
      );
      await _plugin.zonedSchedule(
        id: _id(postId),
        // An absolute instant, so the device's time zone database is not needed.
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Reminders',
            channelDescription: 'Nudges for posts you wanted to come back to',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Exact alarms need a special permission; a few minutes either way is fine here.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: postId,
      );
      return true;
    } catch (e) {
      debugPrint('could not schedule reminder: $e');
      return false;
    }
  }

  static Future<void> cancel(String postId) async {
    try {
      await init();
      await _plugin.cancel(id: _id(postId));
    } catch (_) {}
  }
}

/// The ready-made times offered when setting a reminder.
List<(String, DateTime)> reminderChoices(DateTime now) {
  DateTime at(DateTime day, int hour) => DateTime(day.year, day.month, day.day, hour);
  final tomorrow = now.add(const Duration(days: 1));
  // The coming Saturday; from a Saturday, the one after.
  final weekend = now.weekday >= DateTime.saturday;
  final toSaturday = (DateTime.saturday - now.weekday) % 7;
  final saturday = now.add(Duration(days: toSaturday == 0 ? 7 : toSaturday));
  return [
    ('In an hour', now.add(const Duration(hours: 1))),
    if (now.hour < 19) ('Tonight, 8 pm', at(now, 20)),
    ('Tomorrow, 9 am', at(tomorrow, 9)),
    (weekend ? 'Next Saturday, 10 am' : 'Saturday, 10 am', at(saturday, 10)),
    ('In a week', at(now.add(const Duration(days: 7)), 9)),
  ];
}

/// Bottom sheet of [reminderChoices]. Returns the chosen time, or
/// [clearReminder] when the user removes an existing one.
final clearReminder = DateTime.fromMillisecondsSinceEpoch(0);

Future<DateTime?> pickReminder(BuildContext context, {DateTime? current}) => showModalBottomSheet<DateTime>(
  context: context,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'Remind me',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        for (final (label, time) in reminderChoices(DateTime.now()))
          ListTile(
            leading: const Icon(Icons.notifications_none_rounded),
            title: Text(label),
            onTap: () => Navigator.pop(context, time),
          ),
        if (current != null)
          ListTile(
            leading: Icon(Icons.notifications_off_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Remove reminder', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => Navigator.pop(context, clearReminder),
          ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "today 20:00", "Sat 10:00".
String reminderLabel(DateTime when) {
  final now = DateTime.now();
  final days = DateTime(when.year, when.month, when.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final time = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => _days[when.weekday - 1],
  };
  return '$day $time';
}
