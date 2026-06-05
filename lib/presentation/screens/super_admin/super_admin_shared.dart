// lib/presentation/screens/super_admin/super_admin_shared.dart
//
// Shared widgets used across every Super Admin screen.
// All widgets are proper StatelessWidget classes with const constructors so
// Flutter's diffing can skip unchanged subtrees during rebuilds.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart' show AppRoutes;
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bottom navigation — 4 fixed tabs
// ─────────────────────────────────────────────────────────────────────────────

class SuperAdminBottomNav extends StatelessWidget {
  const SuperAdminBottomNav({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: currentIndex.clamp(0, 3),
        onTap: (i) {
          switch (i) {
            case 0: context.go(AppRoutes.superDashboard);
            case 1: context.go(AppRoutes.manageAdmins);
            case 2: context.go(AppRoutes.nationalReports);
            case 3: context.go(AppRoutes.superProfile);
          }
        },
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              label: context.l10n.superAdminNav1),
          BottomNavigationBarItem(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: context.l10n.superAdminNav2),
          BottomNavigationBarItem(
              icon: const Icon(Icons.bar_chart_outlined),
              label: context.l10n.superAdminNav3),
          BottomNavigationBarItem(
              icon: const Icon(Icons.person_outline),
              label: context.l10n.superAdminNav5),
        ],
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Gold "SUPER ADMIN" badge
// ─────────────────────────────────────────────────────────────────────────────

class SuperAdminBadge extends StatelessWidget {
  const SuperAdminBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          context.l10n.superAdminBadge,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryBlue,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state card
// ─────────────────────────────────────────────────────────────────────────────

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard(this.message, {super.key, this.icon});
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 40, color: AppColors.textHint),
                const SizedBox(height: 12),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat pill — auction count / closed count chips on admin cards
// ─────────────────────────────────────────────────────────────────────────────

class StatPill extends StatelessWidget {
  const StatPill(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceGrey,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            Text(label, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Header stat box — used in the top strip of ManageAdminsScreen
// ─────────────────────────────────────────────────────────────────────────────

class HeaderStatBox extends StatelessWidget {
  const HeaderStatBox(this.label, this.value, this.color, {super.key});
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission toggle row — AddAdminScreen form switches
// ─────────────────────────────────────────────────────────────────────────────

class PermissionToggleRow extends StatelessWidget {
  const PermissionToggleRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.h3),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Switch(
              value: value,
              activeThumbColor: AppColors.primaryBlue,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Info display row — read-only field in profile view mode
// ─────────────────────────────────────────────────────────────────────────────

class InfoDisplayRow extends StatelessWidget {
  const InfoDisplayRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.showChevron = true,
  });
  final IconData icon;
  final String label, value;
  final bool showChevron;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodySmall),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.h3),
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Editable field row — edit mode in profile screen
// ─────────────────────────────────────────────────────────────────────────────

class EditFieldRow extends StatelessWidget {
  const EditFieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodySmall),
                  TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    style: AppTextStyles.h3,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, size: 14, color: AppColors.primaryBlue),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission display row — profile "SYSTEM ACCESS" list
// ─────────────────────────────────────────────────────────────────────────────

class PermissionDisplayRow extends StatelessWidget {
  const PermissionDisplayRow(this.label, this.enabled, {super.key});
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.check_circle : Icons.cancel,
              size: 18,
              color:
                  enabled ? AppColors.success : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.surfaceGrey,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                enabled ? context.l10n.allowed : context.l10n.denied,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile stat cell — used in the 3-column stats strip
// ─────────────────────────────────────────────────────────────────────────────

class ProfileStatCell extends StatelessWidget {
  const ProfileStatCell(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section divider line — between profile stat cells
// ─────────────────────────────────────────────────────────────────────────────

class StatDivider extends StatelessWidget {
  const StatDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 48, color: AppColors.border);
}
