import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/Habit.dart';

class FitnessHighlights {
  /// Calculates the sum of all 'caloriesBurned' from a list of user activities.
  static int calculateTotalCaloriesBurned(List<Map<String, dynamic>> activities) {
    if (activities.isEmpty) return 0;
    return activities.fold<int>(0, (sum, activity) => sum + (activity['calories_burned'] as num).toInt());
  }

  /// Calculates the number of unique days the user has logged an activity.
  static int calculateTotalActiveDays(List<Map<String, dynamic>> activities) {
    if (activities.isEmpty) return 0;
    // Use a Set to automatically handle uniqueness of days
    final uniqueDays = activities.map((activity) {
      final timestamp = activity['date'] as Timestamp;
      final date = timestamp.toDate();
      // Normalize to the start of the day to count unique days
      return DateTime(date.year, date.month, date.day);
    }).toSet();
    return uniqueDays.length;
  }

  /// Calculates the highest number of calories burned in a single day.
  static int calculateHighestSingleDayCalories(List<Map<String, dynamic>> activities) {
    if (activities.isEmpty) return 0;

    final Map<DateTime, int> caloriesPerDay = {};
    for (var activity in activities) {
      final timestamp = activity['date'] as Timestamp;
      final date = timestamp.toDate();
      final day = DateTime(date.year, date.month, date.day);
      final calories = (activity['calories_burned'] as num).toInt();
      // Add calories to the existing day's total, or create a new entry
      caloriesPerDay.update(day, (value) => value + calories, ifAbsent: () => calories);
    }
    // Find the maximum value among all day totals
    return caloriesPerDay.values.fold(0, (max, current) => current > max ? current : max);
  }

  /// Finds the single longest streak among all user habits.
  static int calculateHighestHabitStreak(List<Habit> habits) {
    if (habits.isEmpty) return 0;
    // Find the maximum longestStreak value in the list of habits
    return habits.fold(0, (maxStreak, habit) => habit.longestStreak > maxStreak ? habit.longestStreak : maxStreak);
  }

  /// Calculates the sum of all longest streaks from all habits.
  static int calculateTotalHabitStreaks(List<Habit> habits) {
    if (habits.isEmpty) return 0;
    // Sum up the longestStreak value for every habit
    return habits.fold(0, (sum, habit) => sum + habit.longestStreak);
  }
}
