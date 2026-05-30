// lib/presentation/screens/auth/region_select_screen.dart
//
// ─── SCREEN 3: REGION SELECTION ───────────────────────────────────────────────
// Shows: "Welcome Back, [Name]", 5 region cards (E/W/N/S/C) with
//        district previews, "You can change region anytime" note.
//
// Connected to: currentUserProvider (for name), authRepositoryProvider.updateRegionSelection()
// Navigation: On region tap → home_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../app_router.dart';

class RegionSelectScreen extends ConsumerStatefulWidget {
  const RegionSelectScreen({super.key});

  @override
  ConsumerState<RegionSelectScreen> createState() => _RegionSelectScreenState();
}

class _RegionSelectScreenState extends ConsumerState<RegionSelectScreen> {
  String? _selectedRegion; // Track which region is being tapped
  bool _isLoading = false;

  // Region data: letter, displayName, value (stored in DB), districts preview, color
  static const List<_RegionData> _regions = [
    _RegionData('E', 'Eastern Region',         'Eastern',  'Rwamagana, Kayonza, Bugesera...', AppColors.info),
    _RegionData('W', 'Western Region',         'Western',  'Rubavu, Rusizi, Karongi...',       AppColors.primaryBlue),
    _RegionData('N', 'Northern Region',        'Northern', 'Musanze, Burera, Gicumbi...',      AppColors.darkBlue),
    _RegionData('S', 'Southern Region',        'Southern', 'Huye, Muhanga, Nyanza...',         Color(0xFF4A4A4A)),
    _RegionData('C', 'Central Region — Kigali','Central',  'Gasabo, Kicukiro, Nyarugenge',     AppColors.darkGold),
  ];

  // ── Handle region selection ─────────────────────────────────────────────────
  Future<void> _selectRegion(String regionName) async {
    setState(() {
      _selectedRegion = regionName;
      _isLoading = true;
    });

    // Save region choice to Supabase via auth_repository
    try {
      await ref.read(authRepositoryProvider).updateRegionSelection(regionName);
      // Invalidate cached user so HomeScreen sees the new region immediately
      ref.invalidate(currentUserProvider);
    } catch (_) {
      // Non-fatal — navigate anyway; provider refresh will retry on next read
    }

    setState(() => _isLoading = false);

    if (!mounted) return;
    context.go(AppRoutes.home); // Navigate to home screen
  }

  @override
  Widget build(BuildContext context) {
    // Get user name from currentUserProvider
    final userAsync = ref.watch(currentUserProvider);
    final userName = userAsync.value?.fullNames ?? 'Welcome';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Blue header ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: const BoxDecoration(color: AppColors.primaryBlue),
              child: Column(
                children: [
                  // RNP Logo
                  Image.asset(
                    'assets/images/RNP_logo.png',
                    width: 40,
                    height: 40,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.shield, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'E-CYAMUNARA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            // ── Welcome text ────────────────────────────────────────────────
            const SizedBox(height: 16),
            Text(
              context.l10n.welcomeBack,
              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              userName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.regionSelectSubtitle,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),

            // ── Gold divider ────────────────────────────────────────────────
            const SizedBox(height: 10),
            Container(
              width: 60,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 14),

            // ── Choose Region label ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.chooseRegion,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Region cards list ───────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _regions.length,
                itemBuilder: (context, i) {
                  final region = _regions[i];
                  final isSelected = _selectedRegion == region.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RegionCard(
                      data: region,
                      isSelected: isSelected,
                      isLoading: isSelected && _isLoading,
                      onTap: () => _selectRegion(region.value),
                    ),
                  );
                },
              ),
            ),

            // ── Bottom note ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.canChangeRegion,
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class for region info ─────────────────────────────────────────────────
class _RegionData {
  const _RegionData(this.letter, this.name, this.value, this.districts, this.color);
  final String letter;
  final String name;      // display label e.g. 'Eastern Region'
  final String value;     // canonical DB value e.g. 'Eastern'
  final String districts;
  final Color color;
}

// ── Individual region card ─────────────────────────────────────────────────────
class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.data,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });
  final _RegionData data;
  final bool isSelected, isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected ? data.color.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isSelected ? data.color : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // Letter badge
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: data.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                data.letter,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Region name + districts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(data.districts, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          // Arrow / loading indicator
          isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.chevron_right,
                  color: isSelected ? data.color : AppColors.textSecondary,
                ),
        ],
      ),
    ),
  );
}
