import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  _GoalsPageState createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  String? _userId;

  // Controllers for the form fields
  final _weeklySessionsController = TextEditingController();
  final _weeklyDurationController = TextEditingController();
  final _dailyCalorieController = TextEditingController();
  int? _recommendedCalories;

  @override
  void initState() {
    super.initState();
    _loadCurrentGoals();
  }

  @override
  void dispose() {
    _weeklySessionsController.dispose();
    _weeklyDurationController.dispose();
    _dailyCalorieController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentGoals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    _userId = user.uid;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data()!;
        _weeklySessionsController.text = (data['goal_weekly_sessions'] as num?)?.toString() ?? '';
        _weeklyDurationController.text = (data['goal_weekly_duration'] as num?)?.toString() ?? '';
        _dailyCalorieController.text = (data['daily_burn_goal'] as num?)?.toString() ?? '';
      }
    } catch (e) {
      // Handle error
      print("Failed to load goals: $e");
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveGoals() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return; // If form is not valid, do not proceed.
    }
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Parse values from controllers
      final weeklySessions = _weeklySessionsController.text.isEmpty ? null : int.tryParse(_weeklySessionsController.text);
      final weeklyDuration = _weeklyDurationController.text.isEmpty ? null : int.tryParse(_weeklyDurationController.text);
      final dailyCalories = _dailyCalorieController.text.isEmpty ? null : int.tryParse(_dailyCalorieController.text);

      await FirebaseFirestore.instance.collection('users').doc(_userId).set({
        'goal_weekly_sessions': weeklySessions,
        'goal_weekly_duration': weeklyDuration,
        'daily_burn_goal': dailyCalories,
      }, SetOptions(merge: true));

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goals updated successfully!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }

    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save goals: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Your Fitness Goals'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : FloatingActionButton.extended(
          onPressed: _saveGoals,
          label: const Text(
            'Save Goals',
            style: TextStyle(fontSize: 16),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGoalCard(
                        controller: _weeklySessionsController,
                        icon: Icons.calendar_today,
                        title: 'Weekly Activity Target',
                        labelText: 'Sessions per week',
                      ),
                      const SizedBox(height: 16),
                      _buildGoalCard(
                        controller: _weeklyDurationController,
                        icon: Icons.timer,
                        title: 'Weekly Duration Goal',
                        labelText: 'Minutes per week',
                      ),
                      const SizedBox(height: 16),
                      _buildGoalCard(
                        controller: _dailyCalorieController,
                        icon: Icons.local_fire_department,
                        title: 'Daily Calorie Burn Goal',
                        labelText: 'Calories per day',
                        recommendedValue: _recommendedCalories,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard({
    required TextEditingController controller,
    required IconData icon,
    required String title,
    required String labelText,
    int? recommendedValue,
  }) {

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: Color(0xFF2196F3), size: 32),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: labelText,
                border: const OutlineInputBorder(),
                filled: true,
              ),
              keyboardType: TextInputType.number,
              validator: (value) {

                if (value == null || value.trim().isEmpty) {
                  return null;
                }

                final number = int.tryParse(value);

                if (number == null) {
                  return 'Please enter a valid number.';
                }

                if (number <= 0) {
                  return 'Value must be greater than zero.';
                }

                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
