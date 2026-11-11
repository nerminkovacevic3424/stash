import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Whether Stash is currently allowed to show notifications.
  static Future<bool> enabled() async {
    try {
      await init();
      final android = _android;
      if (android != null) return await android.areNotificationsEnabled() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Shows the system's "allow notifications?" prompt. Android only shows it
  /// a couple of times; after that this returns false without asking, and the
  /// only way forward is the app's settings page ([openSettings]).
  static Future<bool> requestPermission() async {
    try {
      await init();
      final android = _android;
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await const MethodChannel('stash/system').invokeMethod<bool>('openNotificationSettings');
    } catch (_) {}
  }

  /// Makes sure notifications are allowed, asking if they are not: first an
  /// explanation, then the system prompt, and when the system will no longer
  /// ask, a pointer to the settings page. Returns whether they are allowed now.
  static Future<bool> ensurePermission(BuildContext context) async {
    if (await enabled()) return true;
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('Turn on notifications'),
        content: const Text(
          'Stash uses notifications only for the reminders you set, to bring a saved post back at the time you chose.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (go != true) return false;
    if (await requestPermission()) return true;
    if (await enabled()) return true;
    if (!context.mounted) return false;

    // The system declined to ask (it was refused before). Send them to settings.
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications are blocked'),
        content: const Text(
          'Your phone is not letting Stash ask again. Open settings, turn on "Allow notifications" for Stash, '
          'then come back and set the reminder.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (open == true) await openSettings();
    return false;
  }

  /// Why the last [schedule] failed, for showing to the user.
  static String? lastError;

  /// Schedules the notification. Permission must already be granted (see
  /// [ensurePermission]). Returns false and sets [lastError] on failure.
  static Future<bool> schedule(String postId, DateTime when, {required String title, String? body}) async {
    lastError = null;
    try {
      await init();
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
      lastError = e is PlatformException ? (e.message ?? e.code) : '$e';
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

/// Returned by [pickReminder] when the user removes an existing reminder.
final clearReminder = DateTime.fromMillisecondsSinceEpoch(0);

/// Bottom sheet with the ready-made times and "Pick date and time". Returns
/// the chosen moment, [clearReminder], or null when dismissed.
Future<DateTime?> pickReminder(BuildContext context, {DateTime? current}) async {
  const custom = 'custom';
  final choice = await showModalBottomSheet<Object>(
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
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Pick date and time'),
            onTap: () => Navigator.pop(context, custom),
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
  if (choice is DateTime) return choice;
  if (choice != custom || !context.mounted) return null;
  return pickCustomReminder(context, initial: current);
}

/// Date picker, then time picker. Null when cancelled or when the chosen
/// moment has already passed.
Future<DateTime?> pickCustomReminder(BuildContext context, {DateTime? initial}) async {
  final now = DateTime.now();
  final start = initial != null && initial.isAfter(now) ? initial : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: start,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: now.add(const Duration(days: 365)),
    helpText: 'Remind me on',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(start),
    helpText: 'At what time',
  );
  if (time == null) return null;
  final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (!when.isAfter(DateTime.now())) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('Pick a time that is still ahead')));
    }
    return null;
  }
  return when;
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "today 20:00", "Sat 10:00", "24 Dec 09:30".
String reminderLabel(DateTime when) {
  final now = DateTime.now();
  final days = DateTime(when.year, when.month, when.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final time = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    < 7 => _days[when.weekday - 1],
    _ => '${when.day} ${_months[when.month - 1]}',
  };
  return '$day $time';
}
