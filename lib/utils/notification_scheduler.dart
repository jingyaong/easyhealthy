import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'daily_reminder_channel_id', // This ID MUST match the one in AndroidNotificationDetails
  'Daily Reminders',
  description: 'Channel for daily habit and workout reminders',
  importance: Importance.max,
);

class NotificationScheduler {
  static final NotificationScheduler _instance = NotificationScheduler._internal();
  factory NotificationScheduler() => _instance;
  NotificationScheduler._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // 1. Initialize Timezones
    tz.initializeTimeZones();

    final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone();
    final String localTz = tzInfo.identifier;
    tz.setLocalLocation(tz.getLocation(localTz));

    // Get the local timezone
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(channel);

    // 2. Setup Android and iOS initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // Use your app's launcher icon

    final DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        // Handle notification tapped while app is in the foreground on older iOS
      },
    );

    // 3. Initialize the plugin
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {

      // 1. First, request the standard notification permission.
      //    The user must grant this one before we can ask for the next.
      await androidImplementation.requestNotificationsPermission();

      // 2. Then, request the exact alarm permission. This will show the special
      //    system dialog where the user can enable the alarm.
      await androidImplementation.requestExactAlarmsPermission();

    }
    // For iOS, permissions are requested during initialization
  }

  /// Cancels all scheduled notifications. Useful on user logout.
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  /// Main function to schedule all reminders for the logged-in user.
  Future<void> scheduleAllReminders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // First, cancel all previous notifications to avoid duplicates
    await cancelAllNotifications();

    // Fetch user's global reminder setting
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final mainReminderEnabled = (userDoc.data()?['mainReminderEnabled'] as bool?) ?? true;

    // If the master switch is off, do not schedule anything.
    if (!mainReminderEnabled) {
      return;
    }

    // Schedule notifications for both habits and workout plans
    await _scheduleHabitReminders(user.uid);
    await _scheduleWorkoutPlanReminders(user.uid);
  }

  // --- Helper Methods ---

  /// Schedules daily notifications for all habits with reminders enabled.
  Future<void> _scheduleHabitReminders(String userId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final mainHabitReminderEnabled = userDoc.data()?['mainHabitReminderEnabled'] as bool? ?? true;

    //If habit reminders are disabled globally for the user, exit early.
    if (!mainHabitReminderEnabled) {
      return;
    }

    final habitsSnapshot =
    await FirebaseFirestore.instance.collection('user_habits').where('user_id', isEqualTo: userId).get();

    for (final doc in habitsSnapshot.docs) {
      final data = doc.data();

      final lastCompletedTimestamp = data['lastCompletedDate'] as Timestamp?;
      bool isCompletedToday = false;
      if (lastCompletedTimestamp != null) {
        final lastCompletion = lastCompletedTimestamp.toDate();
        final now = DateTime.now();
        // Compare year, month, and day to see if it was completed today.
        isCompletedToday = now.year == lastCompletion.year &&
            now.month == lastCompletion.month &&
            now.day == lastCompletion.day;
      }

      // 2. If it's already completed, skip to the next habit.
      if (isCompletedToday) {
        continue;
      }

      final reminderTimeStr = data['reminderTime'] as String?;
      final reminderEnabled = data['reminderEnabled'] as bool? ?? false;

      if (reminderEnabled && reminderTimeStr != null) {
        final timeParts = reminderTimeStr.split(':');
        if (timeParts.length != 2) continue;
        final habitId = data['habitId'] as String?;

        final hour = int.tryParse(timeParts[0]);
        final minute = int.tryParse(timeParts[1]);

        if (hour != null && minute != null && habitId != null) {
          final habitQuerySnapshot = await FirebaseFirestore.instance
              .collection('habits')
              .where('id', isEqualTo: habitId)
              .get();

          String habitName = 'Your Habit'; // Default name.

          // 2. If a matching habit is found, get its name.
          if (habitQuerySnapshot.docs.isNotEmpty) {
            habitName = habitQuerySnapshot.docs.first.data()['name'] as String? ?? 'Your Habit';
          }

          await _scheduleDailyNotification(
            id: doc.id.hashCode, // Use a hash of the unique doc ID for the notification ID
            title: 'Habit Reminder',
            body: "Don't forget to complete your habit: $habitName!",
            hour: hour,
            minute: minute,
          );
        }
      }
    }
  }

  /// Schedules a notification for the active workout plan if today is a workout day.
  Future<void> _scheduleWorkoutPlanReminders(String userId) async {

    final planSnapshot = await FirebaseFirestore.instance
        .collection('workout_plans')
        .where('userId', isEqualTo: userId)
        .get();

    if (planSnapshot.docs.isEmpty) return;

    for (final planDoc in planSnapshot.docs) {
      final planData = planDoc.data();
      final reminderEnabled = planData['planReminderEnabled'] as bool? ?? false;

      // 1. Check if reminders are enabled for THIS specific plan
      if (!reminderEnabled) {
        continue; // Skip to the next plan
      }

      // 2. Check if today is a workout day for this plan
      final todayWeekday = DateTime.now().weekday; // Monday=1, Sunday=7
      final schedule = planData['schedule'] as Map<String, dynamic>?;
      final String dayKey = _getWeekdayKey(todayWeekday);

      final hasWorkoutToday = schedule != null &&
          schedule[dayKey] != null &&
          (schedule[dayKey] as List).isNotEmpty;

      if (!hasWorkoutToday) {
        continue; // Skip to the next plan
      }

      final now = DateTime.now();
      final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
      // Create a Timestamp for the very beginning of tomorrow
      final startOfTomorrow = Timestamp.fromDate(DateTime(now.year, now.month, now.day + 1));

      final activityLogSnapshot = await FirebaseFirestore.instance
          .collection('user_activities')
          .where('user_id', isEqualTo: userId)
          .where('planId', isEqualTo: planDoc.id)
          .where('date', isGreaterThanOrEqualTo: startOfToday)
          .where('date', isLessThan: startOfTomorrow)
          .where('status', isEqualTo: 'Completed')
          .limit(1)
          .get();

      if (activityLogSnapshot.docs.isNotEmpty) {
        continue;
      }

      // 3. If all checks pass, schedule the notification
      final reminderTimeStr = planData['planReminderTime'] as String?;
      if (reminderTimeStr != null) {
        final timeParts = reminderTimeStr.split(':');
        if (timeParts.length != 2) continue;

        final hour = int.tryParse(timeParts[0]);
        final minute = int.tryParse(timeParts[1]);
        final planName = planData['planName'] as String? ?? 'Your Workout';

        if (hour != null && minute != null) {
          await _scheduleDailyNotification(
            id: planDoc.id.hashCode, // Unique ID for the plan notification
            title: 'Time to Train!',
            body: "Let's crush your workout: $planName!",
            hour: hour,
            minute: minute,
          );
        }
      }
    }

  }

  String _getWeekdayKey(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return '';
    }
  }

  /// Generic function to schedule a daily repeating notification.
  Future<void> _scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {

    final nowUtc = DateTime.now().toUtc();
    final offset = DateTime.now().timeZoneOffset;
    final localNow = nowUtc.add(offset);

    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      localNow.year,
      localNow.month,
      localNow.day,
      hour,
      minute,
    );

    // If time has passed, schedule for tomorrow
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel_id',
          'Daily Reminders',
          channelDescription: 'Channel for daily habit and workout reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // daily repeat
      payload: scheduledDate.toIso8601String(),
    );
  }

}
