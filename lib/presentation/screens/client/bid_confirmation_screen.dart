// lib/presentation/screens/client/bid_confirmation_screen.dart
//
// ─── SCREEN 8: BID CONFIRMATION ───────────────────────────────────────────────
// Shows confirmation after a bid is placed or updated.
// Heading, icon, and status badge adapt based on is_update / is_winning flags
// returned by the place-bid Edge Function via bidNotifierProvider.
//
// Receives: AuctionModel? via GoRouter extra (set by AuctionDetailScreen)
// Connected to: bidNotifierProvider — reads the last successful bid response
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/formatters.dart';
import '../../app_router.dart';

class BidConfirmationScreen extends ConsumerWidget {
  const BidConfirmationScreen({super.key, this.auction});
  final AuctionModel? auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bidData = ref.watch(bidNotifierProvider).value;
    final newBid = (bidData?['new_highest_bid'] as num?)?.toDouble() ?? 0;
    final bidId = bidData?['bid_id'] as String?;
    final isUpdate = bidData?['is_update'] == true;
    final isWinning = bidData?['is_winning'] == true;

    final itemName = auction?.itemName ?? 'Auction Item';
    final region = auction?.region ?? '—';
    final category = auction?.category.toUpperCase() ?? 'VEHICLE';
    final refLabel = bidId != null && bidId.length >= 8
        ? 'RNP-${bidId.substring(0, 8).toUpperCase()}'
        : 'RNP-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 100000}';

    final l10n = context.l10n;
    final dateStr = DateTime.now().toString().substring(0, 16);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isUpdate ? l10n.bidUpdated : l10n.bidPlaced),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // ── Success icon — trophy if winning, checkmark otherwise ────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isWinning ? AppColors.success : AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWinning ? Icons.emoji_events : Icons.check,
                color: Colors.white,
                size: 44,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              isUpdate ? l10n.bidUpdatedTitle : l10n.bidPlacedTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              isUpdate ? l10n.bidUpdatedMessage : l10n.bidPlacedMessage,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),
            Container(height: 3, color: AppColors.gold),
            const SizedBox(height: 20),

            // ── Bid details card ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reference + category badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.bidReference, style: AppTextStyles.label),
                          const SizedBox(height: 4),
                          Text(
                            refLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 24, color: AppColors.border),

                  Text(l10n.itemDetails, style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Text(itemName, style: AppTextStyles.h2),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(region, style: AppTextStyles.bodySmall),
                    ],
                  ),

                  const Divider(height: 24, color: AppColors.border),

                  Text(l10n.yourBidAmount2, style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Text(
                    newBid > 0 ? AppFormatters.rwf(newBid) : 'RWF 0',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkGold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.submittedOn(dateStr),
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Status badge — green WINNING or blue BID REGISTERED ───────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isWinning ? AppColors.success : AppColors.primaryBlue)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: (isWinning ? AppColors.success : AppColors.primaryBlue)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(l10n.currentStatus, style: AppTextStyles.label),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isWinning
                                    ? AppColors.success
                                    : AppColors.primaryBlue,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isWinning ? Icons.stars : Icons.gavel,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isWinning
                                          ? l10n.currentlyWinning
                                          : l10n.bidRegistered,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.go(AppRoutes.myBids),
                child: Text(l10n.viewMyBids, style: AppTextStyles.button),
              ),
            ),

            const SizedBox(height: 12),

            GestureDetector(
              onTap: () => context.go(AppRoutes.home),
              child: Text(
                l10n.backToHome,
                style: const TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
