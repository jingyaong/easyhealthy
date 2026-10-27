import 'dart:convert';
import 'dart:io';

import 'package:easyhealthy/food_api_service.dart';
import 'package:easyhealthy/utils/plan_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'food search stops before network access when no key is supplied',
    () async {
      await expectLater(
        FoodApiService().searchFoods(query: 'apple'),
        throwsA(isA<StateError>()),
      );
      expect(await FoodApiService().searchFoods(query: '   '), isEmpty);
    },
  );

  test(
    'workout generation stops before network access without a key',
    () async {
      await expectLater(
        AiPlanGenerator.generatePlan(
          goal: 'Demo goal',
          workoutDays: 'Mon',
          sessionDuration: '20 minutes',
          intensity: 'Low',
          activityPrefs: '',
          additionalNotes: '',
          dailyCalorieGoal: null,
          availableActivities: ['Walking'],
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'sample recipe records can be consumed by recipe ranking and details',
    () {
      final recipes =
          jsonDecode(File('assets/recipes.json').readAsStringSync())
              as List<dynamic>;
      final ids = <String>{};
      expect(recipes, isNotEmpty);
      for (final item in recipes) {
        final recipe = item as Map<String, dynamic>;
        expect(ids.add(recipe['id'] as String), isTrue);
        expect(recipe['name'], isNotEmpty);
        expect(recipe['ingredients'], isA<List<dynamic>>());
        expect(recipe['steps'], isA<List<dynamic>>());
        expect(recipe['image'], isEmpty);
        expect(recipe['url'], isEmpty);
        expect(recipe['description'], contains('synthetic test fixtures'));
        final nutrients = recipe['nutrients'] as Map<String, dynamic>;
        for (final key in ['kcal', 'protein', 'carbs', 'fat']) {
          expect(num.tryParse(nutrients[key].toString()), isNotNull);
        }
      }
    },
  );
}
