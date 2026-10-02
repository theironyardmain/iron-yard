import 'package:flutter/material.dart';

import '../../equipment/screens/equipment_list_screen.dart';
import '../../members/screens/member_list_screen.dart';
import '../../plans/screens/plan_templates_screen.dart';
import '../../classes/screens/class_schedule_screen.dart';
import 'role_shell.dart';

/// Trainer navigation (brain.md §2 — assigned members, plans, attendance
/// view, class schedule; no payments).
class TrainerShell extends StatelessWidget {
  const TrainerShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      title: 'The Iron Yard',
      destinations: [
        ShellDestination(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: 'Members',
          body: MemberListScreen(),
        ),
        ShellDestination(
          icon: Icons.fitness_center_outlined,
          selectedIcon: Icons.fitness_center,
          label: 'Plans',
          body: PlanTemplatesScreen(),
        ),
        ShellDestination(
          icon: Icons.event_outlined,
          selectedIcon: Icons.event,
          label: 'Classes',
          body: ClassScheduleScreen(),
        ),
        ShellDestination(
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          label: 'Equipment',
          body: EquipmentListScreen(isAdmin: false),
        ),
      ],
    );
  }
}
