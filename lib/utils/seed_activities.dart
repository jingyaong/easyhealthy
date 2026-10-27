import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await seedActivitiesFromJson();

  print('🎉 Seeding complete! You can close this process now.');
}

Future<void> seedActivitiesFromJson() async {
  final firestore = FirebaseFirestore.instance;
  final activitiesRef = firestore.collection('activities');

  // Prevent duplicate seeding
  final existing = await activitiesRef.limit(1).get();
  if (existing.docs.isNotEmpty) {
    print('✅ Activities already exist in Firestore. Skipping seed.');
    return;
  }

  print('🚀 Seeding activities from JSON...');

  final String jsonString =
  await rootBundle.loadString('assets/seeds/activities_seed.json');
  final List<dynamic> jsonData = jsonDecode(jsonString);

  for (final item in jsonData) {
    final activity = Map<String, dynamic>.from(item);
    activity['created_at'] = FieldValue.serverTimestamp();
    await activitiesRef.doc(activity['id']).set(activity);
    print('✅ Added: ${activity['name']}');
  }

  print('🎯 All activities seeded successfully!');
}
