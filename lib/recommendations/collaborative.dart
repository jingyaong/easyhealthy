import 'dart:convert'; // Needed for JSON
import 'package:flutter/services.dart'; // Needed for rootBundle
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CollaborativeRecommender {

  // --- 1. Add Helper to Load Recipes ---
  Future<List<Map<String, dynamic>>> loadRecipes() async {
    final String data = await rootBundle.loadString('assets/recipes.json');
    final List<dynamic> jsonResult = json.decode(data);
    return jsonResult.cast<Map<String, dynamic>>();
  }

  // --- 2. Main Recommend Method (Testing Only) ---
  Future<List<Map<String, dynamic>>> recommend({int topN = 10}) async {
    final allRecipes = await loadRecipes();
    final user = FirebaseAuth.instance.currentUser;

    // A. Fetch History (Logs & Saved) to build User Profile
    final savedNames = <String>{};
    final savedIds = <String>{};
    final loggedMeals = <String>{};
    final allRecipeNames = allRecipes.map((r) => r['name'].toString()).toSet();

    if (user != null) {
      try {
        // Fetch Saved Recipes
        final savedSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('saved_recipes')
            .get();

        for (var doc in savedSnapshot.docs) {
          final data = doc.data();
          final name = data['name']?.toString();
          if (name != null && name.isNotEmpty) savedNames.add(name);

          final recipeId = data['id']?.toString();
          if (recipeId != null) savedIds.add(recipeId);
          else savedIds.add(doc.id);
        }

        // Fetch Meal Logs
        final logsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('meal_logs')
            .get();

        for (var doc in logsSnapshot.docs) {
          final meals = doc.data();
          meals.forEach((mealType, items) {
            if (items is List) {
              for (var item in items) {
                final name = item['name']?.toString();
                if (name != null && name.isNotEmpty && allRecipeNames.contains(name)) {
                  loggedMeals.add(name);
                }
              }
            }
          });
        }
      } catch (e) {
        print("Error fetching history in CF recommender: $e");
      }
    }

    // B. Build User Profile Vectors
    final userHistory = loggedMeals.union(savedNames);

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

    // C. Score Recipes
    List<Map<String, dynamic>> scoredRecipes = allRecipes.map((r) {
      final double cfScore = calculateScore(
        recipe: r,
        userIngredients: userIngredients,
        userSubcategories: userSubcategories,
        userDishTypes: userDishTypes,
        savedIds: savedIds,
      );

      return {
        ...r,
        'hybridScore': cfScore, // Map CF score to Hybrid score for UI
        'contentScore': 0.0,
        'cfScore': cfScore,
      };
    }).toList();

    // D. Sort
    scoredRecipes.sort((a, b) => (b['hybridScore'] as double).compareTo(a['hybridScore'] as double));

    // --- PRINT DEBUG LOGS (MATCHING HYBRID FORMAT) ---
    print("🏆 Top $topN recipes (Collaborative Only) | History: ${userHistory.length}:");
    for (var r in scoredRecipes.take(topN)) {
      print(
          " - ${r['name']} | CF: ${(r['cfScore'] as double).toStringAsFixed(4)}");
    }

    return scoredRecipes.take(topN).toList();
  }

  // --- (Existing Logic Below) ---

  /// Calculates Jaccard Index Similarity
  double _ingredientSimilarity(List<String> a, List<String> b) {
    final setA = a.map((e) => e.toLowerCase()).toSet();
    final setB = b.map((e) => e.toLowerCase()).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0.0;

    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    if (union == 0) return 0.0;
    return intersection / union;
  }

  /// Score a recipe based on user history overlap
  double calculateScore({
    required Map<String, dynamic> recipe,
    required List<String> userIngredients,
    required Set<String> userSubcategories,
    required Set<String> userDishTypes,
    required Set<String> savedIds,
  }) {
    double cfScore = 0;

    if (userIngredients.isNotEmpty) {
      final ingredients = (recipe['ingredients'] as List<dynamic>).cast<String>();

      // 1. Ingredient Similarity (Weight: 0.5)
      cfScore = _ingredientSimilarity(ingredients, userIngredients) * 0.5;

      // 2. Subcategory Similarity (Weight: 0.1)
      final subcat = (recipe['subcategory'] ?? '').toString().toLowerCase();
      if (subcat.isNotEmpty) {
        cfScore += _ingredientSimilarity([subcat], userSubcategories.toList()) * 0.1;
      }

      // 3. Dish Type Similarity (Weight: 0.1)
      final dishType = (recipe['dish_type'] ?? '').toString().toLowerCase();
      if (dishType.isNotEmpty) {
        cfScore += _ingredientSimilarity([dishType], userDishTypes.toList()) * 0.1;
      }
    }

    // 4. Saved Boost (Weight: 0.3)
    if (savedIds.contains(recipe['id'])) {
      cfScore += 0.3;
    }

    return cfScore.clamp(0.0, 1.0);
  }
}
