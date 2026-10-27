import 'package:flutter/material.dart';
import 'activity_tabs.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    // ActivityTabs now provides its own Scaffold with AppBar and FAB
    return ActivityTabs();
  }
}
