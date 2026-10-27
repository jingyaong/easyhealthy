class ActivityLevel {
  final String id;
  final String label;
  final String description;
  final double multiplier;

  const ActivityLevel({
    required this.id,
    required this.label,
    required this.description,
    required this.multiplier,
  });
}

const List<ActivityLevel> activityLevels = [
  ActivityLevel(id: 'sedentary', label: 'Sedentary', multiplier: 1.2, description: 'Little or no exercise, mostly sitting.'),
  ActivityLevel(id: 'light', label: 'Lightly Active', multiplier: 1.375, description: 'Light exercise or sports 1–3 days per week.'),
  ActivityLevel(id: 'moderate', label: 'Moderately Active', multiplier: 1.55, description: 'Moderate exercise or sports 3–5 days per week.'),
  ActivityLevel(id: 'active', label: 'Very Active', multiplier: 1.725, description: 'Hard exercise or sports 6–7 days per week.'),
  ActivityLevel(id: 'super_active', label: 'Super Active', multiplier: 1.9, description: 'Very hard exercise or physical job.'),
];
