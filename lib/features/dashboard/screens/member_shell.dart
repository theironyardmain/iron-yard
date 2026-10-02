import 'package:flutter/material.dart';

import '../../announcements/screens/announcement_feed_screen.dart';
import '../../attendance/screens/member_card_screen.dart';
import '../../plans/screens/my_plans_screen.dart';
import '../../classes/screens/class_schedule_screen.dart';
import 'role_shell.dart';

/// Member navigation (brain.md §6.2).
class MemberShell extends StatelessWidget {
  const MemberShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      title: 'The Iron Yard',
      destinations: [
        ShellDestination(
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
          body: MemberCardScreen(),
        ),
        ShellDestination(
          icon: Icons.fitness_center_outlined,
          selectedIcon: Icons.fitness_center,
          label: 'Plans',
          body: MyPlansScreen(),
        ),
        ShellDestination(
          icon: Icons.event_outlined,
          selectedIcon: Icons.event,
          label: 'Classes',
          body: ClassScheduleScreen(),
        ),
        ShellDestination(
          icon: Icons.campaign_outlined,
          selectedIcon: Icons.campaign,
          label: 'News',
          body: AnnouncementFeedScreen(),
        ),
      ],
    );
  }
}
