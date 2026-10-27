import 'package:cloud_firestore/cloud_firestore.dart';

class Activity {
  final String id;
  final String name;
  final String category;
  final double met;
  final String icon;

  Activity({
    required this.id,
    required this.name,
    required this.category,
    required this.met,
    required this.icon,
  });

  factory Activity.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Activity(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      category: data['category'] ?? 'General',
      met: (data['met'] as num?)?.toDouble() ?? 1.0,
      icon: data['icon'] ?? 'fitness_center',
    );
  }
}
