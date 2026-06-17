// lib/presentation/screens/client/client_shared.dart
//
// Shared widgets used across all client screens.
// Import this file in any client screen — never the other way around.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart' show AppRoutes;
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../data/models/models.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import 'client_providers.dart' show aiBidInsightsProvider;

// ─────────────────────────────────────────────────────────────────────────────
// Bottom navigation — 4 fixed tabs (Home, Search, My Bids, Profile)
// ─────────────────────────────────────────────────────────────────────────────

class ClientBottomNav extends StatelessWidget {
  const ClientBottomNav({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: currentIndex.clamp(0, 3),
        onTap: (i) {
          switch (i) {
            case 0:
              context.go(AppRoutes.home);
            case 1:
              context.go(AppRoutes.feedbackGeneral);
            case 2:
              context.go(AppRoutes.myBids);
            case 3:
              context.go(AppRoutes.profile);
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            label: context.l10n.home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.rate_review_outlined),
            label: context.l10n.feedbackNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.gavel_outlined),
            label: context.l10n.myBidsNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            label: context.l10n.profile,
          ),
        ],
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Auction card — used on Home screen and anywhere an auction is listed
// ─────────────────────────────────────────────────────────────────────────────

class AuctionCard extends StatelessWidget {
  const AuctionCard({
    super.key,
    required this.auction,
    required this.onBidTap,
  });
  final AuctionModel auction;
  final VoidCallback onBidTap;

  @override
  Widget build(BuildContext context) {
    final isEndingSoon =
        auction.endDate.difference(DateTime.now()).inHours < 24;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Vehicle photo ─────────────────────────────────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.lg),
                    topRight: Radius.circular(AppRadius.lg),
                  ),
                  child: auction.photoUrls.isNotEmpty
                      ? Image.network(
                          auction.photoUrls.first,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              AuctionPhotoPlaceholder(auction.resolvedMainCategory),
                        )
                      : AuctionPhotoPlaceholder(auction.resolvedMainCategory),
                ),
                // Category badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: _Badge(auction.resolvedMainCategory.toUpperCase()),
                ),
                // Region badge
                Positioned(
                  bottom: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on,
                            size: 11, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          auction.region,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Card content ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          auction.itemName,
                          style: AppTextStyles.h2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isEndingSoon
                                ? Icons.alarm
                                : Icons.access_time_outlined,
                            size: 13,
                            color: isEndingSoon
                                ? AppColors.warning
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isEndingSoon ? context.l10n.endsSoon : context.l10n.timeLeft,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isEndingSoon
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateHelper.formatCountdown(auction.endDate),
                    style: TextStyle(
                      fontSize: 12,
                      color: isEndingSoon
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(context.l10n.currentBid, style: AppTextStyles.bodyMedium),
                  Text(
                    AppFormatters.rwf(auction.currentHighestBid),
                    style: AppTextStyles.price,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onBidTap,
                      child: Text(context.l10n.bidNow, style: AppTextStyles.button),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auction photo placeholder — category-appropriate icon
// ─────────────────────────────────────────────────────────────────────────────

class AuctionPhotoPlaceholder extends StatelessWidget {
  const AuctionPhotoPlaceholder(this.category, {super.key, this.height = 180});
  final String category;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        color: AppColors.surfaceGrey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (category) {
                'motorcycle' => Icons.motorcycle,
                'bicycle'    => Icons.pedal_bike,
                _            => Icons.directions_car,
              },
              size: 56,
              color: AppColors.border,
            ),
            const SizedBox(height: 8),
            Text(category, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bid tile — single row in My Bids list showing real auction data
// ─────────────────────────────────────────────────────────────────────────────

class BidTile extends ConsumerWidget {
  const BidTile({
    super.key,
    required this.bid,
    this.auction,
  });
  final BidModel bid;
  final AuctionModel? auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _resolveStatus(bid, auction);
    final statusColor = _statusColor(status);
    final statusLabel = status.toUpperCase();

    final photoUrl =
        auction != null && auction!.photoUrls.isNotEmpty
            ? auction!.photoUrls.first
            : null;
    final auctionName = auction?.itemName ?? 'Auction ${bid.auctionId.substring(0, 8)}';
    final category = auction?.resolvedMainCategory ?? 'vehicle';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Photo thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: photoUrl != null
                ? Image.network(
                    photoUrl,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _ThumbnailPlaceholder(category),
                  )
                : _ThumbnailPlaceholder(category),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        auctionName,
                        style: AppTextStyles.h3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusPill(statusLabel, statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                if (auction != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 2),
                      Text(auction!.region, style: AppTextStyles.bodySmall),
                    ],
                  ),
                if (auction?.brand != null || auction?.subCategory != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.label_outline,
                          size: 11, color: AppColors.darkGold),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          [
                            if (auction!.brand != null) auction!.brand!,
                            if (auction!.subCategory != null) auction!.subCategory!,
                          ].join(' • '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.darkGold,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text(context.l10n.yourBidLabel,
                    style: AppTextStyles.bodySmall,
                    textAlign: TextAlign.start),
                Text(
                  AppFormatters.rwf(bid.bidAmount),
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                // ── AI insights chip (active auctions only, Phase 9M) ──────
                if (auction?.auctionStatus == 'active')
                  ref.watch(aiBidInsightsProvider(bid.auctionId)).whenOrNull(
                        data: (ai) => ai == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _BidAiRow(
                                  ai: ai,
                                  bidAmount: bid.bidAmount,
                                ),
                              ),
                      ) ??
                  const SizedBox.shrink(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.access_time_outlined,
                            size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          DateHelper.timeAgo(bid.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (auction?.auctionStatus == 'active' &&
                            !(auction?.isExpired ?? true)) ...[
                          TextButton(
                            onPressed: () =>
                                context.go('/auction/${bid.auctionId}'),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              context.l10n.updateBid,
                              style: const TextStyle(
                                color: AppColors.darkGold,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        TextButton(
                          onPressed: () =>
                              context.go('/auction/${bid.auctionId}'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                          ),
                          child: Text(
                            context.l10n.viewDetails,
                            style: const TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _resolveStatus(BidModel bid, AuctionModel? auction) {
    if (bid.bidStatus == 'won') return 'Won';
    if (auction == null) return bid.bidStatus;
    if (auction.auctionStatus == 'closed' && bid.bidStatus != 'won') {
      return 'Lost';
    }
    if (bid.bidStatus == 'winning') return 'Winning';
    return 'Outbid';
  }

  Color _statusColor(String status) => switch (status.toLowerCase()) {
        'won' => AppColors.gold,
        'winning' => AppColors.success,
        'lost' => AppColors.error,
        _ => AppColors.warning,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// AI row inside BidTile — win probability + value signal (Phase 9M)
// ─────────────────────────────────────────────────────────────────────────────

class _BidAiRow extends StatelessWidget {
  const _BidAiRow({required this.ai, required this.bidAmount});
  final Map<String, dynamic> ai;
  final double bidAmount;

  String _signal(double? price) {
    if (price == null || bidAmount <= 0) return 'FAIR';
    if (price > bidAmount * 1.10) return 'UNDER';
    if (price < bidAmount * 0.90) return 'OVER';
    return 'FAIR';
  }

  @override
  Widget build(BuildContext context) {
    final winProb   = (ai['win_probability'] as double?);
    final price     = (ai['price_estimate'] as double?);
    final signal    = _signal(price);

    return Row(
      children: [
        if (winProb != null) ...[
          const Icon(Icons.show_chart, size: 11, color: AppColors.textSecondary),
          const SizedBox(width: 3),
          Text(
            '${(winProb * 100).toStringAsFixed(0)}% win',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (price != null)
          _BidAiSignalPill(signal),
      ],
    );
  }
}

class _BidAiSignalPill extends StatelessWidget {
  const _BidAiSignalPill(this.signal);
  final String signal;

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (signal) {
      'UNDER' => (const Color(0xFF2E7D32), const Color(0xFFE8F5E9)),
      'OVER'  => (AppColors.error,         const Color(0xFFFFEBEE)),
      _       => (AppColors.warning,       const Color(0xFFFFF8E1)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        signal,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder(this.category);
  final String category;

  @override
  Widget build(BuildContext context) => Container(
        width: 72,
        height: 72,
        color: AppColors.surfaceGrey,
        child: Icon(
          switch (category) {
            'motorcycle' => Icons.motorcycle,
            'bicycle'    => Icons.pedal_bike,
            _            => Icons.directions_car,
          },
          color: AppColors.border,
          size: 32,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification tile — individual notification row
// ─────────────────────────────────────────────────────────────────────────────

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    this.onTap,
  });
  final NotificationModel notification;
  final VoidCallback? onTap;

  static const Map<String, ({IconData icon, Color color, Color bg})>
      _typeConfig = {
    'new_auction': (
      icon: Icons.gavel,
      color: AppColors.gold,
      bg: Color(0xFFFFF9E0),
    ),
    'bid_placed': (
      icon: Icons.gavel,
      color: AppColors.primaryBlue,
      bg: Color(0xFFE3F2FD),
    ),
    'winning': (
      icon: Icons.emoji_events,
      color: AppColors.success,
      bg: Color(0xFFE8F5E9),
    ),
    'outbid': (
      icon: Icons.gavel,
      color: AppColors.error,
      bg: Color(0xFFFFEBEE),
    ),
    'won': (
      icon: Icons.emoji_events,
      color: AppColors.success,
      bg: Color(0xFFE8F5E9),
    ),
    'system': (
      icon: Icons.shield,
      color: AppColors.info,
      bg: Color(0xFFE3F2FD),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[notification.type] ??
        (
          icon: Icons.notifications,
          color: AppColors.textSecondary,
          bg: AppColors.surfaceGrey,
        );
    final isUnread = !notification.isRead;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isUnread
                ? AppColors.primaryBlue.withValues(alpha: 0.2)
                : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cfg.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(cfg.icon, color: cfg.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateHelper.timeAgo(notification.createdAt)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ClientEmptyState — shown when a list is empty
// ─────────────────────────────────────────────────────────────────────────────

class ClientEmptyState extends StatelessWidget {
  const ClientEmptyState(this.message, {super.key, this.icon});
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 56, color: AppColors.border),
                const SizedBox(height: 16),
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
// ClientErrorCard — standardised error display replaces bare Text('Error: $e')
// ─────────────────────────────────────────────────────────────────────────────

class ClientErrorCard extends StatelessWidget {
  const ClientErrorCard(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                context.l10n.somethingWentWrong,
                style: AppTextStyles.h2,
              ),
              const SizedBox(height: 6),
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
// Auction countdown — live ticker updating every 60 seconds
// ─────────────────────────────────────────────────────────────────────────────

class ClientAuctionCountdown extends StatefulWidget {
  const ClientAuctionCountdown({super.key, required this.endDate});
  final DateTime endDate;

  @override
  State<ClientAuctionCountdown> createState() =>
      _ClientAuctionCountdownState();
}

class _ClientAuctionCountdownState extends State<ClientAuctionCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.endDate.difference(DateTime.now());
    final isExpired = remaining.isNegative;
    final isUrgent = !isExpired && remaining.inHours < 2;
    final color =
        (isExpired || isUrgent) ? AppColors.error : AppColors.textSecondary;

    final l10n = context.l10n;
    final String label;
    if (isExpired) {
      label = l10n.timeExpired;
    } else {
      final d = remaining.inDays;
      final h = remaining.inHours.remainder(24);
      final m = remaining.inMinutes.remainder(60);
      if (d > 0) {
        label = l10n.daysHoursRemaining(d, h);
      } else if (h > 0) {
        label = l10n.hoursMinutesRemaining(h, m);
      } else {
        label = l10n.minutesRemaining(m);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isExpired ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryBlue,
          ),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      );
}
