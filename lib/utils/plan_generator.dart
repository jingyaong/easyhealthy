import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../config/app_config.dart';

class AiPlanGenerator {
  /// Generates a workout plan by calling the Gemini API.
  /// Takes user preferences as input and returns a structured map.
  /// Throws an exception if the API call fails or the response is invalid.
  static Future<Map<String, dynamic>> generatePlan({
    required String? goal,
    required String? workoutDays,
    required String? sessionDuration,
    required String? intensity,
    required String activityPrefs,
    required String additionalNotes,
    required double? dailyCalorieGoal,
    required List<String> availableActivities,
  }) async {
    if (AppConfig.geminiApiKey.isEmpty) {
      throw StateError(
        'AI workout planning requires GEMINI_API_KEY. Configure your own key for local development.',
      );
    }
    final model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: AppConfig.geminiApiKey,
    );

    final prompt =
        """
    Create a personalized weekly workout plan based on the following user inputs.

    User Inputs:
    - Primary Goal: ${goal ?? 'Not specified'}
    - Target Daily Calorie Burn: ${dailyCalorieGoal != null ? '${dailyCalorieGoal.toInt()} calories' : 'Not specified'}
    - Workout Days : ${workoutDays != null && workoutDays.isNotEmpty ? workoutDays : 'Not specified'}
    - Session Duration: ${sessionDuration ?? 'Not specified'}
    - Preferred Intensity: ${intensity ?? 'Not specified'}
    - Activity Preferences: ${activityPrefs.isNotEmpty ? activityPrefs : 'Not specified'}
    - Additional Notes: ${additionalNotes.isNotEmpty ? additionalNotes : 'Not specified'}

    Instructions:
    1. Generate a and motivating name for this plan.
    2. **Generate a short, single-sentence motivational comment for the user.**
    3. Design the plan to help the user reach their target daily calorie burn.
    4. Generate a weekly workout schedule for the 7 days: Mon, Tue, Wed, Thu, Fri, Sat, Sun.
    5. **Place workout activities ONLY on the specified "Workout Days". All other days must be rest days.**
    6. For each day, provide a list of activities. Each activity must have a 'name' (string) and a 'duration' (integer in minutes).
    7. If a day is a rest day, the list of activities should be an empty array [].
    8. IMPORTANT: The 'name' of each activity MUST be one of the following strings: ${availableActivities.join(', ')}.
    9. Return the response as a single, valid JSON object with no extra text or markdown.

    JSON Structure Example:
    {
      "planName": "Calorie Crusher Challenge",
      "schedule": {
        "Mon": [{"name": "Running", "duration": 30}, {"name": "Push-ups", "duration": 15}],
        "Tue": [],
        "Wed": [{"name": "Squats", "duration": 20}, {"name": "Lunges", "duration": 15}],
        "Thu": [],
        "Fri": [{"name": "Full Body Workout", "duration": 45}],
        "Sat": [{"name": "Light Jogging", "duration": 30}],
        "Sun": []
      }
    }
    """;

    final response = await model.generateContent([Content.text(prompt)]);
    final responseText = response.text;

    if (responseText == null || responseText.isEmpty) {
      throw Exception('Received an empty response from the Gemini API.');
    }

    try {
      // Find the start and end of the JSON object
      final startIndex = responseText.indexOf('{');
      final endIndex = responseText.lastIndexOf('}');

      if (startIndex == -1 || endIndex == -1) {
        throw FormatException(
          'Could not find a valid JSON object in the API response.',
        );
      }

      // Extract the JSON string
      final jsonString = responseText.substring(startIndex, endIndex + 1);

      // Decode the extracted string
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      // Provide a more informative error message
      throw FormatException(
        'Failed to parse JSON from API response. Error: $e',
      );
    }
  }
}
