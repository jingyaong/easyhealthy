import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/health_calculator.dart';
import '../utils/notification_scheduler.dart';

class PlanDetailsPage extends StatefulWidget {
  final Map<String, dynamic> planData;

  const PlanDetailsPage({super.key, required this.planData});

  @override
  State<PlanDetailsPage> createState() => _PlanDetailsPageState();
}

class _PlanDetailsPageState extends State<PlanDetailsPage> {
  final Map<String, ({double met, int calories})> _activityData = {};
  double? _userWeightKg;
  bool _isLoading = true;
  double _totalWeeklyCalories = 0;
  List<Map<String, dynamic>> _todaysActivities = [];
  bool _isDeleting = false;
  bool _isEditingReminder = false;
  late bool _reminderEnabled;
  TimeOfDay? _reminderTime;

  @override
  void initState() {
    super.initState();
    _reminderEnabled = widget.planData['planReminderEnabled'] as bool? ?? false;
    final timeString = widget.planData['planReminderTime'] as String?;
    if (timeString != null) {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        _reminderTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    }

    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final todayStart = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      final List<dynamic> results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('activities').get(),
        FirebaseFirestore.instance
            .collection('user_activities')
            .where('user_id', isEqualTo: user.uid)
            .where('date', isEqualTo: Timestamp.fromDate(todayStart))
            .where('status', isEqualTo: 'Planned')
            .get(),
      ]);

      final DocumentSnapshot userDoc = results[0] as DocumentSnapshot;
      final QuerySnapshot activitiesSnapshot = results[1] as QuerySnapshot;
      final QuerySnapshot todaysPlannedActivities = results[2] as QuerySnapshot;
      final List<Map<String, dynamic>> activitiesForToday =
          todaysPlannedActivities.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList();


      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        _userWeightKg = (data?['weight'] as num?)?.toDouble();
      }

      // Process activities data
      final Map<String, ({double met, int calories})> dataMap = {};
      for (var doc in activitiesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name'] as String?;
        if (name != null) {
          dataMap[name] = (
            met: (data['met'] as num?)?.toDouble() ?? 0.0,
            calories: (data['calories_per_hour'] as num?)?.toInt() ?? 0,
          );
        }
      }

      setState(() {
        _activityData.addAll(dataMap);
        if (_userWeightKg != null) {
          _calculateTotalWeeklyCalories();
        }
        _todaysActivities = activitiesForToday;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error fetching data: $e')));
    }
  }

  Future<void> _markTodayAsCompleted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _todaysActivities.isEmpty) return;

    final todayStart = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    try {
      final query = FirebaseFirestore.instance
          .collection('user_activities')
          .where('user_id', isEqualTo: user.uid)
          .where('status', isEqualTo: 'Planned')
          .where('date', isEqualTo: Timestamp.fromDate(todayStart));

      final snapshot = await query.get();
      final batch = FirebaseFirestore.instance.batch();
      final Timestamp completionTimestamp = Timestamp.now();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': 'Completed',
          'date': completionTimestamp, // Overwrite the original date
        });
      }

      await batch.commit();

      setState(() {
        _todaysActivities = [];
      });
      await NotificationScheduler().scheduleAllReminders();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Today's activities marked as completed!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating activities: $e')));
    }
  }

  Future<void> _deletePlan() async {
    final user = FirebaseAuth.instance.currentUser;
    final planId = widget.planData['documentId'];
    final planName = widget.planData['planName'];
    if (user == null || planId == null) return;

    // Show confirmation dialog
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: Text(
          'Are you sure you want to delete the "$planName" plan and all its scheduled activities? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    setState(() => _isDeleting = true);

    try {
      final todayStart = Timestamp.fromDate(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      );

      // 1. Find and delete all associated "Planned" activities
      final query = FirebaseFirestore.instance
          .collection('user_activities')
          .where('user_id', isEqualTo: user.uid)
          .where('planId', isEqualTo: planId)
          .where('status', isEqualTo: 'Planned')
          .where('date', isGreaterThanOrEqualTo: todayStart);

      final snapshot = await query.get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // 2. Delete the main plan document
      await FirebaseFirestore.instance
          .collection('workout_plans')
          .doc(planId)
          .delete();
      await NotificationScheduler().scheduleAllReminders();

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$planName" was deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting plan: $e')));
    }
  }

  Future<void> _saveReminderChanges() async {
    setState(() => _isLoading = true);
    try {
      final planDocRef = FirebaseFirestore.instance
          .collection('workout_plans')
          .doc(widget.planData['documentId']);

      await planDocRef.update({
        'planReminderEnabled': _reminderEnabled,
        'planReminderTime': _reminderEnabled && _reminderTime != null
            ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
            : null,
      });

      if (mounted) {

        widget.planData['planReminderEnabled'] = _reminderEnabled;
        widget.planData['planReminderTime'] =
            _reminderEnabled && _reminderTime != null
            ? '${_reminderTime!.hour.toString().padLeft(2, '0')}:${_reminderTime!.minute.toString().padLeft(2, '0')}'
            : null;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        await NotificationScheduler().scheduleAllReminders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEditingReminder = false;
        });
      }
    }
  }

  /// Calculates total weekly calories using the HealthCalculator.
  void _calculateTotalWeeklyCalories() {
    double total = 0;
    final schedule = widget.planData['schedule'] as Map<String, dynamic>? ?? {};
    schedule.forEach((day, activities) {
      for (var activity in (activities as List<dynamic>)) {
        total += _calculateCaloriesForActivity(
          activity['name'] as String,
          (activity['duration'] as num).toInt(),
        );
      }
    });
    _totalWeeklyCalories = total;
  }

  /// Helper to calculate calories using the HealthCalculator.
  double _calculateCaloriesForActivity(String name, int durationInMinutes) {
    // If user weight is not available, we can't calculate accurately.
    if (_userWeightKg == null || _userWeightKg! <= 0) return 0.0;

    final activity = _activityData[name];
    if (activity == null) return 0.0;

    // Use MET value if available and valid
    if (activity.met > 0) {
      return HealthCalculator.calculateCaloriesBurned(
        met: activity.met,
        userWeightKg: _userWeightKg!,
        durationMinutes: durationInMinutes,
      ).toDouble();
    }
    // FALLBACK: Use calories_per_hour if MET is not available
    else if (activity.calories > 0) {
      return (activity.calories / 60) * durationInMinutes;
    }

    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final String planName = widget.planData['planName'] ?? 'Unnamed Plan';
    final Map<String, dynamic> schedule = widget.planData['schedule'] ?? {};
    final daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final int workoutDays = schedule.values
        .where((activities) => (activities as List).isNotEmpty)
        .length;
    final double averageDailyCalories = (workoutDays > 0)
        ? _totalWeeklyCalories / workoutDays
        : 0.0;
    final int weeksDuration = widget.planData['weeksDuration'] ?? 0;
    final Timestamp createdAt = widget.planData['createdAt'] ?? Timestamp.now();
    final DateTime startDate = createdAt.toDate();
    final DateTime endDate = startDate.add(Duration(days: weeksDuration * 7));

    return Scaffold(
      appBar: AppBar(
        title: Text(planName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deletePlan,
            tooltip: 'Delete Plan',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _todaysActivities.isNotEmpty
          ? SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              child: FloatingActionButton.extended(
                onPressed: _markTodayAsCompleted,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark Today Completed'),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userWeightKg == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'Cannot calculate calories. Please set your weight in your profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  elevation: 1,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'Enable Daily Reminder',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        value: _reminderEnabled,
                        onChanged: (bool value) {
                          setState(() {
                            _isEditingReminder =
                                true; // Enter edit mode on change
                            _reminderEnabled = value;
                            if (!value) {
                              _reminderTime = null; // Clear time if disabled
                            } else {
                              // Default to 8:00 AM if enabling and no time was set
                              _reminderTime ??= const TimeOfDay(
                                hour: 8,
                                minute: 0,
                              );
                            }
                          });
                        },
                        secondary: Icon(
                          _reminderEnabled
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                        ),
                      ),
                      if (_reminderEnabled)
                        ListTile(
                          leading: const Icon(Icons.alarm),
                          title: const Text('Reminder Time'),
                          trailing: Text(
                            _reminderTime?.format(context) ?? 'Select Time',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          onTap: () async {
                            final TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: _reminderTime ?? TimeOfDay.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    timePickerTheme: Theme.of(context)
                                        .timePickerTheme
                                        .copyWith(
                                          dayPeriodColor: const Color(
                                            0xFF2196F3,
                                          ),
                                        ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (picked != null) {
                              setState(() {
                                _isEditingReminder =
                                    true; // Enter edit mode on change
                                _reminderTime = picked;
                              });
                            }
                          },
                        ),
                      // Show Save/Cancel buttons only when in edit mode
                      if (_isEditingReminder)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 8.0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () {
                                  // Revert changes and exit edit mode
                                  setState(() {
                                    _isEditingReminder = false;
                                    _reminderEnabled =
                                        widget
                                            .planData['planReminderEnabled'] ??
                                        false;
                                    // Logic to reset time
                                    final timeString =
                                        widget.planData['planReminderTime']
                                            as String?;
                                    if (timeString != null) {
                                      final parts = timeString.split(':');
                                      _reminderTime = TimeOfDay(
                                        hour: int.parse(parts[0]),
                                        minute: int.parse(parts[1]),
                                      );
                                    } else {
                                      _reminderTime = null;
                                    }
                                  });
                                },
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _saveReminderChanges,
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Average Calories Card
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Estimated Calorie Burn Per Workout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${averageDailyCalories.toStringAsFixed(0)} kcal',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (widget.planData['motivationalComment'] != null &&
                    (widget.planData['motivationalComment'] as String)
                        .isNotEmpty)
                  Column(
                    children: [
                      Card(
                        color: Colors.green.shade50,
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.format_quote,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.planData['motivationalComment'],
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildInfoColumn('Duration', '$weeksDuration Weeks'),
                        _buildInfoColumn(
                          'From',
                          DateFormat.yMMMd().format(startDate),
                        ),
                        _buildInfoColumn(
                          'To',
                          DateFormat.yMMMd().format(endDate),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Daily cards
                ...daysOfWeek.map((day) {
                  final List<dynamic> activitiesForDay = schedule[day] ?? [];
                  final double dailyCalories = activitiesForDay.fold(0.0, (
                    sum,
                    activity,
                  ) {
                    return sum +
                        _calculateCaloriesForActivity(
                          activity['name'],
                          (activity['duration'] as num).toInt(),
                        );
                  });
                  final int dailyTotalMinutes = activitiesForDay.fold(0, (
                    sum,
                    activity,
                  ) {
                    return sum + ((activity['duration'] as num?)?.toInt() ?? 0);
                  });

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat('EEEE').format(
                                DateTime.now().add(
                                  Duration(
                                    days:
                                        daysOfWeek.indexOf(day) -
                                        DateTime.now().weekday +
                                        1,
                                  ),
                                ),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              '$dailyTotalMinutes min',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            Text(
                              '${dailyCalories.toStringAsFixed(0)} kcal',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20),
                        if (activitiesForDay.isEmpty)
                          const Text(
                            'No activities scheduled for this day.',
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ...activitiesForDay.map((activity) {
                            final activityName =
                                activity['name'] ?? 'Unknown Activity';
                            final duration =
                                (activity['duration'] as num?)?.toInt() ?? 0;
                            final activityCalories =
                                _calculateCaloriesForActivity(
                                  activityName,
                                  duration,
                                );
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      activityName,
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ),
                                  Text(
                                    '$duration min',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '${activityCalories.toStringAsFixed(0)} kcal',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                      ],
                    ),
                  );
                }).toList(),
                if (_todaysActivities.isNotEmpty) const SizedBox(height: 100),
              ],
            ),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }
}
