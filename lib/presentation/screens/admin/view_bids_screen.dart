// lib/presentation/screens/admin/view_bids_screen.dart
//
// SCREEN 15 — VIEW BIDS (Admin)
// Shows: Auction photo + LOT# + status badge + highest bid + total bidders,
//        Bid History list (ranked, sorted highest first), Export PDF button,
//        "AWARD AUCTION TO WINNER" action panel (only when active).
//
// Providers: auctionWatcherProvider(auctionId), bidsForAuctionProvider(auctionId)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class ViewBidsScreen extends ConsumerWidget {
  const ViewBidsScreen({super.key, required this.auctionId});
  final String auctionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auctionAsync = ref.watch(auctionWatcherProvider(auctionId));
    final bidsAsync = ref.watch(bidsForAuctionProvider(auctionId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.viewBids),
        leading: const BackButton(),
      ),
      body: auctionAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                context.l10n.failedToLoadAuctions,
                style: AppTextStyles.h3,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.invalidate(auctionWatcherProvider(auctionId)),
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
        data: (auction) => SingleChildScrollView(
          child: Column(
            children: [
              // Auction hero photo
              auction.photoUrls.isNotEmpty
                  ? Image.network(
                      auction.photoUrls.first,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, err, _) =>
                          _auctionPhotoPlaceholder(),
                    )
                  : _auctionPhotoPlaceholder(),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'LOT #${auctionId.substring(0, 6).toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkGold,
                          ),
                        ),
                        const Spacer(),
                        _StatusBadge(auction.auctionStatus),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Text(
                      auction.itemName,
                      style: AppTextStyles.displayMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Auction ends: ${DateHelper.formatDateTime(auction.endDate)}',
                      style: AppTextStyles.bodySmall,
                    ),

                    const SizedBox(height: 16),

                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: _StatBox(
                            context.l10n.winningBid,
                            AppFormatters.rwf(auction.currentHighestBid),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatBox(
                            context.l10n.totalBidders,
                            '${auction.totalBids}',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Bid history header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(context.l10n.bidDetails, style: AppTextStyles.h1),
                        // TODO(Phase 3): implement PDF export via generatePdfReport
                        TextButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.download_outlined,
                              size: 16),
                          label: const Text('Export PDF'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    bidsAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => AdminEmptyState(
                        context.l10n.noBidsForAuction,
                        icon: Icons.error_outline,
                      ),
                      data: (bids) {
                        if (bids.isEmpty) {
                          return AdminEmptyState(
                            context.l10n.noBidsForAuction,
                            icon: Icons.gavel_outlined,
                          );
                        }
                        return Column(
                          children: List.generate(
                            bids.length,
                            (i) => BidRankRow(
                              rank: i + 1,
                              bid: bids[i],
                              isHighest: i == 0,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // Award action panel — only when auction is active
                    if (auction.auctionStatus == 'active') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Administrative Action',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Review the highest bidder's information before finalizing the auction award.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () => context
                                    .go('/admin/close/$auctionId'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.gold,
                                  foregroundColor: AppColors.primaryBlue,
                                ),
                                child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'AWARD AUCTION TO WINNER',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        fontSize: 13,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.gavel, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1),
    );
  }

  Widget _auctionPhotoPlaceholder() => Container(
        height: 200,
        color: AppColors.surfaceGrey,
        child: const Center(
          child: Icon(
            Icons.directions_car,
            size: 64,
            color: AppColors.border,
          ),
        ),
      );
}

// ── Local helper widgets ───────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final isClosed = status == 'closed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isClosed ? AppColors.error : AppColors.success)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: isClosed ? AppColors.error : AppColors.success,
        ),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: isClosed ? AppColors.error : AppColors.success,
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.label),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}
