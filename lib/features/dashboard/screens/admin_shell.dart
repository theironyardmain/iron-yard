import 'package:flutter/material.dart';

import '../../announcements/screens/manage_announcements_screen.dart';
import 'admin_home_screen.dart';
import '../../attendance/screens/scanner_screen.dart';
import '../../classes/screens/class_schedule_screen.dart';
import '../../equipment/screens/equipment_list_screen.dart';
import '../../members/screens/member_list_screen.dart';
import '../../payments/screens/payment_list_screen.dart';
import '../../plans/screens/plan_templates_screen.dart';
import '../../memberships/screens/plan_list_screen.dart';
import 'role_shell.dart';

/// Admin navigation (brain.md §6.3).
class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleShell(
      title: 'The Iron Yard',
      destinations: [
        ShellDestination(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Home',
          body: AdminHomeScreen(),
        ),
        ShellDestination(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: 'Members',
          body: MemberListScreen(),
        ),
        ShellDestination(
          icon: Icons.card_membership_outlined,
          selectedIcon: Icons.card_membership,
          label: 'Plans',
          body: PlanListScreen(),
        ),
        ShellDestination(
          icon: Icons.qr_code_scanner_outlined,
          selectedIcon: Icons.qr_code_scanner,
          label: 'Scan',
          body: ScannerScreen(),
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
          body: ManageAnnouncementsScreen(),
        ),
        ShellDestination(
          icon: Icons.fitness_center_outlined,
          selectedIcon: Icons.fitness_center,
          label: 'Training',
          body: PlanTemplatesScreen(),
        ),
        ShellDestination(
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments,
          label: 'Payments',
          body: PaymentListScreen(),
        ),
        ShellDestination(
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
          label: 'Equipment',
          body: EquipmentListScreen(isAdmin: true),
        ),
      ],
    );
  }
}
