import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions
        .currentPlatform, // comment out if not using firebase_options.dart
  );

  await seedHabitsFromJson();

  print('Seeding complete! You can close this process now.');
}

Future<void> seedHabitsFromJson() async {
  final firestore = FirebaseFirestore.instance;
  final habitsRef = firestore.collection('habits');

  // Prevent duplicate seeding
  final existing = await habitsRef.limit(1).get();
  if (existing.docs.isNotEmpty) {
    print('Habits already exist in Firestore. Skipping seed.');
    return;
  }

  print('Seeding habits from JSON...');

  final String jsonString = await rootBundle.loadString(
    'assets/seeds/habits_seed.json',
  );
  final List<dynamic> jsonData = jsonDecode(jsonString);

  for (final item in jsonData) {
    final habit = Map<String, dynamic>.from(item);
    await habitsRef.doc(habit['id'] as String).set(habit);
    print('Added: ${habit['name']}');
  }

  print('All habits seeded successfully!');
}
