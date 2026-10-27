import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import 'recipes_service.dart';
import 'recipes_by_category_page.dart';
import 'recipe_details_page.dart';
import 'recommendations/hybrid.dart';

class DiscoverRecipesPage extends StatefulWidget {
  final DateTime selectedDate;

  const DiscoverRecipesPage({
    Key? key,
    required this.selectedDate,
  }) : super(key: key);

  @override
  State<DiscoverRecipesPage> createState() => _DiscoverRecipesPageState();
}

class _DiscoverRecipesPageState extends State<DiscoverRecipesPage> {
  final RecipesService _service = RecipesService();
  HybridRecommender? _recommender;
  bool _loading = true;
  bool _loadingRecommendations = true; // Start true so shimmer shows immediately

  // This will hold the latest version of the user's main document data.
  Map<String, dynamic>? _currentUserData;

  List<String> _subCategories = [];
  List<Map<String, dynamic>> _recommended = [];

  @override
  void initState() {
    super.initState();
    _loadRecipesAndListen();
  }

  Future<void> _loadRecipesAndListen() async {
    await _service.loadFromAsset();
    if (!mounted) return;

    setState(() {
      _subCategories = _service.uniqueSubCategories();
      _loading = false; // Recipes loaded
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
        });
      }
      return;
    }

    // 1. PRIMARY LISTENER: Listen to the user's main document.
    FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      // Even if data is null (new user), pass empty map so recommender runs
      _currentUserData = snapshot.data() ?? {};
      _updateRecommendations();
    });

    // 2. TRIGGER-ONLY LISTENER: Listens for changes in meal logs.
    FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("meal_logs")
        .snapshots()
        .listen((_) {
      if (!mounted) return;
      // Trigger update if we already have user data
      if (_currentUserData != null) {
        _updateRecommendations();
      }
    });

    // 3. TRIGGER-ONLY LISTENER: Listens for changes in saved recipes.
    FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("saved_recipes")
        .snapshots()
        .listen((_) {
      if (!mounted) return;
      if (_currentUserData != null) {
        _updateRecommendations();
      }
    });
  }

  Future<void> _updateRecommendations() async {
    if (!mounted) return;

    // Ensure we have at least empty map for user data before running
    final userData = _currentUserData ?? {};

    setState(() => _loadingRecommendations = true);

    try {
      _recommender = HybridRecommender(
        userData: userData,
        selectedDate: widget.selectedDate, // <--- Pass the date!
      );
      // Force fetch recommendations even if user has no history
      final results = await _recommender!.recommend(topN: 10);

      if (mounted) {
        setState(() {
          _recommended = results;
          _loadingRecommendations = false;
        });
      }
    } catch (e) {
      print("Error generating recommendations: $e");
      if (mounted) {
        setState(() => _loadingRecommendations = false);
      }
    }
  }

  Stream<Set<String>> _savedIdsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value({});
    return FirebaseFirestore.instance
        .collection("users")
        .doc(user.uid)
        .collection("saved_recipes")
        .snapshots()
    // Ensure every ID from Firestore is also a clean, trimmed string.
        .map((snapshot) => snapshot.docs.map((doc) => doc.id.trim()).toSet());
  }

  Widget _shimmerCard() {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: Container(height: 100, color: Colors.grey[300]),
            ),
          ),
          const SizedBox(height: 6),
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(height: 16, width: 120, color: Colors.grey[300]),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(height: 12, width: 40, color: Colors.grey[300]),
              ),
              Shimmer.fromColors(
                baseColor: Colors.grey[300]!,
                highlightColor: Colors.grey[100]!,
                child: Container(height: 11, width: 30, color: Colors.grey[300]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recipeCard(Map<String, dynamic> recipe, Set<String> savedIds) {
    final nutrients = (recipe['nutrients'] ?? {}) as Map<String, dynamic>;
    final kcal = (nutrients['kcal'] ?? nutrients['calories'] ?? '').toString();

    // --- START: ROBUST ID MATCHING FIX ---
    // Get the raw ID which might be of any type.
    final rawId = recipe['id'];

    // Ensure we are comparing a clean String to a clean String.
    // Convert the recipe's ID to a trimmed string, providing an empty fallback.
    final recipeId = rawId?.toString().trim() ?? "";

    // Check if the set of saved IDs contains our clean recipe ID.
    final isSaved = recipeId.isNotEmpty && savedIds.contains(recipeId);
    // --- END: ROBUST ID MATCHING FIX ---

    // DEBUG: You can uncomment this to verify the IDs in your console.
    /*
    if (recipe['name'].toString().toLowerCase().contains("chilli")) {
      print("DEBUG: '${recipe['name']}' | ID: '$recipeId' | Is Saved? $isSaved");
    }
    */

    return GestureDetector(
      onTap: () {
        // We use the 'recipeId' from above to ensure consistency when saving/unsaving.
        // However, the original 'recipe' map is what we pass to the details page.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecipeDetailsPage(
              recipe: recipe,
              selectedDate: widget.selectedDate,
            ),
          ),
        );
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Image.network(
                  recipe['image'] ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.fastfood, size: 40),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: Text(
                recipe['name'] ?? 'Unknown',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  kcal.isNotEmpty ? '$kcal kcal' : '-',
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
                            content: Text("Please login to save recipes")),
                      );
                      return;
                    }
                    if (recipeId.isEmpty) return; // Don't allow saving if ID is invalid

                    final userRef = FirebaseFirestore.instance
                        .collection("users")
                        .doc(user.uid)
                        .collection("saved_recipes")
                        .doc(recipeId); // Use the clean ID

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
    );
  }

  Widget _recommendationSection(Set<String> savedIds) {
    // If loading, show shimmer. If not loading and empty, hide.
    // If not loading and has items, show items.
    if (!_loadingRecommendations && _recommended.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Recommended For You",
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              if (_recommended.isNotEmpty) // Only show "View More" if we have data
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RecipesByCategoryPage(
                          preloadedRecipes: _recommended,
                          pageTitle: "Recommended For You",
                          selectedDate: widget.selectedDate,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    "View More",
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 4),
            // Ensure we show 5 shimmer cards if loading
            itemCount: _loadingRecommendations ? 5 : _recommended.length,
            itemBuilder: (_, index) {
              if (_loadingRecommendations) return _shimmerCard();
              return _recipeCard(_recommended[index], savedIds);
            },
          ),
        ),
      ],
    );
  }

  Widget _subcategorySection(String subCategory, Set<String> savedIds) {
    final recipes = _service.filter(subCategory: subCategory);
    final previewRecipes = recipes.length > 5 ? recipes.sublist(0, 5) : recipes;

    const exceptions = {
      'a', 'an', 'the', 'and', 'but', 'or', 'for', 'nor', 'on', 'at',
      'to', 'from', 'by', 'in', 'of', 'with'
    };
    final words = subCategory.toLowerCase().split(' ');
    final titleString = words.asMap().entries.map((entry) {
      final index = entry.key;
      final word = entry.value;
      if (word.isEmpty) return '';
      if (index == 0 || !exceptions.contains(word)) {
        return word[0].toUpperCase() + word.substring(1);
      }
      return word;
    }).join(' ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subCategory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(titleString,
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipesByCategoryPage(
                          category: subCategory,
                          selectedDate: widget.selectedDate,
                        ),
                      ),
                    );
                  },
                  child: Text(
                    "View More",
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).primaryColor),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 4),
            itemCount: _loading ? 5 : previewRecipes.length,
            itemBuilder: (_, index) => _loading
                ? _shimmerCard()
                : _recipeCard(previewRecipes[index], savedIds),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Discover Recipes",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: StreamBuilder<Set<String>>(
        stream: _savedIdsStream(),
        initialData: {},
        builder: (context, snapshot) {
          final savedIds = snapshot.data ?? {};
          return ListView(
            children: [
              // Removed the logic that hides the section if loading
              // Now _recommendationSection handles its own loading state (shimmer)
              _recommendationSection(savedIds),

              if (!_loading)
                ..._subCategories.map((cat) => _subcategorySection(cat, savedIds)),
            ],
          );
        },
      ),
    );
  }
}
