// lib/presentation/screens/super_admin/super_admin_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart' show AppRoutes;
import '../../providers/providers.dart'
    show currentSuperAdminProvider, unreadNotifCountProvider;
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';
import 'super_admin_providers.dart';
import 'super_admin_shared.dart';

// ════════════════════════════════════════════════════════════════════════════
// SUPER ADMIN DASHBOARD
// ════════════════════════════════════════════════════════════════════════════
class SuperAdminDashboardScreen extends ConsumerWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync       = ref.watch(superAdminStatsProvider);
    final adminsAsync      = ref.watch(superAdminAllAdminsProvider);
    final superAdminAsync  = ref.watch(currentSuperAdminProvider);
    final superAdmin       = superAdminAsync.valueOrNull;
    final counts           = ref.watch(superAdminAuctionCountsProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: AppColors.primaryBlue,
              child: Row(
                children: [
                  // RNP logo
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Image.asset(
                      'assets/images/RNP_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'E-CYAMUNARA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    superAdmin?.fullNames.split(' ').first ?? 'Admin',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                  _SuperNotificationBell(uid: superAdmin?.uid ?? ''),
                  const SizedBox(width: 4),
                  // Profile avatar — shows real photo if available
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.superProfile),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38),
                      ),
                      child: ClipOval(
                        child: superAdmin?.photoUrl != null
                            ? Image.network(
                                superAdmin!.photoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              )
                            : const Icon(Icons.person_outline,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(superAdminStatsProvider);
                  ref.invalidate(superAdminAllAdminsProvider);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Commissioner card — real name + photo
                      _CommissionerCard(
                        onProfileTap: () =>
                            context.go(AppRoutes.superProfile),
                        superAdmin: superAdmin,
                      ),
                      const SizedBox(height: 16),

                      // ── 4 stat cards ──────────────────────────────────
                      statsAsync.when(
                        loading: () => _StatsGrid(
                          stats: const {
                            'total_auctions': 0,
                            'total_bids': 0,
                            'total_clients': 0,
                          },
                          admins: null,
                        ),
                        error: (_, _) => _StatsGrid(
                          stats: const {
                            'total_auctions': 0,
                            'total_bids': 0,
                            'total_clients': 0,
                          },
                          admins: null,
                        ),
                        data: (stats) => adminsAsync.when(
                          loading: () =>
                              _StatsGrid(stats: stats, admins: null),
                          error: (_, _) =>
                              _StatsGrid(stats: stats, admins: []),
                          data: (admins) =>
                              _StatsGrid(stats: stats, admins: admins),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Revenue banner ────────────────────────────────
                      statsAsync.when(
                        loading: () =>
                            const _RevenueBanner(revenue: 0, auctions: 0),
                        error: (_, _) =>
                            const _RevenueBanner(revenue: 0, auctions: 0),
                        data: (stats) => _RevenueBanner(
                          revenue: (stats['total_revenue'] as num?)
                                  ?.toDouble() ??
                              0,
                          auctions: (stats['closed_auctions'] as num?)
                                  ?.toInt() ??
                              0,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Regions overview ──────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.regionsOverview,
                              style: AppTextStyles.h1),
                          TextButton(
                            onPressed: () =>
                                context.go(AppRoutes.manageAdmins),
                            child: Row(
                              children: [
                                Text(
                                  context.l10n.manage,
                                  style: const TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Icon(Icons.arrow_forward,
                                    size: 14,
                                    color: AppColors.primaryBlue),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      adminsAsync.when(
                        loading: () => SizedBox(
                          height: 60,
                          child: Center(
                            child: Text(context.l10n.loadingRegions,
                                style: AppTextStyles.bodyMedium),
                          ),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (admins) => admins.isEmpty
                            ? EmptyStateCard(
                                context.l10n.noRegionAdmins,
                                icon: Icons.people_outline,
                              )
                            : SizedBox(
                                height: 140,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: admins.length,
                                  itemBuilder: (_, i) => _RegionOverviewCard(
                                    admin: admins[i],
                                    postedCount: counts[admins[i].uid]
                                            ?['posted'] ??
                                        admins[i].totalAuctionsPosted,
                                    closedCount: counts[admins[i].uid]
                                            ?['closed'] ??
                                        admins[i].totalAuctionsClosed,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      // ── Admin activity (top 5 by posted count) ────────
                      Text(context.l10n.adminActivity, style: AppTextStyles.h1),
                      const SizedBox(height: 10),
                      adminsAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (admins) {
                          if (admins.isEmpty) {
                            return EmptyStateCard(
                                context.l10n.noAdminActivity);
                          }
                          // Sort by actual posted count descending
                          final sorted = [...admins]..sort((a, b) {
                              final pa = counts[a.uid]?['posted'] ??
                                  a.totalAuctionsPosted;
                              final pb = counts[b.uid]?['posted'] ??
                                  b.totalAuctionsPosted;
                              return pb.compareTo(pa);
                            });
                          return Column(
                            children: sorted
                                .take(5)
                                .map((a) => _AdminActivityRow(
                                      admin: a,
                                      postedCount: counts[a.uid]?['posted'] ??
                                          a.totalAuctionsPosted,
                                    ))
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── Quick Actions ─────────────────────────────────
                      Text(context.l10n.quickActions, style: AppTextStyles.h1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.settings_outlined,
                              label: context.l10n.appSettings,
                              color: AppColors.primaryBlue,
                              onTap: () =>
                                  context.go(AppRoutes.superSettings),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.bar_chart_outlined,
                              label: context.l10n.nationalReports,
                              color: AppColors.darkGold,
                              onTap: () =>
                                  context.go(AppRoutes.nationalReports),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 0),
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard_fab',
        onPressed: () => context.go(AppRoutes.addEditAdmin),
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.person_add, color: AppColors.primaryBlue),
      ),
    );
  }
}

// ── Dashboard-private sub-widgets ─────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 16, color: color),
            ],
          ),
        ),
      );
}

class _CommissionerCard extends StatelessWidget {
  const _CommissionerCard({
    required this.onProfileTap,
    this.superAdmin,
  });
  final VoidCallback onProfileTap;
  final SuperAdminModel? superAdmin;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.darkBlue, AppColors.primaryBlue],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            // Avatar: real profile photo → RNP logo fallback
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: superAdmin?.photoUrl != null
                    ? Image.network(
                        superAdmin!.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Image.asset(
                          'assets/images/RNP_logo.png',
                          fit: BoxFit.contain,
                        ),
                      )
                    : Image.asset(
                        'assets/images/RNP_logo.png',
                        fit: BoxFit.contain,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.commissioner,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(
                    superAdmin?.fullNames ?? context.l10n.superAdministrator,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  const SuperAdminBadge(),
                ],
              ),
            ),
            IconButton(
              icon:
                  const Icon(Icons.settings_outlined, color: Colors.white70),
              onPressed: onProfileTap,
            ),
          ],
        ),
      );
}

class _RevenueBanner extends StatelessWidget {
  const _RevenueBanner(
      {required this.revenue, required this.auctions});
  final double revenue;
  final int auctions;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.darkBlue,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.nationalRevenue,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            Text(
              context.l10n.totalCollectedAllTime,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              AppFormatters.rwf(revenue),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.gavel_outlined,
                    color: AppColors.gold, size: 14),
                const SizedBox(width: 6),
                Text(
                  context.l10n.closedAuctionsCount(auctions),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      );
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.admins});
  final Map<String, dynamic> stats;
  final List<RegionAdminModel>? admins;

  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          _NatStatCard(
            '${stats['total_auctions'] ?? 0}',
            context.l10n.totalAuctions,
            Icons.gavel_outlined,
          ),
          _NatStatCard(
            '${stats['total_bids'] ?? 0}',
            context.l10n.totalBidsLabel,
            Icons.monetization_on_outlined,
          ),
          _NatStatCard(
            '${stats['total_clients'] ?? 0}',
            context.l10n.clients,
            Icons.group_outlined,
          ),
          _NatStatCard(
            admins == null ? '…' : '${admins!.length}',
            context.l10n.regionAdmins,
            Icons.admin_panel_settings_outlined,
          ),
        ],
      );
}

class _NatStatCard extends StatelessWidget {
  const _NatStatCard(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RegionOverviewCard extends StatelessWidget {
  const _RegionOverviewCard({
    required this.admin,
    required this.postedCount,
    required this.closedCount,
  });
  final RegionAdminModel admin;
  final int postedCount;
  final int closedCount;

  @override
  Widget build(BuildContext context) => Container(
        width: 180,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    admin.region,
                    style: AppTextStyles.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: admin.isActive
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    admin.isActive ? context.l10n.activeBadge : context.l10n.offBadge,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: admin.isActive
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              context.l10n.auctionsCount(postedCount),
              style: AppTextStyles.bodySmall,
            ),
            Row(
              children: [
                _MiniStat(context.l10n.postedStat, '$postedCount'),
                const SizedBox(width: 12),
                _MiniStat(context.l10n.closedStat, '$closedCount'),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    admin.fullNames.split(' ').first,
                    style: AppTextStyles.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );
}

class _AdminActivityRow extends StatelessWidget {
  const _AdminActivityRow({
    required this.admin,
    required this.postedCount,
  });
  final RegionAdminModel admin;
  final int postedCount;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Avatar: real photo → initials fallback
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: admin.profilePhotoUrl != null
                    ? Image.network(
                        admin.profilePhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initials(),
                      )
                    : _initials(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    admin.fullNames,
                    style: AppTextStyles.h3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(context.l10n.regionLabel(admin.region),
                      style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$postedCount',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
                Text(context.l10n.auctionsLabel, style: AppTextStyles.bodySmall),
              ],
            ),
          ],
        ),
      );

  Widget _initials() => Center(
        child: Text(
          admin.fullNames.split(' ').take(2).map((w) => w[0]).join(),
          style: const TextStyle(
            color: AppColors.darkGold,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _SuperNotificationBell extends ConsumerWidget {
  const _SuperNotificationBell({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isEmpty) {
      return const IconButton(
        icon: Icon(Icons.notifications_outlined, color: Colors.white),
        onPressed: null,
      );
    }
    final count = ref.watch(unreadNotifCountProvider(uid)).value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () => context.push(AppRoutes.superNotifications),
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
