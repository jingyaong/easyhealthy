import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HybridRecommender {
  final Map<String, dynamic> userData;
  final DateTime? selectedDate;

  HybridRecommender({
    required this.userData,
    required this.selectedDate,
  });

  // ADD THIS METHOD
  Future<void> init() async {
    // If you need to preload heavy data (like vectors), do it here.
    // For now, it can be empty or just pre-load recipes.
    await loadRecipes();
  }


  /// Load all recipes from JSON
  Future<List<Map<String, dynamic>>> loadRecipes() async {
    final String data = await rootBundle.loadString('assets/recipes.json');
    final List<dynamic> jsonResult = json.decode(data);
    return jsonResult.cast<Map<String, dynamic>>();
  }

  /// ---------------- Content-Based Helpers ----------------

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // UPDATED: Accepts external logs if fetched
  Map<String, double> _calculateConsumedToday([Map<String, dynamic>? externalLogs]) {
    double consumedCalories = 0, consumedProtein = 0, consumedCarbs = 0, consumedFat = 0;

    // USE TARGET DATE IF AVAILABLE, OTHERWISE TODAY
    final dateToUse = selectedDate ?? DateTime.now();

    final dateKey =
        "${dateToUse.day.toString().padLeft(2, '0')}-${dateToUse.month.toString().padLeft(2, '0')}-${dateToUse.year}";

    // Use fetched logs if available, otherwise fallback to userData
    final allLogs = externalLogs ?? userData['meal_logs'];

    if (allLogs is Map) {
      // Look for the correct dateKey
      final mealsToday = allLogs[dateKey] ?? {};
      if (mealsToday is Map) {
        mealsToday.forEach((mealType, mealItems) {
          if (mealItems is List) {
            for (var item in mealItems) {
              consumedCalories += _toInt(item['calories']).toDouble();
              consumedProtein += _toInt(item['protein']).toDouble();
              consumedCarbs += _toInt(item['carbs']).toDouble();
              consumedFat += _toInt(item['fat']).toDouble();
            }
          }
        });
      }
    }

    return {
      'calories': consumedCalories,
      'protein': consumedProtein,
      'carbs': consumedCarbs,
      'fat': consumedFat,
    };
  }

  double _calculateContentScore(Map<String, dynamic> recipe, Map<String, double> remaining) {
    double score = 0;

    final nutrients = recipe['nutrients'] ?? {};
    final double calories = _toInt(nutrients['kcal']).toDouble();
    final double protein = _toInt(nutrients['protein']).toDouble();
    final double carbs = _toInt(nutrients['carbs']).toDouble();
    final double fat = _toInt(nutrients['fat']).toDouble();

    final double targetCalories = remaining['calories']!;
    final double targetProtein = remaining['protein']!;
    final double targetCarbs = remaining['carbs']!;
    final double targetFat = remaining['fat']!;

    if (targetCalories == 0 && calories > 200) return 0;

    final fitnessGoal = (userData['fitnessGoal'] ?? 'maintain').toString().toLowerCase();
    double proteinWeight = 0.25, carbWeight = 0.10, fatWeight = 0.15;
    double fitnessBonus = 0.0;

    if (fitnessGoal.contains('lose') || fitnessGoal.contains('reduce')) {
      proteinWeight = 0.30;
      carbWeight = 0.05;
      fatWeight = 0.15;
      if (calories <= targetCalories) fitnessBonus += 0.03;
      if (protein >= targetProtein) fitnessBonus += 0.03;
    } else if (fitnessGoal.contains('gain') || fitnessGoal.contains('build')) {
      proteinWeight = 0.20;
      carbWeight = 0.20;
      fatWeight = 0.10;
      if (calories >= targetCalories) fitnessBonus += 0.03;
      if (protein >= targetProtein) fitnessBonus += 0.03;
    } else {
      if ((calories - targetCalories).abs() <= targetCalories * 0.1) fitnessBonus += 0.03;
      if ((protein - targetProtein).abs() <= targetProtein * 0.2) fitnessBonus += 0.03;
    }

    double calDiff = calories - targetCalories;
    double calPenalty = 0.0;
    if (targetCalories > 0) {
      if (fitnessGoal.contains('lose') && calDiff > 0) calPenalty = calDiff / targetCalories;
      else if (fitnessGoal.contains('gain') && calDiff < 0) calPenalty = -calDiff / targetCalories;
      else calPenalty = (calDiff.abs() / targetCalories);
    } else {
      calPenalty = calories / 500.0;
    }
    score += (1 - calPenalty).clamp(0.0, 1.0) * 0.32;

    double macroScore(double amount, double target, double weight) {
      double diffRatio = target > 0 ? ((amount - target) / target).abs() : amount / 30.0;
      return (1 - (diffRatio.clamp(0.0, 1.0) * diffRatio.clamp(0.0, 1.0))) * weight;
    }

    score += macroScore(protein, targetProtein, proteinWeight);
    score += macroScore(carbs, targetCarbs, carbWeight);
    score += macroScore(fat, targetFat, fatWeight);
    score += fitnessBonus;

    return score.clamp(0.0, 1.0);
  }

  // Helper to merge a main dish with a side dish
  Map<String, dynamic> _createCombo(Map<String, dynamic> main, Map<String, dynamic> side) {
    // 1. Create a list of components
    List<Map<String, dynamic>> components = [];
    if (main['components'] != null) {
      components.addAll(List<Map<String, dynamic>>.from(main['components']));
    } else {
      components.add(main);
    }
    components.add(side);

    // 2. Sum up the nutrients properly
    double totalCals = 0;
    double totalPro = 0;
    double totalCarbs = 0;
    double totalFat = 0;

    for (var c in components) {
      totalCals += _toInt(c['nutrients']?['kcal']).toDouble();
      totalPro += _toInt(c['nutrients']?['protein']).toDouble();
      totalCarbs += _toInt(c['nutrients']?['carbs']).toDouble();
      totalFat += _toInt(c['nutrients']?['fat']).toDouble();
    }

    // 3. Return the new Combo Object with CORRECT TOTALS
    return {
      'id': "${main['id']}_plus_${side['id']}", // Create unique ID
      'name': main['name'], // Keep main name for display (or append side name if you prefer)
      'image': main['image'],
      'dish_type': main['dish_type'], // Keep main category
      'subcategory': main['subcategory'],
      'components': components, // Store the list so we can print it later

      // ✅ CRITICAL FIX: The new combined nutrients
      'nutrients': {
        'kcal': totalCals,
        'protein': totalPro,
        'carbs': totalCarbs,
        'fat': totalFat,
      },

      // Inherit other fields to avoid null errors
      'ingredients': main['ingredients'],
      'time': main['time'],
    };
  }

  // UPDATED: Accepts external logs
  Map<String, double> _calculateSmartTarget([Map<String, dynamic>? externalLogs]) {
    final consumed = _calculateConsumedToday(externalLogs);
    final dailyConsume = userData['daily_consume_goal'] ?? {};
    double totalCalGoal = _toInt(dailyConsume['calories']).toDouble();
    double totalProGoal = _toInt(dailyConsume['protein']).toDouble();
    double totalCarbGoal = _toInt(dailyConsume['carbs']).toDouble();
    double totalFatGoal = _toInt(dailyConsume['fat']).toDouble();

    double remCal = (totalCalGoal - consumed['calories']!).clamp(0.0, double.infinity);
    double remPro = (totalProGoal - consumed['protein']!).clamp(0.0, double.infinity);
    double remCarb = (totalCarbGoal - consumed['carbs']!).clamp(0.0, double.infinity);
    double remFat = (totalFatGoal - consumed['fat']!).clamp(0.0, double.infinity);

    return {
      'calories': remCal < 50 ? 50 : remCal,
      'protein': remPro < 5 ? 5 : remPro,
      'carbs': remCarb < 5 ? 5 : remCarb,
      'fat': remFat < 5 ? 5 : remFat,
    };
  }

  /// ---------------- Collaborative Helpers ----------------

  double _ingredientSimilarity(List<String> a, List<String> b) {
    final setA = a.map((e) => e.toLowerCase()).toSet();
    final setB = b.map((e) => e.toLowerCase()).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  /// ---------------- Hybrid Recommendation ----------------

  Future<List<Map<String, dynamic>>> recommend({
    int topN = 10,
    double cbWeight = 0.7,
    double cfWeight = 0.3,
    String? categoryFilter,
    int? targetCalories,
    int? targetProtein,
    int? targetCarbs,
    int? targetFat,
    List<String>? avoidRecipes,
  }) async {
    final allRecipes = await loadRecipes();
    final user = FirebaseAuth.instance.currentUser;

    // 1️⃣ FETCH LOGS & SAVED RECIPES: Manually fetch subcollections
    Map<String, dynamic> fetchedLogs = {};
    final savedNames = <String>{};
    final savedIds = <String>{};

    if (user != null) {
      try {
        // A. Fetch Meal Logs
        final logsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meal_logs')
            .get();

        for (var doc in logsSnapshot.docs) {
          fetchedLogs[doc.id] = doc.data();
        }

        // B. Fetch Saved Recipes
        final savedSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('saved_recipes')
            .get();

        for (var doc in savedSnapshot.docs) {
          final data = doc.data();
          final name = data['name']?.toString();
          if (name != null && name.isNotEmpty) {
            savedNames.add(name);
          }
          savedIds.add(doc.id);
        }

      } catch (e) {
        print("Error fetching data in recommender: $e");
      }
    }

    // ---------------------------------------------------------
    // 2️⃣ DEFINE SMART TARGETS (Dual Mode)
    // ---------------------------------------------------------
    Map<String, double> smartTarget;

    // SCENARIO A: Strict Mode (Meal Planner passed specific values)
    if (targetCalories != null && targetCalories > 0) {
      smartTarget = {
        'calories': targetCalories.toDouble(),
        // If protein is passed, use it. If not, default to 0 (or a safe ratio)
        'protein': (targetProtein ?? 0).toDouble(),
        'carbs': (targetCarbs ?? 0).toDouble(),
        'fat': (targetFat ?? 0).toDouble(),
      };

      // Fallback: If macros weren't passed but calories were, estimate macros
      if (smartTarget['protein'] == 0) {
        // Default balanced split: 25% Pro / 45% Carb / 30% Fat
        smartTarget['protein'] = (smartTarget['calories']! * 0.25) / 4;
        smartTarget['carbs'] = (smartTarget['calories']! * 0.45) / 4;
        smartTarget['fat'] = (smartTarget['calories']! * 0.30) / 9;
      }

    }
    // SCENARIO B: General Mode (Discover Page - No targets passed)
    else {
      // 1. Calculate what is remaining for the day based on logs
      var remainingDaily = _calculateSmartTarget(fetchedLogs);

      // 2. Pick a "Standard Meal Size" (e.g. 35% of remaining daily needs)
      // If the user has already eaten everything, default to a standard 600kcal meal.
      double remainingCals = (remainingDaily['calories'] ?? 0).toDouble();

      if (remainingCals <= 0) {
        // Fallback if user exceeded goals: Suggest a light, healthy meal
        smartTarget = {
          'calories': 500,
          'protein': 30,
          'carbs': 50,
          'fat': 15
        };
      } else {
        // Normal case: Suggest a meal that takes up ~35% of remaining budget
        double ratio = 0.35;
        smartTarget = {
          'calories': remainingCals * ratio,
          'protein': (remainingDaily['protein'] ?? 0) * ratio,
          'carbs': (remainingDaily['carbs'] ?? 0) * ratio,
          'fat': (remainingDaily['fat'] ?? 0) * ratio,
        };
      }
    }

    // 3️⃣ Parse logged meals history
    final loggedMeals = <String>{};
    final eatenToday = <String>{};

    // Date Parsing Setup
    final targetDate = selectedDate ?? DateTime.now();
    final simpleTarget = "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";

    Map<String, dynamic> combinedLogs = {};

    // Merge logs from UserData and Manual Fetch
    if (userData.containsKey('meal_logs') && userData['meal_logs'] is Map) {
      combinedLogs.addAll(Map<String, dynamic>.from(userData['meal_logs']));
    }
    combinedLogs.addAll(fetchedLogs);

    if (combinedLogs.isNotEmpty) {
      combinedLogs.forEach((dateKey, mealsRaw) {

        // --- 1. Robust Date Check ---
        bool isSameDay = false;

        // Check A: Exact String Match
        if (dateKey == simpleTarget) {
          isSameDay = true;
        }
        // Check B: Parse YYYY-MM-DD vs DD-MM-YYYY
        else {
          try {
            List<String> parts = dateKey.split(RegExp(r'[-/]'));
            if (parts.length == 3) {
              int p1 = int.parse(parts[0]);
              int p2 = int.parse(parts[1]);
              int p3 = int.parse(parts[2]);

              DateTime? logDate;
              if (p1 > 31) logDate = DateTime(p1, p2, p3);
              else logDate = DateTime(p3, p2, p1);

              if (logDate.year == targetDate.year &&
                  logDate.month == targetDate.month &&
                  logDate.day == targetDate.day) {
                isSameDay = true;
              }
            }
          } catch (e) { /* Ignore parse errors */ }
        }

        // --- 2. Extract & Clean Meal Names ---
        if (mealsRaw is Map) {
          mealsRaw.forEach((mealType, items) {
            if (items is List) {
              for (var item in items) {
                String? name;

                // Handle complex object vs simple string
                if (item is Map) {
                  name = item['name']?.toString();
                } else if (item is String) {
                  name = item;
                }

                if (name != null && name.isNotEmpty) {
                  // --- AGGRESSIVE CLEANING (STEP 3) ---
                  String cleanName = name.toLowerCase().trim();
                  // 1. Remove [Tags]
                  cleanName = cleanName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
                  // 2. Replace & with 'and'
                  cleanName = cleanName.replaceAll('&', 'and');
                  // 3. Remove non-word chars
                  cleanName = cleanName.replaceAll(RegExp(r'[^\w\s]'), '');
                  // 4. Collapse spaces
                  cleanName = cleanName.replaceAll(RegExp(r'\s+'), ' ').trim();

                  loggedMeals.add(cleanName);

                  if (isSameDay) {
                    eatenToday.add(cleanName);
                  }
                }
              }
            }
          });
        }
      });
    }

    // DEBUG: Validate Cleaning
    print("--- LOGGED MEALS DEBUG ---");
    loggedMeals.forEach((m) => print("HISTORY ITEM: '$m'"));
    print("--------------------------");

    // 4️⃣ Combine History (Logged + Saved Names)
    final userHistory = loggedMeals.union(savedNames);

    // 5️⃣ Prepare user profile for Collaborative Filtering
    final userRecipes = allRecipes.where((r) => userHistory.contains(r['name'])).toList();
    final userIngredients = userRecipes
        .expand((r) => (r['ingredients'] as List<dynamic>).cast<String>())
        .toList();
    final userSubcategories = userRecipes
        .map((r) => (r['subcategory'] ?? '').toString().toLowerCase())
        .toSet();
    final userDishTypes = userRecipes
        .map((r) => (r['dish_type'] ?? '').toString().toLowerCase())
        .toSet();

    // 6️⃣ Score all recipes
    List<Map<String, dynamic>> allScoredRecipes = allRecipes.map((r) {
      // A. Calculate Content-Based Score
      final contentScore = _calculateContentScore(r, smartTarget);

      // B. Calculate Collaborative Filtering Score
      double cfScore = 0;
      if (userIngredients.isNotEmpty) {
        final ingredients = (r['ingredients'] as List<dynamic>).cast<String>();

        // 1. Ingredient Similarity (Weight: 0.5)
        cfScore = _ingredientSimilarity(ingredients, userIngredients) * 0.5;

        // 2. Subcategory Similarity (Weight: 0.1)
        final subcat = (r['subcategory'] ?? '').toString().toLowerCase();
        if (subcat.isNotEmpty) {
          cfScore += _ingredientSimilarity([subcat], userSubcategories.toList()) * 0.1;
        }

        // 3. Dish Type Similarity (Weight: 0.1)
        final dishType = (r['dish_type'] ?? '').toString().toLowerCase();
        if (dishType.isNotEmpty) {
          cfScore += _ingredientSimilarity([dishType], userDishTypes.toList()) * 0.1;
        }
      }

      // Add boost for being saved directly to the CF score.
      if (savedIds.contains(r['id'])) {
        cfScore += 0.3;
      }

      // Explicitly clamp the raw CF score to 1.0 right here.
      cfScore = cfScore.clamp(0.0, 1.0);

      return {...r, 'contentScore': contentScore, 'cfScore': cfScore};
    }).toList();

    // Initialize the working list from the master scored list
    List<Map<String, dynamic>> scoredRecipes = List.from(allScoredRecipes);

    // 7️⃣ Normalize and Combine Scores
    scoredRecipes = scoredRecipes.map((r) {
      double normContent = r['contentScore'] as double;
      double normCF = r['cfScore'] as double;

      // Calculate the final weighted hybrid score
      double hybridScore = (normContent * cbWeight + normCF * cfWeight);

      // --- CRITICAL FIX START ---
      // 1. Get the raw name
      String rawName = (r['name'] ?? '').toString();

      // 2. Clean it EXACTLY the same way we cleaned the history in Step 3
      String cleanRecipeName = rawName.toLowerCase().trim();

      // 1. Remove [Tags]
      cleanRecipeName = cleanRecipeName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      // 2. Replace & with 'and'
      cleanRecipeName = cleanRecipeName.replaceAll('&', 'and');
      // 3. Remove non-word chars
      cleanRecipeName = cleanRecipeName.replaceAll(RegExp(r'[^\w\s]'), '');
      // 4. Collapse spaces
      cleanRecipeName = cleanRecipeName.replaceAll(RegExp(r'\s+'), ' ').trim();

      // 3. Now check against the history
      bool foundInHistory = false;

      // Debug specific difficult items
      if (cleanRecipeName.contains('smoked salmon')) {
        print("CHECKING RECIPE: '$cleanRecipeName'");
        print("AGAINST HISTORY: $loggedMeals");
      }

      if (loggedMeals.contains(cleanRecipeName)) {
        foundInHistory = true;
      } else {
        for (var logName in loggedMeals) {
          if (logName.length < 4) continue;
          if (cleanRecipeName.contains(logName) || logName.contains(cleanRecipeName)) {
            foundInHistory = true;
            break;
          }
        }
      }
      // --- CRITICAL FIX END ---

      if (foundInHistory) {
        hybridScore *= 0.5; // Penalty applied!
        // print("📉 PENALTY APPLIED TO: $cleanRecipeName");
      }

      // --- NEW: AVOID DUPLICATES ACROSS MEALS ---
      if (avoidRecipes != null) {
        // Check if this recipe OR any of its components are in the avoid list
        String name = (r['name'] ?? '').toString().toLowerCase();

        bool shouldAvoid = false;

        // Check main name
        if (avoidRecipes.any((avoid) => name.contains(avoid.toLowerCase()))) {
          shouldAvoid = true;
        }

        // If strict match fails, try fuzzy match
        for (var avoid in avoidRecipes) {
          if (name == avoid.toLowerCase()) shouldAvoid = true;
        }

        if (shouldAvoid) {
          hybridScore *= 0.1; // Nuclear penalty (Make it impossible to pick)
        }
      }

      return {
        ...r,
        'contentScore': normContent.clamp(0.0, 1.0),
        'cfScore': normCF.clamp(0.0, 1.0),
        'hybridScore': hybridScore.clamp(0.0, 1.0)
      };
    }).toList();

    scoredRecipes.sort((a, b) {
      double scoreA = (a['hybridScore'] as num).toDouble();
      double scoreB = (b['hybridScore'] as num).toDouble();
      return scoreB.compareTo(scoreA); // Descending (High to Low)
    });

    // 8. APPLY CATEGORY FILTER
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      final inputFilter = categoryFilter.toLowerCase();

      // We will define a strict list of ALLOWED types/subcategories for each filter.
      // These must match the strings in your JSON exactly (ignoring case).
      List<String> allowedTypes = [];

      if (inputFilter == 'snacks') {
        allowedTypes.addAll([
          'snacks recipes',
          'healthy snack recipes',
          // Subcategories
          'desserts',
          'storecupboard',
          'breakfast recipes',
          'cheese recipes',

          // Dish Types
          'apple dessert recipes',
          'chocolate desserts',
          'easy dessert recipes',
          'healthy dessert recipes',
          'breakfast muffins',
          'breakfast smoothies',
          'blue cheese recipes',
          'cheddar recipes',
          'goat\'s cheese recipes',
          'halloumi recipes'
        ]);
      }
      else if (inputFilter == 'lunch') {
        allowedTypes.addAll([
          // Subcategories
          'lunch recipes',
          'storecupboard',
          'meat',
          'fish and seafood',
          'pasta',
          'vegan',
          'vegetarian',
          'chicken',
          'cheese recipes',
          'desserts',

          // Dish Types
          'dinner-to-lunch recipes',
          'family lunch recipes',
          'healthy lunch recipes',
          'healthy packed lunches',
          'quick lunch recipes',
          'pasta salad recipes',
          'vegan soup recipes',
          'pasta recipes',
          'quick pasta recipes',

          // Legumes/Sides for Lunch Bowls
          'runner bean recipes',
          'black bean recipes',
          'broad bean recipes',
          'kidney bean recipes'
        ]);
      }
      else if (inputFilter == 'dinner') {
        allowedTypes.addAll([
          // Subcategories (Broad Categories)
          'dinner recipes',
          'meat',
          'fish and seafood',
          'pasta',
          'vegan',
          'vegetarian',
          'chicken',
          'cheese recipes',
          'storecupboard',
          'desserts',

          // Dish Types (Specific Mains)
          'beef slow cooker',
          'black bean recipes',
          'broad bean recipes',
          'chicken breast recipes',
          'chicken casseroles',
          'chicken mince recipes',
          'chicken thigh recipes',
          'chilli con carne recipes',
          'diced beef recipes',
          'easy dinner recipes',
          'easy vegan recipes',
          'easy vegetarian recipes',
          'fish pie recipes',
          'healthy fish recipes',
          'kidney bean recipes',
          'lamb chop recipes',
          'one pot recipes',
          'pasta bake recipes',
          'pasta recipes',
          'pork chop recipes',
          'quick pasta recipes',
          'runner bean recipes',
          'seafood paella recipes',
          'spaghetti recipes',
          'vegan dinner recipes',
          'vegan pasta recipes',
          'vegetarian dinners',
          'vegetarian pasta recipes',
          'vegetarian slow cooker',
          'white fish recipes'
        ]);
      }
      else if (inputFilter == 'breakfast') {
        allowedTypes.addAll([
          // Subcategories
          'breakfast recipes',
          'storecupboard',
          'desserts',
          'meat',
          'fish and seafood',
          'pasta',
          'vegan',
          'vegetarian',
          'chicken',
          'cheese recipes',

          // Dish Types
          'breakfast muffins',
          'breakfast pancakes',
          'breakfast smoothies',
          'overnight oat recipes',
          'easy vegetarian recipes'
        ]);
      }

      scoredRecipes = scoredRecipes.where((r) {
        // Get the exact strings from the recipe
        final sub = (r['subcategory'] ?? '').toString().toLowerCase().trim();
        final dish = (r['dish_type'] ?? '').toString().toLowerCase().trim();

        // Check if the recipe's Category or Dish Type exists in our Allowed List
        // We use 'contains' to allow partial matches if the JSON has extra spaces,
        // but it is checking against your specific list.
        for (var type in allowedTypes) {
          if (sub == type || dish == type) {
            return true;
          }
        }
        return false;
      }).toList();
    }

    // ---------------------------------------------------------
// 8️⃣ COMBO LOGIC: Dynamic Gap Filling (Any number of items)
// ---------------------------------------------------------
    if (targetCalories != null && targetCalories > 0) {

      // Threshold helper
      bool hasGap(Map<String, dynamic> item) {
        double cals = _toInt(item['nutrients']?['kcal']).toDouble();
        double pro = _toInt(item['nutrients']?['protein']).toDouble();
        double carbs = _toInt(item['nutrients']?['carbs']).toDouble();
        double fat = _toInt(item['nutrients']?['fat']).toDouble();

        double targetPro = smartTarget['protein'] ?? 0;
        double targetCarbs = smartTarget['carbs'] ?? 0;
        double targetFat = smartTarget['fat'] ?? 0;

        // Gap if below 90-95% of target
        bool lowCals = cals < targetCalories * 0.90;
        bool lowPro = targetPro > 10 && pro < targetPro * 0.90;
        bool lowCarbs = targetCarbs > 10 && carbs < targetCarbs * 0.90;
        bool lowFat = targetFat > 10 && fat < targetFat * 0.85;

        return lowCals || lowPro || lowCarbs || lowFat;
      }

      List<Map<String, dynamic>> finalCombos = [];

      // Start with top candidates
      List<Map<String, dynamic>> candidates = scoredRecipes.take(5).toList();

      for (var baseItem in candidates) {
        var currentCombo = baseItem;
        int itemsAdded = 0;
        const int maxItems = 4;

        while (itemsAdded < maxItems && hasGap(currentCombo)) {

          double currentCals = _toInt(currentCombo['nutrients']?['kcal']).toDouble();
          double currentPro = _toInt(currentCombo['nutrients']?['protein']).toDouble();
          double currentCarbs = _toInt(currentCombo['nutrients']?['carbs']).toDouble();
          double currentFat = _toInt(currentCombo['nutrients']?['fat']).toDouble();

          double missingCals = (targetCalories - currentCals).clamp(0.0, double.infinity);
          double missingPro = ((smartTarget['protein'] ?? 0) - currentPro).clamp(0.0, double.infinity);
          double missingCarbs = ((smartTarget['carbs'] ?? 0) - currentCarbs).clamp(0.0, double.infinity);
          double missingFat = ((smartTarget['fat'] ?? 0) - currentFat).clamp(0.0, double.infinity);

          double maxSideCals = missingCals * 1.4;
          if (maxSideCals < 250) maxSideCals = 250;

          // Filter valid sides
          var potentialSides = allScoredRecipes.where((r) {
            // Avoid duplicates
            if (r['id'] == currentCombo['id']) return false;
            if (currentCombo['components'] != null) {
              if ((currentCombo['components'] as List).any((c) => c['id'] == r['id'])) return false;
            }

            // Avoid meals in avoidRecipes
            if (avoidRecipes != null) {
              String rName = (r['name'] ?? '').toString().toLowerCase();
              if (avoidRecipes.any((avoid) => rName.contains(avoid.toLowerCase()))) return false;
            }

            double sideCals = _toInt(r['nutrients']?['kcal']).toDouble();
            double sidePro = _toInt(r['nutrients']?['protein']).toDouble();
            double sideCarbs = _toInt(r['nutrients']?['carbs']).toDouble();
            double sideFat = _toInt(r['nutrients']?['fat']).toDouble();

            // Calorie filter
            if (sideCals < 40 || sideCals > maxSideCals) return false;

            // Fat filter if over target
            double fatBuffer = (smartTarget['fat'] ?? 0) * 0.2;
            if (currentFat > (smartTarget['fat'] ?? 0) && sideFat > fatBuffer) return false;

            return true;
          }).toList();

          if (potentialSides.isEmpty) break;

          // Sort by simple macro closeness
          potentialSides.sort((a, b) {
            double score(Map<String, dynamic> item) {
              double p = _toInt(item['nutrients']?['protein']).toDouble();
              double c = _toInt(item['nutrients']?['carbs']).toDouble();
              double f = _toInt(item['nutrients']?['fat']).toDouble();
              double k = _toInt(item['nutrients']?['kcal']).toDouble();

              // Sum of relative differences
              double score =
                  (missingPro - p).abs() / ((missingPro < 1) ? 1 : missingPro) +
                      (missingCarbs - c).abs() / ((missingCarbs < 1) ? 1 : missingCarbs) +
                      (missingFat - f).abs() / ((missingFat < 1) ? 1 : missingFat) +
                      (missingCals - k).abs() / ((missingCals < 1) ? 1 : missingCals);

              return score;
            }

            return score(a).compareTo(score(b));
          });

          var bestSide = potentialSides.first;
          currentCombo = _createCombo(currentCombo, bestSide);
          itemsAdded++;
        }

        if (itemsAdded > 0) {
          currentCombo['contentScore'] = _calculateContentScore(currentCombo, smartTarget);

          if (currentCombo['components'] != null) {
            var comps = (currentCombo['components'] as List);
            currentCombo['cfScore'] = comps.map((c) => (c['cfScore'] ?? 0.0).toDouble()).reduce((a, b) => a + b) / comps.length;
          }

          currentCombo['hybridScore'] = ((currentCombo['contentScore'] as double) * cbWeight) +
              ((currentCombo['cfScore'] as double) * cfWeight);

          finalCombos.add(currentCombo);
        }
      }

      scoredRecipes.addAll(finalCombos);
    }

    // Sort by the final hybrid score
    scoredRecipes.sort((a, b) => (b['hybridScore'] as double).compareTo(a['hybridScore'] as double));

    // --- Remove Duplicates based on Name ---
    final seen = <String>{};
    final uniqueRecipes = scoredRecipes.where((r) {
      final name = r['name'] as String;
      if (seen.contains(name)) return false;
      seen.add(name);
      return true;
    }).toList();

    print("🏆 Top $topN recipes (Category: ${categoryFilter ?? 'All'}, History: ${userHistory.length}):");
    for (var r in uniqueRecipes.take(topN)) {
      String mealName = r['name'];

      // Get the category to confirm it matches what you asked for
      String category = (r['dish_type'] ?? 'Unknown').toString().toUpperCase();

      // Check if it's a combo and print the details
      if (r['components'] != null && (r['components'] as List).length > 1) {
        var comps = (r['components'] as List);
        var sideNames = comps.skip(1).map((c) => c['name']).join(' + ');
        mealName = "${comps.first['name']} [Sides: $sideNames]";
      }

      print(
          " - [$category] $mealName | "
              "Hyb: ${(r['hybridScore'] as double).toStringAsFixed(4)} | "
              "CB: ${(r['contentScore'] as double).toStringAsFixed(4)} | "
              "CF: ${(r['cfScore'] as double).toStringAsFixed(4)} | "
              "Kcal: ${_toInt(r['nutrients']?['kcal'])}"
      );
    }

    return uniqueRecipes.take(topN).toList();
  }
}
