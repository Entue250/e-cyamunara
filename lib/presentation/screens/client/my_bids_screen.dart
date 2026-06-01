// lib/presentation/screens/client/my_bids_screen.dart
//
// ─── SCREEN 7: MY BIDS ────────────────────────────────────────────────────────
// Shows: Top bar, stats row (Total / Winning / Won), filter tabs
//        (All / Active / Won / Lost), bid tiles with real auction name + photo.
//
// Connected to: clientBidsWithAuctionsProvider(uid)
// Navigation: View Details → auction_detail_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'client_shared.dart';
import 'client_providers.dart';

class MyBidsScreen extends ConsumerWidget {
  const MyBidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final uid = userAsync.value?.uid ?? '';

    final bidsAsync = userAsync.isLoading
        ? const AsyncLoading<List<(BidModel, AuctionModel?)>>()
        : uid.isNotEmpty
            ? ref.watch(clientBidsWithAuctionsProvider(uid))
            : const AsyncData<List<(BidModel, AuctionModel?)>>([]);

    final filterIndex = ref.watch(myBidsFilterProvider);
    final l10n = context.l10n;
    final filterLabels = [l10n.all, l10n.active, l10n.won, l10n.lost];

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.home);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Container(
              color: AppColors.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 18),
                    onPressed: () => context.go(AppRoutes.home),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.myBids,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: Colors.white),
                    onPressed: () => context.go(AppRoutes.notifications),
                  ),
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            Expanded(
              child: bidsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primaryBlue),
                ),
                error: (e, _) => ClientErrorCard(e.toString()),
                data: (items) {
                  final winning =
                      items.where((i) => i.$1.bidStatus == 'winning').length;
                  final won =
                      items.where((i) => i.$1.bidStatus == 'won').length;

                  final filtered = _applyFilter(items, filterIndex);

                  return Column(
                    children: [
                      // ── Stats row ──────────────────────────────────────────
                      Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            _StatCell(l10n.total, '${items.length}',
                                AppColors.textPrimary),
                            Container(
                                width: 1, height: 40, color: AppColors.border),
                            _StatCell(l10n.winning, '$winning', AppColors.success),
                            Container(
                                width: 1, height: 40, color: AppColors.border),
                            _StatCell(l10n.won, '$won', AppColors.darkGold),
                          ],
                        ),
                      ),

                      // ── Filter tabs ────────────────────────────────────────
                      Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          children:
                              List.generate(filterLabels.length, (i) {
                            final isSel = i == filterIndex;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () => ref
                                    .read(myBidsFilterProvider.notifier)
                                    .state = i,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? AppColors.primaryBlue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.full),
                                    border: Border.all(
                                      color: isSel
                                          ? AppColors.primaryBlue
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    filterLabels[i],
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSel
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      // ── Bid list ───────────────────────────────────────────
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primaryBlue,
                          onRefresh: () async {
                            if (uid.isNotEmpty) {
                              ref.invalidate(
                                  clientBidsWithAuctionsProvider(uid));
                            }
                          },
                          child: filtered.isEmpty
                              ? ListView(
                                  children: [
                                    ClientEmptyState(
                                      filterIndex == 0
                                          ? l10n.noBidsYet
                                          : l10n.noFilterBids(filterLabels[filterIndex]),
                                      icon: Icons.gavel_outlined,
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => BidTile(
                                    bid: filtered[i].$1,
                                    auction: filtered[i].$2,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const ClientBottomNav(currentIndex: 2),
      ),
    );
  }

  List<(BidModel, AuctionModel?)> _applyFilter(
    List<(BidModel, AuctionModel?)> items,
    int index,
  ) =>
      switch (index) {
        // Active: auction is still open
        1 => items
            .where((i) => i.$2?.auctionStatus == 'active')
            .toList(),
        // Won: bid_status is 'won'
        2 => items.where((i) => i.$1.bidStatus == 'won').toList(),
        // Lost: auction closed AND bid_status != 'won'
        3 => items
            .where((i) =>
                i.$2?.auctionStatus == 'closed' &&
                i.$1.bidStatus != 'won')
            .toList(),
        // All
        _ => items,
      };
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppTextStyles.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w900, color: color),
              ),
            ),
          ],
        ),
      );
}
