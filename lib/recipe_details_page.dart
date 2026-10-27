import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RecipeDetailsPage extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final DateTime selectedDate;

  const RecipeDetailsPage({
    Key? key,
    required this.recipe,
    required this.selectedDate,
  }) : super(key: key);

  @override
  State<RecipeDetailsPage> createState() => _RecipeDetailsPageState();
}

class _RecipeDetailsPageState extends State<RecipeDetailsPage> {
  bool _adding = false;
  String _chosenCategory = 'Breakfast';
  final List<String> _categories = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

  // Stream of saved recipe IDs
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

  Future<void> _addToMeal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }

    setState(() => _adding = true);

    final recipe = widget.recipe;
    final nutrients = (recipe['nutrients'] ?? {}) as Map<String, dynamic>;

    // HELPER: 1. Parses decimal strings ("12.5") -> 2. Rounds to nearest Integer (13)
    int getSafeInt(dynamic value) {
      if (value == null) return 0;
      // tryParse handles "12.5", "12", and 12.5 correctly
      double? val = double.tryParse(value.toString());
      return val?.round() ?? 0;
    }

    final entry = {
      'name': recipe['name'] ?? 'Recipe',
      'quantity': 1.0,
      // Use the helper to get clean Integers
      'calories': getSafeInt(nutrients['kcal'] ?? nutrients['calories']),
      'protein': getSafeInt(nutrients['protein']),
      'carbs': getSafeInt(nutrients['carbs']),
      'fat': getSafeInt(nutrients['fat']),

      // Base values for future scaling
      'base_calories': getSafeInt(nutrients['kcal'] ?? nutrients['calories']),
      'base_protein': getSafeInt(nutrients['protein']),
      'base_carbs': getSafeInt(nutrients['carbs']),
      'base_fat': getSafeInt(nutrients['fat']),

      'time': Timestamp.now(),
    };

    final dateKey = widget.selectedDate;
    final formatted = '${dateKey.day.toString().padLeft(2, '0')}-${dateKey.month.toString().padLeft(2, '0')}-${dateKey.year}';

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_logs')
        .doc(formatted);

    try {
      await docRef.set({
        _chosenCategory: FieldValue.arrayUnion([entry])
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Added "${entry['name']}" to $_chosenCategory')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add: $e')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final nutrients = (r['nutrients'] ?? {}) as Map<String, dynamic>;
    final kcal = (nutrients['kcal'] ?? nutrients['calories'] ?? '').toString();

    return StreamBuilder<Set<String>>(
      stream: _savedIdsStream(),
      builder: (context, snapshot) {
        final savedIds = snapshot.data ?? {};
        final recipeId = r['id'];
        final isSaved = savedIds.contains(recipeId);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              r['name'] ?? 'Recipe',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: Colors.black,
                ),
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please login to save recipes')));
                    return;
                  }

                  final userRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('saved_recipes')
                      .doc(recipeId);

                  if (isSaved) {
                    await userRef.delete();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Removed from Favorites"),
                      duration: Duration(seconds: 1),
                    ));
                  } else {
                    await userRef.set(r);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Saved to Favorites"),
                      duration: Duration(seconds: 1),
                    ));
                  }
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image with smaller height and subtle shadow
                if ((r['image'] ?? '').toString().isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.grey.shade300,
                            blurRadius: 6,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        r['image'],
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  r['name'] ?? '',
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if ((r['description'] ?? '').toString().isNotEmpty)
                  Text(
                    r['description'],
                    style: GoogleFonts.poppins(
                        color: Colors.grey[700], fontSize: 14, height: 1.4),
                  ),
                const SizedBox(height: 16),

                // Nutrients card
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _nutrientColumn('Calories',
                            '${kcal.isNotEmpty ? kcal : '-'} kcal', Icons.local_fire_department, Colors.redAccent),
                        _nutrientColumn('Protein',
                            '${nutrients['protein'] ?? '-'} g', Icons.fitness_center, Colors.blueAccent),
                        _nutrientColumn('Carbs',
                            '${nutrients['carbs'] ?? '-'} g', Icons.grain, Colors.orangeAccent),
                        _nutrientColumn('Fat',
                            '${nutrients['fat'] ?? '-'} g', Icons.opacity, Colors.green),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Ingredients
                Text('Ingredients',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Card(
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: r['ingredients'] is List
                        ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: (r['ingredients'] as List)
                          .map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${i.toString()}',
                            style: GoogleFonts.poppins(fontSize: 14)),
                      ))
                          .toList(),
                    )
                        : Text('No ingredients available',
                        style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                ),

                const SizedBox(height: 16),

                // Steps
                Text('Steps',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Card(
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: r['steps'] is List
                        ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(
                        (r['steps'] as List).length,
                            (index) {
                          final step = (r['steps'] as List)[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text('${index + 1}.',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    step.toString(),
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.normal, fontSize: 14, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    )
                        : Text('No steps available',
                        style: GoogleFonts.poppins(color: Colors.grey[600])),
                  ),
                ),
              ],
            ),
          ),

          // Sticky Add to Meal section
          bottomNavigationBar: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade300,
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _chosenCategory,
                    items: _categories
                        .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500, fontSize: 14)),
                    ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _chosenCategory = v);
                    },
                    decoration: InputDecoration(
                      labelText: 'Add to',
                      labelStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[700]),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade400)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _adding ? null : _addToMeal,
                  icon: _adding
                      ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.add, size: 18, color: Colors.white),
                  label: Text(
                    _adding ? 'Adding...' : 'Add to Meal',
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _nutrientColumn(String label, String value, IconData icon, Color iconColor) {
    return Column(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
