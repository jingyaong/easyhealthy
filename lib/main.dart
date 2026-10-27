import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyhealthy/screens/activity_tabs.dart';
import 'package:easyhealthy/utils/notification_scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'meal_page.dart';
import 'screens/activity_screen.dart';
import 'progress_page.dart';
import 'profile_page.dart';
import 'screens/onboarding.dart';
import 'utils/health_calculator.dart';
import 'utils/theme_provider.dart';
import 'app_theme.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'discover_recipes_page.dart';
import 'saved_recipes_page.dart';
import 'generate_meal_plan_page.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationScheduler().initialize();
  await NotificationScheduler().requestPermissions();
  await NotificationScheduler().scheduleAllReminders();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en', ''), // Default English
            Locale('en', 'GB'), // British English for dd/MM/yyyy
          ],
          title: 'Easy Healthy',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          // User is logged in, Redirector will send them to the correct page.
          return const Redirector();
        } else {
          // Pass initialPage: 0 to ensure the PageView starts on the welcome screen.
          return const OnboardingPage(initialPage: 0);
        }
      },
    );
  }
}

//This widget decides where to go after a user is logged in.
class Redirector extends StatelessWidget {
  const Redirector({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Pass initialPage: 1 to ensure the PageView starts on the details screen.
          return const OnboardingPage(initialPage: 1);
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final hasCompletedSecondStep =
        (data != null &&
            (data.containsKey('age') || data.containsKey('activity_level')));

        final weight = (data?['weight'] as num?)?.toDouble() ?? 0.0;
        final height = (data?['height'] as num?)?.toDouble() ?? 0.0;
        // 2. If weight or height missing, go to details page
        if (weight == 0.0 || height == 0.0) {
          return const OnboardingPage(initialPage: 1);
        }

        if (hasCompletedSecondStep) {
          return const MainPage();
        } else {
          final weight = (data?['weight'] as num?)?.toDouble() ?? 0.0;
          final height = (data?['height'] as num?)?.toDouble() ?? 0.0;
          final bmi = HealthCalculator.calculateBMI(weight, height);
          return OnboardingInfoScreen(
            bmi: bmi,
            onFinished: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainPage()),
                    (Route<dynamic> route) => false,
              );
            },
          );
        }
      },
    );
  }
}

class OnboardingPage extends StatefulWidget {
  final int initialPage; // Add this to allow starting at a specific page
  const OnboardingPage({super.key, this.initialPage = 0});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late PageController _pageController;
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _goalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize the page controller to the correct starting page from the widget
    _pageController = PageController(initialPage: widget.initialPage);
  }

  // Sign in with Google. AuthWrapper and Redirector will handle navigation.
  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; // User canceled the sign-in

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      // This will trigger the AuthWrapper and Redirector
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sign in with Google: $e')),
      );
    }
  }

  // Save user details to Firestore
  Future<void> _saveUserDetails() async {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);

    if (weight == null || weight <= 0 || height == null || height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid weight and height.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final bmi = HealthCalculator.calculateBMI(weight, height);

      // 1. Calculate Burn Goal
      final int initialBurnGoal =
      HealthCalculator.calculateRecommendedCalorieBurn(bmi: bmi);

      // 2. Default values for onboarding
      final age = 25;
      final gender = 'Male';
      final activityLevel = 'Sedentary';
      final fitnessGoal = 'Maintain current weight';

      // 3. Calculate Daily Nutrient Goals
      final goals = HealthCalculator.calculateDailyNutrientGoals(
        weightKg: weight,
        heightCm: height,
        age: age,
        gender: gender,
        activityLevel: activityLevel,
        fitnessGoal: fitnessGoal,
      );

      // 4. Save user profile + daily goals
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'weight': weight,
        'height': height,
        'age': age,
        'gender': gender,
        'activity_level': activityLevel,
        'fitnessGoal': fitnessGoal,
        'daily_burn_goal': initialBurnGoal,
        'daily_consume_goal': {
          'calories': goals['calories']!,
          'protein': goals['protein']!,
          'carbs': goals['carbs']!,
          'fat': goals['fat']!,
        },
        'mainHabitReminderEnabled': true,
        'mainReminderEnabled': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Navigate to next onboarding screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => OnboardingInfoScreen(
            bmi: bmi,
            onFinished: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainPage()),
                    (Route<dynamic> route) => false,
              );
            },
          ),
        ),
            (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics:
        const NeverScrollableScrollPhysics(), // Prevents user from swiping
        children: [
          _buildWelcomePage(), // Page 0
          _buildDetailsPage(), // Page 1
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20.0),
              child: Image.asset('assets/EasyHealthyLogo.png', height: 150),
            ),
            const SizedBox(height: 100),
            Text(
              "Welcome to Easy Healthy",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Sign in to begin your personalized health journey.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _signInWithGoogle,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
              icon: Image.asset(
                'assets/google_logo.png',
                height: 24.0,
              ),
              label: Text(
                "Sign in with Google",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsPage() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Let\'s Get Started'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "We need some basic information to set up your profile.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Weight (kg)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Height (cm)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _saveUserDetails,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _goalController.dispose();
    super.dispose();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    MealPage(),
    ActivityScreen(),
    ProgressPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        height: 70,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Meal',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // --- STATE VARIABLES ---
  bool _isLoading = true;
  String _userName = 'User';

  // Live Subscriptions
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  StreamSubscription<DocumentSnapshot>? _mealSubscription;
  StreamSubscription<QuerySnapshot>? _activitySubscription;

  // Activity Metadata Cache
  Map<String, Map<String, dynamic>> _activityDetails = {};

  // Goals (Defaults)
  double _goalCalories = 2000;
  double _goalProtein = 150;
  double _goalCarbs = 250;
  double _goalFat = 70;
  double _targetBurnGoal = 0; // From profile settings

  // Actual Progress (Live)
  double _consumedCalories = 0;
  double _consumedProtein = 0;
  double _consumedCarbs = 0;
  double _consumedFat = 0;
  double _burnedCalories = 0; // Actual burned from activities

  List<Map<String, dynamic>> _completedWorkouts = [];

  @override
  void initState() {
    super.initState();
    _initData(); // Initialize static data then start listeners
  }

  @override
  void dispose() {
    // Stop listening when we leave the page to prevent memory leaks
    _userSubscription?.cancel();
    _mealSubscription?.cancel();
    _activitySubscription?.cancel();
    super.dispose();
  }

  // --- INITIALIZATION & LIVE LISTENERS ---
  Future<void> _initData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _userName = user.displayName ?? 'User');

    // 1. Fetch Static Activity Details (Names/Icons) - Run once
    try {
      final activitiesSnapshot = await FirebaseFirestore.instance.collection('activities').get();
      _activityDetails = {
        for (var doc in activitiesSnapshot.docs)
          doc.id: {
            'name': doc.data()['name'] as String,
            'category': doc.data()['category'] as String? ?? 'Other',
          },
      };
    } catch (e) {
      debugPrint("Error fetching activity details: $e");
    }

    // 2. Start Real-time Listeners
    _setupLiveListeners(user.uid);
  }

  void _setupLiveListeners(String uid) {
    // --- LISTENER A: User Profile (Goals) ---
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final userData = snapshot.data() as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          // Get Target Burn
          _targetBurnGoal = (userData['daily_burn_goal'] as num?)?.toDouble() ?? 0.0;

          // Get Nutritional Goals
          final dailyGoal = userData['daily_consume_goal'] as Map<String, dynamic>?;
          if (dailyGoal != null) {
            // Base Goal - Burn Goal = Net Target
            double rawCalorieGoal = (dailyGoal['calories'] as num).toDouble();
            _goalCalories = rawCalorieGoal - _targetBurnGoal;

            _goalProtein = (dailyGoal['protein'] as num).toDouble();
            _goalCarbs = (dailyGoal['carbs'] as num).toDouble();
            _goalFat = (dailyGoal['fat'] as num).toDouble();
          }
        });
      }
    });

    // --- LISTENER B: Today's Consumed Meals ---
    final now = DateTime.now();
    final String todayDocId = "${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}";

    _mealSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meal_logs')
        .doc(todayDocId)
        .snapshots()
        .listen((snapshot) {

      double tCal = 0, tPro = 0, tCarb = 0, tFat = 0;

      if (snapshot.exists) {
        final data = snapshot.data()!;
        for (String category in ['Breakfast', 'Lunch', 'Dinner', 'Snacks']) {
          if (data.containsKey(category) && data[category] is List) {
            final items = List<Map<String, dynamic>>.from(data[category]);
            for (var item in items) {
              tCal += (item['calories'] as num? ?? 0).toDouble();
              tPro += (item['protein'] as num? ?? 0).toDouble();
              tCarb += (item['carbs'] as num? ?? 0).toDouble();
              tFat += (item['fat'] as num? ?? 0).toDouble();
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _consumedCalories = tCal;
          _consumedProtein = tPro;
          _consumedCarbs = tCarb;
          _consumedFat = tFat;
          _isLoading = false; // Data loaded at least once
        });
      }
    });

    // --- LISTENER C: Today's Activities (Burned) ---
    final startOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final endOfToday = Timestamp.fromDate(DateTime(now.year, now.month, now.day + 1));

    _activitySubscription = FirebaseFirestore.instance
        .collection('user_activities')
        .where('user_id', isEqualTo: uid)
        .where('date', isGreaterThanOrEqualTo: startOfToday)
        .where('date', isLessThan: endOfToday)
        .where('status', isEqualTo: 'Completed')
        .snapshots()
        .listen((snapshot) {

      double tBurn = 0;
      List<Map<String, dynamic>> workouts = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        tBurn += (data['calories_burned'] as num?)?.toDouble() ?? 0.0;

        // Resolve Name & Icon
        String workoutName;
        IconData activityIcon;

        if (data['custom_name'] != null && (data['custom_name'] as String).isNotEmpty) {
          workoutName = data['custom_name'];
          activityIcon = Icons.edit;
        } else {
          final activityId = data['activity_id'] as String?;
          final details = _activityDetails[activityId];
          workoutName = details?['name'] ?? 'Workout';
          final category = details?['category']?.toLowerCase() ?? 'other';

          switch (category) {
            case 'cardio': activityIcon = Icons.directions_run; break;
            case 'strength': activityIcon = Icons.fitness_center; break;
            case 'flexibility': activityIcon = Icons.self_improvement; break;
            default: activityIcon = Icons.task_alt;
          }
        }

        workouts.add({
          'name': workoutName,
          'calories': (data['calories_burned'] as num?)?.toDouble() ?? 0.0,
          'duration': (data['duration_minutes'] as num?)?.toInt() ?? 0,
          'icon': activityIcon,
        });
      }

      if (mounted) {
        setState(() {
          _burnedCalories = tBurn;
          _completedWorkouts = workouts;
        });
      }
    });
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final double netCalories = _consumedCalories - _burnedCalories;
    // Prevent negative progress or division by zero
    final double progress = _goalCalories > 0 ? netCalories / _goalCalories : 0.0;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text("Easy Healthy"),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
            },
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hello, $_userName 👋",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Here’s your daily health summary",

            ),
            const SizedBox(height: 25),

            // Calorie progress circle
            Center(
              child: CircularPercentIndicator(
                radius: 120.0,
                lineWidth: 16.0,
                percent: progress.clamp(0.0, 1.0),
                circularStrokeCap: CircularStrokeCap.round,
                progressColor: const Color(0xFF2196F3),
                center: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "${netCalories.toInt()} / ${_goalCalories.toInt()}",
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Target Net Calories",
                      style: GoogleFonts.poppins(
                        fontSize: 14,

                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Summary chips with Math Operators
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildSummaryChip("Consumed", _consumedCalories, Colors.orange),
                Text("-", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                _buildSummaryChip("Burned", _burnedCalories, const Color(0xFF2196F3)),
                Text("=", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                _buildSummaryChip("Net", netCalories, const Color(0xFF4CAF50)),
              ],
            ),

            const SizedBox(height: 25),

            // Macronutrients section
            Text(
              "Macronutrients",
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _buildMacroRow("Protein", _consumedProtein.toInt(), _goalProtein.toInt(), Colors.orange),
            _buildMacroRow("Carbs", _consumedCarbs.toInt(), _goalCarbs.toInt(), const Color(0xFF2196F3)),
            _buildMacroRow("Fat", _consumedFat.toInt(), _goalFat.toInt(), Colors.purple),

            const SizedBox(height: 25),

            // Discover Recipes Shortcuts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Discover", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiscoverRecipesPage(
                      selectedDate: DateTime.now(),
                    ),
                  ),
                );
              },
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        height: 55, width: 55,
                        decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.restaurant_menu, color: Color(0xFF2196F3), size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Discover Recipes", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                            Text("Browse a variety of healthy recipes", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GenerateMealPlanPage(
                      selectedDate: DateTime.now(),
                    ),
                  ),
                );
              },
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        height: 55, width: 55,
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.auto_awesome, color: Colors.green, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Generate Meal Plan", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                            Text("Let AI plan your meals for the day", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SavedRecipesPage(
                      selectedDate: DateTime.now(),
                    ),
                  ),
                );
              },
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        height: 55, width: 55,
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.bookmark, color: Colors.orange, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Saved Recipes", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                            Text("Your favorite recipes at a glance", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            // Explore Grid
            Text("Explore", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 15),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.3,
              children: [
                _buildNavigationCard("Log Activity", Icons.bar_chart_rounded, const Color(0xFF4CAF50), () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ActivityTabs(initialTabIndex: 0)));
                }),
                _buildNavigationCard("Start Planning", Icons.event_note_rounded, const Color(0xFF2196F3), () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ActivityTabs(initialTabIndex: 1)));
                }),
                _buildNavigationCard("Develop Habits", Icons.task_alt_rounded, Colors.orange, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ActivityTabs(initialTabIndex: 2)));
                }),
                _buildNavigationCard("Fitness Summary", Icons.pie_chart_rounded, Colors.purple, () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ActivityTabs(initialTabIndex: 3)));
                }),
              ],
            ),

            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }

  // --- HELPERS ---

  Widget _buildSummaryChip(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          "${value.toInt()}",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: color,
          ),
        ),
        Text(label, style: GoogleFonts.poppins(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildNavigationCard(
      String title,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign:
                TextAlign.center,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMacroRow(String name, int current, int goal, Color color) {
    double percent = (goal > 0) ? (current / goal) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
                "$current / $goal g",
                style: GoogleFonts.poppins(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: percent.clamp(0.0, 1.0),
            backgroundColor: Colors.grey[300],
            color: color,
            minHeight: 8,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    );
  }

}