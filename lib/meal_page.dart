import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'searchFood.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'utils/health_calculator.dart';

class MealPage extends StatefulWidget {
  const MealPage({Key? key}) : super(key: key);

  @override
  State<MealPage> createState() => _MealPageState();
}

class _MealPageState extends State<MealPage> {
  // --- DATE STATE ---
  DateTime _selectedDate = DateTime.now();

  String _getDateKey(DateTime date) {
    return DateFormat('dd-MM-yyyy').format(date);
  }

  // --- FIREBASE HELPERS ---
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference get _dayDocRef {
    if (_uid == null) throw Exception("User not logged in");
    final dateKey = _getDateKey(_selectedDate);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('meal_logs')
        .doc(dateKey);
  }

  // --- BUSINESS LOGIC (FIREBASE) ---
  Future<void> _addFoodItem(Map<String, dynamic> food, String category) async {
    if (_uid == null) return;

    try {
      // 1. Fetch current data to check for duplicates
      final docSnapshot = await _dayDocRef.get();
      List<dynamic> currentList = [];

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        if (data.containsKey(category)) {
          currentList = List.from(data[category]);
        }
      }

      // 2. Search for existing item by name
      final existingIndex = currentList.indexWhere((item) => item['name'] == food['name']);

      if (existingIndex != -1) {
        // --- UPDATE EXISTING ITEM ---
        final existingItem = Map<String, dynamic>.from(currentList[existingIndex]);

        double currentQty = (existingItem['quantity'] as num?)?.toDouble() ?? 1.0;
        double newQty = currentQty + 1.0;

        // Use base values for calculation to ensure accuracy
        int baseCalories = existingItem['base_calories'] ?? existingItem['calories'];
        int baseProtein = existingItem['base_protein'] ?? existingItem['protein'] ?? 0;
        int baseCarbs = existingItem['base_carbs'] ?? existingItem['carbs'] ?? 0;
        int baseFat = existingItem['base_fat'] ?? existingItem['fat'] ?? 0;

        existingItem['quantity'] = newQty;
        existingItem['calories'] = (baseCalories * newQty).round();
        existingItem['protein'] = (baseProtein * newQty).round();
        existingItem['carbs'] = (baseCarbs * newQty).round();
        existingItem['fat'] = (baseFat * newQty).round();

        // Ensure time field exists on the existing item
        if (existingItem['time'] == null) {
          existingItem['time'] = Timestamp.now();
        }

        currentList[existingIndex] = existingItem;

      } else {
        // --- ADD NEW ITEM ---
        final entry = {
          'name': food['name'],
          'quantity': 1.0,
          'calories': food['calories'],
          'protein': food['protein'] ?? 0,
          'carbs': food['carbs'] ?? 0,
          'fat': food['fat'] ?? 0,
          'base_calories': food['calories'],
          'base_protein': food['protein'] ?? 0,
          'base_carbs': food['carbs'] ?? 0,
          'base_fat': food['fat'] ?? 0,
          'time': Timestamp.now(),
        };
        currentList.add(entry);
      }

      // 3. Sort list by time (Ascending: Oldest -> Newest)
      currentList.sort((a, b) {
        Timestamp t1 = a['time'] ?? Timestamp(0, 0);
        Timestamp t2 = b['time'] ?? Timestamp(0, 0);
        return t1.compareTo(t2);
      });

      // 4. Save the full sorted list
      await _dayDocRef.set({
        category: currentList
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error adding food: $e");
    }
  }

  Future<void> _removeItem(String category, Map<String, dynamic> itemToRemove) async {
    if (_uid == null) return;
    try {
      await _dayDocRef.update({
        category: FieldValue.arrayRemove([itemToRemove])
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${itemToRemove['name']}"'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print("Error removing item: $e");
    }
  }

  Future<void> _editItem(String category, Map<String, dynamic> oldItem) async {
    // 1. Get Base Values
    final double currentQty = (oldItem['quantity'] as num? ?? 1.0).toDouble();

    final int baseCalories = oldItem['base_calories'] ?? (oldItem['calories'] as int? ?? 0);
    final int baseProtein = oldItem['base_protein'] ?? (oldItem['protein'] as int? ?? 0);
    final int baseCarbs = oldItem['base_carbs'] ?? (oldItem['carbs'] as int? ?? 0);
    final int baseFat = oldItem['base_fat'] ?? (oldItem['fat'] as int? ?? 0);

    String quantityStr = currentQty.toString();

    // 2. Show Dialog
    final newQtyStr = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        // Create controller once
        final TextEditingController qtyController = TextEditingController(text: quantityStr);
        // 1. Add Error State Variable
        String? qtyError;

        return StatefulBuilder(builder: (context, setStateDialog) {
          double qty = double.tryParse(qtyController.text) ?? 0;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            // INCREASED TOP PADDING HERE for better spacing
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),

            // --- TITLE ROW WITH DELETE ICON ---
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    // Push text down slightly so it aligns vertically with the icon
                    padding: const EdgeInsets.only(top: 14.0),
                    child: Text(
                      oldItem['name'] ?? 'Edit Item',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 18),
                      // Text wraps automatically now
                    ),
                  ),
                ),

                // Space between text and button
                const SizedBox(width: 8),

                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 24),
                  tooltip: 'Delete Item',
                  onPressed: () async {
                    // Show Confirmation Dialog
                    final bool? shouldDelete = await showDialog<bool>(
                      context: ctx,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Delete Item?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                          content: Text('Are you sure you want to remove this item?',
                              style: GoogleFonts.poppins()),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600])),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: Text('Delete',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        );
                      },
                    );

                    // If confirmed, delete and close
                    if (shouldDelete == true) {
                      Navigator.pop(ctx); // Close Edit Dialog
                      _removeItem(category, oldItem);
                    }
                  },
                ),
              ],
            ),
            // ----------------------------------

            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text("Number of Servings:",
                      style: GoogleFonts.poppins(color: Colors.grey[600])),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 2.0),
                    child: Text(
                      "Note: 1.0 equals 100g or 1 full serving",
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[500], fontStyle: FontStyle.italic),
                    ),
                  ),
                  TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // 2. Updated Decoration to show Error
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      errorText: qtyError, // Displays the red border and message
                    ),
                    onChanged: (v) {
                      // Update preview AND clear error when typing
                      setStateDialog(() {
                        if (qtyError != null) qtyError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 20),

                  // Live Preview
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Text("Nutrients Summary",
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[500],
                                letterSpacing: 1)),
                        const SizedBox(height: 4),

                        // BIG CALORIE NUMBER
                        Text(
                          "${(baseCalories * qty).round()} kcal",
                          style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2196F3)),
                        ),
                        // NEW CALORIES LABEL
                        Text(
                          "Calories",
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey[600]),
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _macroPreview(
                                "Protein", (baseProtein * qty).round(), Colors.orange),
                            _macroPreview("Carbs", (baseCarbs * qty).round(),
                                const Color(0xFF2196F3)),
                            _macroPreview(
                                "Fat", (baseFat * qty).round(), Colors.purple),
                          ],
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey[600]))),
              ElevatedButton(
                // 3. Validation Logic on Save
                  onPressed: () {
                    final text = qtyController.text.trim();
                    final val = double.tryParse(text);

                    if (text.isEmpty) {
                      setStateDialog(() { qtyError = "Please enter a quantity"; });
                      return;
                    }
                    if (val == null) {
                      setStateDialog(() { qtyError = "Please enter a valid number"; });
                      return;
                    }
                    if (val <= 0) {
                      setStateDialog(() { qtyError = "Quantity must be > 0"; });
                      return;
                    }

                    // If valid, return the text
                    Navigator.pop(ctx, text);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Update', style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
            ],
          );
        });
      },
    );

    // 3. Save Logic
    if (newQtyStr != null && _uid != null) {
      double newQty = double.tryParse(newQtyStr) ?? currentQty;
      if (newQty <= 0) newQty = 1.0;

      try {
        // Fetch current data to modify in-place (preserving order)
        final docSnapshot = await _dayDocRef.get();
        if (docSnapshot.exists) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          List<dynamic> currentList = [];
          if (data.containsKey(category)) {
            currentList = List.from(data[category]);
          }

          // Find the item to update by name
          final index = currentList.indexWhere((item) => item['name'] == oldItem['name']);

          if (index != -1) {
            final updatedItem = Map<String, dynamic>.from(currentList[index]);

            // Update properties
            updatedItem['quantity'] = newQty;
            updatedItem['base_calories'] = baseCalories;
            updatedItem['base_protein'] = baseProtein;
            updatedItem['base_carbs'] = baseCarbs;
            updatedItem['base_fat'] = baseFat;

            updatedItem['calories'] = (baseCalories * newQty).round();
            updatedItem['protein'] = (baseProtein * newQty).round();
            updatedItem['carbs'] = (baseCarbs * newQty).round();
            updatedItem['fat'] = (baseFat * newQty).round();

            // Replace the item at the specific index
            currentList[index] = updatedItem;

            // Sort by time (Oldest -> Newest) to ensure order is fixed
            currentList.sort((a, b) {
              Timestamp t1 = a['time'] ?? Timestamp(0, 0);
              Timestamp t2 = b['time'] ?? Timestamp(0, 0);
              return t1.compareTo(t2);
            });

            // Save the entire sorted list back
            await _dayDocRef.update({
              category: currentList
            });
          }
        }
      } catch (e) {
        print("Error editing item: $e");
      }
    }
  }

  // Helper widget for the dialog preview
  Widget _macroPreview(String label, int value, Color color) {
    return Column(
      children: [
        Text(
            "${value}g",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: color
            )
        ),
        const SizedBox(height: 2),
        Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[600]
            )
        ),
      ],
    );
  }

  Future<void> _showClearAllConfirmationDialog() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('Reset Day?', style: GoogleFonts.poppins()),
          content: Text(
            'This will remove all food entries for the selected day. Are you sure?',
            style: GoogleFonts.poppins(),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _dayDocRef.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All meal entries have been cleared for this day.')),
        );
      }
    }
  }

  Future<void> _openSearchAndAdd(String defaultCategory) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchFoodPage(
          defaultCategory: defaultCategory,
          selectedDate: _selectedDate,
          onFoodAdded: _addFoodItem,
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('en', 'GB'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _getDateDisplayString(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final selectedDay = DateTime(date.year, date.month, date.day);

    if (selectedDay == today) {
      return 'Today';
    } else if (selectedDay == yesterday) {
      return 'Yesterday';
    } else if (selectedDay == tomorrow) {
      return 'Tomorrow';
    } else {
      return DateFormat.EEEE().format(date);
    }
  }

  // --- WIDGET HELPERS ---
  Widget _smallMacro(String label, int value, int goal, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
            '$value / ${goal}g',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: color, fontSize: 14
            )
        ),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildTopSummary(
      int totalCalories, int calorieGoal,
      int totalProtein, int proteinGoal,
      int totalCarbs, int carbsGoal,
      int totalFat, int fatGoal
      ) {
    final percent = (calorieGoal > 0) ? (totalCalories / calorieGoal).clamp(0.0, 1.0) : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_getDateDisplayString(_selectedDate),
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700])),
                Text(
                  DateFormat.yMMMMd().format(_selectedDate),
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Calories Section (Linear Bar + Circular Chart)
            Row(
              children: [
                // Left Side: Text & Linear Bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$totalCalories / $calorieGoal kcal',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 10,
                          color: const Color(0xFF2196F3),
                          backgroundColor: const Color(0xFFF0F4FB),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right Side: Percentage Circle
                CircularPercentIndicator(
                  radius: 24.0, // Total size approx 48px
                  lineWidth: 4.0,
                  percent: percent,
                  center: Text(
                    "${(percent * 100).toInt()}%",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.grey[800]
                    ),
                  ),
                  progressColor: const Color(0xFF2196F3),
                  backgroundColor: const Color(0xFFF0F4FB),
                  circularStrokeCap: CircularStrokeCap.round,
                ),
              ],
            ),

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Macros Row with Goals
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _smallMacro('Protein', totalProtein, proteinGoal, Colors.orange),
                _smallMacro('Carbs', totalCarbs, carbsGoal, const Color(0xFF2196F3)),
                _smallMacro('Fat', totalFat, fatGoal, Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSection(String category, List<Map<String, dynamic>> items) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            // Header Row
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openSearchAndAdd(category),
                  icon: const Icon(Icons.add_outlined, size: 18),
                  label: Text('Add', style: GoogleFonts.poppins()),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF2196F3),
                    textStyle: GoogleFonts.poppins(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Items List
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No items yet. Tap Add to add food.',
                      style: GoogleFonts.poppins(color: Colors.grey[600])),
                ),
              )
            else
              Column(
                children: items.map((item) {
                  final uniqueKey = ValueKey("${item['name']}_${item['calories']}_${item['time']}");
                  final qty = item['quantity']?.toString() ?? '1.0';

                  return Dismissible(
                    key: uniqueKey,
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _removeItem(category, item),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        splashFactory: InkRipple.splashFactory,
                        splashColor: Colors.grey.withOpacity(0.2),
                        highlightColor: Colors.grey.withOpacity(0.1),
                        onTap: () async {
                          await Future.delayed(const Duration(milliseconds: 250));
                          if (context.mounted) {
                            _editItem(category, item);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          child: Row(
                            // --- CHANGED: BASELINE ALIGNMENT ---
                            // This ensures the "Food Name" and "Calories" sit on the exact same line
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] ?? '',
                                      style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Qty: ${qty}x",
                                      style: GoogleFonts.poppins(
                                          fontSize: 12, color: Colors.grey[500]),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // --- CHANGED: Removed Padding Wrapper ---
                              Text(
                                '${item['calories']} kcal',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2196F3)
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Center(child: Text("Please log in to view meals"));
    }

    // 1. WRAP IN FUTURE BUILDER TO FETCH USER GOALS
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(_uid).get(),
      builder: (context, userSnapshot) {

        // Default fallback goals
        int calorieGoal = 2000;
        int proteinGoal = 150;
        int carbsGoal = 250;
        int fatGoal = 70;

        // 2. CALCULATE REAL GOALS IF DATA EXISTS
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          try {
            final userData = userSnapshot.data!.data() as Map<String, dynamic>;

            final weight = (userData['weight'] as num?)?.toDouble() ?? 70.0;
            final height = (userData['height'] as num?)?.toDouble() ?? 170.0;
            final age = (userData['age'] as num?)?.toInt() ?? 25;
            final gender = userData['gender'] as String? ?? 'Male';
            final activityLevel = userData['activity_level'] as String? ?? 'Sedentary';
            final fitnessGoal = userData['goal'] as String? ?? 'Maintain';

            // Use the shared HealthCalculator
            final goals = HealthCalculator.calculateDailyNutrientGoals(
              weightKg: weight,
              heightCm: height,
              age: age,
              gender: gender,
              activityLevel: activityLevel,
              fitnessGoal: fitnessGoal,
            );

            calorieGoal = goals['calories']!;
            proteinGoal = goals['protein']!;
            carbsGoal = goals['carbs']!;
            fatGoal = goals['fat']!;

          } catch (e) {
            debugPrint("Error calculating goals in MealPage: $e");
          }
        }

        // 3. EXISTING STREAM BUILDER FOR MEAL LOGS
        return StreamBuilder<DocumentSnapshot>(
          stream: _dayDocRef.snapshots(),
          builder: (context, snapshot) {
            Map<String, List<Map<String, dynamic>>> data = {
              'Breakfast': [], 'Lunch': [], 'Dinner': [], 'Snacks': [],
            };

            if (snapshot.hasData && snapshot.data!.exists) {
              final docData = snapshot.data!.data() as Map<String, dynamic>;
              List<Map<String, dynamic>> getList(String key) {
                final list = docData[key] as List?;
                if (list == null) return [];
                return list.map((e) => Map<String, dynamic>.from(e)).toList();
              }
              data['Breakfast'] = getList('Breakfast');
              data['Lunch'] = getList('Lunch');
              data['Dinner'] = getList('Dinner');
              data['Snacks'] = getList('Snacks');
            }

            int _sumNutrient(String key) {
              int total = 0;
              for (var cat in ['Breakfast', 'Lunch', 'Dinner', 'Snacks']) {
                final list = data[cat]!;
                for (var item in list) {
                  total += (item[key] as num? ?? 0).toInt();
                }
              }
              return total;
            }

            int totalCalories = _sumNutrient('calories');
            int totalProtein = _sumNutrient('protein');
            int totalCarbs = _sumNutrient('carbs');
            int totalFat = _sumNutrient('fat');

            return Scaffold(
              appBar: AppBar(
                title: Padding(
                  padding: const EdgeInsets.only(top: 3.0),
                  child: Text('Meals', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
                centerTitle: true,
                leading: IconButton(
                  iconSize: 21.0,
                  icon: const Icon(Icons.calendar_today_outlined),
                  onPressed: () => _selectDate(context),
                ),
                actions: [
                  IconButton(
                    iconSize: 25,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _showClearAllConfirmationDialog,
                  ),
                ],
              ),
              body: RefreshIndicator(
                onRefresh: () async => await Future.delayed(const Duration(milliseconds: 300)),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96, top: 8),
                  children: [
                    // PASS ALL GOALS HERE
                    _buildTopSummary(
                        totalCalories, calorieGoal,
                        totalProtein, proteinGoal,
                        totalCarbs, carbsGoal,
                        totalFat, fatGoal
                    ),
                    _buildMealSection('Breakfast', data['Breakfast']!),
                    _buildMealSection('Lunch', data['Lunch']!),
                    _buildMealSection('Dinner', data['Dinner']!),
                    _buildMealSection('Snacks', data['Snacks']!),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
