import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../model/Habit.dart';

class HabitDetailsPage extends StatefulWidget {
  final Habit habit;
  final Future<void> Function(Habit habit)? onDelete;
  final Future<void> Function(Habit habit, bool isCompletedToday)? onToggleCompletion;

  const HabitDetailsPage({
    super.key,
    required this.habit,
    this.onDelete,
    this.onToggleCompletion,
  });

  @override
  State<HabitDetailsPage> createState() => _HabitDetailsPageState();
}

class _HabitDetailsPageState extends State<HabitDetailsPage> {
  late bool _reminderEnabled;
  late TimeOfDay? _selectedTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _reminderEnabled = false;
    _selectedTime = null;

    if (widget.habit.reminderTime != null) {
      final timeParts = widget.habit.reminderTime!.split(':');
      _selectedTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
      _reminderEnabled = true;
    }
  }

  Future<void> _updateHabit() async {
    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not logged in.");

      final querySnapshot = await FirebaseFirestore.instance
          .collection('user_habits')
          .where('user_id', isEqualTo: user.uid)
          .where('habitId', isEqualTo: widget.habit.id)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw Exception("Could not find the habit to update.");
      }
      final docRef = querySnapshot.docs.first.reference;

      await docRef.update({
        'reminderEnabled': _reminderEnabled,
        'reminderTime': _reminderEnabled && _selectedTime != null
            ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
            : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Habit updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update habit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isHabitCompletedToday() {
    if (widget.habit.lastCompletedDate == null) return false;
    final now = DateTime.now();
    final lastCompletion = widget.habit.lastCompletedDate!;
    return now.year == lastCompletion.year &&
        now.month == lastCompletion.month &&
        now.day == lastCompletion.day;
  }

  Future<void> _handleToggleCompletion() async {
    // Check if the callback exists
    if (widget.onToggleCompletion == null) return;

    // Show loading indicator
    setState(() => _isLoading = true);

    // Call the passed-in function
    await widget.onToggleCompletion!(widget.habit, _isHabitCompletedToday());

    // Hide loading indicator and pop the screen to see the updated state on the list
    if (mounted) {
      // A short delay gives the user feedback that the action was successful
      // before popping the screen.
      await Future.delayed(const Duration(milliseconds: 300));
      Navigator.of(context).pop();
    }
  }

  Widget _buildToggleCompletionButton() {
    final isCompletedToday = _isHabitCompletedToday();

    // Do not show the button if the callback wasn't provided
    if (widget.onToggleCompletion == null) {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      icon: Icon(
        isCompletedToday ? Icons.replay_circle_filled_outlined : Icons.check_circle,
      ),
      label: Text(
        isCompletedToday ? 'Undo Today\'s Completion' : 'Mark as Complete Today',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        foregroundColor: isCompletedToday ? Theme.of(context).colorScheme.onSurface : Colors.white,
        backgroundColor: isCompletedToday ? Colors.grey.shade300 : Colors.green,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: _isLoading ? null : _handleToggleCompletion,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool initialReminderEnabled = widget.habit.reminderTime != null;
    final String? initialTimeStr = widget.habit.reminderTime;

    // Determine the current state from the UI.
    final String? currentTimeStr = _reminderEnabled && _selectedTime != null
        ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
        : null;

    // A change has occurred if the enabled status is different OR the time strings are different.
    final bool hasChanges =
        (initialReminderEnabled != _reminderEnabled) || (initialTimeStr != currentTimeStr);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.habit.name),
        actions: [
          // Show loading indicator or update button
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Delete Habit',
            onPressed: () async {
              final bool? confirmDelete = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Delete Habit'),
                    content: Text(
                        'Are you sure you want to delete "${widget.habit.name}"? This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child:
                        const Text('Delete', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  );
                },
              );

              if (confirmDelete == true && widget.onDelete != null) {
                await widget.onDelete!(widget.habit);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (hasChanges && !_isLoading)
          ? SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: FloatingActionButton.extended(
          heroTag: 'update-habit-fab--${widget.habit.id}',
          onPressed: _updateHabit,
          label: const Text('Update Habit'),
          icon: const Icon(Icons.save_alt_outlined),
        ),
      )
          : null,

      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Row(
            children: [
              Text(
                widget.habit.icon,
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.habit.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.habit.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                widget.habit.description,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.grey.shade600, height: 1.5),
              ),
            ),
          const Divider(),

          const SizedBox(height: 16),
          Text(
            'Reminders',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable Daily Reminder'),
                  secondary: const Icon(Icons.notifications_active_outlined),
                  value: _reminderEnabled,
                  onChanged: (value) {
                    setState(() {
                      _reminderEnabled = value;
                      // If user disables reminders, but no time was set, ensure a default time is ready
                      if (_reminderEnabled && _selectedTime == null) {
                        _selectedTime = TimeOfDay.now();
                      }
                    });
                  },
                ),
                if (_reminderEnabled)
                  ListTile(
                    leading: const Icon(Icons.alarm),
                    title: const Text('Reminder Time'),
                    trailing: Text(
                      _selectedTime?.format(context) ?? 'Select Time',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    onTap: () async {
                      final TimeOfDay? pickedTime = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime ?? TimeOfDay.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              timePickerTheme: Theme.of(context).timePickerTheme.copyWith(
                                dayPeriodColor: const Color(0xFF2196F3),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (pickedTime != null) {
                        setState(() {
                          _selectedTime = pickedTime;
                        });
                      }
                    },
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _buildToggleCompletionButton(),
          const SizedBox(height: 16),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Statistics',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.local_fire_department,
                  label: 'Current Streak',
                  value: '${widget.habit.currentStreak} Days',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.workspace_premium,
                  label: 'Longest Streak',
                  value: '${widget.habit.longestStreak} Days',
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.event_available, color: Colors.green),
              title: const Text('Last Completed'),
              subtitle: Text(
                widget.habit.lastCompletedDate != null
                    ? 'On ${MaterialLocalizations.of(context).formatFullDate(widget.habit.lastCompletedDate!)}'
                    : 'Not completed yet',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context,
      {required IconData icon,
        required String label,
        required String value,
        required Color color}) {
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
