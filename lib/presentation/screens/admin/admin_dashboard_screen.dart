// lib/presentation/screens/admin/admin_dashboard_screen.dart
//
// SCREEN 12 — ADMIN DASHBOARD
// Shows: RNP logo + header bar, admin profile card (initials, name, region,
//        ADMIN badge), 4 stat cards (Active Auctions, Bids Today,
//        Closed Auctions, Registered Clients), Recent Auctions list (top 3)
//        with LOT# + status badge + Manage button, bottom nav (5 tabs), FAB.
//
// Providers: currentAdminProvider, adminAuctionsProvider(uid)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import 'admin_providers.dart';
import 'admin_shared.dart';
import '../../../core/localization/app_localizations_ext.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminAsync = ref.watch(currentAdminProvider);
    final admin = adminAsync.value;
    final adminUid = admin?.uid ?? '';
    final auctionsAsync = adminUid.isNotEmpty
        ? ref.watch(adminAuctionsProvider(adminUid))
        : const AsyncData<List<AuctionModel>>([]);
    final statsAsync = adminUid.isNotEmpty
        ? ref.watch(adminDashboardStatsProvider((
            adminUid: adminUid,
            region: admin?.region ?? '',
          )))
        : const AsyncData<Map<String, dynamic>>({
            'active_auctions': 0,
            'closed_auctions': 0,
            'bids_today': 0,
            'registered_clients': 0,
          });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              color: AppColors.primaryBlue,
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Image.asset(
                      'assets/images/RNP_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.adminDashboard,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _NotificationBell(adminUid: adminUid),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Admin profile card ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Row(
                        children: [
                          _AdminAvatar(admin: admin),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  admin?.fullNames ?? 'Region Admin',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  context.l10n.regionAdminTitle(admin?.region ?? ''),
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              context.l10n.admin,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 4 stats grid ───────────────────────────────────────
                    statsAsync.when(
                      loading: () => const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 32),
                            const SizedBox(height: 8),
                            Text(context.l10n.failedToLoadStats),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () => ref.invalidate(
                                adminDashboardStatsProvider((
                                  adminUid: adminUid,
                                  region: admin?.region ?? '',
                                )),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(context.l10n.retry),
                            ),
                          ],
                        ),
                      ),
                      data: (stats) => GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.15,
                        children: [
                          AdminStatCard(
                            '${stats['active_auctions'] ?? 0}',
                            context.l10n.activeAuctionsCount,
                            AppColors.textPrimary,
                            false,
                          ),
                          AdminStatCard(
                            '${stats['bids_today'] ?? 0}',
                            context.l10n.bidsToday,
                            AppColors.textPrimary,
                            true,
                          ),
                          AdminStatCard(
                            '${stats['closed_auctions'] ?? 0}',
                            context.l10n.closedAuctions,
                            AppColors.textPrimary,
                            false,
                          ),
                          AdminStatCard(
                            '${stats['registered_clients'] ?? 0}',
                            context.l10n.registeredClients,
                            AppColors.textPrimary,
                            false,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Recent Auctions ────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.recentAuctions, style: AppTextStyles.h1),
                        TextButton(
                          onPressed: () =>
                              context.go(AppRoutes.manageAuctions),
                          child: Row(
                            children: [
                              Text(
                                context.l10n.seeAll,
                                style: const TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppColors.primaryBlue,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    auctionsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.error, size: 32),
                            const SizedBox(height: 8),
                            Text(context.l10n.failedToLoadRecentAuctions),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  ref.invalidate(adminAuctionsProvider(adminUid)),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(context.l10n.retry),
                            ),
                          ],
                        ),
                      ),
                      data: (auctions) => Column(
                        children: auctions
                            .take(3)
                            .map(
                              (a) => RecentAuctionCard(
                                auction: a,
                                onManage: () =>
                                    context.go('/admin/bids/${a.auctionId}'),
                              ),
                            )
                            .toList(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Client Feedback quick link ─────────────────────────
                    GestureDetector(
                      onTap: () => context.go(AppRoutes.adminFeedbacks),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.rate_review_outlined,
                                size: 22, color: AppColors.primaryBlue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.clientFeedback,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    context.l10n.viewFeedbackDesc,
                                    style: AppTextStyles.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 20, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 0),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go(AppRoutes.postAuction),
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.add, color: AppColors.primaryBlue),
      ),
    );
  }
}

// ── Admin avatar: photo if available, else initials ───────────────────────────
class _AdminAvatar extends StatelessWidget {
  const _AdminAvatar({required this.admin});
  final RegionAdminModel? admin;

  @override
  Widget build(BuildContext context) {
    final photoUrl = admin?.profilePhotoUrl;
    final initials = admin?.fullNames.split(' ').take(2).map((w) => w[0]).join() ?? 'AD';

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (context, err, stack) => _Initials(initials: initials),
        ),
      );
    }
    return _Initials(initials: initials);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: AppColors.gold,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
      );
}

// ── Notification bell with real-time unread badge ─────────────────────────────
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.adminUid});
  final String adminUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (adminUid.isEmpty) {
      return const IconButton(
        icon: Icon(Icons.notifications_outlined, color: Colors.white),
        onPressed: null,
      );
    }
    final countAsync = ref.watch(unreadNotifCountProvider(adminUid));
    final count = countAsync.value ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () => context.push(AppRoutes.adminNotifications),
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
