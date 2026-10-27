import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../model/PlannedActivity.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../utils/notification_scheduler.dart';
import '../utils/plan_generator.dart';
import '../utils/health_calculator.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import '../screens/view_plan.dart';

class WorkoutPlanPage extends StatefulWidget {
  const WorkoutPlanPage({super.key});

  @override
  _WorkoutPlanPageState createState() => _WorkoutPlanPageState();
}

class _WorkoutPlanPageState extends State<WorkoutPlanPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _planNameController = TextEditingController();
  final _planDurationController = TextEditingController();
  final _generatePlanDurationController = TextEditingController();
  final Map<String, ({String id, double met})> _activityMasterData = {};
  double? _userWeightKg;
  double? _userCalorieGoal;
  List<String> _availableGoals = ['Lose Weight'];
  bool _planReminderEnabled = false;
  TimeOfDay? _planReminderTime;
  final _customPlanFormKey = GlobalKey<FormState>();
  final _generatePlanFormKey = GlobalKey<FormState>();

  ValueNotifier<String?> _goalController = ValueNotifier(null);
  List<String> _selectedWorkoutDays = [];
  final List<String> _allWeekDays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  final ValueNotifier<String?> _sessionDurationController = ValueNotifier(null);
  final ValueNotifier<String?> _intensityController = ValueNotifier(null);
  final _activityPrefsController = TextEditingController();
  final _additionalNotesController = TextEditingController();

  final Map<String, List<PlannedActivity>> _weeklySchedule = {
    'Mon': [],
    'Tue': [],
    'Wed': [],
    'Thu': [],
    'Fri': [],
    'Sat': [],
    'Sun': [],
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    _goalController = ValueNotifier(null);
    _fetchPrerequisites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _planNameController.dispose();
    _planDurationController.dispose();
    _generatePlanDurationController.dispose();
    _goalController.dispose();
    _sessionDurationController.dispose();
    _intensityController.dispose();
    _activityPrefsController.dispose();
    _additionalNotesController.dispose();
    super.dispose();
  }

  Future<bool> _fetchPrerequisites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final List<dynamic> results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('activities').get(),
      ]);

      final DocumentSnapshot userDoc = results[0] as DocumentSnapshot;
      final QuerySnapshot activitiesSnapshot = results[1] as QuerySnapshot;

      // Get user weight
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        _userWeightKg = (data?['weight'] as num?)?.toDouble();
        _userCalorieGoal = (data?['daily_burn_goal'] as num?)?.toDouble();
        final double? userHeightCm = (data?['height'] as num?)?.toDouble();

        if (_userWeightKg != null && userHeightCm != null) {
          // 1. Calculate BMI
          final double bmi = HealthCalculator.calculateBMI(
            _userWeightKg!,
            userHeightCm,
          );

          // 2. Get the list of suggested goals from the calculator
          final List<String> suggestedGoals =
              HealthCalculator.getFitnessGoalsForBMI(bmi);

          // 3. Use the first and most relevant goal as the default
          setState(() {
            _availableGoals = suggestedGoals;
            // Set the pre-selected goal to the first (most relevant) one.
            if (_availableGoals.isNotEmpty) {
              _goalController.value = _availableGoals.first;
            }
          });
        }

        if (_userCalorieGoal == null) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please set your "Daily Calorie Goal" in your profile to generate a plan.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          return false; // Stop if calorie goal is missing
        }
      } else {
        // Handle case where user document doesn't exist
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'User profile not found. Please complete your profile.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      // Get master list of activities with their IDs and MET values
      _activityMasterData.clear();
      for (var doc in activitiesSnapshot.docs) {
        // This is now safe
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name'] as String?;
        if (name != null) {
          _activityMasterData[name] = (
            id: doc.id, // Store the document ID
            met: (data['met'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching data: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Widget _buildReminderControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Enable Daily Reminder',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                value: _planReminderEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _planReminderEnabled = value;
                    if (!value) {
                      _planReminderTime =
                          null; // Clear time if reminder is disabled
                    } else {
                      _planReminderTime ??= const TimeOfDay(
                        hour: 8,
                        minute: 0,
                      ); // Default to 8:00 AM if enabling
                    }
                  });
                },
                secondary: Icon(
                  _planReminderEnabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
              ),
              if (_planReminderEnabled)
                ListTile(
                  leading: const Icon(Icons.alarm),
                  title: const Text('Reminder Time'),
                  trailing: Text(
                    _planReminderTime?.format(context) ?? 'Select Time',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: _planReminderTime ?? TimeOfDay.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            timePickerTheme: Theme.of(context).timePickerTheme
                                .copyWith(
                                  dayPeriodColor: const Color(0xFF2196F3),
                                ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _planReminderTime = picked;
                      });
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _saveCustomPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    final planName = _planNameController.text.trim();

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to save a plan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (planName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for your plan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final int? weeks = int.tryParse(_planDurationController.text.trim());
    if (weeks == null || weeks <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid number of weeks.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!(_customPlanFormKey.currentState?.validate() ?? false)) {
      return;
    }

    // Check if at least one activity has been scheduled
    final hasAtLeastOneActivity = _weeklySchedule.values.any(
      (dayList) => dayList.isNotEmpty,
    );
    if (!hasAtLeastOneActivity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one activity to your schedule.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bool canProceed = await _fetchPrerequisites();
    if (!canProceed) {
      return;
    }

    final now = DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    final planType = _tabController.index == 0 ? 'Custom' : 'Generated';
    final planDocRef = FirebaseFirestore.instance
        .collection('workout_plans')
        .doc();
    final String newPlanId = planDocRef.id;

    final scheduleForFirestore = _weeklySchedule.map((day, activities) {
      return MapEntry(
        day,
        activities
            .map(
              (activity) => {
                'name': activity.name,
                'duration': activity.duration,
              },
            )
            .toList(),
      );
    });

    batch.set(planDocRef, {
      'userId': user.uid,
      'planName': planName,
      'planType': planType,
      'weeksDuration': weeks,
      'schedule': scheduleForFirestore,
      'createdAt': FieldValue.serverTimestamp(),
      'planReminderEnabled': _planReminderEnabled,
      'planReminderTime': _planReminderEnabled && _planReminderTime != null
          ? '${_planReminderTime!.hour.toString().padLeft(2, '0')}:${_planReminderTime!.minute.toString().padLeft(2, '0')}'
          : null,
    });

    for (int week = 0; week < weeks; week++) {
      _weeklySchedule.forEach((day, activities) {
        if (activities.isNotEmpty) {
          final dayIndex = [
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat',
            'Sun',
          ].indexOf(day);
          final int daysToAdd = (dayIndex - (now.weekday - 1) + 7) % 7;
          final DateTime activityDate = DateTime(
            now.year,
            now.month,
            now.day,
          ).add(Duration(days: daysToAdd + (week * 7)));

          for (var activity in activities) {
            final masterActivity = _activityMasterData[activity.name];
            if (masterActivity == null)
              continue; // Skip if activity not found in master list

            final calories = HealthCalculator.calculateCaloriesBurned(
              met: masterActivity.met,
              userWeightKg: _userWeightKg!,
              durationMinutes: activity.duration,
            );

            final docRef = FirebaseFirestore.instance
                .collection('user_activities')
                .doc();

            batch.set(docRef, {
              'user_id': user.uid,
              'planId': newPlanId,
              'activity_id': masterActivity.id,
              'custom_name': activity.name,
              'duration_minutes': activity.duration,
              'calories_burned': calories.toInt(),
              'date': Timestamp.fromDate(activityDate),
              'status': 'Planned',
              'notes': 'Activity of $planName plan.',
              'created_at': FieldValue.serverTimestamp(),
            });
          }
        }
      });
    }

    try {
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan scheduled successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      final planDataForNav = {
        'documentId': planDocRef.id,
        'planName': planName,
        'planType': 'Custom',
        'weeksDuration': weeks,
        'schedule': scheduleForFirestore,
        'createdAt': Timestamp.now(),
      };

      await NotificationScheduler().scheduleAllReminders();

      // Navigate to the details page
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlanDetailsPage(planData: planDataForNav),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save plan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _generatePlanWithAI() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to generate a plan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!(_generatePlanFormKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_selectedWorkoutDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one workout day.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }


    final weeksText = _generatePlanDurationController.text.trim();
    final int? weeks = int.tryParse(weeksText);
    if (weeks == null || weeks <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid duration in weeks.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating and saving your plan...'),
        duration: Duration(seconds: 25),
      ),
    );

    // Fetch user weight, calorie goal, and master activity list before proceeding
    final bool canProceed = await _fetchPrerequisites();
    if (!canProceed) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).hideCurrentSnackBar();
      return;
    }

    try {
      // Use the master list of activities already fetched by _fetchPrerequisites
      final List<String> availableActivities = _activityMasterData.keys
          .toList();
      if (availableActivities.isEmpty) {
        throw Exception(
          "Could not find any activities in the database. Please add some first.",
        );
      }

      // 1. Call the AI Service to get the plan structure
      final jsonResponse = await AiPlanGenerator.generatePlan(
        goal: _goalController.value,
        workoutDays: _selectedWorkoutDays.join(', '),
        sessionDuration: _sessionDurationController.value,
        intensity: _intensityController.value,
        activityPrefs: _activityPrefsController.text,
        additionalNotes: _additionalNotesController.text,
        dailyCalorieGoal: _userCalorieGoal,
        availableActivities: availableActivities,
      );

      // 2. Parse the AI response
      final generatedPlanName = jsonResponse['planName'] as String;
      final generatedScheduleMap =
          jsonResponse['schedule'] as Map<String, dynamic>;
      final motivationalComment =
          jsonResponse['motivationalComment'] as String? ??
          'Let\'s get started!'; // Default value

      // 3. Prepare all Firestore writes in a single batch
      final batch = FirebaseFirestore.instance.batch();
      final now = DateTime.now();
      final planDocRef = FirebaseFirestore.instance
          .collection('workout_plans')
          .doc();
      final newPlanId = planDocRef.id;

      // 3a. Prepare the main `workout_plans` document
      final scheduleForFirestore = generatedScheduleMap.map((day, activities) {
        return MapEntry(
          day,
          (activities as List).map((activity) {
            return {
              'name': activity['name'],
              'duration': (activity['duration'] as num).toInt(),
            };
          }).toList(),
        );
      });

      batch.set(planDocRef, {
        'userId': user.uid,
        'planName': generatedPlanName,
        'planType': 'Generated',
        'weeksDuration': weeks,
        'schedule': scheduleForFirestore,
        'createdAt': FieldValue.serverTimestamp(),
        'motivationalComment': motivationalComment,
        'planReminderEnabled': _planReminderEnabled,
        'planReminderTime': _planReminderEnabled && _planReminderTime != null
            ? '${_planReminderTime!.hour.toString().padLeft(2, '0')}:${_planReminderTime!.minute.toString().padLeft(2, '0')}'
            : null,
      });

      // 3b. Prepare all the scheduled `user_activities` documents
      for (int week = 0; week < weeks; week++) {
        generatedScheduleMap.forEach((day, activities) {
          if ((activities as List).isNotEmpty) {
            final dayIndex = [
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
              'Sun',
            ].indexOf(day);
            final int daysToAdd = (dayIndex - (now.weekday - 1) + 7) % 7;
            final DateTime activityDate = DateTime(
              now.year,
              now.month,
              now.day,
            ).add(Duration(days: daysToAdd + (week * 7)));

            for (var activity in activities) {
              final activityName = activity['name'] as String;
              final masterActivity = _activityMasterData[activityName];

              // Only save activities that are in our master list to ensure data integrity
              if (masterActivity == null) continue;

              final duration = (activity['duration'] as num).toInt();
              final calories = HealthCalculator.calculateCaloriesBurned(
                met: masterActivity.met,
                userWeightKg: _userWeightKg!,
                durationMinutes: duration,
              );

              final docRef = FirebaseFirestore.instance
                  .collection('user_activities')
                  .doc();
              batch.set(docRef, {
                'user_id': user.uid,
                'planId': newPlanId,
                'activity_id': masterActivity.id,
                'custom_name': activityName,
                'duration_minutes': duration,
                'calories_burned': calories.toInt(),
                'date': Timestamp.fromDate(activityDate),
                'status': 'Planned',
                'notes': 'Activity of "$generatedPlanName" plan.',
                'created_at': FieldValue.serverTimestamp(),
              });
            }
          }
        });
      }

      // 4. Commit all writes in a single atomic operation
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generated plan saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      await NotificationScheduler().scheduleAllReminders();

      final planDataForNav = {
        'documentId': newPlanId,
        'planName': generatedPlanName,
        'planType': 'Generated',
        'weeksDuration': weeks,
        'schedule': scheduleForFirestore,
        'motivationalComment': motivationalComment,
        'createdAt': Timestamp.now(), // Use current time as a placeholder
      };

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PlanDetailsPage(planData: planDataForNav),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate or save plan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showActivityPicker(BuildContext context, String day) async {
    final activitiesSnapshot = await FirebaseFirestore.instance
        .collection('activities')
        .get();
    final activityNames = activitiesSnapshot.docs
        .map((doc) => doc.data()['name'] as String)
        .toList();
    String? selectedActivity;
    final durationController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Add Activity to $day'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownSearch<String>(
                  popupProps: PopupProps.menu(
                    showSearchBox: true,
                    searchFieldProps: TextFieldProps(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search activities',
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                    emptyBuilder: (context, searchEntry) =>
                        Center(child: Text('No activity found')),
                  ),
                  items: activityNames,
                  dropdownDecoratorProps: DropDownDecoratorProps(
                    dropdownSearchDecoration: InputDecoration(
                      labelText: "Activity",
                      hintText: "Select an activity",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  onChanged: (value) => selectedActivity = value,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (in minutes)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (selectedActivity != null &&
                    durationController.text.isNotEmpty) {
                  final duration = int.tryParse(durationController.text);
                  if (duration != null && duration > 0) {
                    setState(() {
                      _weeklySchedule[day]!.add(
                        PlannedActivity(
                          name: selectedActivity!,
                          duration: duration,
                        ),
                      );
                    });
                    Navigator.of(dialogContext).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid duration.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please select an activity and enter a duration.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Workout Plan'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Custom Plan'),
            Tab(text: 'Generate Plan'),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFloatingActionButton(),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCustomPlanTab(), _buildGeneratePlanTab()],
      ),
    );
  }

  /// UI for the "Custom Plan" tab
  Widget _buildCustomPlanTab() {
    final daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Form(
      key: _customPlanFormKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const Text(
            'Plan Name',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _planNameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'My Summer Shred',
              hintStyle: TextStyle(color: Colors.grey),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a plan name.';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          const Text(
            'Plan Duration (in weeks)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _planDurationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '4',
              hintStyle: TextStyle(color: Colors.grey),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a duration.';
              }
              final weeks = int.tryParse(value);
              if (weeks == null || weeks <= 0) {
                return 'Please enter a valid number of weeks.';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          _buildReminderControls(),
          const SizedBox(height: 24),

          const Text(
            'Weekly Schedule',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          ...daysOfWeek.map((day) {
            final activitiesForDay = _weeklySchedule[day]!;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      alignment: Alignment.center,
                      child: Text(
                        day,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const VerticalDivider(),
                    Expanded(
                      child: activitiesForDay.isEmpty
                          ? const Text(
                              'No activities scheduled.',
                              style: TextStyle(color: Colors.grey),
                            )
                          : Wrap(
                              // Use Wrap to handle multiple activities nicely
                              spacing: 8.0,
                              runSpacing: 4.0,
                              children: activitiesForDay.map((activity) {
                                return Chip(
                                  label: Text(
                                    '${activity.name} (${activity.duration} min)',
                                  ),
                                  onDeleted: () {
                                    setState(() {
                                      _weeklySchedule[day]!.remove(activity);
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.blue,
                      ),
                      onPressed: () => _showActivityPicker(context, day),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// UI for the "Generate Plan" tab (AI-powered)
  Widget _buildGeneratePlanTab() {
    return Form(
      key: _generatePlanFormKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          _buildReminderControls(),
          const SizedBox(height: 20),

          _buildSectionHeader('Primary Goal'),
          DropdownButtonFormField<String>(
            value: _goalController.value,
            hint: const Text('Select your main objective'),
            onChanged: (val) => setState(() => _goalController.value = val),
            items: _availableGoals
                .map((goal) => DropdownMenuItem(value: goal, child: Text(goal)))
                .toList(),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Workout Days'),
          MultiSelectDialogField<String>(
            items: _allWeekDays
                .map((day) => MultiSelectItem(day, day))
                .toList(),
            title: const Text("Select Workout Days"),
            selectedColor: Theme.of(context).primaryColor,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              border: Border.all(color: Colors.grey.shade600, width: 1),
            ),
            buttonText: const Text("Select days you want to work out"),
            onConfirm: (results) {
              setState(() {
                _selectedWorkoutDays = results;
              });
            },
            initialValue: _selectedWorkoutDays,
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Plan Duration (in weeks)'),
          TextFormField(
            controller: _generatePlanDurationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '8',
              hintStyle: TextStyle(color: Colors.grey),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a plan duration.';
              }
              final weeks = int.tryParse(value);
              if (weeks == null || weeks <= 0) {
                return 'Please enter a valid number of weeks.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Session Duration'),
          DropdownButtonFormField<String>(
            value: _sessionDurationController.value,
            hint: const Text('How long per session?'),
            onChanged: (val) =>
                setState(() => _sessionDurationController.value = val),
            items:
                [
                      '15-30 minutes',
                      '30-45 minutes',
                      '45-60 minutes',
                      '60+ minutes',
                    ]
                    .map(
                      (duration) => DropdownMenuItem(
                        value: duration,
                        child: Text(duration),
                      ),
                    )
                    .toList(),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            validator: (value) {
              if (value == null) {
                return 'Please select a session duration.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Activity Preferences'),
          TextFormField(
            controller: _activityPrefsController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Running, Gym, Yoga',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Intensity Level'),
          DropdownButtonFormField<String>(
            value: _intensityController.value,
            hint: const Text('Choose your preferred intensity'),
            onChanged: (val) =>
                setState(() => _intensityController.value = val),
            items: ['Light', 'Moderate', 'Vigorous']
                .map(
                  (intensity) => DropdownMenuItem(
                    value: intensity,
                    child: Text(intensity),
                  ),
                )
                .toList(),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('Additional Notes'),
          TextFormField(
            controller: _additionalNotesController,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'I prefer cardio',
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Builds the appropriate FloatingActionButton based on the current tab.
  Widget _buildFloatingActionButton() {
    bool isCustomTab = _tabController.index == 0;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.7,
      child: FloatingActionButton.extended(
        onPressed: () {
          if (isCustomTab) {
            _saveCustomPlan();
          } else {
            _generatePlanWithAI();
          }
        },
        icon: isCustomTab ? null : const Icon(Icons.auto_awesome),
        label: Text(isCustomTab ? 'Save Custom Plan' : 'Generate Plan with AI'),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}
