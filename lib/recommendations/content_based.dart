import 'dart:convert'; // Needed for JSON
import 'package:flutter/services.dart'; // Needed for rootBundle
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ContentBasedRecommender {
  final Map<String, dynamic> userData;

  ContentBasedRecommender({required this.userData});

  // --- 1. Add Helper to Load Recipes (Same as Hybrid) ---
  Future<List<Map<String, dynamic>>> loadRecipes() async {
    final String data = await rootBundle.loadString('assets/recipes.json');
    final List<dynamic> jsonResult = json.decode(data);
    return jsonResult.cast<Map<String, dynamic>>();
  }

  // --- 2. Main Recommend Method (Testing Only) ---
  Future<List<Map<String, dynamic>>> recommend({int topN = 10}) async {
    final allRecipes = await loadRecipes();
    final user = FirebaseAuth.instance.currentUser;

    // A. Fetch Logs (To get accurate Smart Targets)
    Map<String, dynamic> fetchedLogs = {};
    if (user != null) {
      try {
        final logsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meal_logs')
            .get();
        for (var doc in logsSnapshot.docs) {
          fetchedLogs[doc.id] = doc.data();
        }
      } catch (e) {
        print("Error fetching logs in CB recommender: $e");
      }
    }

    // B. Calculate Smart Target
    final smartTarget = calculateSmartTarget(fetchedLogs);

    // C. Score Recipes
    List<Map<String, dynamic>> scoredRecipes = allRecipes.map((r) {
      final double score = calculateScore(r, smartTarget);

      return {
        ...r,
        'hybridScore': score, // For compatibility with UI, we map CB score to Hybrid score
        'contentScore': score,
        'cfScore': 0.0,
      };
    }).toList();

    // D. Sort
    scoredRecipes.sort((a, b) => (b['hybridScore'] as double).compareTo(a['hybridScore'] as double));

    // --- PRINT DEBUG LOGS (MATCHING HYBRID FORMAT) ---
    print("🏆 Top $topN recipes (Content-Based Only):");
    for (var r in scoredRecipes.take(topN)) {
      print(
          " - ${r['name']} | CB: ${(r['contentScore'] as double).toStringAsFixed(4)}");
    }

    return scoredRecipes.take(topN).toList();
  }

  // --- (Existing Helper Methods below remain unchanged) ---

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, double> calculateConsumedToday([Map<String, dynamic>? externalLogs]) {
    double consumedCalories = 0, consumedProtein = 0, consumedCarbs = 0, consumedFat = 0;

    final today = DateTime.now();
    final todayKey =
        "${today.day.toString().padLeft(2, '0')}-${today.month.toString().padLeft(2, '0')}-${today.year}";

    final allLogs = externalLogs ?? userData['meal_logs'];

    if (allLogs is Map) {
      final mealsToday = allLogs[todayKey] ?? {};
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

  Map<String, double> calculateSmartTarget([Map<String, dynamic>? externalLogs]) {
    final consumed = calculateConsumedToday(externalLogs);
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

  double calculateScore(Map<String, dynamic> recipe, Map<String, double> remaining) {
    double score = 0;

    final nutrients = recipe['nutrients'] ?? {};
    final double calories = _toInt(nutrients['calories'] ?? nutrients['kcal']).toDouble();
    final double protein = _toInt(nutrients['protein']).toDouble();
    final double carbs = _toInt(nutrients['carbs']).toDouble();
    final double fat = _toInt(nutrients['fat']).toDouble();

    final double targetCalories = remaining['calories']!;
    final double targetProtein = remaining['protein']!;
    final double targetCarbs = remaining['carbs']!;
    final double targetFat = remaining['fat']!;

    if (targetCalories == 0 && calories > 200) return 0;

    final fitnessGoal = (userData['fitnessGoal'] ?? 'maintain').toString().toLowerCase();
    double proteinWeight = 0.15, carbWeight = 0.075, fatWeight = 0.075;
    double fitnessBonus = 0.0;

    if (fitnessGoal.contains('lose') || fitnessGoal.contains('reduce')) {
      proteinWeight = 0.2;
      carbWeight = 0.05;
      fatWeight = 0.05;
      if (calories <= targetCalories) fitnessBonus += 0.03;
      if (protein >= targetProtein) fitnessBonus += 0.03;
    } else if (fitnessGoal.contains('gain') || fitnessGoal.contains('build')) {
      proteinWeight = 0.15;
      carbWeight = 0.1;
      fatWeight = 0.1;
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
    score += (1 - calPenalty).clamp(0.0, 1.0) * 0.44;

    double macroScore(double amount, double target, double weight) {
      double diffRatio = target > 0 ? ((amount - target) / target).abs() : amount / 30.0;
      return (1 - (diffRatio.clamp(0.0, 1.0) * diffRatio.clamp(0.0, 1.0))) * weight;
    }

    score += macroScore(protein, targetProtein, proteinWeight);
    score += macroScore(carbs, targetCarbs, carbWeight);
    score += macroScore(fat, targetFat, fatWeight);
    score += fitnessBonus;

    final subcategory = (recipe['subcategory'] ?? '').toString().toLowerCase();
    final dishType = (recipe['dish_type'] ?? '').toString().toLowerCase();

    if (userData['preferredMeal'] != null) {
      final preferred = userData['preferredMeal'].toString().toLowerCase();
      if (subcategory.contains(preferred) || dishType.contains(preferred)) score += 0.15;
    }

    if (userData['preferredDifficulty'] != null) {
      final difficulty = userData['preferredDifficulty'].toString().toLowerCase();
      if ((recipe['difficult'] ?? '').toString().toLowerCase() != difficulty) score -= 0.05;
    }

    return score.clamp(0.0, 1.0);
  }
}
