import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/health_calculator.dart';
import '../model/ActivityLevel.dart';

class OnboardingInfoScreen extends StatefulWidget {
  final VoidCallback onFinished;
  // Receive BMI from the previous screen
  final double bmi;

  const OnboardingInfoScreen({
    super.key,
    required this.onFinished,
    required this.bmi,
  });

  @override
  State<OnboardingInfoScreen> createState() => _OnboardingInfoScreenState();
}

class _OnboardingInfoScreenState extends State<OnboardingInfoScreen> {

  final _ageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _fitnessGoal;
  String? _gender;
  ActivityLevel? _selectedActivityLevel;
  bool _isLoading = false;

  late List<String> _fitnessGoalOptions;

  @override
  void initState() {
    super.initState();
    // Populate the fitness goals based on the passed BMI
    _fitnessGoalOptions = HealthCalculator.getFitnessGoalsForBMI(widget.bmi);
  }

  Future<void> _saveUserInfo() async {
    if (!_formKey.currentState!.validate()) {
      return; // Stop if form is invalid
    }

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final existingData = userDoc.data();

      final double? weight = (existingData?['weight'] as num?)?.toDouble();
      final double? height = (existingData?['height'] as num?)?.toDouble();

      if (weight == null || height == null) {
        widget.onFinished();
        return;
      }

      final dataToSave = <String, dynamic>{
        'age': int.parse(_ageController.text),
        'gender': _gender!,
        'fitnessGoal': _fitnessGoal!,
        'activity_level': _selectedActivityLevel!.label,
      };

      final int calcAge = int.parse(_ageController.text);
      final String calcGender = _gender!;
      final String calcActivity = _selectedActivityLevel!.label;
      final String calcGoal = _fitnessGoal!;

      // --- Calculate Daily Burn Goal ---
      final int detailedBurnGoal = HealthCalculator.calculateRecommendedCalorieBurn(
        bmi: widget.bmi,
        weightKg: weight,
        heightCm: height,
        age: calcAge,
        gender: _gender,
        activityMultiplier: _selectedActivityLevel?.multiplier,
        fitnessGoal: _fitnessGoal,
      );
      dataToSave['daily_burn_goal'] = detailedBurnGoal;

      // --- Calculate Daily Consume Goal (calories & macros) ---
      final dailyConsume = HealthCalculator.calculateDailyNutrientGoals(
        weightKg: weight,
        heightCm: height,
        age: calcAge,
        gender: calcGender,
        activityLevel: calcActivity,
        fitnessGoal: calcGoal,
      );

      dataToSave['daily_consume_goal'] = dailyConsume;

      // --- Save to Firestore ---
      if (dataToSave.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(dataToSave, SetOptions(merge: true));
      }

      widget.onFinished();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save info: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add details for better accuracy'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "These information helps us personalize your experience.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Age Input
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Your Age',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  // If the field is empty, it's valid because it's optional.
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your age.';
                  }
                  final age = int.tryParse(value);
                  if (age == null) {
                    return 'Please enter a valid number.';
                  }

                  if (age < 5 || age > 120) {
                    return 'Please enter a realistic age.';
                  }
                  return null; // Return null if the input is valid
                },
              ),
              const SizedBox(height: 24),

              DropdownButtonFormField<String>(
                value: _gender,
                hint: const Text('Select Gender'),
                items: ['Male', 'Female']
                    .map(
                      (label) =>
                          DropdownMenuItem(child: Text(label), value: label),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _gender = value),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null) {
                    return 'Please select a gender.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Fitness Goal Dropdown (Dynamic)
              DropdownButtonFormField<String>(
                value: _fitnessGoal,
                hint: const Text('Fitness Goal'),
                items: _fitnessGoalOptions
                    .map(
                      (goal) =>
                          DropdownMenuItem(child: Text(goal), value: goal),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _fitnessGoal = value),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null) {
                    return 'Please select a fitness goal.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Activity Level Dropdown
              DropdownButtonFormField<ActivityLevel>(
                value: _selectedActivityLevel,
                isExpanded: true,
                hint: const Text('Activity Level'),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                selectedItemBuilder: (BuildContext context) {
                  return activityLevels.map<Widget>((ActivityLevel level) {
                    return Text(level.label);
                  }).toList();
                },
                items: activityLevels.map((level) {
                  return DropdownMenuItem<ActivityLevel>(
                    value: level,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(level.label),
                      subtitle: Text(
                        level.description,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedActivityLevel = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select your activity level.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 48),

              ElevatedButton(
                onPressed: _isLoading ? null : _saveUserInfo,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
