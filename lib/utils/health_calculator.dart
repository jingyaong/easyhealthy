import 'dart:math';
import '../model/ActivityLevel.dart';

class HealthCalculator {

  // Looks up the multiplier based on the label string (e.g., "Sedentary")
  static double _findMultiplier(String levelLabel) {
    try {
      // Case-insensitive match to find the correct ActivityLevel object
      final activity = activityLevels.firstWhere(
            (a) => a.label.toLowerCase() == levelLabel.toLowerCase(),
        orElse: () => activityLevels[0], // Default to Sedentary if not found
      );
      return activity.multiplier;
    } catch (e) {
      return 1.2; // Fallback
    }
  }

  // --- Daily Intake Goals ---
  static Map<String, int> calculateDailyNutrientGoals({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
    required String activityLevel,
    required String fitnessGoal,
  }) {
    // 1. Reuse existing BMR calculation
    double bmr = calculateBMR(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    );

    // 2. Use centralized multiplier from ActivityLevel.dart
    double multiplier = _findMultiplier(activityLevel);

    // 3. Calculate TDEE
    double tdee = bmr * multiplier;

    // 4. Adjust for Fitness Goal
    double targetCalories = tdee;
    final goal = fitnessGoal.toLowerCase();

    // -- MACRO RATIOS (Defaults to Balanced/Maintenance) --
    double proteinRatio = 0.30;
    double fatRatio = 0.30;
    double carbsRatio = 0.40;

    // LOGIC GROUP 1: WEIGHT LOSS
    if (goal.contains('lose') || goal.contains('reduce')) {
      targetCalories = tdee - 500;
      proteinRatio = 0.40;
      fatRatio = 0.35;
      carbsRatio = 0.25;
    }

    // LOGIC GROUP 2: GAIN / BUILD
    else if (goal.contains('gain') || goal.contains('build')) {
      targetCalories = tdee + 300;
      proteinRatio = 0.30;
      fatRatio = 0.25;
      carbsRatio = 0.45;
    }

    // LOGIC GROUP 3: MAINTENANCE / TONE / STRENGTH
    else {
      targetCalories = tdee;
      proteinRatio = 0.30;
      fatRatio = 0.30;
      carbsRatio = 0.40;
    }

    // Safety floors
    if (gender == 'Male' && targetCalories < 1500) targetCalories = 1500;
    if (gender == 'Female' && targetCalories < 1200) targetCalories = 1200;

    return {
      'calories': targetCalories.round(),
      'protein': ((targetCalories * proteinRatio) / 4).round(),
      'fat': ((targetCalories * fatRatio) / 9).round(),
      'carbs': ((targetCalories * carbsRatio) / 4).round(),
    };
  }


  static int calculateRecommendedCalorieBurn({
    required double bmi,
    double? weightKg,
    double? heightCm,
    int? age,
    String? gender,
    double? activityMultiplier,
    String activityLevel = "Sedentary",
    String? fitnessGoal,
  }) {
    // TIER 1: Basic BMI
    int baseBurn;
    if (bmi < 18.5) baseBurn = 250;
    else if (bmi < 25) baseBurn = 350;
    else if (bmi < 30) baseBurn = 450;
    else baseBurn = 400;

    if (weightKg == null || heightCm == null || age == null || gender == null) {
      return _roundTo50(baseBurn);
    }

    // TIER 2: Reuse BMR Logic
    double bmr = calculateBMR(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender
    );

    // Use provided multiplier OR look it up from the list
    double multiplier = activityMultiplier ?? _findMultiplier(activityLevel);

    // TIER 3: TDEE
    double tdee = bmr * multiplier;
    double burnGoal = tdee * 0.12;

    // TIER 4: Goal Adjustment
    if (fitnessGoal != null) {
      final goal = fitnessGoal.toLowerCase();
      if (goal.contains("lose") || goal.contains("reduce")) {
        burnGoal = tdee * 0.15;
      } else if (goal.contains("gain") || goal.contains("build")) {
        burnGoal = max(burnGoal, 300);
      } else if (goal.contains("maintain")) {
        burnGoal = tdee * 0.10;
      }
    }

    return _roundTo50(burnGoal.clamp(200, 800).toInt());
  }

  // --- UTILITIES ---

  static double calculateBMI(double weightKg, double heightCm) {
    if (heightCm <= 0) return 0.0;
    final double heightM = heightCm / 100;
    final double bmi = weightKg / (heightM * heightM);
    return (bmi * 10).round() / 10;
  }

  static double calculateBMR({
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
  }) {
    if (weightKg <= 0 || heightCm <= 0 || age <= 0) return 0.0;
    double bmr;
    if (gender == 'Male') {
      bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) + 5;
    } else {
      bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * age) - 161;
    }
    return (bmr).round().toDouble();
  }

  static List<String> getFitnessGoalsForBMI(double bmi) {
    if (bmi <= 0) return ['Maintain weight', 'Lose weight', 'Gain muscle'];
    if (bmi < 18.5) return ['Gain healthy weight', 'Build muscle mass', 'Improve strength'];
    if (bmi < 25) return ['Maintain current weight', 'Tone body', 'Increase strength'];
    if (bmi < 30) return ['Lose weight gradually', 'Reduce body fat', 'Improve fitness'];
    return ['Start weight loss journey', 'Improve mobility', 'Increase overall fitness'];
  }

  static int calculateCaloriesBurned({
    required double met,
    required double userWeightKg,
    required int durationMinutes,
  }) {
    if (userWeightKg <= 0 || durationMinutes <= 0) return 0;
    final double calories = (met * 3.5 * userWeightKg) / 200 * durationMinutes;
    return calories.toInt();
  }

  static int _roundTo50(int value) {
    return (value / 50).round() * 50;
  }
}
