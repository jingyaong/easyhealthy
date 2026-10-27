import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'food_api_service.dart';
import 'discover_recipes_page.dart';
import 'recipe_details_page.dart';
import 'generate_meal_plan_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SearchFoodPage extends StatefulWidget {
  final String? defaultCategory;
  final DateTime selectedDate;
  final Function(Map<String, dynamic> food, String category)? onFoodAdded;

  const SearchFoodPage({
    super.key,
    required this.defaultCategory,
    required this.selectedDate,
    required this.onFoodAdded,
  });

  @override
  State<SearchFoodPage> createState() => _SearchFoodPageState();
}

class _SearchFoodPageState extends State<SearchFoodPage> {
  List<Map<String, dynamic>> filtered = [];
  final TextEditingController _searchC = TextEditingController();
  late FocusNode _searchFocusNode;
  late String selectedCategory;
  final List<String> categories = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];
  bool isLoading = false;
  Timer? _debounce;
  String _lastQuery = '';

  int _currentLimit = 25;
  bool _canShowMore = true;
  bool _isFetchingMore = false;
  bool _isDebouncing = false;
  dynamic _justAddedFdcId;

  Timer? _feedbackTimer;

  late Stream<List<Map<String, dynamic>>> _myFoodsStream;

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.defaultCategory ?? 'Breakfast';
    _searchC.addListener(_onSearch);
    _searchFocusNode = FocusNode();

    // ADD THIS INITIALIZATION LOGIC
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _myFoodsStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('custom_foods')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'name': data['name'] ?? 'Unknown Food',
                'serving_size': data['serving_size'] ?? '1 serving',
                'calories': data['calories'] ?? 0,
                'protein': data['protein'] ?? 0,
                'carbs': data['carbs'] ?? 0,
                'fat': data['fat'] ?? 0,
              };
            }).toList(),
          );
    } else {
      _myFoodsStream = Stream.value([]); // Empty stream if no user
    }
  }

  void _onSearch() {
    if (_searchC.text.trim().isEmpty) {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      setState(() {
        filtered = [];
        _lastQuery = '';
        _currentLimit = 25;
        _canShowMore = true;
        _isDebouncing = false;
      });
      return;
    }

    if (!(_debounce?.isActive ?? false)) {
      setState(() {
        _isDebouncing = true;
      });
    }

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      final query = _searchC.text.trim();

      if (query == _lastQuery) {
        setState(() => _isDebouncing = false);
        return;
      }
      _lastQuery = query;

      setState(() {
        isLoading = true;
        _isDebouncing = false;
        filtered = [];
        _currentLimit = 25;
        _canShowMore = true;
      });

      _fetchResults(query);
    });
  }

  Future<void> _fetchResults(String query) async {
    try {
      final results = await FoodApiService().searchFoods(
        query: query,
        limit: _currentLimit,
      );

      if (mounted) {
        setState(() {
          filtered = results;
          if (results.length < _currentLimit) {
            _canShowMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error fetching foods: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _isFetchingMore = false;
        });
      }
    }
  }

  void _onShowMore() {
    setState(() {
      _currentLimit += 25;
      _isFetchingMore = true;
    });
    _fetchResults(_lastQuery);
  }

  void _handleAddFood(Map<String, dynamic> item) {
    if (_justAddedFdcId != null) return;

    widget.onFoodAdded?.call(item, selectedCategory);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${item['name']}" to $selectedCategory'),
        duration: const Duration(seconds: 1),
      ),
    );

    setState(() {
      _justAddedFdcId = item['fdcId'];
    });

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _justAddedFdcId = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchC.removeListener(_onSearch);
    _searchC.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Add Foods',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
          ),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          bottom: TabBar(
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(),
            labelColor: Colors.black87,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).primaryColor,
            tabs: const [
              Tab(text: 'Search Foods'),
              Tab(text: 'My Foods'),
              Tab(text: 'Recipes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildFoodSearchTab(),
            _buildMyFoodsTab(),
            _buildRecipeTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildFoodSearchTab() {
    return Column(
      children: [
        // Top bar (category + search)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            children: [
              // Custom Meal Category Selector
              LayoutBuilder(
                builder: (context, constraints) {
                  return Material(
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: PopupMenuButton<String>(
                      // Offset: x=0 (align left), y=58 (54px Height + 4px Gap)
                      offset: const Offset(0, 58),
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      color: Colors.white,
                      elevation: 0,
                      tooltip: '',
                      onSelected: (String newValue) {
                        setState(() {
                          selectedCategory = newValue;
                        });
                        if (_searchFocusNode.hasFocus) {
                          _searchFocusNode.unfocus();
                        }
                        FocusScope.of(context).requestFocus(FocusNode());
                      },
                      onCanceled: () {
                        if (_searchFocusNode.hasFocus) {
                          _searchFocusNode.unfocus();
                        }
                        FocusScope.of(context).requestFocus(FocusNode());
                      },
                      itemBuilder: (context) {
                        // Using fixed list to match My Foods tab style
                        return ['Breakfast', 'Lunch', 'Dinner', 'Snacks']
                            .map((String value) {
                          final isSelected = value == selectedCategory;
                          return PopupMenuItem<String>(
                            value: value,
                            height: 48,
                            child: SizedBox(
                              width: double.infinity,
                              child: Text(
                                value,
                                style: GoogleFonts.poppins(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF2196F3)
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        }).toList();
                      },
                      child: Container(
                        height: 54,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(Icons.restaurant_menu,
                                size: 20, color: Colors.grey[600]),
                            const SizedBox(width: 12),
                            Text(
                              "Adding to:",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    selectedCategory,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: const Color(0xFF2196F3),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Color(0xFF2196F3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchC,
                focusNode: _searchFocusNode,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: 'Search foods…',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 18, right: 6),
                    child: Icon(Icons.search, size: 20, color: Colors.grey[600]),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF2F5F8),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2196F3), width: 1.5),
                  ),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
              ),
            ],
          ),
        ),

        const Divider(height: 1, thickness: 1),

        // Results
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : _isDebouncing && filtered.isEmpty
              ? Center(
                  child: Text(
                    'Searching…',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'No results found',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount:
                      filtered.length +
                      (_canShowMore && filtered.isNotEmpty ? 1 : 0),
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.8,
                    color: Colors.grey[300],
                  ),
                  itemBuilder: (ctx, i) {
                    if (i == filtered.length) {
                      return _isFetchingMore
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : TextButton(
                              onPressed: _onShowMore,
                              child: Text(
                                'Show More',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            );
                    }

                    final item = filtered[i];
                    final serving = item['formattedServing'] ?? 'Per 100g';
                    final subtitleText = '${item['calories']} kcal • $serving';

                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -1),
                      title: Text(
                        item['name'],
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        subtitleText,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: _justAddedFdcId == item['fdcId']
                              ? Colors.green
                              : const Color(0xFF2196F3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _handleAddFood(item),
                        child: _justAddedFdcId == item['fdcId']
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : Text(
                                'ADD',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  letterSpacing: 0.4,
                                ),
                              ),
                      ),
                      onTap: () async {
                        _searchFocusNode.unfocus();
                        FocusScope.of(context).unfocus();
                        await Future.delayed(const Duration(milliseconds: 80));
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          barrierColor: Colors.black54,
                          builder: (ctx) => Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['name'],
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => Navigator.pop(ctx),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.close, size: 20),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    '$serving',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F5F8),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      children: [
                                        _macroRow(
                                          'Calories',
                                          '${item['calories']} kcal',
                                        ),
                                        _macroRow(
                                          'Protein',
                                          '${item['protein']} g',
                                        ),
                                        _macroRow(
                                          'Carbs',
                                          '${item['carbs']} g',
                                        ),
                                        _macroRow('Fat', '${item['fat']} g'),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          style: TextButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF2196F3,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _handleAddFood(item);
                                          },
                                          child: Text(
                                            'ADD FOOD',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _macroRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyFoodsTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Please sign in'));
    }

    void _showFoodDialog({Map<String, dynamic>? existingItem}) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _CreateFoodDialog(existingItem: existingItem),
      );
    }

    final cardBorderColor =
        Colors.grey.shade300; // same as create button border

    return Column(
      children: [
        // ---- CREATE BUTTON ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2196F3),
              elevation: 0,
              side: BorderSide(color: cardBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _showFoodDialog(),
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text(
              'Create Custom Food',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),

        // ---- 2. MEAL CATEGORY SELECTION (DROPDOWN STYLE) ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Wrap in Material to force the InkWell (ripple) to respect the rounded shape
              return Material(
                color: Colors.white,
                // ADDED: This physically cuts off the corners of the click ripple
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: cardBorderColor),
                ),
                child: PopupMenuButton<String>(
                  // Offset: x=0 (align left), y=58 (54px Height + 4px Gap)
                  offset: const Offset(0, 58),
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: constraints.maxWidth,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: cardBorderColor),
                  ),
                  color: Colors.white,
                  elevation: 0,
                  tooltip: '',
                  // Removing initialValue stops the menu from jumping vertically
                  onSelected: (String newValue) {
                    setState(() {
                      selectedCategory = newValue;
                    });
                  },
                  itemBuilder: (context) {
                    return ['Breakfast', 'Lunch', 'Dinner', 'Snacks']
                        .map((String value) {
                      final isSelected = value == selectedCategory;
                      return PopupMenuItem<String>(
                        value: value,
                        height: 48,
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            value,
                            style: GoogleFonts.poppins(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFF2196F3)
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList();
                  },
                  // The Trigger Child is the entire "Button" container
                  child: Container(
                    height: 54,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Icon(Icons.restaurant_menu,
                            size: 20, color: Colors.grey[600]),
                        const SizedBox(width: 12),
                        Text(
                          "Adding to:",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                selectedCategory,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: const Color(0xFF2196F3),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: Color(0xFF2196F3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // ---- DIVIDER ----
        const Divider(height: 1, color: Colors.grey),

        // ---- FOOD LIST ----
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _myFoodsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final foods = snapshot.data ?? [];

              if (foods.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // Hug content height
                    children: [
                      Icon(
                        Icons.no_food_outlined,
                        size: 60,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No custom foods yet',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Add your own foods to track them easily every day.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                      ),
                      // This empty space pushes the center visual slightly up
                      const SizedBox(height: 50),
                    ],
                  ),
                );
              }

              return ListView.separated(
                // 1. Set outer padding to 16 so top/bottom of the whole list matches
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: foods.length,
                // 2. Set space between items to 16
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final item = foods[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Dismissible(
                      key: ValueKey(item['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              "Delete",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.delete_outline, color: Colors.white),
                          ],
                        ),
                      ),
                      onDismissed: (_) {
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('custom_foods')
                            .doc(item['id'])
                            .delete();

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${item['name']} deleted')),
                        );
                      },
                      child: Card(
                        // 3. Remove vertical margin here so only ListView controls spacing
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: cardBorderColor, width: 1),
                        ),
                        elevation: 3,
                        shadowColor: Colors.black26,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showFoodDialog(existingItem: item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name'],
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${item['calories']} kcal • ${item['serving_size'] ?? '1 serving'}",
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor:
                                        _justAddedFdcId == item['id']
                                        ? Colors.green
                                        : const Color(0xFF2196F3),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    // Matches search tab padding
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    // Removes extra touch target spacing
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    // REMOVED: minimumSize: Size.zero, to match Search tab size
                                  ),
                                  onPressed: () {
                                    if (_justAddedFdcId != null) return;

                                    // Trigger the add callback
                                    widget.onFoodAdded?.call(
                                      item,
                                      selectedCategory,
                                    );

                                    // Show SnackBar
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Added "${item['name']}" to $selectedCategory',
                                        ),
                                        duration: const Duration(seconds: 2),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    );

                                    // Trigger Animation Logic
                                    setState(() {
                                      _justAddedFdcId =
                                          item['id']; // Use 'id' for custom foods
                                    });

                                    _feedbackTimer?.cancel();
                                    _feedbackTimer = Timer(
                                      const Duration(seconds: 1),
                                      () {
                                        if (mounted) {
                                          setState(() {
                                            _justAddedFdcId = null;
                                          });
                                        }
                                      },
                                    );
                                  },
                                  child: _justAddedFdcId == item['id']
                                      ? const Icon(
                                          Icons.check,
                                          size:
                                              18, // Matches font size/icon size balance
                                          color: Colors.white,
                                        )
                                      : Text(
                                          'ADD',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecipeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Buttons Row
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _RecipeActionButton(
                    title: 'Discover\nRecipes',
                    subtitle: 'Browse a variety of healthy recipes',
                    icon: Icons.restaurant_menu,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DiscoverRecipesPage(
                            selectedDate: widget.selectedDate,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _RecipeActionButton(
                    title: 'Generate\nMeal Plan',
                    subtitle: 'Let AI plan your meals for the day',
                    icon: Icons.fastfood,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GenerateMealPlanPage(
                            selectedDate: widget.selectedDate,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Divider for separation
          const Divider(thickness: 1.2, color: Colors.grey),
          const SizedBox(height: 16),

          // Saved Recipes Section Header
          Text(
            'Saved Recipes',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your favorite recipes at a glance',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // Saved Recipes Section (no container wrapping)
          _buildSavedRecipesSection(),
        ],
      ),
    );
  }

  Widget _buildSavedRecipesSection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    Stream<List<Map<String, dynamic>>> _savedRecipesStream() {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('saved_recipes')
          .snapshots()
          .map(
            (snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'name': data['name'] ?? data['title'] ?? 'No Title',
                'image': data['image'] ?? 'https://via.placeholder.com/150',
                'description': data['description'] ?? '',
                'ingredients': data['ingredients'] ?? [],
                'steps': data['steps'] ?? [],
                'nutrients': data['nutrients'] ?? {},
                'url': data['url'] ?? '',
              };
            }).toList(),
          );
    }

    Future<void> _removeRecipe(String recipeId) async {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved_recipes')
            .doc(recipeId)
            .delete();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from Favorites')));
      } catch (e) {
        debugPrint('Error removing saved recipe: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove recipe.')),
        );
      }
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _savedRecipesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final recipes = snapshot.data!;
        if (recipes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                "You haven't saved any recipes yet.",
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            final nutrients = recipe['nutrients'] ?? {};
            final kcal = nutrients['kcal'] ?? nutrients['calories'] ?? '-';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent, // Keep container background visible
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
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
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            recipe['image'],
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 60,
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recipe['name'],
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$kcal kcal',
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.bookmark_remove,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeRecipe(recipe['id']),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// --------------------------------------------------------------------------
// HELPER CLASSES
// --------------------------------------------------------------------------
class _CreateFoodDialog extends StatefulWidget {
  final Map<String, dynamic>? existingItem;

  const _CreateFoodDialog({this.existingItem});

  @override
  State<_CreateFoodDialog> createState() => _CreateFoodDialogState();
}

class _CreateFoodDialogState extends State<_CreateFoodDialog> {
  final _nameController = TextEditingController();
  final _servingController = TextEditingController();
  final _calController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbController = TextEditingController();
  final _fatController = TextEditingController();

  final _calFocus = FocusNode();
  final _proteinFocus = FocusNode();
  final _carbFocus = FocusNode();
  final _fatFocus = FocusNode();

  bool _isLoading = false;

  String? _nameError;
  String? _servingError;
  String? _calError;
  String? _macrosError;

  @override
  void initState() {
    super.initState();

    _calFocus.addListener(() => setState(() {}));
    _proteinFocus.addListener(() => setState(() {}));
    _carbFocus.addListener(() => setState(() {}));
    _fatFocus.addListener(() => setState(() {}));

    if (widget.existingItem != null) {
      _nameController.text = widget.existingItem!['name'].toString();
      _servingController.text =
          widget.existingItem!['serving_size']?.toString() ?? '1 serving';
      _calController.text = widget.existingItem!['calories'].toString();
      _proteinController.text = widget.existingItem!['protein'].toString();
      _carbController.text = widget.existingItem!['carbs'].toString();
      _fatController.text = widget.existingItem!['fat'].toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _servingController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbController.dispose();
    _fatController.dispose();

    // Dispose focus nodes
    _calFocus.dispose();
    _proteinFocus.dispose();
    _carbFocus.dispose();
    _fatFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isEditing = widget.existingItem != null;

    // Helper for macro input fields
    Widget _buildMacroInput(
      String label,
      String suffix,
      TextEditingController controller,
      Color color,
    ) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.start,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: "0",
                suffixText: suffix,
                suffixStyle: TextStyle(fontSize: 12, color: Colors.grey[600]),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== HEADER =====
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fastfood,
                    color: Color(0xFF2196F3),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Wrap Column in Expanded to push the delete button to the right
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'Edit Food' : 'Create Food',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Enter food information',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),

                // Only show Delete button if editing
                if (isEditing)
                  IconButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Delete Food"),
                          content: const Text(
                            "Are you sure you want to delete this custom food?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text("Delete"),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true && uid != null) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('custom_foods')
                            .doc(widget.existingItem!['id'])
                            .delete();

                        if (context.mounted) {
                          Navigator.pop(context); // Close the Edit Dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${widget.existingItem!['name']} deleted',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Delete Food',
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // ===== FOOD NAME =====
            Text(
              "Food Name",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              // Clear error on type
              onChanged: (_) => setState(() => _nameError = null),
              decoration: InputDecoration(
                hintText: 'e.g. Chicken Salad',
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: const Icon(
                  Icons.restaurant_menu,
                  size: 18,
                  color: Colors.grey,
                ),
                // Change border color on error
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _nameError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : const BorderSide(color: Colors.blue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            if (_nameError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _nameError!,
                  style: GoogleFonts.poppins(color: Colors.red, fontSize: 11),
                ),
              ),

            const SizedBox(height: 14),

            // ===== SERVING SIZE =====
            Text(
              "Serving Size",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _servingController,
              onChanged: (_) => setState(() => _servingError = null),
              decoration: InputDecoration(
                hintText: 'e.g. 100g, 1 bowl',
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: const Icon(
                  Icons.set_meal,
                  size: 18,
                  color: Colors.grey,
                ),
                // Change border color on error
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _servingError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _servingError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: _servingError != null
                      ? const BorderSide(color: Colors.redAccent)
                      : const BorderSide(color: Colors.blue, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
            ),
            if (_servingError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _servingError!,
                  style: GoogleFonts.poppins(color: Colors.red, fontSize: 11),
                ),
              ),

            const SizedBox(height: 18),

            // ===== CALORIES BOX =====
            Text(
              "Calories",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                // Change border color on error
                border: Border.all(
                  color: _calError != null
                      ? Colors.redAccent
                      : _calFocus.hasFocus
                      ? Colors.blue
                      : Colors.orange.withOpacity(0.25),
                  width: _calFocus.hasFocus && _calError == null ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_fire_department,
                    color: Colors.orange,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _calController,
                      focusNode: _calFocus,
                      onChanged: (_) => setState(() => _calError = null),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign:
                          TextAlign.start, // hint and input aligned to start
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: "0",
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "kcal",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            if (_calError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _calError!,
                  style: GoogleFonts.poppins(color: Colors.red, fontSize: 11),
                ),
              ),

            const SizedBox(height: 18),

            // ===== MACROS =====
            Text(
              "Macronutrients",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                // PROTEIN
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      // Change border color on error
                      border: Border.all(
                        color: _macrosError != null
                            ? Colors.redAccent
                            : _proteinFocus.hasFocus
                            ? Colors.blue
                            : Colors.green.withOpacity(0.3),
                        width: _proteinFocus.hasFocus && _macrosError == null
                            ? 1.5
                            : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Protein",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _proteinController,
                                focusNode: _proteinFocus,
                                onChanged: (_) =>
                                    setState(() => _macrosError = null),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "0",
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "g",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // CARBS
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      // Change border color on error
                      border: Border.all(
                        color: _macrosError != null
                            ? Colors.redAccent
                            : _carbFocus.hasFocus
                            ? Colors.blue
                            : Colors.blue.withOpacity(0.3),
                        width: _carbFocus.hasFocus && _macrosError == null
                            ? 1.5
                            : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Carbs",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _carbController,
                                focusNode: _carbFocus,
                                onChanged: (_) =>
                                    setState(() => _macrosError = null),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "0",
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "g",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // FATS
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      // Change border color on error
                      border: Border.all(
                        color: _macrosError != null
                            ? Colors.redAccent
                            : _fatFocus.hasFocus
                            ? Colors.blue
                            : Colors.red.withOpacity(0.3),
                        width: _fatFocus.hasFocus && _macrosError == null
                            ? 1.5
                            : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Fats",
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _fatController,
                                focusNode: _fatFocus,
                                onChanged: (_) =>
                                    setState(() => _macrosError = null),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "0",
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "g",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
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
            // SHARED MACRO ERROR
            if (_macrosError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _macrosError!,
                  style: GoogleFonts.poppins(color: Colors.red, fontSize: 11),
                ),
              ),

            const SizedBox(height: 26),

            // ===== ACTIONS =====
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "Cancel",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading
                        ? null
                        : () async {
                            // --- VALIDATION START ---
                            if (uid == null) return;

                            bool isValid = true;
                            // Reset errors
                            setState(() {
                              _nameError = null;
                              _servingError = null;
                              _calError = null;
                              _macrosError = null;
                            });

                            // 1. Validate Name
                            final name = _nameController.text.trim();
                            if (name.isEmpty) {
                              setState(
                                () => _nameError = 'Please enter a food name',
                              );
                              isValid = false;
                            }

                            // 2. Validate Serving Size
                            final servingSize = _servingController.text.trim();
                            if (servingSize.isEmpty) {
                              setState(
                                () => _servingError =
                                    'Please enter a serving size',
                              );
                              isValid = false;
                            } else if (!RegExp(r'^\d+').hasMatch(servingSize)) {
                              setState(
                                () => _servingError =
                                    'Serving size must start with a number (e.g. "100g", "1 bowl")',
                              );
                              isValid = false;
                            } else {
                              // Extract the number part to ensure it is > 0
                              final match = RegExp(
                                r'^(\d+(\.\d+)?)',
                              ).firstMatch(servingSize);
                              if (match != null) {
                                final val = double.tryParse(match.group(1)!);
                                if (val != null && val <= 0) {
                                  setState(
                                    () => _servingError =
                                        'Serving size must be more than 0',
                                  );
                                  isValid = false;
                                }
                              }

                              // Check for missing unit ONLY if we haven't already flagged an error (like value <= 0)
                              if (_servingError == null &&
                                  RegExp(
                                    r'^\d+(\.\d+)?\s*$',
                                  ).hasMatch(servingSize)) {
                                setState(
                                  () => _servingError =
                                      'Please specify a unit (e.g. "100g", "1 cup")',
                                );
                                isValid = false;
                              }
                            }

                            // 3. Validate Calories
                            final calories = double.tryParse(
                              _calController.text.trim(),
                            );
                            if (calories == null || calories < 0) {
                              setState(
                                () => _calError =
                                    'Please enter a valid calories value',
                              );
                              isValid = false;
                            }

                            // 4. Validate Macros (Shared)
                            final protein = double.tryParse(
                              _proteinController.text.trim(),
                            );
                            final carbs = double.tryParse(
                              _carbController.text.trim(),
                            );
                            final fat = double.tryParse(
                              _fatController.text.trim(),
                            );

                            if (protein == null ||
                                protein < 0 ||
                                carbs == null ||
                                carbs < 0 ||
                                fat == null ||
                                fat < 0) {
                              setState(
                                () => _macrosError =
                                    'Please enter valid values for all macros',
                              );
                              isValid = false;
                            }

                            if (!isValid) return;
                            // --- VALIDATION END ---

                            setState(() => _isLoading = true);
                            try {
                              final data = {
                                'name': name,
                                'serving_size': servingSize,
                                'calories': calories!.round(),
                                'protein': protein!.round(),
                                'carbs': carbs!.round(),
                                'fat': fat!.round(),
                                if (!isEditing)
                                  'createdAt': FieldValue.serverTimestamp(),
                              };

                              final collection = FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('custom_foods');

                              if (isEditing) {
                                await collection
                                    .doc(widget.existingItem!['id'])
                                    .update(data);
                              } else {
                                await collection.add(data);
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? '${data['name']} updated successfully'
                                          : '${data['name']} created successfully',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                      ),
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Error saving food: $e',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            isEditing ? 'Update Food' : 'Save Food',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeActionButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final Gradient? gradient;

  const _RecipeActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color,
    this.gradient,
  });

  @override
  State<_RecipeActionButton> createState() => _RecipeActionButtonState();
}

class _RecipeActionButtonState extends State<_RecipeActionButton>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250), // SLOWER animation
      lowerBound: 0.94, // Slightly deeper press
      upperBound: 1.0,
      value: 1.0,
    );

    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic, // smoother curve
      reverseCurve: Curves.easeInCubic,
    );

    _controller.addListener(() {
      setState(() {
        _scale = _curve.value;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _controller.reverse(); // shrink while holding
      },
      onTapUp: (_) async {
        await Future.delayed(const Duration(milliseconds: 120)); // longer pause
        await _controller.forward(); // slow expand
        widget.onTap();
      },
      onTapCancel: () {
        _controller.forward();
      },
      child: Transform.scale(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          decoration: BoxDecoration(
            color: widget.color,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 28, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
