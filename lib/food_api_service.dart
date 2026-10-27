import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config/app_config.dart';

class FoodApiService {
  final String apiKey = AppConfig.usdaApiKey;

  // --- 1. ADD limit to the function signature ---
  Future<List<Map<String, dynamic>>> searchFoods({
    required String query,
    int pageSize = 200,
    int limit = 25,
  }) async {
    if (query.trim().isEmpty) return [];
    if (apiKey.isEmpty) {
      throw StateError(
        'Food search requires USDA_API_KEY. Configure your own key for local development.',
      );
    }

    // 1. FIX: Use Uri.https to build the URL safely.
    // This handles special characters and spaces automatically.
    final uri = Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
      'api_key': apiKey,
      'query': query,
      'dataType': 'SR Legacy',
      'pageSize': pageSize.toString(),
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch foods (${response.statusCode})');
    }

    final data = json.decode(response.body);
    List foods = data['foods'] ?? [];

    // 2. FIX: Fallback logic also uses Uri.https
    if (foods.isEmpty) {
      final fallbackUri = Uri.https(
        'api.nal.usda.gov',
        '/fdc/v1/foods/search',
        {
          'api_key': apiKey,
          'query': query,
          // Removed dataType to search all databases
          'pageSize': pageSize.toString(),
        },
      );

      final fallbackResponse = await http.get(fallbackUri);
      if (fallbackResponse.statusCode == 200) {
        final fallbackData = json.decode(fallbackResponse.body);
        foods = fallbackData['foods'] ?? [];
      } else {
        throw Exception(
          'Failed to fetch fallback results (${fallbackResponse.statusCode})',
        );
      }
    }

    // ... The rest of your code remains exactly the same ...
    final results = foods.map<Map<String, dynamic>>((food) {
      final nutrients = food['foodNutrients'] as List<dynamic>? ?? [];
      int calories = 0, protein = 0, carbs = 0, fat = 0;

      for (var n in nutrients) {
        final name = (n['nutrientName'] ?? '').toString().toLowerCase();
        final unit = (n['unitName'] ?? '').toString().toLowerCase();
        final value = (n['value'] is num) ? n['value'].toDouble() : 0.0;

        switch (name) {
          case 'energy':
            if (unit == 'kj') {
              calories = (value / 4.184).round();
            } else {
              calories = value.round();
            }
            break;

          case 'protein':
            protein = value.round();
            break;

          case 'carbohydrate, by difference':
            carbs = value.round();
            break;

          case 'total lipid (fat)':
            fat = value.round();
            break;
        }
      }

      final double servingSize = (food['servingSize'] is num)
          ? (food['servingSize'] as num).toDouble()
          : 0.0;
      final String servingUnit = food['servingSizeUnit'] ?? '';
      final String householdServing = food['householdServingFullText'] ?? '';
      final String formattedServing = _formatServing(
        householdServing,
        servingSize,
        servingUnit,
      );

      return {
        'fdcId': food['fdcId'],
        'name': food['description'] ?? 'Unknown Food',
        'brandName': food['brandName'] ?? '',
        'brandOwner': food['brandOwner'] ?? '',
        'dataType': food['dataType'] ?? '',
        'foodCategory': food['foodCategory'] ?? '',
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'servingSize': servingSize,
        'servingUnit': servingUnit,
        'householdServing': householdServing,
        'formattedServing': formattedServing,
      };
    }).toList();

    // Deduplicate by FDC ID
    final seen = <int>{};
    final uniqueResults = <Map<String, dynamic>>[];
    for (var food in results) {
      final id = food['fdcId'];
      if (!seen.contains(id)) {
        uniqueResults.add(food);
        seen.add(id);
      }
    }

    // Sort by the user-defined ranking groups, then alphabetically.
    final lowerQuery = query.toLowerCase().trim();
    uniqueResults.sort((a, b) {
      final nameA = (a['name'] as String);
      final nameB = (b['name'] as String);

      final scoreA = _getRelevanceScore(nameA, lowerQuery);
      final scoreB = _getRelevanceScore(nameB, lowerQuery);

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA);
      }

      if (nameA.length != nameB.length) {
        return nameA.length.compareTo(nameB.length);
      }

      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });

    return uniqueResults.take(limit).toList();
  }

  // Relevance scoring that creates sorting groups based on the user's rules.
  int _getRelevanceScore(String name, String query) {
    final normalizedName = _normalizeWord(name);
    final normalizedQuery = _normalizeWord(query);

    // Isolate the "first part" of the food name (before the comma).
    final nameParts = normalizedName.split(',');
    final firstPart = nameParts[0].trim();

    // Rule 1: Exact match on the first part (e.g., "Egg")
    if (firstPart == normalizedQuery) {
      return 10000;
    }

    // Rule 2: Plural form match (e.g., "Eggs")
    if (firstPart == '${normalizedQuery}s' ||
        firstPart == '${normalizedQuery}es') {
      return 9000;
    }

    // Rule 3: "Starts with" whole word match (e.g., "Egg" in "Egg custards")
    final startsWithRegex = RegExp(
      r'^' + RegExp.escape(normalizedQuery) + r'\b',
    );
    if (startsWithRegex.hasMatch(firstPart)) {
      return 8000;
    }

    // --- NEW Rule 4: All words in query must be present in the name ---
    // This handles "chicken wing" matching "Chicken, raw, wing".
    final queryWords = normalizedQuery
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (queryWords.length > 1) {
      bool allWordsFound = queryWords.every(
        (word) => normalizedName.contains(word),
      );
      if (allWordsFound) {
        return 5000; // High score for matching all words
      }
    }

    // Rule 5: Fallback for any other single-word containment
    if (normalizedName.contains(normalizedQuery)) {
      return 1000;
    }

    return 0; // No match
  }

  // Simplify normalization to only handle case and spacing.
  String _normalizeWord(String text) {
    return text.toLowerCase().trim();
  }

  // Serving helper
  String _formatServing(String household, double size, String unit) {
    if (household.isNotEmpty && size > 0 && unit.isNotEmpty) {
      return '$household (${size.toStringAsFixed(0)} $unit)';
    } else if (household.isNotEmpty) {
      return household;
    } else if (size > 0 && unit.isNotEmpty) {
      return '${size.toStringAsFixed(0)} $unit';
    } else {
      return 'Per 100g';
    }
  }
}
