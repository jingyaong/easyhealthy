import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RecipesService {
  static final RecipesService _instance = RecipesService._internal();
  factory RecipesService() => _instance;
  RecipesService._internal();

  List<Map<String, dynamic>> _recipes = [];

  // --------------------------
  // 🔥 Fetch saved recipe IDs
  // --------------------------
  Future<Set<String>> _fetchSavedRecipeIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    final snap = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("saved_recipes")
        .get();

    return snap.docs.map((doc) => doc.id).toSet();
  }

  // --------------------------
  // 🔥 Load JSON + mark isSaved
  // --------------------------
  Future<void> loadFromAsset([String path = 'assets/recipes.json']) async {
    if (_recipes.isNotEmpty) return;

    final raw = await rootBundle.loadString(path);
    final data = json.decode(raw);

    if (data is List) {
      _recipes = data.map<Map<String, dynamic>>((e) {
        final recipe = Map<String, dynamic>.from(e);

        // ✅ Ensure every recipe has an ID
        if (recipe['id'] == null || recipe['id'].toString().trim().isEmpty) {
          throw Exception("Recipe missing required 'id': ${recipe['name'] ?? recipe}");
        }

        // Default saved state
        recipe['isSaved'] = false;

        return recipe;
      }).toList();
    } else {
      _recipes = [];
    }

    // 🔥 Load saved IDs from Firebase
    final savedIds = await _fetchSavedRecipeIds();

    // 🔥 Sync saved state into recipe list
    for (var recipe in _recipes) {
      final id = recipe['id']?.toString();
      if (id != null && savedIds.contains(id)) {
        recipe['isSaved'] = true;
      }
    }
  }

  // --------------------------
  // Getter
  // --------------------------
  List<Map<String, dynamic>> allRecipes() => List.unmodifiable(_recipes);

  // --------------------------
  // 🔍 Search
  // --------------------------
  List<Map<String, dynamic>> search(String query, {int limit = 200}) {
    if (query.trim().isEmpty) return _recipes.take(limit).toList();
    final q = query.toLowerCase();

    return _recipes.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final author = (r['author'] ?? '').toString().toLowerCase();
      final category = (r['dish_type'] ?? '').toString().toLowerCase();

      return name.contains(q) || author.contains(q) || category.contains(q);
    }).take(limit).toList();
  }

  // --------------------------
  // 🔎 Filter (main, dish, sub)
  // --------------------------
  List<Map<String, dynamic>> filter({
    String? mainCategory,
    String? dishType,
    String? subCategory,
    int limit = 200,
  }) {
    return _recipes.where((r) {
      if (mainCategory != null &&
          (r['maincategory'] ?? '').toString().toLowerCase() != mainCategory.toLowerCase()) {
        return false;
      }

      if (dishType != null) {
        final dt = r['dish_type'];
        if (dt is String && dt.toLowerCase() != dishType.toLowerCase()) return false;
        if (dt is List && !dt.map((e) => e.toString().toLowerCase()).contains(dishType.toLowerCase())) return false;
      }

      if (subCategory != null) {
        final sc = r['subcategory'];
        if (sc is String && sc.toLowerCase() != subCategory.toLowerCase()) return false;
        if (sc is List && !sc.map((e) => e.toString().toLowerCase()).contains(subCategory.toLowerCase())) return false;
      }

      return true;
    }).take(limit).toList();
  }

  // --------------------------
  // Unique lists
  // --------------------------
  List<String> uniqueMainCategories() {
    final set = <String>{};
    for (final r in _recipes) {
      final s = (r['maincategory'] ?? '').toString();
      if (s.isNotEmpty) set.add(s);
    }
    return set.toList();
  }

  List<String> uniqueDishTypes() {
    final set = <String>{};
    for (final r in _recipes) {
      final dt = r['dish_type'];
      if (dt is String && dt.isNotEmpty) set.add(dt);
      if (dt is List) set.addAll(dt.map((e) => e.toString()));
    }
    return set.toList();
  }

  List<String> uniqueSubCategories() {
    final set = <String>{};
    for (final r in _recipes) {
      final sc = r['subcategory'];
      if (sc is String && sc.isNotEmpty) set.add(sc);
      if (sc is List) set.addAll(sc.map((e) => e.toString()));
    }
    return set.toList();
  }
}
