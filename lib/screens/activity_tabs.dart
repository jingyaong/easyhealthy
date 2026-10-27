import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import '../model/Habit.dart';
import '../utils/fitness_highlights.dart';
import '../utils/health_calculator.dart';
import '../model/Activity.dart';
import 'package:intl/intl.dart';
import '../utils/notification_scheduler.dart';
import '../utils/pdf_generator.dart';
import 'add_goals.dart';
import 'habit_details.dart';
import 'plan_workout.dart';
import 'view_plan.dart';

class ActivityTabs extends StatefulWidget {
  @override
  State<ActivityTabs> createState() => _ActivityTabsState();
  final int initialTabIndex;

  const ActivityTabs({super.key, this.initialTabIndex = 0});
}

class _ActivityTabsState extends State<ActivityTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Stream<QuerySnapshot> _workoutPlansStream;
  int _currentTabIndex = 0;
  bool _isLoading = true; // Initialize to true to show a loader initially
  int _dailyTarget = 500;
  bool _mainHabitReminderEnabled = true;

  DateTime _selectedDate = DateTime.now();
  final ScrollController _scrollController =
      ScrollController(); // Controls the day selector scroll position.
  List<DateTime> _weekDays = []; // Holds the list of dates for the selector.
  Map<String, List<Map<String, dynamic>>> _plannerActivities = {};

  List<Habit> _userHabits = [];
  List<Habit> _defaultHabits = [];

  int _totalCaloriesBurned = 0;
  int _avgCaloriesPerDay = 0;
  int _highestDayCalories = 0;
  int _totalActiveDays = 0;
  int _highestHabitStreak = 0;
  int _totalHabitStreaks = 0;

  Map<String, double> _activityBreakdown = {};

  List<Map<String, dynamic>> _loggedActivitiesToday = [];

  final List<Tab> myTabs = <Tab>[
    Tab(text: 'Overview'),
    Tab(text: 'Planner'),
    Tab(text: 'Habits'),
    Tab(text: 'Summary'),
  ];

  int? _selectedYear; // This is already nullable, which is correct
  int? _selectedMonth;
  List<int> _availableYears = [];
  Map<DateTime, List<Map<String, dynamic>>> _groupedActivitiesList = {};
  List<Map<String, dynamic>> _userActivities = [];

  List<Activity> _masterActivityList = [];
  Map<String, List<Activity>> _groupedActivities = {};
  double _userWeightKg = 70.0; // Default weight, will be fetched

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: myTabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTabIndex = _tabController.index);

      if (_tabController.index == 1 && _scrollController.hasClients) {
        _centerSelectedDay(isInitial: true);
      }
    });

    _selectedYear = DateTime.now().year;
    _selectedMonth = null;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Set up the stream to listen for workout plans for the current user
      _workoutPlansStream = FirebaseFirestore.instance
          .collection('workout_plans')
          .where('userId', isEqualTo: user.uid) // Filter by user ID
          .orderBy('createdAt', descending: true) // Show newest plans first
          .snapshots(); // Listen for real-time updates
    } else {
      // If no user is logged in, use an empty stream to avoid errors
      _workoutPlansStream = Stream.empty();
    }

    _fetchActivitiesAndUserData();
    _generateWeekDays();
  }

  void _calculateSummaryHighlights(
    List<Map<String, dynamic>> allUserActivities,
    List<Habit> userHabits,
  ) {
    // Call the static methods from the FitnessHighlights class
    _totalCaloriesBurned = FitnessHighlights.calculateTotalCaloriesBurned(
      allUserActivities,
    );
    _totalActiveDays = FitnessHighlights.calculateTotalActiveDays(
      allUserActivities,
    );
    _highestDayCalories = FitnessHighlights.calculateHighestSingleDayCalories(
      allUserActivities,
    );
    _highestHabitStreak = FitnessHighlights.calculateHighestHabitStreak(
      _userHabits,
    );
    _totalHabitStreaks = FitnessHighlights.calculateTotalHabitStreaks(
      _userHabits,
    );

    // Calculate average based on the results
    _avgCaloriesPerDay = _totalActiveDays > 0
        ? (_totalCaloriesBurned / _totalActiveDays).round()
        : 0;
  }

  void _filterAndGroupActivities() {
    if (!mounted) return;

    final allActivities =
        _userActivities;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Get all unique years from the activities to populate the dropdown
    final years = allActivities
        .map((act) => (act['date'] as Timestamp).toDate().year)
        .toSet()
        .toList();
    if (!years.contains(DateTime.now().year)) {
      years.add(DateTime.now().year);
    }
    years.sort((a, b) => b.compareTo(a)); // Sort descending

    // Filter activities by the selected year/month AND ensure they are not in the future.
    final filtered = allActivities.where((activity) {
      final date = (activity['date'] as Timestamp).toDate();
      final isBeforeOrToday = !date.isAfter(today);

      // Primary filter: Year must match and activity must be in the past/today.
      bool yearMatches = date.year == _selectedYear && isBeforeOrToday;

      // Secondary (optional) filter: If a month is selected, it must also match.
      bool monthMatches = _selectedMonth == null
          ? true
          : date.month == _selectedMonth;

      return yearMatches && monthMatches;
    }).toList();

    // Group the filtered activities by date
    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (var activity in filtered) {
      final date = (activity['date'] as Timestamp).toDate();
      final dayOnly = DateTime(date.year, date.month, date.day);
      if (grouped[dayOnly] == null) {
        grouped[dayOnly] = [];
      }
      grouped[dayOnly]!.add(activity);
    }

    // Update the state
    setState(() {
      _availableYears = years;
      _groupedActivitiesList = grouped;
    });
  }

  Widget _buildActivityHistoryList() {
    if (_groupedActivitiesList.isEmpty) {
      return const Card(
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Text(
              'No activities found for this period.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    // Sort dates from newest to oldest
    final sortedDates = _groupedActivitiesList.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final date = sortedDates[index];
        final activitiesOnDate = _groupedActivitiesList[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header Section (The separator)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                DateFormat.yMMMMEEEEd().format(
                  date,
                ), // e.g., "Saturday, November 22, 2025"
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            const Divider(height: 1),

            // Activity List Section (Seamless List)
            ...activitiesOnDate.map((activity) {
              final status = activity['displayStatus'] as String;
              Color statusColor;
              if (status == 'Completed') {
                statusColor = Colors.green;
              } else if (status == 'Missed') {
                statusColor = Colors.red;
              } else {
                statusColor = Colors.grey;
              }

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),

                title: Text(
                  activity['activityName'] as String? ?? 'Unknown Activity',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                trailing: Text(
                  status,
                  style: TextStyle(color: statusColor, fontSize: 14),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<void> _updateMainReminder(bool isEnabled) async {
    setState(() {
      _mainHabitReminderEnabled = isEnabled;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'mainHabitReminderEnabled': isEnabled},
        SetOptions(merge: true),
      ); // Use merge to not overwrite other user fields
      await NotificationScheduler().scheduleAllReminders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update reminder setting: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _mainHabitReminderEnabled = !isEnabled;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchActivitiesAndUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _loggedActivitiesToday = [];
        });
        return;
      }

      // 1. Define date boundaries for the query
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final plannerStartDate = startOfToday.subtract(const Duration(days: 15));
      final plannerEndDate = startOfToday.add(const Duration(days: 16));

      // 2. Fetch all necessary data in parallel
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance.collection('activities').get(),
        FirebaseFirestore.instance
            .collection('user_activities')
            .where('user_id', isEqualTo: user.uid)
            .where(
              'date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(plannerStartDate),
            )
            .where('date', isLessThan: Timestamp.fromDate(plannerEndDate))
            .orderBy('date', descending: true)
            .get(),
        FirebaseFirestore.instance.collection('habits').get(),
        FirebaseFirestore.instance
            .collection('user_habits')
            .where('user_id', isEqualTo: user.uid)
            .get(),
        FirebaseFirestore.instance
            .collection('user_activities')
            .where('user_id', isEqualTo: user.uid)
            .get(),
      ]);

      // 3. Process the results after all data has arrived
      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final activitiesSnapshot =
          results[1] as QuerySnapshot<Map<String, dynamic>>;
      final loggedActivitiesSnapshot =
          results[2] as QuerySnapshot<Map<String, dynamic>>;
      final defaultHabitsSnapshot =
          results[3] as QuerySnapshot<Map<String, dynamic>>;
      final userHabitsSnapshot =
          results[4] as QuerySnapshot<Map<String, dynamic>>;
      final allTimeActivitiesSnapshot =
          results[5] as QuerySnapshot<Map<String, dynamic>>;

      // Process user data from the userDoc
      final userData = userDoc.data() ?? {};
      _userWeightKg =
          (userData['weight'] as num?)?.toDouble() ?? 70.0; // Default weight

      final double bmi = HealthCalculator.calculateBMI(
        _userWeightKg,
        (userData['height'] as num?)?.toDouble() ?? 170.0,
      );

      _defaultHabits = defaultHabitsSnapshot.docs
          .map((doc) => Habit.fromMap(doc.data(), doc.id))
          .toList();

      _userHabits = userHabitsSnapshot.docs.map((userHabitDoc) {
        final userHabitData = userHabitDoc.data();
        final String baseHabitId = userHabitData['habitId'] ?? '';

        // Find the original habit definition from the master list using the habitId.
        final Habit baseHabit = _defaultHabits.firstWhere(
          (h) => h.id == baseHabitId,
          // If the original habit is not found (e.g., deleted), create a fallback.
          orElse: () => Habit(
            id: '',
            name: userHabitData['name'] ?? 'Unknown Habit',
            icon: userHabitData['icon'] ?? '❓',
            description: '',
            reminderTime: null,
            category: 'Unknown',
            isDefault: false,
          ),
        );

        // Create a new, complete Habit object by merging the data from both sources.
        return Habit(
          // --- Data from the original habit definition ---
          name: baseHabit.name,
          icon: baseHabit.icon,
          description: baseHabit.description,
          category: baseHabit.category,
          isDefault: baseHabit.isDefault,
          id: baseHabitId,
          reminderEnabled: userHabitData['reminderEnabled'],
          reminderTime: userHabitData['reminderTime'],
          currentStreak: userHabitData['currentStreak'] ?? 0,
          longestStreak: userHabitData['longestStreak'] ?? 0,
          lastCompletedDate: (userHabitData['lastCompletedDate'] as Timestamp?)
              ?.toDate(),
        );
      }).toList();

      _userActivities = allTimeActivitiesSnapshot.docs.map((doc) {
        final systemActivities = activitiesSnapshot.docs
            .map((doc) => Activity.fromFirestore(doc))
            .toList();
        _masterActivityList = systemActivities;

        final data = doc.data();
        final activityId = data['activity_id'] as String?;
        final activityDate = (data['date'] as Timestamp).toDate();

        // Find the corresponding activity in the master list to get its name
        final masterActivity = _masterActivityList.firstWhere(
          (act) => act.id == activityId,
          // Provide a fallback if the activity is not found
          orElse: () => Activity(
            id: '',
            name: 'Unknown Activity',
            met: 0,
            category: 'Unknown',
            icon: '❓',
          ),
        );

        // Dynamically determine the display status
        String displayStatus = data['status'] as String? ?? 'Completed';
        if (displayStatus == 'Planned' && activityDate.isBefore(startOfToday)) {
          displayStatus = 'Missed';
        }

        // Return a new map that includes all necessary data
        return {
          ...data,
          'activityName': masterActivity.name,
          'displayStatus': displayStatus, // Use this new field for the UI
        };
      }).toList();

      final newDailyTarget =
          (userData['daily_burn_goal'] as num?)?.toInt() ?? 500;

      // Process master list of system activities
      final systemActivities = activitiesSnapshot.docs
          .map((doc) => Activity.fromFirestore(doc))
          .toList();
      final grouped = <String, List<Activity>>{};
      for (var activity in systemActivities) {
        (grouped[activity.category] ??= []).add(activity);
      }

      // Process today's logs
      final allFetchedActivities = loggedActivitiesSnapshot.docs.map((doc) {
        final data = doc.data();
        String activityTitle;
        IconData activityIcon;

        if (data['custom_name'] != null) {
          activityTitle = data['custom_name'];
          activityIcon = Icons.edit;
        } else if (data['activity_id'] != null) {
          final activityId = data['activity_id'];
          final activity = systemActivities.firstWhere(
            (act) => act.id == activityId,
            orElse: () => Activity(
              id: '',
              name: 'Logged Activity',
              category: '',
              met: 0,
              icon: '',
            ),
          );

          activityTitle = activity.name;

          switch (activity.category.toLowerCase()) {
            case 'cardio':
              activityIcon = Icons.directions_run; // Icon for Cardio
              break;
            case 'strength':
              activityIcon = Icons.fitness_center; // Icon for Strength
              break;
            case 'flexibility':
              activityIcon = Icons.self_improvement; // Icon for Flexibility
              break;
            default:
              activityIcon = Icons.task_alt; // A fallback icon
          }
        } else {
          activityTitle = 'Unknown Activity';
          activityIcon = Icons.help_outline;
        }
        return {
          'id': doc.id,
          'icon': activityIcon,
          'title': activityTitle,
          'subtitle': '${data['calories_burned']} calories',
          'color': const Color(0xFF2196F3),
          'calories_burned': data['calories_burned'] ?? 0,
          'duration_minutes': (data['duration_minutes'] as num?)?.toInt() ?? 0,
          'notes': data['notes'] as String?,
          'date': (data['date'] as Timestamp).toDate(),
          'last_updated_at': data['last_updated_at'],
          'status': data['status'] as String? ?? 'Completed',
        };
      }).toList();

      final activityBreakdown = {
        'Cardio': 0.0,
        'Strength': 0.0,
        'Flexibility': 0.0,
        'Other': 0.0,
      };

      for (final doc in allTimeActivitiesSnapshot.docs) {
        final loggedActivityData = doc.data();

        // Only count activities that are 'Completed'.
        final status = loggedActivityData['status'] as String? ?? 'Completed';
        if (status != 'Completed') {
          continue; // Skip activities that are not completed.
        }

        final activityId = loggedActivityData['activity_id'] as String?;

        if (activityId != null) {
          // Find the original system activity to get its category.
          final systemActivity = systemActivities.firstWhere(
            (act) => act.id == activityId,
            // If the base activity was deleted, default its category to 'Other'.
            orElse: () =>
                Activity(id: '', name: '', category: 'Other', met: 0, icon: ''),
          );

          final category = systemActivity.category;

          // Increment the count for the determined category.
          if (activityBreakdown.containsKey(category)) {
            activityBreakdown[category] = activityBreakdown[category]! + 1;
          } else {
            // If the category is something unexpected, group it into 'Other'.
            activityBreakdown['Other'] = activityBreakdown['Other']! + 1;
          }
        } else {
          // If the log is for a custom activity (no activity_id), count it as 'Other'.
          activityBreakdown['Other'] = activityBreakdown['Other']! + 1;
        }
      }

      final newPlannerActivities = <String, List<Map<String, dynamic>>>{};
      for (final activity in allFetchedActivities) {
        final dateKey = DateFormat(
          'yyyy-MM-dd',
        ).format(activity['date'] as DateTime);
        (newPlannerActivities[dateKey] ??= []).add(activity);
      }

      final mainHabitReminderEnabled =
          (userData?['mainHabitReminderEnabled'] as bool?) ?? true;
      final todaysCompletedLogs = allFetchedActivities
          .where(
            (act) =>
                DateUtils.isSameDay(act['date'] as DateTime?, now) &&
                act['status'] == 'Completed',
          )
          .toList();

      _calculateSummaryHighlights(
        allTimeActivitiesSnapshot.docs.map((doc) => doc.data()).toList(),
        _userHabits,
      );

      // 5. Call setState ONCE with all the final, correct data
      if (mounted) {
        setState(() {
          _masterActivityList = systemActivities;
          _groupedActivities = grouped;
          _loggedActivitiesToday = todaysCompletedLogs;
          _plannerActivities = newPlannerActivities;
          _dailyTarget = newDailyTarget;
          _userHabits = _userHabits;
          _isLoading = false;
          _mainHabitReminderEnabled = mainHabitReminderEnabled;
          _activityBreakdown = activityBreakdown;
        });
        _filterAndGroupActivities();
      }

      await NotificationScheduler().scheduleAllReminders();
    } catch (e) {
      if (!mounted) return;
      print('Failed to load activity data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load activity data: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteActivityFromFirestore(String userActivityId) async {
    try {
      await FirebaseFirestore.instance
          .collection('user_activities')
          .doc(userActivityId)
          .delete();

      // Show a confirmation snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Activity removed successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Refresh the data to update the UI
      _fetchActivitiesAndUserData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildWorkoutPlansList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _workoutPlansStream,
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // Handle error state
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading plans.'));
        }
        // Handle no data state
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: Text(
                'You have no saved plans.\nCreate one to get started!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final plans = snapshot.data!.docs;
        return ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount: plans.length,
          itemBuilder: (context, index) {
            final plan = plans[index].data() as Map<String, dynamic>;
            final planName = plan['planName'] ?? 'Unnamed Plan';
            final createdDate = (plan['createdAt'] as Timestamp?)?.toDate();
            final planType = plan['planType'] ?? 'Custom';
            IconData typeIcon = planType == 'Generated'
                ? Icons.auto_awesome
                : Icons.edit;

            return Card(
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: Icon(typeIcon, color: Color(0xFF2196F3)),
                title: Text(
                  planName + ' ($planType Plan)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  createdDate != null
                      ? 'Started on ${DateFormat.yMMMMd().format(createdDate)}'
                      : 'No date',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final String planId = plans[index].id;
                  final Map<String, dynamic> planDataWithId =
                      Map<String, dynamic>.from(plan);
                  planDataWithId['documentId'] = planId;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          PlanDetailsPage(planData: planDataWithId),
                    ),
                  );
                  _fetchActivitiesAndUserData();
                },
              ),
            );
          },
        );
      },
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) {
      return Colors.green; // Goal met or exceeded
    }
    if (progress >= 0.8) {
      return const Color(0xFF2196F3); // Nearing goal (standard blue)
    }
    if (progress >= 0.4) {
      return Colors.orange; // Good progress
    }
    return Colors.red.shade400; // Just starting
  }

  void _openAddActivityDialog() async {
    String? selectedCategory;
    Activity? selectedActivity;
    final durationController = TextEditingController();
    final customNameController = TextEditingController();
    final notesController = TextEditingController();
    String? intensity = null;

    const intensityMetMap = {
      'Low': 4.0,
      'Medium': 6.0,
      'High': 8.0,
      'Very High': 10.0,
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final _formKey = GlobalKey<FormState>();
            final categories = [..._groupedActivities.keys, 'Custom'];
            final isCustom = selectedCategory == 'Custom';

            final activitiesForCategory =
                (selectedCategory != null && !isCustom)
                ? _groupedActivities[selectedCategory]
                : null;

            return AlertDialog(
              title: const Text('Log Activity'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        hint: const Text('Select category'),
                        items: categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCategory = value;
                            selectedActivity =
                                null; // Reset activity on category change
                          });
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null) {
                            return 'Please select a category.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      if (isCustom) ...[
                        TextFormField(
                          controller: customNameController,
                          decoration: const InputDecoration(
                            labelText: 'Activity Name',
                            border: OutlineInputBorder(),
                            labelStyle: TextStyle(color: Colors.grey),
                          ),
                          validator: (value) {
                            if (isCustom) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter activity name.';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: intensity,
                          hint: const Text(
                            'Select Intensity',
                          ),
                          items: intensityMetMap.keys
                              .map(
                                (i) =>
                                    DropdownMenuItem(value: i, child: Text(i)),
                              )
                              .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value != null) intensity = value;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (isCustom) {
                              if (value == null) {
                                return 'Please select an intensity.';
                              }
                            }
                            return null;
                          },
                        ),
                      ] else if (selectedCategory != null) ...[
                        // SYSTEM ACTIVITY FIELDS
                        if (activitiesForCategory != null)
                          DropdownButtonFormField<Activity>(
                            isExpanded: true,
                            value: selectedActivity,
                            hint: const Text('Select activity'),
                            items: activitiesForCategory
                                .map(
                                  (a) => DropdownMenuItem(
                                    value: a,
                                    child: Text(
                                      a.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setDialogState(() => selectedActivity = value);
                            },
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null) {
                                return 'Please select an activity.';
                              }
                              return null;
                            },
                          ),
                      ] else ...[
                        const SizedBox(
                          height: 60,
                          child: AbsorbPointer(
                            child: TextField(
                              enabled: false,
                              decoration: InputDecoration(
                                labelText: 'Select activity',
                                border: OutlineInputBorder(),
                                labelStyle: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      TextFormField(
                        controller: durationController,
                        decoration: const InputDecoration(
                          labelText: 'Duration (minutes)',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(color: Colors.grey),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a duration.';
                          }
                          final duration = int.tryParse(value);
                          if (duration == null) {
                            return 'Please enter a valid number.';
                          }
                          if (duration <= 0) {
                            return 'Duration must be greater than 0.';
                          }
                          return null; // Return null if input is valid
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(color: Colors.grey),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(ctx, {
                        'isCustom': isCustom,
                        'activity': isCustom ? null : selectedActivity,
                        'customName': isCustom
                            ? customNameController.text
                            : null,
                        'intensity': isCustom ? intensity : null,
                        'met': isCustom
                            ? intensityMetMap[intensity!]
                            : selectedActivity!.met,
                        'duration': int.parse(
                          durationController.text,
                        ),
                        'notes': notesController.text,
                        'status': 'completed',
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return; // User cancelled

    final int duration = result['duration'];
    if (duration > 0) {
      final double metValue = result['met'];
      final int caloriesBurned = HealthCalculator.calculateCaloriesBurned(
        met: metValue,
        userWeightKg: _userWeightKg,
        durationMinutes: duration,
      );
      final bool isCustom = result['isCustom'];
      final String displayName = isCustom
          ? result['customName']
          : result['activity'].name;
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      // Prepare data for Firestore
      final logData = {
        'user_id': user.uid,
        'activity_id': isCustom ? null : result['activity'].id,
        'custom_name': isCustom ? result['customName'] : null,
        'duration_minutes': duration,
        'calories_burned': caloriesBurned.toInt(),
        'date': Timestamp.now(),
        'status': 'Completed',
        'notes': result['notes'],
        'created_at': FieldValue.serverTimestamp(),
      };

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('user_activities')
          .add(logData);
      await _fetchActivitiesAndUserData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged "$displayName" for $duration minutes!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _generateAndSavePdf() async {
    if (_selectedYear == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a year first to generate a report.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show a loading indicator
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Generating PDF...')));

    try {
      // 1. Generate the PDF bytes using the utility class
      final pdfBytes = await PdfGenerator.generateActivityPdf(
        year: _selectedYear,
        month: _selectedMonth,
        groupedActivities: _groupedActivitiesList,

        // Activity Summary
        totalCalories: _totalCaloriesBurned,
        avgCalories: _avgCaloriesPerDay,
        highestCalories: _highestDayCalories,
        totalActiveDays: _totalActiveDays,

        // Habit Summary
        highestHabitStreak: _highestHabitStreak,
        totalHabitStreaks: _totalHabitStreaks,

        // Activity Breakdown
        activityBreakdown: _activityBreakdown,
      );

      // 2. Use the 'printing' package to save the PDF
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Fitness_Summary_Report_${_selectedYear}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _generateWeekDays() {
    _weekDays.clear();
    // Generate a wide range of dates to allow for scrolling (e.g., 30 days centered around today).
    final today = DateTime.now();
    for (int i = -15; i <= 15; i++) {
      _weekDays.add(today.add(Duration(days: i)));
    }
  }

  void _centerSelectedDay({bool isInitial = false}) {
    if (!_scrollController.hasClients) return;
    final selectedDayIndex = _weekDays.indexWhere(
      (date) => DateUtils.isSameDay(date, _selectedDate),
    );
    if (selectedDayIndex != -1) {
      final screenWidth = MediaQuery.of(context).size.width;

      const double itemWidth = 70.0;
      // Calculate the offset to center the item.
      final double scrollOffset =
          (selectedDayIndex * itemWidth) - (2 * itemWidth);

      if (isInitial) {
        // Jump directly without animation on initial load.
        _scrollController.jumpTo(
          scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        );
      } else {
        // Animate to the new position.
        _scrollController.animateTo(
          scrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  // Helper to build a single day item in the scrollable list
  Widget _buildDayItem(DateTime date) {
    final bool isSelected = DateUtils.isSameDay(date, _selectedDate);
    final isToday = DateUtils.isSameDay(date, DateTime.now());

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDate = date;
        });
        _centerSelectedDay(); // Center the newly selected day.
      },
      child: Container(
        width: 60,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : const Color(0xFFF0F4FB),
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected
              ? Border.all(color: const Color(0xFF2196F3), width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('E').format(date).substring(0, 3), // e.g., "Wed"
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white : Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('d').format(date), // e.g., "12"
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to build the activity list based on the selected date
  Widget _buildActivityListForSelectedDate() {
    final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final activitiesToShow = _plannerActivities[dateKey] ?? [];

    if (activitiesToShow.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(40.0),
        child: Center(
          child: Text(
            "No activities scheduled for this day.",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    // Define styles for different statuses.
    final statusStyles = {
      'Completed': {'color': Colors.green, 'icon': Icons.check_circle},
      'Missed': {'color': Colors.red, 'icon': Icons.cancel},
      'Planned': {'color': Colors.orange, 'icon': Icons.watch_later_outlined},
    };

    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: activitiesToShow.length,
      itemBuilder: (context, index) {
        final activity = activitiesToShow[index];
        final activityDate = DateTime(
          (activity['date'] as DateTime).year,
          (activity['date'] as DateTime).month,
          (activity['date'] as DateTime).day,
        );
        String status = activity['status'] as String? ?? 'completed';
        if (status.toLowerCase() == 'planned' && activityDate.isBefore(today)) {
          status = 'Missed';
        }
        status = status[0].toUpperCase() + status.substring(1).toLowerCase();
        // 3. Use a safe lookup with a fallback style to prevent crashes
        final style = statusStyles[status] ?? statusStyles['Planned']!;

        return Card(
          elevation: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: Icon(
              activity['icon'] as IconData,
              color: style['color'] as Color,
            ),
            title: Text(
              activity['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  style['icon'] as IconData,
                  color: style['color'] as Color,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(status, style: TextStyle(color: style['color'] as Color)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double totalCaloriesToday = _loggedActivitiesToday
        .map(
          (activity) =>
              (activity['calories_burned'] as num?)?.toDouble() ?? 0.0,
        )
        .fold(0.0, (sum, calories) => sum + calories);

    final double progress =
        (_dailyTarget > 0 ? totalCaloriesToday / _dailyTarget : 0.0).clamp(
          0.0,
          1.0,
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activities'),
        bottom: TabBar(controller: _tabController, tabs: myTabs),
        centerTitle: true,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Overview tab
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            children: [
              // Daily goal progress
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Goal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          color: _getProgressColor(progress),
                          backgroundColor: const Color(0xFFF0F4FB),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${totalCaloriesToday.toInt()} / $_dailyTarget calories burned',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Today\'s activity',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),

              const SizedBox(height: 4),
              if (_loggedActivitiesToday.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      "You haven't logged any activities today.\nPress the button below to add one!",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _loggedActivitiesToday.length,
                  itemBuilder: (context, index) {
                    final activity = _loggedActivitiesToday[index];
                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: Icon(
                          activity['icon'] as IconData,
                          color: const Color(0xFF2196F3),
                          size: 24,
                        ),
                        title: Text(
                          activity['title'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          activity['subtitle'] as String,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                _showActivityDetailsDialog(activity);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                side: BorderSide(color: Color(0xFF2196F3)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'View',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            // DELETE BUTTON
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(4),
                              onPressed: () {
                                _confirmDeleteActivity(
                                  activity['id'] as String,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 80),
            ],
          ),

          // Planner tab
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            children: [
              SizedBox(
                height: 70,
                child: ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: _weekDays.length,
                  itemBuilder: (context, index) {
                    return _buildDayItem(_weekDays[index]);
                  },
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Activities for ${DateFormat.yMMMMd().format(_selectedDate)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),

              _buildActivityListForSelectedDate(),
              const SizedBox(height: 16),
              const Text(
                'Plan Your Fitness Journey',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),

              _goalOption(
                icon: Icons.flag_outlined,
                title: 'Set Goals',
                subtitle:
                    'Set daily or weekly workout goals to stay motivated.',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const GoalsPage()),
                  );
                },
              ),
              _goalOption(
                icon: Icons.playlist_add_check_outlined,
                title: 'Create Workout Plan',
                subtitle: 'Build a personalized plan that fits your routine.',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const WorkoutPlanPage(),
                    ),
                  );
                  _fetchActivitiesAndUserData();
                },
              ),

              const SizedBox(height: 16),
              const Text(
                'Current plan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              _buildWorkoutPlansList(),
              const SizedBox(height: 40),
            ],
          ),

          // Habits
          _buildHabitsTab(),

          // Summary
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            children: [
              // Header row with Share button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Summary Report',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Download History as PDF',
                    onPressed: () {
                      _generateAndSavePdf();
                    },
                  ),
                ],
              ),

              // Key Metrics-like Highlights
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Highlights',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.local_fire_department_outlined,
                      title: 'Total Burned',
                      value: '${_totalCaloriesBurned} kcal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.trending_up_outlined,
                      title: 'Avg Burn/Day',
                      value: '${_avgCaloriesPerDay} kcal',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.whatshot_outlined,
                      title: 'Highest Single Day',
                      value: '${_highestDayCalories} kcal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.star_border_rounded,
                      title: 'Longest Habit Streak',
                      value: '${_highestHabitStreak} days',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.calendar_month_outlined,
                      title: 'Total Active Days',
                      value: '$_totalActiveDays',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _highlightCard(
                      icon: Icons.repeat_rounded,
                      title: 'Total Habit Streaks',
                      value: '$_totalHabitStreaks',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'Activity Breakdown',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  // Calculate the total from the breakdown data
                  Text(
                    'Total: ${_activityBreakdown.values.fold(0, (sum, count) => sum + count.toInt())}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Donut chart with percentage labels INSIDE
                      Expanded(
                        flex: 1,
                        child: SizedBox(
                          height: 200,
                          child: _PieChart(
                            data: _activityBreakdown,
                            showPercentageLabels: true,
                          ),
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Legend with color + name + count (no percent)
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _activityBreakdown.entries.map((e) {
                            final color = _PieChart.getColorForKey(e.key);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${e.key} - ${e.value.toInt()} workouts',
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Activity History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),

              // Filter Dropdowns
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      // Year Dropdown
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedYear,
                          hint: const Text('Select Year'), // Show a hint text
                          decoration: const InputDecoration(
                            labelText: 'Year',
                            border: InputBorder.none,
                          ),
                          items: _availableYears.map((year) {
                            return DropdownMenuItem(
                              value: year,
                              child: Text(year.toString()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedYear = value;
                                // Reset the month selection to show the whole year by default
                                _selectedMonth = null;
                              });
                              _filterAndGroupActivities();
                            }
                          },
                        ),
                      ),
                      // Conditionally show the month dropdown only if a year is selected
                      if (_selectedYear != null) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedMonth,
                            hint: const Text(
                              'All Months',
                            ), // Show hint when no month is selected
                            decoration: InputDecoration(
                              labelText: 'Month',
                              border: InputBorder.none,
                              // Add a clear button to reset the month filter
                              suffixIcon: _selectedMonth != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 20),
                                      onPressed: () {
                                        setState(() => _selectedMonth = null);
                                        _filterAndGroupActivities();
                                      },
                                    )
                                  : null,
                            ),
                            items: List.generate(12, (index) {
                              return DropdownMenuItem(
                                value: index + 1,
                                child: Text(
                                  DateFormat(
                                    'MMMM',
                                  ).format(DateTime(0, index + 1)),
                                ),
                              );
                            }),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedMonth = value);
                                _filterAndGroupActivities();
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Activity List
              _buildActivityHistoryList(),

              const SizedBox(height: 15),
            ],
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _highlightCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return SizedBox(
      height: 130,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 26, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalOption({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Color(0xFF2196F3)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  Widget? _buildFab() {
    if (_currentTabIndex == 2) {
      return FloatingActionButton.extended(
        heroTag: 'fab-habit',
        onPressed: _openCreateHabitDialog,
        backgroundColor: const Color(0xFF2196F3),
        icon: const Icon(Icons.add),
        label: const Text('Create Habit'),
      );
    }
    if (_currentTabIndex == 0) {
      return FloatingActionButton.extended(
        heroTag: 'fab-activity',
        onPressed: _openAddActivityDialog,
        backgroundColor: const Color(0xFF2196F3),
        icon: const Icon(Icons.add),
        label: const Text('Log Activity'),
      );
    }
    return null; // hide on Planner (1) and Summary (3)
  }

  Future<void> _addUserHabit(Habit habit, {TimeOfDay? reminderTime}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final newUserHabitData = {
        'user_id': user.uid,
        'habitId': habit.id,
        'reminderEnabled': reminderTime != null,
        'reminderTime': reminderTime != null
            ? '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}'
            : null,
        'currentStreak': 0, // Always starts at 0
        'longestStreak': 0, // Always starts at 0
        'lastCompletedDate': null, // No completion date when first added
        'createdAt':
            FieldValue.serverTimestamp(), // Track when the user added this habit
      };

      await FirebaseFirestore.instance
          .collection('user_habits')
          .add(newUserHabitData);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Habit "${habit.name}" added!'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchActivitiesAndUserData(); // Refresh the data to show the new habit
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add habit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openCreateCustomHabitDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final iconController = TextEditingController(text: '🎯');

    TimeOfDay? selectedTime;
    bool enableReminder = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Use a StatefulBuilder to manage the state of the switch and time picker
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final _formKey = GlobalKey<FormState>();
            return AlertDialog(
              title: const Text('Create Custom Habit'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Habit Name',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a habit name.';
                          }
                          return null;
                        },
                      ),
                      TextFormField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description (optional)',
                        ),
                      ),
                      TextFormField(
                        controller: iconController,
                        decoration: const InputDecoration(labelText: 'Icon'),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter an icon.';
                          }
                          return null;
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Enable Daily Reminder?',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Switch(
                            value: enableReminder,
                            onChanged: (value) {
                              setDialogState(() {
                                enableReminder = value;
                                if (!enableReminder) {
                                  selectedTime = null;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (enableReminder)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.alarm),
                          title: Text(
                            selectedTime?.format(context) ?? 'Select a time',
                          ),
                          onTap: () async {
                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: selectedTime ?? TimeOfDay.now(),
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
                            if (pickedTime != null) {
                              setDialogState(() {
                                selectedTime = pickedTime;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      try {
                        final newHabitDocRef = FirebaseFirestore.instance
                            .collection('habits')
                            .doc();
                        // 1. Save the new habit definition to the main `habits` collection.
                        final habitDefinition = {
                          'id': newHabitDocRef.id,
                          'name': nameController.text,
                          'description': descriptionController.text,
                          'icon': iconController.text,
                          'category': 'Custom',
                          'isDefault': false,
                          'createdAt': FieldValue.serverTimestamp(),
                        };

                        // 2. Create the Habit object with the new ID.
                        final newHabitForUser = Habit(
                          id: newHabitDocRef.id,
                          name: nameController.text,
                          description: descriptionController.text,
                          icon: iconController.text,
                          category: 'Custom',
                          isDefault: false,
                        );

                        await newHabitDocRef.set(habitDefinition);

                        // 3. Call _addUserHabit directly with the new habit and the selected reminder time.
                        _addUserHabit(
                          newHabitForUser,
                          reminderTime: selectedTime,
                        );

                        if (!mounted) return;
                        Navigator.of(context).pop(); // Close the dialog
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not save custom habit: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Create Habit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openSystemHabitDialog(Habit habit) {
    TimeOfDay? parseReminderTime(String? timeString) {
      if (timeString == null || !timeString.contains(':')) return null;
      try {
        final parts = timeString.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      } catch (e) {
        // Return null if parsing fails for any reason
        return null;
      }
    }

    // Use the parsing function to initialize the variables
    TimeOfDay? selectedTime = parseReminderTime(habit.reminderTime);
    bool enableReminder = selectedTime != null;

    showDialog(
      context: context,
      // Use StatefulBuilder to manage the state of the switch and time picker inside the dialog
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(habit.name),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (habit.description.isNotEmpty) ...[
                      Text(
                        habit.description,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const Divider(height: 24),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Enable Daily Reminder?',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: enableReminder,
                          onChanged: (value) {
                            setDialogState(() {
                              enableReminder = value;
                              // If user disables reminder, clear the time
                              if (!enableReminder) {
                                selectedTime = null;
                              } else {
                                // If they enable it, set it back to the default
                                selectedTime = parseReminderTime(
                                  habit.reminderTime,
                                );
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    // Conditionally show the time input field
                    if (enableReminder)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.alarm),
                        title: Text(
                          selectedTime?.format(context) ?? 'Select a time',
                        ),
                        onTap: () async {
                          final TimeOfDay? pickedTime = await showTimePicker(
                            context: context,
                            initialTime: selectedTime ?? TimeOfDay.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  timePickerTheme: Theme.of(context)
                                      .timePickerTheme
                                      .copyWith(
                                        dayPeriodColor: Color(0xFF2196F3),
                                      ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (pickedTime != null) {
                            setDialogState(() {
                              selectedTime = pickedTime;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Pass the habit and the selected time to the add method
                    _addUserHabit(habit, reminderTime: selectedTime);
                    Navigator.of(context).pop(); // Close this dialog
                  },
                  child: const Text('Start Habit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _navigateToHabitDetails(Habit habit) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HabitDetailsPage(
          habit: habit,
          onDelete: _deleteHabit,
          onToggleCompletion: _toggleHabitCompletion,
        ),
      ),
    );
    _fetchActivitiesAndUserData();
    await NotificationScheduler().scheduleAllReminders();
  }

  Future<void> _deleteHabit(Habit habit) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("No user logged in.");
      }

      // 1. Query the 'user_habits' collection to find the specific document
      final querySnapshot = await FirebaseFirestore.instance
          .collection('user_habits')
          .where('user_id', isEqualTo: user.uid)
          .where('habitId', isEqualTo: habit.id)
          .limit(1)
          .get();

      // 2. Check if the document was found and delete it.
      if (querySnapshot.docs.isNotEmpty) {
        await querySnapshot.docs.first.reference.delete();
      } else {
        print("User habit to delete was not found in Firestore.");
      }

      // 3. If the habit is a custom habit, also delete it from the base 'habits' collection.
      if (!habit.isDefault) {
        await FirebaseFirestore.instance
            .collection('habits')
            .doc(habit.id)
            .delete();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Habit "${habit.name}" deleted.'),
          backgroundColor: Colors.green,
        ),
      );

      setState(() {
        _userHabits.removeWhere((h) => h.id == habit.id);
      });
      await NotificationScheduler().scheduleAllReminders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete habit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleHabitCompletion(
    Habit habit,
    bool isCompletedToday,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("No user logged in.");
      }

      final querySnapshot = await FirebaseFirestore.instance
          .collection('user_habits')
          .where('user_id', isEqualTo: user.uid)
          .where('habitId', isEqualTo: habit.id)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception("Could not find the habit to update for this user.");
      }

      final userHabitRef = querySnapshot.docs.first.reference;
      final docData = querySnapshot.docs.first.data();

      final Timestamp? previousDateTS = docData['previousCompletedDate'];
      final DateTime? previousCompletedDate = previousDateTS != null
          ? previousDateTS.toDate()
          : null;

      Map<String, dynamic> updates = {};

      if (isCompletedToday) {
        // Undo only reduces streak by 1 if streak > 0
        final newStreak = habit.currentStreak > 0 ? habit.currentStreak - 1 : 0;

        updates['currentStreak'] = newStreak;

        // Restore the previous date instead of nullifying
        updates['lastCompletedDate'] = previousCompletedDate != null
            ? Timestamp.fromDate(previousCompletedDate)
            : null;

        // Clear the previous date
        updates['previousCompletedDate'] = null;
      } else {
        final now = DateTime.now();

        bool isConsecutive = false;
        if (habit.lastCompletedDate != null) {
          final last = habit.lastCompletedDate!;
          final yesterday = DateTime(now.year, now.month, now.day - 1);

          if (last.year == yesterday.year &&
              last.month == yesterday.month &&
              last.day == yesterday.day) {
            isConsecutive = true;
          }
        }

        final int newStreak = isConsecutive ? habit.currentStreak + 1 : 1;

        // Save current lastCompletedDate before overwriting
        updates['previousCompletedDate'] = habit.lastCompletedDate != null
            ? Timestamp.fromDate(habit.lastCompletedDate!)
            : null;

        updates['currentStreak'] = newStreak;
        updates['lastCompletedDate'] = Timestamp.now();

        if (newStreak > habit.longestStreak) {
          updates['longestStreak'] = newStreak;
        }
      }

      await userHabitRef.update(updates);

      await _fetchActivitiesAndUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCompletedToday
                  ? 'Completion undone for "${habit.name}"'
                  : 'Great job on completing "${habit.name}"!',
            ),
            backgroundColor: isCompletedToday ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating habit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _getDisplayStreakInfo(Habit habit) {
    // A streak is considered broken if it was not completed yesterday or today.
    bool isStreakActive = false;
    final DateTime? lastCompletion = habit.lastCompletedDate;

    if (lastCompletion != null) {
      final now = DateTime.now();
      // Normalize dates to ignore time of day
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final lastCompletionDay = DateTime(
        lastCompletion.year,
        lastCompletion.month,
        lastCompletion.day,
      );

      // The streak is active if the last completion was today or yesterday
      if (lastCompletionDay == today || lastCompletionDay == yesterday) {
        isStreakActive = true;
      }
    }

    // If the streak is not active, display 0. Otherwise, show the real streak.
    final int displayStreak = isStreakActive ? habit.currentStreak : 0;

    return {
      'streak': displayStreak,
      'isActive': isStreakActive && displayStreak > 0,
    };
  }

  void _openCreateHabitDialog() {
    // Get a list of habit names the user already has to prevent adding duplicates
    final existingHabitNames = _userHabits.map((h) => h.name).toSet();

    // Filter out default habits that the user has already added
    final availableDefaultHabits = _defaultHabits
        .where((h) => !existingHabitNames.contains(h.name))
        .toList();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: const Text('Start a New Habit'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Button to create a completely new custom habit
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Create a Custom Habit'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the first dialog
                    _openCreateCustomHabitDialog();
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(height: 20),
                const Text(
                  'Or select a pre-defined habit:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (availableDefaultHabits.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('You have added all available default habits!'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: availableDefaultHabits.length,
                      itemBuilder: (context, index) {
                        final habit = availableDefaultHabits[index];
                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            side: isDarkMode
                                ? BorderSide(
                                    color: Colors.grey.shade700,
                                    width: 1,
                                  )
                                : BorderSide.none,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade200,
                              child: Text(
                                habit.icon,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                            title: Text(habit.name),
                            onTap: () {
                              Navigator.of(context).pop();
                              _openSystemHabitDialog(habit);
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showActivityDetailsDialog(Map<String, dynamic> activity) {
    // Controller for the editable duration
    final durationController = TextEditingController(
      text: activity['duration_minutes'].toString(),
    );
    final notesController = TextEditingController(
      text: activity['notes'] as String? ?? '',
    );
    bool hasChanges = false;

    showDialog(
      context: context,
      builder: (ctx) {
        final _formKey = GlobalKey<FormState>();

        return StatefulBuilder(
          // Use StatefulBuilder to manage state inside the dialog
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(activity['icon'] as IconData, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(child: Text(activity['title'] as String)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,

                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(activity['calories_burned'] as num).toInt()} calories burned',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: durationController,
                              keyboardType: TextInputType.number,
                              maxLines: 1,
                              textAlignVertical: TextAlignVertical.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                suffixIcon: Icon(
                                  Icons.edit_outlined,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              ),

                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a duration.';
                                }
                                final duration = int.tryParse(value);
                                if (duration == null) {
                                  return 'Please enter a valid number.';
                                }
                                if (duration <= 0) {
                                  return 'Duration must be greater than 0.';
                                }
                                return null; // Return null if valid
                              },

                              onChanged: (value) {
                                setDialogState(() {
                                  hasChanges =
                                      value !=
                                          activity['duration_minutes']
                                              .toString() ||
                                      notesController.text !=
                                          (activity['notes'] as String? ?? '');
                                });
                              },
                            ),
                          ),
                        ],
                      ),

                      if (activity['notes'] != null &&
                          (activity['notes'] as String).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.notes_outlined,
                              color: Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: notesController,
                                maxLines: null,
                                textAlignVertical: TextAlignVertical.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  suffixIcon: Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                onChanged: (value) {
                                  setDialogState(() {
                                    hasChanges =
                                        durationController.text !=
                                            activity['duration_minutes']
                                                .toString() ||
                                        value !=
                                            (activity['notes'] as String? ??
                                                '');
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat.jm().format(
                                  activity['date'] as DateTime,
                                ),
                              ),
                              if (activity['last_updated_at'] != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '(edited ${DateFormat.jm().format((activity['last_updated_at'] as Timestamp).toDate())})',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),

                ElevatedButton(
                  onPressed: hasChanges
                      ? () {
                          if (_formKey.currentState!.validate()) {
                            // If valid, pop with the results
                            Navigator.of(ctx).pop({
                              'newDuration': int.parse(durationController.text),
                              'newNotes': notesController.text,
                            });
                          }
                        }
                      : null, // Button is disabled if there are no changes
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    ).then((result) {
      if (result != null && result is Map<String, dynamic>) {
        final newDuration = result['newDuration'] as int;
        final newNotes = result['newNotes'] as String;
        _updateActivity(activity['id'] as String, newDuration, newNotes);
      }
    });
  }

  Future<double> _getMetForActivity(String userActivityId) async {
    final doc = await FirebaseFirestore.instance
        .collection('user_activities')
        .doc(userActivityId)
        .get();
    final data = doc.data();

    if (data == null) return 4.0; // Default MET if something goes wrong

    if (data['activity_id'] != null) {
      // It's a system activity, find its MET value in the master list
      final activity = _masterActivityList.firstWhere(
        (act) => act.id == data['activity_id'],
        orElse: () =>
            Activity(id: '', name: '', category: '', met: 4.0, icon: ''),
      );
      return activity.met;
    } else {
      final originalCalories =
          (data['calories_burned'] as num?)?.toDouble() ?? 0.0;
      final originalDuration =
          (data['duration_minutes'] as num?)?.toDouble() ?? 1.0;
      if (originalDuration > 0) {
        return (originalCalories * 200) /
            (3.5 * _userWeightKg * originalDuration);
      }
      return 4.0; // Fallback
    }
  }

  Future<void> _updateActivity(
    String userActivityId,
    int newDuration,
    String newNotes,
  ) async {
    try {
      final double metValue = await _getMetForActivity(userActivityId);

      final int newCaloriesBurned = HealthCalculator.calculateCaloriesBurned(
        met: metValue,
        userWeightKg: _userWeightKg,
        durationMinutes: newDuration,
      );

      await FirebaseFirestore.instance
          .collection('user_activities')
          .doc(userActivityId)
          .update({
            'duration_minutes': newDuration,
            'calories_burned': newCaloriesBurned,
            'notes': newNotes,
            'last_updated_at': FieldValue.serverTimestamp(),
          });

      _fetchActivitiesAndUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Activity updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteActivity(String userActivityId) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Activity?'),
        content: const Text(
          'This will permanently delete this activity log. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteActivityFromFirestore(userActivityId);
    }
  }

  Widget _buildHabitsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile.adaptive(
              value: _mainHabitReminderEnabled,
              onChanged: _updateMainReminder,
              secondary: Icon(
                _mainHabitReminderEnabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
              ),
              title: const Text(
                'Enable Habit Reminders',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Active Habits',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _userHabits.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.emoji_nature_rounded,
                        size: 60,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No Habits Yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Tap "Create Habit" to start building a better you!',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _userHabits.length,
                  itemBuilder: (context, index) {
                    final habit = _userHabits[index];
                    final bool isCompletedToday =
                        habit.lastCompletedDate != null &&
                        DateUtils.isSameDay(
                          habit.lastCompletedDate,
                          DateTime.now(),
                        );
                    final streakInfo = _getDisplayStreakInfo(habit);
                    final int displayStreak = streakInfo['streak'];
                    final bool isActive = streakInfo['isActive'];

                    return Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: () {
                          _navigateToHabitDetails(habit);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.transparent,
                            child: Text(
                              habit.icon,
                              style: const TextStyle(fontSize: 28),
                            ),
                          ),
                          title: Text(
                            habit.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: isActive
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$displayStreak day${displayStreak == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      '🔥',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ],
                                )
                              : const Text(
                                  '0 days',
                                  style: TextStyle(color: Colors.grey),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.check_circle,
                                  color: isCompletedToday
                                      ? Colors.green
                                      : Colors.grey.shade300,
                                ),
                                onPressed: () {
                                  _toggleHabitCompletion(
                                    habit,
                                    isCompletedToday,
                                  );
                                },
                              ),
                              // Delete habit button
                              IconButton(
                                icon: Icon(
                                  Icons.cancel,
                                  color: Colors.red.shade300,
                                ),
                                onPressed: () async {
                                  // Show a confirmation dialog before deleting
                                  final bool?
                                  confirmDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: const Text('Delete Habit'),
                                        content: Text(
                                          'Are you sure you want to delete "${habit.name}"? This action cannot be undone.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text(
                                              'Delete',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );

                                  // If the user confirmed, then call the delete method
                                  if (confirmDelete == true) {
                                    _deleteHabit(habit);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PieChart extends StatelessWidget {
  final Map<String, double> data;
  final bool showPercentageLabels;

  const _PieChart({required this.data, this.showPercentageLabels = false});

  static const List<Color> _defaultColors = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.amber,
  ];

  // Assigns unique colors by consistent index
  static Color getColorForKey(String key) {
    final keys = _keyColorMap.keys.toList();
    if (!_keyColorMap.containsKey(key)) {
      // Assign a new color based on next available index
      final nextIndex = _keyColorMap.length % _defaultColors.length;
      _keyColorMap[key] = _defaultColors[nextIndex];
    }
    return _keyColorMap[key]!;
  }

  static final Map<String, Color> _keyColorMap = {};

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final total = data.values.fold<double>(0, (a, b) => a + b);

    final sections = data.entries.map((entry) {
      final color = getColorForKey(entry.key);
      final percentage = ((entry.value / total) * 100).toStringAsFixed(1);
      return PieChartSectionData(
        color: color,
        value: entry.value,
        radius: 55,
        title: showPercentageLabels ? '$percentage%' : '',
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titlePositionPercentageOffset: 0.6,
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 30,
        borderData: FlBorderData(show: false),
        sectionsSpace: 2,
      ),
    );
  }
}
