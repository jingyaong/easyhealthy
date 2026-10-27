import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'recommendations/hybrid.dart';
import 'recipe_details_page.dart';

class GenerateMealPlanPage extends StatefulWidget {
  final DateTime selectedDate;

  const GenerateMealPlanPage({super.key, required this.selectedDate});

  @override
  State<GenerateMealPlanPage> createState() => _GenerateMealPlanPageState();
}

class _GenerateMealPlanPageState extends State<GenerateMealPlanPage> {
  final List<String> meals = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

  // Map meal -> list of food/recipes
  Map<String, List<Map<String, dynamic>>> mealPlan = {};
  bool _isLoading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    for (var meal in meals) {
      mealPlan[meal] = [];
    }
    _generatePlan();
  }

  Future<void> _generatePlan() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Analyzing profile & history...";
    });

    try {
      // ---------------------------------------------------------
      // 1. FORCE DATA REFRESH
      // ---------------------------------------------------------
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      Map<String, dynamic> userData = userDoc.data() ?? {};

      final logsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('meal_logs')
          .get();

      Map<String, dynamic> logsMap = {};
      for (var doc in logsSnapshot.docs) {
        logsMap[doc.id] = doc.data();
      }
      userData['meal_logs'] = logsMap;

      debugPrint("GeneratePlan: passed ${logsMap.length} days of history to Recommender.");

      // ---------------------------------------------------------
      // 2. PARSE GOALS
      // ---------------------------------------------------------
      int dailyCalorieGoal = 2000;
      int dailyProtein = 150;
      int dailyCarbs = 250;
      int dailyFat = 70;

      if (userData.containsKey('daily_consume_goal') && userData['daily_consume_goal'] is Map) {
        final goalMap = userData['daily_consume_goal'] as Map<String, dynamic>;
        dailyCalorieGoal = (goalMap['calories'] as num?)?.toInt() ?? 2000;
        dailyProtein = (goalMap['protein'] as num?)?.toInt() ?? 150;
        dailyCarbs = (goalMap['carbs'] as num?)?.toInt() ?? 250;
        dailyFat = (goalMap['fat'] as num?)?.toInt() ?? 70;
      }

      // ---------------------------------------------------------
      // 3. INITIALIZE RECOMMENDER
      // ---------------------------------------------------------
      final recommender = HybridRecommender(
        userData: Map<String, dynamic>.from(userData),
        selectedDate: widget.selectedDate,
      );
      await recommender.init();

      // ---------------------------------------------------------
      // 4. GENERATE MEALS
      // ---------------------------------------------------------
      Map<String, double> ratios = {
        'Breakfast': 0.25,
        'Lunch': 0.35,
        'Dinner': 0.30,
        'Snacks': 0.10
      };

      // Clear existing UI plan
      mealPlan.forEach((key, value) => value.clear());

      // --- NEW: Track picked items to prevent duplicates across meals ---
      List<String> pickedNames = [];

      for (String mealType in meals) {
        if (!mounted) return;
        setState(() => _statusMessage = "Planning $mealType...");

        double ratio = ratios[mealType] ?? 0.25;

        int totalMealTarget = (dailyCalorieGoal * ratio).round();
        int targetProtein = (dailyProtein * ratio).round();
        int targetCarbs = (dailyCarbs * ratio).round();
        int targetFat = (dailyFat * ratio).round();

        // Get Recommendations (Passing 'avoidRecipes')
        final suggestions = await recommender.recommend(
          topN: 3,
          categoryFilter: mealType.toLowerCase(),
          targetCalories: totalMealTarget,
          targetProtein: targetProtein,
          targetCarbs: targetCarbs,
          targetFat: targetFat,
          avoidRecipes: pickedNames, // <--- PASS THE AVOID LIST HERE
        );

        if (suggestions.isNotEmpty) {
          var bestMatch = suggestions.first;

          // --- NEW: Add selected recipe AND its sides to the avoid list ---
          pickedNames.add(bestMatch['name'] ?? '');

          if (bestMatch['components'] != null) {
            for (var c in bestMatch['components']) {
              pickedNames.add(c['name'] ?? '');
            }
          }
          // ----------------------------------------------------------------

          // Helper to safely get nutrient values
          num getSafeValue(Map<String, dynamic> source, String key, [String? altKey]) {
            if (source[key] != null && source[key] is num) return source[key];
            if (source[key] != null && source[key] is String) return num.tryParse(source[key]) ?? 0;
            final n = source['nutrients'] is Map ? source['nutrients'] : {};
            if (n[key] != null && n[key] is num) return n[key];
            if (n[key] != null && n[key] is String) return num.tryParse(n[key]) ?? 0;
            if (altKey != null) {
              if (n[altKey] != null && n[altKey] is num) return n[altKey];
              if (n[altKey] != null && n[altKey] is String) return num.tryParse(n[altKey]) ?? 0;
            }
            return 0;
          }

          double quantity = 1.0;

          List<Map<String, dynamic>> itemsToAdd = [];
          if (bestMatch['components'] != null && (bestMatch['components'] as List).isNotEmpty) {
            itemsToAdd = List<Map<String, dynamic>>.from(bestMatch['components']);
          } else {
            itemsToAdd = [bestMatch];
          }

          for (var recipe in itemsToAdd) {
            int baseCals = getSafeValue(recipe, 'calories', 'kcal').toInt();
            int basePro = getSafeValue(recipe, 'protein').toInt();
            int baseCarb = getSafeValue(recipe, 'carbs', 'carbohydrate').toInt();
            int baseFat = getSafeValue(recipe, 'fat').toInt();

            final item = {
              'name': recipe['name'] ?? 'Unknown Recipe',
              'calories': (baseCals * quantity).toInt(),
              'protein': (basePro * quantity).toInt(),
              'carbs': (baseCarb * quantity).toInt(),
              'fat': (baseFat * quantity).toInt(),
              'image': recipe['image'] ?? '',
              'id': recipe['id'],
              'quantity': quantity,
              'base_calories': baseCals,
              'base_protein': basePro,
              'base_carbs': baseCarb,
              'base_fat': baseFat,
              'steps': recipe['steps'] ?? [],
              'ingredients': recipe['ingredients'] ?? [],
              'description': recipe['description'] ?? '',
              'nutrients': recipe['nutrients'] ?? {},
            };

            mealPlan[mealType]!.add(item);
          }
        }
      }

    } catch (e) {
      debugPrint("Error generating plan: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _removeFood(String meal, int index) {
    setState(() {
      mealPlan[meal]?.removeAt(index);
    });
  }

  // --- NEW: Helper to show details dialog ---
  void _showRecipeDetails(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecipeDetailsPage(
          recipe: item,
          selectedDate: widget.selectedDate,
        ),
      ),
    );
  }

  int _calculateMealCalories(String meal) {
    final items = mealPlan[meal] ?? [];
    int total = 0;
    for (var item in items) {
      total += (item['calories'] as num? ?? 0).toInt();
    }
    return total;
  }

  int _calculateTotalCalories() {
    int total = 0;
    for (var meal in meals) {
      total += _calculateMealCalories(meal);
    }
    return total;
  }

  Future<void> _saveMealPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    final dateKey = widget.selectedDate;
    final formattedDate = '${dateKey.day.toString().padLeft(2, '0')}-${dateKey.month.toString().padLeft(2, '0')}-${dateKey.year}';

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('meal_logs')
        .doc(formattedDate);

    try {
      Map<String, dynamic> updates = {};

      mealPlan.forEach((category, items) {
        if (items.isNotEmpty) {
          // Create a filtered map with ONLY the specific fields you need
          final itemsWithTime = items.map((item) => {
            'name': item['name'],
            'calories': item['calories'],
            'protein': item['protein'],
            'carbs': item['carbs'],
            'fat': item['fat'],
            'quantity': item['quantity'],
            'base_calories': item['base_calories'],
            'base_protein': item['base_protein'],
            'base_carbs': item['base_carbs'],
            'base_fat': item['base_fat'],
            'time': Timestamp.now(),
          }).toList();

          updates[category] = FieldValue.arrayUnion(itemsWithTime);
        }
      });

      if (updates.isNotEmpty) {
        await docRef.set(updates, SetOptions(merge: true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Meal plan saved for $formattedDate!')),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meal plan is empty!')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AI Meal Planner',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _generatePlan,
            tooltip: "Regenerate Plan",
          )
        ],
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _statusMessage ?? 'Generating Plan...',
              style: GoogleFonts.poppins(color: Colors.grey[600]),
            ),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Proposed Plan for ${widget.selectedDate.day}/${widget.selectedDate.month}/${widget.selectedDate.year}',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ...meals.map((meal) {
            final items = mealPlan[meal]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$meal',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.green[800]),
                        ),
                        Text(
                          '${_calculateMealCalories(meal)} kcal',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: Colors.grey[700]),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'No suggestion found.',
                          style: GoogleFonts.poppins(
                              color: Colors.grey[500], fontStyle: FontStyle.italic),
                        ),
                      )
                    else
                      ...List.generate(items.length, (index) {
                        final item = items[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          // Add interaction to show details
                          onTap: () => _showRecipeDetails(item),
                          leading: SizedBox( // <--- 1. Add SizedBox here
                            width: 50,
                            height: 50,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: item['image'] != '' && item['image'] != null
                                  ? Image.network(
                                item['image'],
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 50,
                                  height: 50,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.broken_image,
                                      size: 20, color: Colors.grey),
                                ),
                              )
                                  : Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey[200],
                                child: const Icon(Icons.restaurant,
                                    size: 20, color: Colors.grey),
                              ),
                            ),
                          ),
                          title: Text(item['name'],
                              style: GoogleFonts.poppins(
                                  fontSize: 14, fontWeight: FontWeight.w500)),
                          // Only show Calories here
                          subtitle: Text(
                              '${(item['quantity'] as num).toInt()} serving(s) • ${item['calories']} kcal',
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey[600])),
                          trailing: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.redAccent, size: 20),
                            onPressed: () => _removeFood(meal, index),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            );
          }).toList(),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[100]!)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Daily Total",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, color: Colors.blue[900])),
                Text("${_calculateTotalCalories()} kcal",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: Colors.blue[900])),
              ],
            ),
          ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saveMealPlan,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: Text(
              'Accept & Save Meal Plan',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
