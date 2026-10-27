import 'package:cloud_firestore/cloud_firestore.dart';

class Habit {
  final String id;
  final String name;
  final String description;
  final String category;
  final String icon;
  final bool isDefault;

  final String? reminderTime;
  final bool reminderEnabled;

  final int currentStreak;
  final int longestStreak;

  final DateTime? lastCompletedDate;

  Habit({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.isDefault,
    this.reminderTime,
    this.reminderEnabled = false,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastCompletedDate,
  });

  /// Convert Firestore document to Habit object
  factory Habit.fromMap(Map<String, dynamic> data, String documentId) {

    return Habit(
      id: data['id'],
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      icon: data['icon'] ?? '',
      isDefault: data['isDefault'] ?? false,
      reminderTime: data['defaultReminderTime'],
    );
  }

  /// Convert Habit object to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'category': category,
      'icon': icon,
      'isDefault': isDefault,
      'reminderTime': reminderTime,
      'reminderEnabled': reminderEnabled,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastCompletedDate':
      lastCompletedDate != null ? Timestamp.fromDate(lastCompletedDate!) : null,
    };
  }

  factory Habit.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Habit(
      id: data['habitId'],
      name: data['name'] ?? 'Unnamed Habit',
      description: data['description'] ?? '',
      icon: data['icon'] ?? '🎯',
      category: data['category'] ?? 'General',
      isDefault: data['isDefault'] ?? false,
      currentStreak: data['currentStreak'] ?? 0,
      longestStreak: data['longestStreak'] ?? 0,
      lastCompletedDate: (data['lastCompletedDate'] as Timestamp?)?.toDate(),
      reminderEnabled: data['reminderEnabled'] ?? false,
      reminderTime: data['reminderTime'],
    );
  }

  /// Copy method for updates
  Habit copyWith({
    String? reminderTime,
    bool? reminderEnabled,
    int? currentStreak,
    int? longestStreak,
    DateTime? lastCompletedDate,
  }) {
    return Habit(
      id: id,
      name: name,
      description: description,
      category: category,
      icon: icon,
      isDefault: isDefault,
      reminderTime: reminderTime ?? this.reminderTime,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastCompletedDate: lastCompletedDate ?? this.lastCompletedDate,
    );
  }
}
