import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'recipes_service.dart';
import 'recipe_details_page.dart';

class RecipesByCategoryPage extends StatefulWidget {
  final String? category; // Made nullable to allow direct list passing
  final List<Map<String, dynamic>>? preloadedRecipes; // New: For recommendations
  final String? pageTitle; // New: Custom title for recommendations page
  final DateTime selectedDate;

  const RecipesByCategoryPage({
    Key? key,
    this.category,
    this.preloadedRecipes,
    this.pageTitle,
    required this.selectedDate,
  }) : super(key: key);

  @override
  State<RecipesByCategoryPage> createState() => _RecipesByCategoryPageState();
}

class _RecipesByCategoryPageState extends State<RecipesByCategoryPage> {
  final RecipesService _service = RecipesService();
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;

  // Preloaded saved IDs for instant UI
  Set<String> _savedIds = {};

  @override
  void initState() {
    super.initState();
    _initData();
    _preloadSavedIds();
  }

  Future<void> _initData() async {
    // CASE 1: We passed a list of recipes directly (e.g. Recommendations)
    if (widget.preloadedRecipes != null) {
      setState(() {
        _results = widget.preloadedRecipes!;
        _loading = false;
      });
      return;
    }

    // CASE 2: We passed a category string -> Load from Asset
    if (widget.category != null) {
      await _service.loadFromAsset();
      setState(() {
        _results = _service.filter(subCategory: widget.category!, limit: 200);
        _loading = false;
      });
    } else {
      // Fallback if nothing is passed
      setState(() => _loading = false);
    }
  }

  // Preload saved recipe IDs for instant bookmark icons
  Future<void> _preloadSavedIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("saved_recipes")
        .get();

    if (mounted) {
      setState(() {
        _savedIds = snapshot.docs.map((doc) => doc.id).toSet();
      });
    }
  }

  // Stream for real-time updates
  Stream<Set<String>> _savedIdsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value({});
    return FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("saved_recipes")
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toSet());
  }

  // --- UI REMAINS EXACTLY AS BEFORE ---
  Widget _recipeCard(Map<String, dynamic> recipe, Set<String> savedIds) {
    final nutrients = (recipe['nutrients'] ?? {}) as Map<String, dynamic>;
    final kcal = (nutrients['kcal'] ?? nutrients['calories'] ?? '').toString();
    final image = recipe['image'] as String?;
    final recipeId = recipe['id'];
    final isSaved = savedIds.contains(recipeId);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeDetailsPage(
            recipe: recipe,
            selectedDate: widget.selectedDate,
          ),
        ),
      ),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: image != null && image.isNotEmpty
                  ? Image.network(
                image,
                height: 110,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(height: 110, color: Colors.grey[200]),
              )
                  : Container(height: 110, color: Colors.grey[200]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      recipe['name'] ?? 'Unknown',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${kcal.isNotEmpty ? kcal : '-'} kcal',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[800],
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Please login to save recipes"),
                                ),
                              );
                              return;
                            }

                            final userRef = FirebaseFirestore.instance
                                .collection("users")
                                .doc(user.uid)
                                .collection("saved_recipes")
                                .doc(recipeId);

                            if (isSaved) {
                              await userRef.delete();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Removed from Favorites"),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            } else {
                              await userRef.set(recipe);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Saved to Favorites"),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          child: Icon(
                            isSaved ? Icons.bookmark : Icons.bookmark_border,
                            size: 18,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Logic to determine title: Use custom title OR format the category
    String titleString = widget.pageTitle ?? '';

    if (titleString.isEmpty && widget.category != null) {
      const exceptions = {
        'a', 'an', 'the', 'and', 'but', 'or', 'for', 'nor', 'on', 'at',
        'to', 'from', 'by', 'in', 'of', 'with'
      };

      final words = widget.category!.toLowerCase().split(' ');
      titleString = words
          .asMap()
          .entries
          .map((entry) {
        final index = entry.key;
        final word = entry.value;
        if (word.isEmpty) return '';
        if (index == 0 || !exceptions.contains(word)) {
          return word[0].toUpperCase() + word.substring(1);
        }
        return word;
      })
          .join(' ');
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            titleString,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_results.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            titleString,
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
        ),
        body: Center(
          child: Text(
            "No recipes found.",
            style: GoogleFonts.poppins(color: Colors.grey[600]),
          ),
        ),
      );
    }

    // Grid with instant saved IDs and real-time updates
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleString,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<Set<String>>(
        stream: _savedIdsStream(),
        initialData: _savedIds,
        builder: (context, snapshot) {
          final savedIds = snapshot.data ?? _savedIds;

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.78, // Kept exactly as your previous code
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _results.length,
            itemBuilder: (ctx, i) => _recipeCard(_results[i], savedIds),
          );
        },
      ),
    );
  }
}
