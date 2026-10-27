import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easyhealthy/utils/notification_scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'main.dart';
import 'package:provider/provider.dart';
import 'model/ActivityLevel.dart';
import 'utils/theme_provider.dart';
import 'utils/health_calculator.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _userDataFuture;
  bool notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userDataFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    }
  }

  Future<void> _signOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthWrapper()),
          (Route<dynamic> route) => false,
    );
  }

  Future<void> _updateDailyBurnGoal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // We need to fetch the most up-to-date data to perform the calculation
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();

    if (data == null) return;

    // Safely extract all required values
    final double? weight = (data['weight'] as num?)?.toDouble();
    final double? height = (data['height'] as num?)?.toDouble();
    final int? age = (data['age'] as num?)?.toInt();
    final String? gender = data['gender'] as String?;
    final String? activityLevelLabel = data['activity_level'] as String?;
    final String? fitnessGoal = data['fitnessGoal'] as String?;

    // Find the corresponding ActivityLevel object (or null if not found).
    final ActivityLevel? activityLevel = activityLevelLabel != null
        ? activityLevels.firstWhere(
          (level) => level.label == activityLevelLabel,
      orElse: () => activityLevels
          .first, // Fallback to avoid crash, but multiplier will be used correctly
    )
        : null;

    // Ensure we have the minimum required data before calculating
    if (weight! > 0 && height! > 0) {
      final int recommendedBurn =
      HealthCalculator.calculateRecommendedCalorieBurn(
        bmi: HealthCalculator.calculateBMI(weight, height),
        weightKg: weight,
        heightCm: height,
        age: age,
        gender: gender,
        activityMultiplier: activityLevel?.multiplier,
        fitnessGoal: fitnessGoal,
      );

      // Update the daily_burn_goal in Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'daily_burn_goal': recommendedBurn},
      );
    }
  }

  // ---  Update Daily Consume Goal (Nutrition) ---
  Future<void> _updateDailyConsumeGoal() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return;

    final double? weight = (data['weight'] as num?)?.toDouble();
    final double? height = (data['height'] as num?)?.toDouble();
    final int? age = (data['age'] as num?)?.toInt();
    final String? gender = data['gender'] as String?;
    final String? activityLevelLabel = data['activity_level'] as String?;
    final String? fitnessGoal = data['fitnessGoal'] as String?;

    // Ensure we have minimum data to calculate Goals
    if (weight != null && height != null && age != null && gender != null) {

      final Map<String, dynamic> newGoals = HealthCalculator.calculateDailyNutrientGoals(
        weightKg: weight,
        heightCm: height,
        age: age,
        gender: gender,
        activityLevel: activityLevelLabel ?? 'Sedentary',
        fitnessGoal: fitnessGoal ?? 'maintain',
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'daily_consume_goal': newGoals});
    }
  }

  // --- DIALOGS ---

  Future<void> _showSelectionDialog(
      String field,
      String currentValue,
      String label,
      List<String> options,
      ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Select $label"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options[index];
              return ListTile(
                title: Text(option),
                // Highlight the currently selected option
                selected: option == currentValue,
                selectedTileColor: Theme.of(
                  context,
                ).primaryColor.withOpacity(0.1),
                onTap: () {
                  Navigator.pop(context, option);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );

    if (newValue != null && newValue.isNotEmpty && newValue != currentValue) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {field: newValue},
      );

      // Update BOTH goals
      await _updateDailyBurnGoal();
      await _updateDailyConsumeGoal();

      // Refresh the UI with the new data
      setState(() {
        _userDataFuture = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
      });
    }
  }

  Future<void> _showActivityLevelDialog(String currentValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final List<ActivityLevel> options = activityLevels;

    final String? newLevelLabel = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Activity Level"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final level = options[index];
              return ListTile(
                // Use the 'label' and 'description' properties from your class
                title: Text(level.label),
                subtitle: Text(
                  level.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                selected: level.label == currentValue, // Compare with the label
                selectedTileColor: Theme.of(
                  context,
                ).primaryColor.withOpacity(0.1),
                onTap: () {
                  Navigator.pop(
                    context,
                    level.label,
                  ); // Return the label string
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );

    if (newLevelLabel != null &&
        newLevelLabel.isNotEmpty &&
        newLevelLabel != currentValue) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'activity_level': newLevelLabel},
      ); // Save the label to Firestore

      // Update BOTH goals
      await _updateDailyBurnGoal();
      await _updateDailyConsumeGoal();

      setState(() {
        _userDataFuture = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
      });
    }
  }

  Future<void> _showEditDialog(
      String field,
      String currentValue,
      String label,
      ) async {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController controller = TextEditingController(
      text: currentValue,
    );
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final String? result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $label"),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "Enter new $label",
              border: const OutlineInputBorder(),
              errorStyle: const TextStyle(fontWeight: FontWeight.w500),
            ),
            keyboardType:
            (field == 'weight' || field == 'height' || field == 'age')
                ? const TextInputType.numberWithOptions(
              decimal: true,
            ) // Allow decimals
                : TextInputType.text,

            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'This field cannot be empty.';
              }

              if (field == 'username') {
                if (value.trim().length < 3) {
                  return 'Username must be at least 3 characters.';
                }
              }

              // Specific validation for numeric fields
              if (field == 'weight' || field == 'height' || field == 'age') {
                final number = double.tryParse(value.trim());
                if (number == null) {
                  return 'Please enter a valid number.';
                }
                if (number <= 0) {
                  return 'Value must be greater than zero.';
                }
                if (field == 'age' && number > 120) {
                  return 'Please enter a realistic age.';
                }
                if (field == 'height' && number > 270) {
                  return 'Please enter a realistic height in cm.';
                }
              }
              return null; // Return null if input is valid
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              // 5. Check if the form is valid before closing the dialog
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, controller.text);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    // If dialog was cancelled or nothing was entered
    if (result == null || result.trim().isEmpty || result == currentValue)
      return;

    if (field == 'username') {
      try {
        await user.updateDisplayName(result.trim());
        await user.reload();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update username: $e")),
        );
        return;
      }
    } else {
      // Handle numeric fields
      dynamic valueToSave = num.parse(
        result.trim(),
      ); // Use num.parse directly, it's safe now

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {field: valueToSave},
      );

      // Recalculate burn goal when numeric fields change
      if (field == 'weight' || field == 'height' || field == 'age') {
        await _updateDailyBurnGoal();
        await _updateDailyConsumeGoal();
      }
    }

    // Refresh UI
    setState(() {
      _userDataFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    });
  }

  Future<AuthCredential?> _promptForReauthentication() async {
    try {

      final googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {

        return null;
      }

      final googleAuth = await googleUser.authentication;

      return GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text(
          "Are you sure you want to delete your account? This will permanently erase all your data. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Show a loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Deleting account and all associated data..."),
        ),
      );

      final db = FirebaseFirestore.instance;
      final uid = user.uid;

      // 1. Delete associated data from other collections in batches
      final collectionsToDelete = [
        'user_activities',
        'user_habits',
        'workout_plans',
      ];

      final userHabitsSnapshot = await db
          .collection('user_habits')
          .where('user_id', isEqualTo: uid)
          .get();

      final habitIds = userHabitsSnapshot.docs
          .map((doc) => doc.data()['habitId'] as String?)
          .where((id) => id != null)
          .toList();

      // Now, check which of these are custom habits and delete them
      if (habitIds.isNotEmpty) {
        final habitsToDeleteBatch = db.batch();

        final customHabitsQuery = await db
            .collection('habits')
            .where('id', whereIn: habitIds)
            .where('isDefault', isEqualTo: false)
            .get();

        for (final doc in customHabitsQuery.docs) {
          habitsToDeleteBatch.delete(doc.reference);
        }
        await habitsToDeleteBatch.commit();
      }

      for (final collectionName in collectionsToDelete) {
        final fieldToQuery = collectionName == 'workout_plans'
            ? 'userId'
            : 'user_id';
        final querySnapshot = await db
            .collection(collectionName)
            .where(fieldToQuery, isEqualTo: uid)
            .get();
        final batch = db.batch();
        for (final doc in querySnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      final subcollectionsToDelete = ['meal_logs', 'saved_recipes', 'custom_foods'];
      //Delete subcollections
      for (final subcollectionName in subcollectionsToDelete) {
        final subcollectionSnapshot = await db
            .collection('users')
            .doc(uid)
            .collection(subcollectionName)
            .get();

        final batch = db.batch();
        for (final doc in subcollectionSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Delete the main user document from the 'users' collection
      await db.collection('users').doc(uid).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account successfully deleted."),
            backgroundColor: Colors.green,
          ),
        );

        // A small delay helps the user see the message
        await Future.delayed(const Duration(seconds: 1));

        // Navigate away and remove all previous routes
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (_) => false,
        );
      }

      try {
        // Sign out from Google first if that's the provider.
        if (user.providerData.any((p) => p.providerId == GoogleAuthProvider.PROVIDER_ID)) {
          await GoogleSignIn().signOut();
        }

        await user.delete();

      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          final credential = await _promptForReauthentication();
          if (credential != null) {
            await user.reauthenticateWithCredential(credential);
            await user.delete();
          }
        }
      }

    } catch (e) {
      // Handle any errors during deletion
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete account: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Profile")),
        body: const Center(child: Text("No user logged in.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Profile", style: GoogleFonts.poppins()),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _userDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("User data not found."));
          }

          final userData = snapshot.data!.data();
          final double height = (userData?['height'] as num?)?.toDouble() ?? 0;
          final double weight = (userData?['weight'] as num?)?.toDouble() ?? 0;
          double bmi = 0;
          if (height > 0 && weight > 0) {
            bmi = HealthCalculator.calculateBMI(weight, height);
          }

          // Get the dynamic list of goals
          final List<String> fitnessGoals =
          HealthCalculator.getFitnessGoalsForBMI(bmi);
          final bool mainReminderEnabled =
              userData?['mainReminderEnabled'] ?? true;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // HEADER
                _buildProfileHeader(user),
                const SizedBox(height: 32),

                // PERSONAL INFORMATION
                _buildSectionTitle("Basic Information"),
                const SizedBox(height: 16),
                _buildInfoCard(
                  "Weight",
                  "${userData?['weight']} kg",
                  onTap: () => _showEditDialog(
                    'weight',
                    userData?['weight']?.toString() ?? '',
                    'Weight',
                  ),
                ),
                _buildInfoCard(
                  "Height",
                  "${userData?['height']} cm",
                  onTap: () => _showEditDialog(
                    'height',
                    userData?['height']?.toString() ?? '',
                    'Height',
                  ),
                ),

                const SizedBox(height: 16),

                // FITNESS GOALS
                _buildSectionTitle("Additional Information"),
                const SizedBox(height: 16),
                _buildInfoCard(
                  "Age",
                  "${userData?['age'] ?? 'Not Set'}",
                  onTap: () => _showEditDialog(
                    'age',
                    userData?['age']?.toString() ?? '',
                    'Age',
                  ),
                ),
                _buildInfoCard(
                  "Gender",
                  "${userData?['gender'] ?? 'Not Set'}",
                  onTap: () => _showSelectionDialog(
                    'gender',
                    userData?['gender'] ?? '',
                    'Gender',
                    ['Male', 'Female', 'Prefer not to say'],
                  ),
                ),
                _buildInfoCard(
                  "Activity Level",
                  "${userData?['activity_level'] ?? 'Not Set'}",
                  onTap: () => _showActivityLevelDialog(
                    userData?['activity_level'] ?? '',
                  ),
                ),
                _buildInfoCard(
                  "Fitness Goal",
                  "${userData?['fitnessGoal'] ?? 'Not Set'}",
                  onTap: () => _showSelectionDialog(
                    'fitnessGoal',
                    userData?['fitnessGoal'] ?? '',
                    'Fitness Goal',
                    fitnessGoals,
                  ),
                ),
                const SizedBox(height: 16),

                // SETTINGS
                _buildSectionTitle("App Settings"),
                const SizedBox(height: 16),
                _buildInfoCard(
                  "Dark Mode",
                  null,
                  icon: themeProvider.isDarkMode
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  trailing: Switch(
                    value: themeProvider.isDarkMode,
                    onChanged: (value) {
                      themeProvider.toggleTheme(value);
                    },
                  ),
                ),
                _buildInfoCard(
                  "Notifications",
                  null,
                  icon: Icons.notifications_active_outlined,
                  trailing: Switch(

                    value: mainReminderEnabled,

                    onChanged: (value) async {

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .update({'mainReminderEnabled': value});

                      await NotificationScheduler().scheduleAllReminders();

                      setState(() {
                        _userDataFuture = FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get();
                      });
                    },

                  ),
                ),

                const SizedBox(height: 32),

                // DANGER ZONE
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _deleteAccount,
                  child: Text(
                    "Delete Account",
                    style: GoogleFonts.poppins(fontSize: 16),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // UI Helpers
  Widget _buildProfileHeader(User user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundImage: user.photoURL != null
              ? NetworkImage(user.photoURL!)
              : null,
          child: user.photoURL == null
              ? const Icon(Icons.person, size: 50)
              : null,
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () =>
              _showEditDialog('username', user.displayName ?? '', 'Username'),
          borderRadius: BorderRadius.circular(8), // For a nice ripple effect
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user.displayName ?? "No Name",
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.edit, size: 18, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          user.email ?? "No Email",
          style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildInfoCard(
      String label,
      String? value, {
        IconData? icon,
        Widget? trailing,
        VoidCallback? onTap,
      }) {
    // Use the value for the subtitle, so it appears below the title (label)
    final Widget valueWidget = Text(
      value ?? 'N/A',
      style: GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );

    // Determine the trailing widget
    Widget? computedTrailing = trailing;

    // If trailing is null and it's tappable (e.g., Weight, Activity Level), show only the edit icon
    if (trailing == null && onTap != null) {
      computedTrailing = Icon(
        Icons.edit_outlined,
        color: Colors.grey[400],
        size: 18,
      );
    }
    // If trailing is null and it's NOT tappable (e.g., a simple view-only card), computedTrailing remains null.

    return Card(
      elevation: 1,
      child: ListTile(
        onTap: onTap,

        // Use default padding for better visual spacing
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),

        leading: Icon(icon ?? Icons.info_outline),

        // 1. Use the simple label as the title
        title: Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),

        // 2. Use the value as the subtitle (second row), but only if a value is provided
        subtitle: value != null ? valueWidget : null,

        // 3. Use the computed trailing (Switch or Edit Icon)
        trailing: computedTrailing,
      ),
    );
  }
}