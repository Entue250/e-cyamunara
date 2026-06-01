// lib/presentation/screens/client/home_screen.dart
//
// ─── SCREEN 4: CLIENT HOME ────────────────────────────────────────────────────
// Shows: RNP logo + "E-CYAMUNARA" + bell + profile icons in header,
//        "DASHBOARD / Welcome, [Name]", search bar, category filter tabs
//        (All / Cars / Motorcycles / Bicycles), "Active Auctions", auction
//        cards (real photo, region badge, name, current bid, countdown,
//        BID NOW button), bottom nav bar.
//
// Connected to: auctionsByRegionProvider(region) — Supabase Realtime stream
//               currentUserProvider — for name and region
// Navigation: BID NOW → auction_detail_screen.dart
//             Bell → notifications_screen.dart
//             Profile icon → profile_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../app_router.dart';
import 'client_shared.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedCategoryIndex = 0;
  String _searchQuery = '';

  List<_Category> _getCategories(AppLocalizations l10n) => [
    _Category(l10n.all, null, null),
    _Category(l10n.cars, '🚗', 'car'),
    _Category(l10n.motorcycles, '🏍️', 'motorcycle'),
    _Category(l10n.bicycles, '🚲', 'bicycle'),
  ];

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final region = user?.region ?? 'Eastern';
    final userName = user?.fullNames.split(' ').first ?? 'Client';
    final categories = _getCategories(context.l10n);
    final selectedCategory = categories[_selectedCategoryIndex];

    final auctionsAsync = selectedCategory.filter == null
        ? ref.watch(auctionsByRegionProvider(region))
        : ref.watch(
            auctionsByCategoryProvider((
              region: region,
              category: selectedCategory.filter!,
            )),
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, ref, user?.uid ?? '', region),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primaryBlue,
                onRefresh: () async {
                  ref.invalidate(auctionsByRegionProvider(region));
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildDashboardHeader(userName, region)),
                    SliverToBoxAdapter(child: _buildSearchBar()),
                    SliverToBoxAdapter(child: _buildCategoryTabs(categories)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          context.l10n.activeAuctions,
                          style: AppTextStyles.h1,
                        ),
                      ),
                    ),
                    auctionsAsync.when(
                      loading: () => const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primaryBlue),
                        ),
                      ),
                      error: (e, _) => SliverToBoxAdapter(
                        child: ClientErrorCard(e.toString()),
                      ),
                      data: (auctions) {
                        final filtered = _searchQuery.isEmpty
                            ? auctions
                            : auctions
                                .where(
                                  (a) => a.itemName.toLowerCase().contains(
                                        _searchQuery.toLowerCase(),
                                      ),
                                )
                                .toList();

                        if (filtered.isEmpty) {
                          return SliverToBoxAdapter(
                            child: ClientEmptyState(
                              context.l10n.noAuctionsInRegion(region),
                              icon: Icons.gavel,
                            ),
                          );
                        }

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => AuctionCard(
                              auction: filtered[i],
                              onBidTap: () => context
                                  .go('/auction/${filtered[i].auctionId}'),
                            ),
                            childCount: filtered.length,
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const ClientBottomNav(currentIndex: 0),
    );
  }

  Widget _buildTopBar(
    BuildContext ctx,
    WidgetRef ref,
    String uid,
    String region,
  ) {
    final countAsync = uid.isNotEmpty
        ? ref.watch(unreadNotifCountProvider(uid))
        : const AsyncData(0);
    final unreadCount = countAsync.value ?? 0;

    final userAsync = ref.watch(currentUserProvider);
    final photoUrl = userAsync.value?.profilePhotoUrl;
    final initials = userAsync.value?.fullNames
            .split(' ')
            .take(2)
            .map((w) => w.isNotEmpty ? w[0] : '')
            .join()
            .toUpperCase() ??
        'U';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.surface,
      child: Row(
        children: [
          // RNP Logo
          Image.asset(
            'assets/images/RNP_logo.png',
            width: 36,
            height: 36,
            errorBuilder: (_, _, _) => Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue,
              ),
              child: const Icon(Icons.shield, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'E-CYAMUNARA',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
          // Bell with unread badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: AppColors.primaryBlue),
                onPressed: () => ctx.go(AppRoutes.notifications),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Profile avatar — real photo or initials fallback
          GestureDetector(
            onTap: () => ctx.go(AppRoutes.profile),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue.withValues(alpha: 0.12),
                border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: photoUrl != null && photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => _InitialsAvatar(initials),
                      placeholder: (_, _) => _InitialsAvatar(initials),
                    )
                  : _InitialsAvatar(initials),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader(String name, String region) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.dashboard, style: AppTextStyles.labelGold),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.welcomeUser(name),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.go(AppRoutes.regionSelect),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: AppColors.primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          region,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined,
                            size: 11, color: AppColors.primaryBlue),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: context.l10n.searchAuctions,
            prefixIcon:
                const Icon(Icons.search, color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceGrey,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );

  Widget _buildCategoryTabs(List<_Category> categories) => SizedBox(
        height: 44,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: categories.length,
          itemBuilder: (_, i) {
            final cat = categories[i];
            final isSel = i == _selectedCategoryIndex;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedCategoryIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        isSel ? AppColors.primaryBlue : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryBlue
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    cat.emoji != null
                        ? '${cat.emoji} ${cat.label}'
                        : cat.label,
                    style: TextStyle(
                      color: isSel ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _Category {
  const _Category(this.label, this.emoji, this.filter);
  final String label;
  final String? emoji, filter;
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.primaryBlue.withValues(alpha: 0.15),
        child: Center(
          child: Text(
            initials.isEmpty ? 'U' : initials,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
}
