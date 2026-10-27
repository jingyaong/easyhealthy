import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, double> _mealData = {
    "daily_consume_goal": 0,
    "consumed": 0,
    "protein": 0,
    "carbs": 0,
    "fat": 0,
  };

  Map<String, Map<String, double>> _categoryBreakdown = {
    'Breakfast': {'kcal': 0, 'p': 0, 'c': 0, 'f': 0},
    'Lunch': {'kcal': 0, 'p': 0, 'c': 0, 'f': 0},
    'Dinner': {'kcal': 0, 'p': 0, 'c': 0, 'f': 0},
    'Snack': {'kcal': 0, 'p': 0, 'c': 0, 'f': 0},
  };

  Map<String, double> _weeklyBurnData = {};
  Map<String, double> _weeklyMealData = {};
  final Map<String, double> _monthlyBurnData = {};
  final Map<String, double> _monthlyMealData = {};
  final Map<String, String> _monthlyChartLabels = {};

  double _workoutGoal = 300.0;
  double _caloriesBurnedToday = 0.0;

  int _goalWeeklySessions = 0;
  int _goalWeeklyDuration = 0;
  int _currentWeeklySessions = 0;
  int _currentWeeklyDuration = 0;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchProgressData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProgressData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 1. Define the time range
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final twentyEightDaysAgo = startOfToday.subtract(const Duration(days: 27));

    // 2. Fetch all data in parallel
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        FirebaseFirestore.instance
            .collection('user_activities')
            .where('user_id', isEqualTo: user.uid)
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(twentyEightDaysAgo))
            .where('status', isEqualTo: 'Completed')
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meal_logs')
            .get(),
      ]);

      // 3. Process the results
      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final last28DaysActivitiesSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final mealLogsSnapshot = results[2] as QuerySnapshot<Map<String, dynamic>>;

      // ---------------- Workout Goals ----------------
      final goal = (userDoc.data()?['daily_burn_goal'] as num?)?.toDouble() ?? 300.0;
      final weeklySessionsGoal = userDoc.data()?['goal_weekly_sessions'] as int? ?? 0;
      final weeklyDurationGoal = userDoc.data()?['goal_weekly_duration'] as int? ?? 0;

      // ---------------- Daily Consume Goal ----------------
      final dailyConsumeGoalData = userDoc.data()?['daily_consume_goal'] as Map<String, dynamic>? ?? {};
      final calorieGoal = (dailyConsumeGoalData['calories'] as num?)?.toDouble() ?? 2000;
      final proteinGoal = (dailyConsumeGoalData['protein'] as num?)?.toDouble() ?? 100;
      final carbsGoal = (dailyConsumeGoalData['carbs'] as num?)?.toDouble() ?? 250;
      final fatGoal = (dailyConsumeGoalData['fat'] as num?)?.toDouble() ?? 70;

      // ---------------- Workout Data ----------------
      final dailyBurnData = <String, double>{};
      for (int i = 0; i < 28; i++) {
        final day = startOfToday.subtract(Duration(days: i));
        final dayKey = DateFormat('yyyy-MM-dd').format(day);
        dailyBurnData[dayKey] = 0.0;
      }

      for (final doc in last28DaysActivitiesSnapshot.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        final dayKey = DateFormat('yyyy-MM-dd').format(date);
        final calories = (data['calories_burned'] as num?)?.toDouble() ?? 0.0;
        if (dailyBurnData.containsKey(dayKey)) {
          dailyBurnData[dayKey] = dailyBurnData[dayKey]! + calories;
        }
      }

      // ---------------- Weekly Workout Tracking ----------------
      int sessionsThisWeek = 0;
      int durationThisWeek = 0;
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfWeekDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

      for (final doc in last28DaysActivitiesSnapshot.docs) {
        final data = doc.data();
        final activityDate = (data['date'] as Timestamp).toDate();
        if (!activityDate.isBefore(startOfWeekDate)) {
          sessionsThisWeek++;
          durationThisWeek += (data['duration_minutes'] as num?)?.toInt() ?? 0;
        }
      }

      final weeklyData = Map.fromEntries(
        dailyBurnData.entries.where((entry) {
          final date = DateTime.parse(entry.key);
          return !date.isBefore(startOfToday.subtract(const Duration(days: 6)));
        }),
      );

      // ---------------- Monthly Burn Data ----------------
      final monthlyBurn = <String, double>{};
      final monthlyLabels = <String, String>{};

      for (int i = 0; i < 4; i++) {
        final weekEnd = startOfToday.subtract(Duration(days: i * 7));
        final weekStart = weekEnd.subtract(const Duration(days: 6));
        final weekKey = "Week ${4 - i}";

        double weekTotal = 0;
        dailyBurnData.forEach((dayKey, calories) {
          final date = DateTime.parse(dayKey);
          if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
            weekTotal += calories;
          }
        });

        monthlyBurn[weekKey] = weekTotal;
        monthlyLabels[weekKey] = "${DateFormat('dd/MM').format(weekStart)} - ${DateFormat('dd/MM').format(weekEnd)}";
      }

      final todayBurnKey = DateFormat('yyyy-MM-dd').format(now);
      final burnedToday = dailyBurnData[todayBurnKey] ?? 0.0;

      // ---------------- Meal Logs Processing (Daily & Weekly) ----------------
      double consumedToday = 0, proteinToday = 0, carbsToday = 0, fatToday = 0;
      final todayKey = DateFormat('dd-MM-yyyy').format(now);
      final weeklyCaloriesData = <String, double>{};

      // ---  Reset breakdown for fresh calculation ---
      _categoryBreakdown.forEach((key, value) {
        value['kcal'] = 0;
        value['p'] = 0;
        value['c'] = 0;
        value['f'] = 0;
      });

      for (var doc in mealLogsSnapshot.docs) {
        DateTime? date;
        try {
          date = DateFormat('dd-MM-yyyy').parse(doc.id);
        } catch (e) {
          continue;
        }

        double dailyTotal = 0;
        final mealsData = doc.data();

        mealsData.forEach((mealType, meals) {
          if (meals is List) {
            // Determine category name (normalize "Snacks" to "Snack")
            String categoryName = mealType;
            if (mealType == 'Snacks') categoryName = 'Snack';

            for (var meal in meals) {
              double cals = (meal['calories'] ?? 0).toDouble();
              dailyTotal += cals;

              // If it's today, sum macros AND calculate category breakdown
              if (doc.id == todayKey) {
                double p = (meal['protein'] ?? 0).toDouble();
                double c = (meal['carbs'] ?? 0).toDouble();
                double f = (meal['fat'] ?? 0).toDouble();

                consumedToday += cals;
                proteinToday += p;
                carbsToday += c;
                fatToday += f;

                // --- Add to category specific totals ---
                if (_categoryBreakdown.containsKey(categoryName)) {
                  _categoryBreakdown[categoryName]!['kcal'] = _categoryBreakdown[categoryName]!['kcal']! + cals;
                  _categoryBreakdown[categoryName]!['p'] = _categoryBreakdown[categoryName]!['p']! + p;
                  _categoryBreakdown[categoryName]!['c'] = _categoryBreakdown[categoryName]!['c']! + c;
                  _categoryBreakdown[categoryName]!['f'] = _categoryBreakdown[categoryName]!['f']! + f;
                }
              }
            }
          }
        });

        // Add to Weekly Data if within range
        if (!date.isBefore(startOfToday.subtract(const Duration(days: 6)))) {
          weeklyCaloriesData[DateFormat('yyyy-MM-dd').format(date)] = dailyTotal;
        }
      }

      // ---------------- Monthly Meal Data ----------------
      final monthlyCaloriesData = <String, double>{};

      for (int i = 0; i < 4; i++) {
        final weekEnd = startOfToday.subtract(Duration(days: i * 7));
        final weekStart = weekEnd.subtract(const Duration(days: 6));
        final weekKey = "Week ${4 - i}";

        double weekTotal = 0;

        for (var doc in mealLogsSnapshot.docs) {
          DateTime? date;
          try {
            date = DateFormat('dd-MM-yyyy').parse(doc.id);
          } catch (e) {
            continue;
          }

          if (!date.isBefore(weekStart) && !date.isAfter(weekEnd)) {
            final mealsData = doc.data();
            mealsData.forEach((mealType, meals) {
              if (meals is List) {
                for (var meal in meals) {
                  weekTotal += (meal['calories'] ?? 0).toDouble();
                }
              }
            });
          }
        }
        monthlyCaloriesData[weekKey] = weekTotal;
      }

      // ---------------- Set State ----------------
      if (mounted) {
        setState(() {
          _workoutGoal = goal;
          _caloriesBurnedToday = burnedToday;
          _weeklyBurnData = weeklyData;

          _monthlyBurnData.clear();
          _monthlyBurnData.addAll(Map.fromEntries(monthlyBurn.entries.toList().reversed));

          _monthlyChartLabels.clear();
          _monthlyChartLabels.addAll(Map.fromEntries(monthlyLabels.entries.toList().reversed));

          _monthlyMealData.clear();
          _monthlyMealData.addAll(Map.fromEntries(monthlyCaloriesData.entries.toList().reversed));

          _goalWeeklySessions = weeklySessionsGoal;
          _goalWeeklyDuration = weeklyDurationGoal;
          _currentWeeklySessions = sessionsThisWeek;
          _currentWeeklyDuration = durationThisWeek;

          _mealData = {
            "daily_consume_goal": calorieGoal,
            "consumed": consumedToday,
            "protein": proteinToday,
            "carbs": carbsToday,
            "fat": fatToday,
            "protein_goal": proteinGoal,
            "carbs_goal": carbsGoal,
            "fat_goal": fatGoal,
          };
          _weeklyMealData = Map.from(weeklyCaloriesData);

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print("Error fetching progress data: $e");
    }
  }

  // ---------- HELPER: generate insights dynamically ----------
  String _getCalorieInsight() {
    double consumed = _mealData["consumed"]!;
    double goal = _mealData["daily_consume_goal"]!;

    if (goal == 0) return "Set your daily calorie goal to start tracking!";

    double diff = consumed - goal;

    // 1. Perfect / Spot On (Within +/- 50 kcal)
    if (diff.abs() <= 50) {
      return "🏆 Outstanding! You hit your calorie goal perfectly.";
    }
    // 2a. Slightly Over (Between 50 and 200 over)
    else if (diff > 50 && diff <= 200) {
      return "⚠️ You're slightly over your goal, but still close!";
    }
    // 2b. Slightly Under (Between 50 and 200 under)
    else if (diff >= -200 && diff < -50) {
      return "⚖️ Nice! You’re very close to your daily goal.";
    }
    // 3. Significantly Under (More than 200 kcal under)
    else if (diff < -200) {
      return "🍃 You're under your calorie goal — great control!";
    }
    // 4. Significantly Over (More than 200 kcal over)
    else {
      return "⚠️ You went over your target today — try balancing your next meals.";
    }
  }

  String _getMacroInsight(String macro) {
    double current = _mealData[macro]!;
    double goal = _mealData["${macro}_goal"] ?? 0;

    if (goal == 0) return "Set your $macro goal!";

    final percent = (current / goal * 100);

    if (percent < 50) {
      return "📉 Low intake! Try to boost your $macro levels.";
    } else if (percent < 85) {
      return "💪 On track! You're getting closer to your $macro target.";
    } else if (percent <= 115) {
      return "🏆 Perfect! You hit your $macro goal spot on.";
    } else if (percent <= 130) {
      return "⚠️ ${macro[0].toUpperCase()}${macro.substring(1)} is a bit high, but still within a reasonable range.";
    } else {
      return "🛑 Limit exceeded. Watch your $macro intake for the rest of the day.";
    }
  }

  String _getWorkoutInsight() {
    double burned = _caloriesBurnedToday;
    double goal = _workoutGoal;
    if (burned >= goal) {
      return "🔥 Fantastic! You hit your workout goal!";
    } else if (burned >= goal * 0.75) {
      return "💪 Almost there! One more push to reach your goal.";
    } else {
      return "🏃‍♂️ Keep going! Every step counts.";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Progress Overview', style: GoogleFonts.poppins()),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF2196F3),
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: const Color(0xFF2196F3),
          tabs: const [
            Tab(text: "Daily"),
            Tab(text: "Weekly"),
            Tab(text: "Monthly"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDailyProgress(),
          _buildWeeklyProgress(),
          _buildMonthlyProgress(),
        ],
      ),
    );
  }

  // ------------------ DAILY PROGRESS ------------------
  Widget _buildDailyProgress() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final dailyGoal = _mealData['daily_consume_goal'] ?? 0;
    final consumed = _mealData['consumed'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle("Today's Nutrition Progress 🥗"),
          const SizedBox(height: 20),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CircularProgressIndicator(
                    value: dailyGoal == 0 ? 0 : (consumed / dailyGoal).clamp(0.0, 1.0),
                    strokeWidth: 14,
                    backgroundColor: Colors.grey[300],
                    color: const Color(0xFF2196F3),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${consumed.toInt()} kcal",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                    Text(
                      "of ${dailyGoal.toInt()} kcal",
                      style: GoogleFonts.poppins(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Text(
              _getCalorieInsight(),
              style: GoogleFonts.poppins(
                  color: Colors.grey[700], fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 25),
          _buildSectionTitle("Macronutrients ⚡"),
          const SizedBox(height: 15),
          _buildMacroRow(
              "Protein",
              _mealData['protein'] ?? 0,
              _mealData['protein_goal'] ?? 0,
              Colors.orange,
              insight: _getMacroInsight("protein")),
          _buildMacroRow(
              "Carbs",
              _mealData['carbs'] ?? 0,
              _mealData['carbs_goal'] ?? 0,
              const Color(0xFF2196F3),
              insight: _getMacroInsight("carbs")),
          _buildMacroRow(
              "Fat",
              _mealData['fat'] ?? 0,
              _mealData['fat_goal'] ?? 0,
              Colors.purple,
              insight: _getMacroInsight("fat")),
          const SizedBox(height: 25),
          _buildSectionTitle("Today's Meals 🍽️"),
          const SizedBox(height: 15),
          _buildMealCategoryCard("Breakfast", _categoryBreakdown['Breakfast']!, Colors.orangeAccent),
          _buildMealCategoryCard("Lunch", _categoryBreakdown['Lunch']!, Colors.blueAccent),
          _buildMealCategoryCard("Dinner", _categoryBreakdown['Dinner']!, Colors.purpleAccent),
          _buildMealCategoryCard("Snack", _categoryBreakdown['Snack']!, Colors.greenAccent),
          const SizedBox(height: 30),
          _buildSectionTitle("Workout Progress 🏋️‍♂️"),
          const SizedBox(height: 20),
          _buildWorkoutCard(),
          const SizedBox(height: 10),
          Center(
            child: Text(
              _getWorkoutInsight(),
              style: GoogleFonts.poppins(
                  color: Colors.grey[700], fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMealCategoryCard(String title, Map<String, double> data, Color color) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4, height: 24,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 10),
                    Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
                  ],
                ),
                Text("${data['kcal']?.toInt()} kcal", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniMacro("Protein", "${data['p']?.toInt()}g"),
                _buildMiniMacro("Carbs", "${data['c']?.toInt()}g"),
                _buildMiniMacro("Fat", "${data['f']?.toInt()}g"),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMacro(String label, String value) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  String _getWeeklyGoalInsight() {
    final sessionProgress = _goalWeeklySessions > 0
        ? _currentWeeklySessions / _goalWeeklySessions
        : 0;
    final durationProgress = _goalWeeklyDuration > 0
        ? _currentWeeklyDuration / _goalWeeklyDuration
        : 0;

    if (_isLoading) {
      return "Analyzing your week...";
    }

    if (_currentWeeklySessions == 0) {
      return "Let's start the week strong with your first workout!";
    }

    if (sessionProgress >= 1 && durationProgress >= 1) {
      return "Amazing! You've crushed both your session and duration goals this week!";
    }

    if (sessionProgress >= 1) {
      return "You've hit your session goal! Keep pushing on duration.";
    }

    if (durationProgress >= 1) {
      return "Great work on duration! A few more sessions to hit your goal.";
    }

    if (sessionProgress > 0.5) {
      return "You're over halfway there. Keep up the great momentum!";
    }

    return "Great start to the week. Every session counts!";
  }

  Widget _buildWorkoutCard() {
    double percent = _caloriesBurnedToday > 0 && _workoutGoal > 0
        ? _caloriesBurnedToday / _workoutGoal
        : 0.0;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[300],
                    color: Colors.green,
                    strokeWidth: 8,
                  ),
                ),
                Text(
                  "${(percent.clamp(0.0, 1.0) * 100).toInt()}%",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Calories Burned",
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "${_caloriesBurnedToday.toInt()} of ${_workoutGoal.toInt()} kcal",
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroRow(
      String title, double value, double goal, Color color,
      {required String insight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row: Title on Left, Value on Right (No Brackets)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              Text(
                "${value.toInt()}g / ${goal.toInt()}g", // Format: 50g / 100g
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // 2. Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: goal == 0 ? 0 : (value / goal).clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              color: color,
              minHeight: 10,
            ),
          ),

          // 3. Insight Text below
          const SizedBox(height: 4),
          Text(
            insight,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow({
    required String name,
    required double current,
    required double goal,
    required Color color,
  }) {
    // Ensure goal is not zero to prevent division by zero errors
    final double progress = (goal > 0 && current > 0) ? (current / goal) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              Text(
                // Show progress, e.g., "3 / 4" for sessions or "90 / 120" for minutes
                "${current.toInt()} / ${goal.toInt()}",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyGoalProgress() {
    final bool goalsAreSet = _goalWeeklySessions > 0 || _goalWeeklyDuration > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Weekly Goal Progress 🎯"),
        const SizedBox(height: 16),

        // If goals are set, show the progress bars.
        if (goalsAreSet)
          _buildGoalProgressRows()
        // Otherwise, show a message asking the user to set their goals.
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                "Set your weekly goals in planner to track your progress here!",
                style: GoogleFonts.poppins(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGoalProgressRows() {
    return Column(
      children: [
        if (_goalWeeklySessions > 0)
          _buildProgressRow(
            name: "Workout Sessions",
            current: _currentWeeklySessions.toDouble(),
            goal: _goalWeeklySessions.toDouble(),
            color: Colors.green,
          ),

        if (_goalWeeklyDuration > 0)
          _buildProgressRow(
            name: "Workout Duration (minutes)",
            current: _currentWeeklyDuration.toDouble(),
            goal: _goalWeeklyDuration.toDouble(),
            color: Colors.blueAccent,
          ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _getWeeklyGoalInsight(),
            style: GoogleFonts.poppins(
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildAverageBurnDisplay() {
    final last7DaysData = _weeklyBurnData.values.toList();
    final hasActivity = last7DaysData.any((burn) => burn > 0);

    final averageBurn = hasActivity
        ? last7DaysData.reduce((a, b) => a + b) / last7DaysData.length
        : 0.0;

    return Center(
      child: Column(
        children: [
          Text(
            "Avg. Daily Burn (7 Days)",
            style: GoogleFonts.poppins(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${averageBurn.toInt()} kcal",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.orangeAccent,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------ WEEKLY PROGRESS ------------------
  Widget _buildWeeklyProgress() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    // Last 7 days
    final List<String> last7DaysKeys = [];
    final List<String> last7DaysLabels = [];
    final List<double> last7DaysMealValues = [];
    final List<double> last7DaysBurnValues = [];

    for (int i = 6; i >= 0; i--) {
      final day = startOfToday.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(day);
      last7DaysKeys.add(key);
      last7DaysLabels.add(DateFormat('dd/MM').format(day));
      last7DaysMealValues.add(_weeklyMealData[key] ?? 0.0);
      last7DaysBurnValues.add(_weeklyBurnData[key] ?? 0.0);
    }

    // 2. Calculate Average
    double totalConsumed = last7DaysMealValues.fold(0, (sum, item) => sum + item);
    double averageConsumed = totalConsumed / 7;

    final hasBurnData = last7DaysBurnValues.any((v) => v > 0);
    final hasMealData = last7DaysMealValues.any((v) => v > 0);

    double maxMealY = last7DaysMealValues.isEmpty ? 10 : last7DaysMealValues.reduce((a, b) => a > b ? a : b);
    double maxBurnY = last7DaysBurnValues.isEmpty ? 10 : last7DaysBurnValues.reduce((a, b) => a > b ? a : b);
    double mealChartMaxY = (maxMealY * 1.1).ceilToDouble();
    double burnChartMaxY = (maxBurnY * 1.1).ceilToDouble();
    if (mealChartMaxY < 50) mealChartMaxY = 50;
    if (burnChartMaxY < 50) burnChartMaxY = 50;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle("Calories Consumed (7 Days) 🥗"),
          const SizedBox(height: 16),
          _buildLineChartWithLegend(
            Map.fromIterables(last7DaysKeys, last7DaysMealValues),
            _mealData['daily_consume_goal'] ?? 0,
            Colors.blueAccent,
          ),

          const SizedBox(height: 20),

          Center(
            child: Column(
              children: [
                Text(
                  "Avg. Daily Consumption (7 Days)",
                  style: GoogleFonts.poppins(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${averageConsumed.toInt()} kcal",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _getWeeklyNutritionInsight(),
                style: GoogleFonts.poppins(
                  color: Colors.grey[700],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          const SizedBox(height: 25),
          _buildSectionTitle("Calories Burned (7 Days) 🔥"),
          const SizedBox(height: 16),
          if (hasBurnData)
            AspectRatio(
              aspectRatio: 1.8,
              child: Padding(
                padding: const EdgeInsets.only(left: 15),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: burnChartMaxY,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i >= 0 && i < last7DaysLabels.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  last7DaysLabels[i],
                                  style: GoogleFonts.poppins(fontSize: 10),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                          interval: 1,
                        ),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        isCurved: true,
                        preventCurveOverShooting: true,
                        color: Colors.orangeAccent,
                        barWidth: 4,
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.orangeAccent.withOpacity(0.25),
                        ),
                        spots: List.generate(
                          last7DaysBurnValues.length,
                              (i) => FlSpot(i.toDouble(), last7DaysBurnValues[i]),
                        ),
                      ),
                    ],
                    minX: 0,
                    maxX: (last7DaysBurnValues.length - 1).toDouble(),
                  ),
                ),
              ),
            )
          else
            Center(
              child: Text(
                "No workouts logged this week. Let's get moving! 🏋️‍♂️",
                style: GoogleFonts.poppins(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          if (hasBurnData) _buildAverageBurnDisplay(),
          const SizedBox(height: 16),
          _buildWeeklyGoalProgress(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _getMonthlyInsight() {
    if (_isLoading) {
      return "Analyzing your monthly progress...";
    }

    final monthlyTotals = _monthlyBurnData.values.toList();
    if (monthlyTotals.every((burn) => burn == 0)) {
      return "No workouts logged this month. Let's get started!";
    }

    final average =
        monthlyTotals.reduce((a, b) => a + b) / monthlyTotals.length;

    if (average > (_workoutGoal * 5)) {
      // Assuming an average of 5 workouts/week
      return "Incredible consistency! You're building a powerful habit.";
    } else if (average > (_workoutGoal * 3)) {
      return "Great job! You're consistently active week over week.";
    } else if (average > 0) {
      return "Good start! Aim for a little more activity each week to build momentum.";
    }

    return "Let's make this month a great one!";
  }

  String _getWeeklyNutritionInsight() {
    if (_isLoading) return "Analyzing your week...";

    final double dailyGoal = _mealData['daily_consume_goal'] ?? 0;
    if (dailyGoal == 0) return "Set a daily calorie goal to see insights!";

    // Calculate Average Consumption for the last 7 days
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    double totalConsumed = 0;
    int daysLogged = 0;

    for (int i = 0; i < 7; i++) {
      final day = startOfToday.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(day);
      final val = _weeklyMealData[key] ?? 0.0;
      totalConsumed += val;
      if (val > 0) daysLogged++;
    }

    if (daysLogged == 0) return "No meals logged in the last 7 days.";

    // We calculate average based on 7 days to show true weekly impact
    // Or you can divide by 'daysLogged' if you only want to average active days.
    // Let's use 7 to encourage consistency.
    final average = totalConsumed / 7;
    final diff = average - dailyGoal;

    if (daysLogged < 3) {
      return "Tip: Log more frequently to get accurate weekly insights.";
    }

    if (diff > 250) {
      return "⚠️ Your weekly average is higher than your goal. Try to balance upcoming meals.";
    } else if (diff < -250) {
      return "📉 Your weekly average is quite low. Make sure you're fueling enough!";
    } else if (diff > 0) {
      return "⚖️ You're slightly over your weekly average, but staying consistent!";
    } else {
      return "🏆 Excellent work! Your weekly average is nicely under your goal limit.";
    }
  }

  String _getMonthlyNutritionInsight(double averageWeeklyConsumed, double weeklyGoal) {
    if (weeklyGoal == 0) return "Set a daily goal to get insights!";
    if (averageWeeklyConsumed == 0) return "No meal data logged this month.";

    double diff = averageWeeklyConsumed - weeklyGoal;

    // Threshold: +/- 1750 kcal (approx 250 kcal per day variance over a week)
    if (diff > 1750) {
      return "⚠️ Your weekly average is higher than your goal. Try to adjust next week.";
    } else if (diff < -1750) {
      return "📉 Your intake is lower than planned. Ensure you're fueling enough for the month.";
    } else if (diff > 0) {
      return "⚖️ Slightly over, but you are maintaining good consistency!";
    } else {
      return "🏆 Great job! You are consistently staying within your weekly targets.";
    }
  }

  // ------------------ MONTHLY PROGRESS ------------------
  Widget _buildMonthlyProgress() {
    final weeks = _monthlyChartLabels.values.toList();
    final burnCalories = _monthlyBurnData.values.toList();
    final mealCalories = _monthlyMealData.values.toList();

    final hasBurnDataThisMonth = burnCalories.any((burn) => burn > 0);
    final hasMealDataThisMonth = mealCalories.any((meal) => meal > 0);

    // --- 1. CALCULATE MEAL STATS ---
    final double weeklyGoal = (_mealData['daily_consume_goal'] ?? 0) * 7;
    double totalConsumed = mealCalories.fold(0, (a, b) => a + b);
    // Avoid division by zero
    double averageWeeklyConsumed = mealCalories.isNotEmpty
        ? totalConsumed / mealCalories.length
        : 0.0;

    // --- 2. CALCULATE BURN STATS ---
    double maxWeeklyBurn = burnCalories.isEmpty
        ? 1000
        : burnCalories.reduce((a, b) => a > b ? a : b);
    double chartMaxYBurn = (maxWeeklyBurn * 1.2).ceil().toDouble();

    final averageWeeklyBurn = hasBurnDataThisMonth
        ? burnCalories.reduce((a, b) => a + b) / burnCalories.length
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle("Monthly Summary 📅"),
            const SizedBox(height: 25),

            // ------------------ MONTHLY MEAL BAR CHART ------------------
            _buildSectionTitle("Weekly Calories Consumed 🥗"),
            const SizedBox(height: 10),

            if (hasMealDataThisMonth)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    _buildLegendItem(Colors.blueAccent, "Consumed"),
                    const SizedBox(width: 16),
                    _buildLegendItem(Colors.redAccent, "Weekly Goal", isDashed: true),
                  ],
                ),
              ),

            if (hasMealDataThisMonth) ...[
              SizedBox(
                height: 200,
                child: _buildBarChart(
                  _monthlyMealData,
                  weeklyGoal,
                  labels: _monthlyChartLabels.values.toList(),
                ),
              ),

              const SizedBox(height: 20),

              // --- AVERAGE WEEKLY CONSUMPTION DISPLAY ---
              Center(
                child: Column(
                  children: [
                    Text(
                      "Avg. Weekly Consumption",
                      style: GoogleFonts.poppins(
                        color: Colors.grey[700],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${averageWeeklyConsumed.toInt()} kcal",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- INSIGHT TEXT ---
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    _getMonthlyNutritionInsight(averageWeeklyConsumed, weeklyGoal),
                    style: GoogleFonts.poppins(
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              // -----------------------------------------------
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  child: Text(
                    "No meal data logged this month.",
                    style: GoogleFonts.poppins(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            const SizedBox(height: 25),

            // ------------------ MONTHLY WORKOUT BAR CHART ------------------
            _buildSectionTitle("Weekly Calorie Burn 🔥"),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (hasBurnDataThisMonth)
              SizedBox(
                height: 250,
                child: BarChart(
                  BarChartData(
                    maxY: chartMaxYBurn,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            if (value == 0 || value >= meta.max)
                              return const SizedBox.shrink();
                            return Text(
                              '${(value / 1000).toStringAsFixed(1)}k',
                              style: GoogleFonts.poppins(fontSize: 10),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < weeks.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(weeks[index],
                                    style: GoogleFonts.poppins(fontSize: 10)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                          reservedSize: 30,
                        ),
                      ),
                    ),
                    barGroups: List.generate(
                      weeks.length,
                          (i) => BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: burnCalories[i],
                          color: Colors.orangeAccent,
                          borderRadius: BorderRadius.circular(4),
                          width: 22,
                        )
                      ]),
                    ),
                  ),
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  child: Text(
                    "No workouts logged this month.",
                    style: GoogleFonts.poppins(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            const SizedBox(height: 25),

            // Average Burn Display
            Center(
              child: Column(
                children: [
                  Text(
                    "Avg. Weekly Burn",
                    style: GoogleFonts.poppins(
                      color: Colors.grey[700],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${averageWeeklyBurn.toInt()} kcal",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  _getMonthlyInsight(), // This is your existing Workout Insight
                  style: GoogleFonts.poppins(
                    color: Colors.grey[700],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ HELPER: LINE CHART ------------------
  Widget _buildLineChart(Map<String, double> data, double goal, Color color) {
    final labels = data.keys
        .map((k) => DateFormat('dd/MM').format(DateTime.parse(k)))
        .toList();
    final values = data.values.toList();

    double rawMax = [...values, goal].reduce((a, b) => a > b ? a : b);
    double minMaxY = 50;
    double maxY = rawMax * 1.2;
    if (maxY < minMaxY) maxY = minMaxY;

    // Calculate dynamic interval
    double interval = (maxY / 5);
    if (maxY > 500) {
      interval = (interval / 100).ceil() * 100;
    } else if (maxY > 100) {
      interval = (interval / 50).ceil() * 50;
    } else {
      interval = (interval / 10).ceil() * 10;
    }
    maxY = interval * 5;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: goal,
              color: Colors.redAccent,
              strokeWidth: 2,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (line) => 'Goal: ${goal.toInt()}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 4, top: 2),
              ),
            ),
          ],
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: GoogleFonts.poppins(fontSize: 10),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32, // <--- INCREASED SIZE (was 22) to fit padding
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i >= 0 && i < labels.length) {
                  // <--- ADDED PADDING HERE
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(labels[i],
                        style: GoogleFonts.poppins(fontSize: 10)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
                values.length, (i) => FlSpot(i.toDouble(), values[i])),
            color: color,
            barWidth: 4,
            isCurved: true,
            preventCurveOverShooting: true,
            belowBarData:
            BarAreaData(show: true, color: color.withOpacity(0.2)),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: color,
                  strokeWidth: 0,
                );
              },
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchSpotThreshold: 40,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.black87,
            tooltipMargin: 14,
            tooltipPadding: const EdgeInsets.all(6),
            fitInsideHorizontally: true,
            fitInsideVertically: false,
            getTooltipItems: (spots) {
              return spots.map((spot) {
                return LineTooltipItem(
                  'Consumed: ${spot.y.toInt()} kcal',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLineChartWithLegend(Map<String, double> data, double goal, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend Row
        Row(
          children: [
            _buildLegendItem(color, 'Consumed'),
            const SizedBox(width: 16),
            _buildLegendItem(Colors.redAccent, 'Daily Goal', isDashed: true),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: _buildLineChart(data, goal, color),
        ),
      ],
    );
  }

  // ------------------ HELPER: BAR CHART ------------------
  Widget _buildBarChart(Map<String, double> data, double goal, {List<String>? labels}) {
    final sortedKeys = data.keys.toList()..sort();
    final values = sortedKeys.map((k) => data[k] ?? 0).toList();
    final chartLabels = labels ?? sortedKeys;

    double rawMax = [...values, goal].reduce((a, b) => a > b ? a : b);
    double minMaxY = 50;
    double maxY = rawMax * 1.2;
    if (maxY < minMaxY) maxY = minMaxY;

    double interval = maxY / 5;
    if (maxY > 500) {
      interval = (interval / 100).ceil() * 100;
    } else if (maxY > 100) {
      interval = (interval / 50).ceil() * 50;
    } else {
      interval = (interval / 10).ceil() * 10;
    }
    maxY = interval * 5;

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barGroups: List.generate(values.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: values[i],
                color: Colors.blueAccent,
                width: 22,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < chartLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(chartLabels[index],
                        style: GoogleFonts.poppins(fontSize: 10)),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: interval,
              getTitlesWidget: (value, meta) {
                return Text(value.toInt().toString(),
                    style: GoogleFonts.poppins(fontSize: 10));
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: goal,
              color: Colors.redAccent,
              strokeWidth: 2,
              dashArray: [5, 5],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (line) => 'Goal: ${goal.toInt()}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 4, top: 2),
              ),
            ),
          ],
        ),
        barTouchData: BarTouchData(
          enabled: true,
          handleBuiltInTouches: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (spot) => Colors.black87,
            tooltipMargin: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                'Consumed: ${rod.toY.toInt()} kcal',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
            fitInsideHorizontally: true,
            fitInsideVertically: false,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {bool isDashed = false}) {
    return Row(
      children: [
        if (isDashed)
          SizedBox(
            width: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(width: 5, height: 2, color: color),
                Container(width: 5, height: 2, color: color),
              ],
            ),
          )
        else
          Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }
}
