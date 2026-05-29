// lib/presentation/screens/admin/admin_shared.dart
//
// Shared widgets used across all Region Admin screens (12–18).
// All widgets are proper StatelessWidget classes with const constructors so
// Flutter's diffing can skip unchanged subtrees during rebuilds.
//
// Import this file in any admin screen, never the other way around.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart' show AppRoutes;
import '../../theme/app_theme.dart';
import '../../../data/models/models.dart';
import '../../../data/models/user_model.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/localization/app_localizations_ext.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bottom navigation — 5 fixed tabs (Home, Auctions, Clients, Reports, Profile)
// ─────────────────────────────────────────────────────────────────────────────

class AdminBottomNav extends StatelessWidget {
  const AdminBottomNav({super.key, required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
        currentIndex: currentIndex.clamp(0, 4),
        onTap: (i) {
          switch (i) {
            case 0:
              context.go(AppRoutes.adminDashboard);
            case 1:
              context.go(AppRoutes.manageAuctions);
            case 2:
              context.go(AppRoutes.userManagement);
            case 3:
              context.go(AppRoutes.regionReports);
            case 4:
              context.go(AppRoutes.adminProfile);
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            label: context.l10n.homeNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.gavel_outlined),
            label: context.l10n.auctionsNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.group_outlined),
            label: context.l10n.clientsNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bar_chart_outlined),
            label: context.l10n.reportsNav,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            label: context.l10n.profileNav,
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
// Dashboard stat card — 2×2 grid on the admin dashboard
// ─────────────────────────────────────────────────────────────────────────────

class AdminStatCard extends StatelessWidget {
  const AdminStatCard(
    this.value,
    this.label,
    this.color,
    this.isHighlight, {
    super.key,
  });
  final String value, label;
  final Color color;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isHighlight ? AppColors.gold : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: isHighlight
                      ? AppColors.primaryBlue
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 24, height: 3, color: AppColors.primaryBlue),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isHighlight
                        ? AppColors.primaryBlue
                        : AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent auction card — dashboard "Recent Auctions" list
// ─────────────────────────────────────────────────────────────────────────────

class RecentAuctionCard extends StatelessWidget {
  const RecentAuctionCard({
    super.key,
    required this.auction,
    required this.onManage,
  });
  final AuctionModel auction;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final isActive = auction.auctionStatus == 'active';
    final isClosed = auction.auctionStatus == 'closed';
    final statusText = isActive ? 'LIVE' : isClosed ? 'ENDED' : 'DRAFT';
    final statusColor = isActive
        ? AppColors.success
        : isClosed
            ? AppColors.primaryBlue
            : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: auction.photoUrls.isNotEmpty
                ? Image.network(
                    auction.photoUrls.first,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, err, _) => _photoPlaceholder(),
                  )
                : _photoPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOT #${auction.auctionId.substring(0, 6).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  auction.itemName,
                  style: AppTextStyles.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  isClosed ? context.l10n.winningBid : context.l10n.currentBidAdmin,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppFormatters.rwf(
                    isClosed && auction.winningAmount != null
                        ? auction.winningAmount!
                        : auction.currentHighestBid,
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
                  ),
                ),
                if (auction.auctionStatus == 'active') ...[
                  const SizedBox(height: 4),
                  _AuctionCountdown(endDate: auction.endDate),
                ],
              ],
            ),
          ),
          Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: onManage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.primaryBlue,
                  minimumSize: const Size(70, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(context.l10n.manage),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        width: 64,
        height: 64,
        color: AppColors.surfaceGrey,
        child: const Icon(Icons.directions_car, color: AppColors.border),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Manage auction card — ManageAuctionsScreen list item
// ─────────────────────────────────────────────────────────────────────────────

class ManageAuctionCard extends StatelessWidget {
  const ManageAuctionCard({
    super.key,
    required this.auction,
    required this.onViewBids,
    required this.onClose,
    this.onEdit,
    this.onDelete,
  });
  final AuctionModel auction;
  final VoidCallback onViewBids, onClose;
  final VoidCallback? onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final status = auction.auctionStatus;
    final statusColor = status == 'active'
        ? AppColors.success
        : status == 'closed'
            ? AppColors.error
            : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo + status overlay
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
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, err, _) => _auctionPhotoPlaceholder(),
                      )
                    : _auctionPhotoPlaceholder(),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOT #${auction.auctionId.substring(0, 6).toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkGold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(auction.itemName, style: AppTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  auction.description,
                  style: AppTextStyles.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status == 'closed' ? context.l10n.winningBid : context.l10n.currentBidAdmin,
                            style: AppTextStyles.bodySmall,
                          ),
                          Text(
                            AppFormatters.rwf(auction.currentHighestBid),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryBlue,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (status == 'active') ...[
                      IconButton(
                        icon: const Icon(
                          Icons.gavel,
                          color: AppColors.error,
                          size: 20,
                        ),
                        tooltip: context.l10n.closeAuctionTooltip,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: onClose,
                      ),
                    ],
                    if (status != 'closed') ...[
                      IconButton(
                        icon: const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: onViewBids,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.info,
                          size: 20,
                        ),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: onEdit,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: onDelete,
                      ),
                    ],
                    if (status == 'closed') ...[
                      TextButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.bar_chart_outlined, size: 16),
                        label: Text(context.l10n.viewReport),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.visibility_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: onViewBids,
                      ),
                    ],
                  ],
                ),
                if (status == 'active') ...[
                  const SizedBox(height: 8),
                  _AuctionCountdown(endDate: auction.endDate),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _auctionPhotoPlaceholder() => Container(
        height: 150,
        color: AppColors.surfaceGrey,
        child: const Center(
          child: Icon(Icons.directions_car, size: 56, color: AppColors.border),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Form section header — grouped form sections in PostAuctionScreen
// ─────────────────────────────────────────────────────────────────────────────

class FormSectionHeader extends StatelessWidget {
  const FormSectionHeader(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.labelGold),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Form label — ALL CAPS label above input fields
// ─────────────────────────────────────────────────────────────────────────────

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text, style: AppTextStyles.label),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bid rank row — ordered bid list in ViewBidsScreen / CloseAuctionScreen
// ─────────────────────────────────────────────────────────────────────────────

class BidRankRow extends StatelessWidget {
  const BidRankRow({
    super.key,
    required this.rank,
    required this.bid,
    required this.isHighest,
  });
  final int rank;
  final BidModel bid;
  final bool isHighest;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isHighest ? AppColors.gold : AppColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isHighest
                        ? AppColors.primaryBlue
                        : AppColors.textSecondary,
                  ),
                ),
              ),
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
                          bid.bidderName,
                          style: AppTextStyles.h3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isHighest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            context.l10n.highestBadge,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    'ID: ${bid.bidderUid.substring(0, 12)}...',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  AppFormatters.rwf(bid.bidAmount),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  DateHelper.timeAgo(bid.createdAt),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Client stat bar — horizontal stat strip in ClientManagementScreen
// ─────────────────────────────────────────────────────────────────────────────

class ClientStatBar extends StatelessWidget {
  const ClientStatBar(
    this.label,
    this.value,
    this.color,
    this.badge,
    this.isAlert, {
    super.key,
  });
  final String label, value, badge;
  final Color color;
  final bool isAlert;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border(
            left: BorderSide(color: color, width: 4),
            top: BorderSide(color: AppColors.border),
            right: BorderSide(color: AppColors.border),
            bottom: BorderSide(color: AppColors.border),
          ),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodySmall),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isAlert)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Text(
                badge,
                style:
                    TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini stat pill — inline bid/win stats on client cards
// ─────────────────────────────────────────────────────────────────────────────

class MiniStat extends StatelessWidget {
  const MiniStat(this.value, this.label, {super.key});
  final String value, label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceGrey,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(label, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Client card — ClientManagementScreen list item
// ─────────────────────────────────────────────────────────────────────────────

class ClientCard extends StatelessWidget {
  const ClientCard({
    super.key,
    required this.user,
    required this.onSuspend,
    required this.onActivate,
    this.onView,
    this.isLoading = false,
  });
  final UserModel user;
  final VoidCallback onSuspend, onActivate;
  final VoidCallback? onView;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isActive = user.isActive;
    final statusColor = isActive ? AppColors.success : AppColors.error;
    final statusLabel = isActive ? context.l10n.activeBadge : context.l10n.suspended;
    final hasPhoto = user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceGrey,
                ),
                clipBehavior: Clip.hardEdge,
                child: hasPhoto
                    ? CachedNetworkImage(
                        imageUrl: user.profilePhotoUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            const Icon(Icons.person, color: AppColors.textSecondary, size: 22),
                      )
                    : const Icon(Icons.person, color: AppColors.textSecondary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullNames, style: AppTextStyles.h3),
                    Text(user.district, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              MiniStat('${user.totalBidsPlaced}', context.l10n.bidsCount),
              const SizedBox(width: 12),
              MiniStat('${user.totalAuctionsWon}', context.l10n.winsCount),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.info,
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'View client details',
                onPressed: onView,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: 'Edit (Phase 3)',
                onPressed: null,
              ),
              isLoading
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        isActive
                            ? Icons.block_outlined
                            : Icons.check_circle_outlined,
                        size: 18,
                        color: isActive ? AppColors.error : AppColors.success,
                      ),
                      onPressed: isActive ? onSuspend : onActivate,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag chip — small labeled pill (region, category tags)
// ─────────────────────────────────────────────────────────────────────────────

class TagChip extends StatelessWidget {
  const TagChip(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Checkbox item — final review checklist in CloseAuctionScreen
// ─────────────────────────────────────────────────────────────────────────────

class CheckboxItem extends StatelessWidget {
  const CheckboxItem({
    super.key,
    required this.text,
    required this.checked,
    required this.onChanged,
  });
  final String text;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: checked,
              onChanged: onChanged,
              activeColor: AppColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(text, style: AppTextStyles.bodyMedium),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Report stat card — 2×2 grid in RegionReportsScreen
// ─────────────────────────────────────────────────────────────────────────────

class ReportStatCard extends StatelessWidget {
  const ReportStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.trend,
    required this.isHighlight,
  });
  final IconData icon;
  final String label, value, trend;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isHighlight ? AppColors.primaryBlue : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isHighlight ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: isHighlight ? AppColors.gold : AppColors.primaryBlue,
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isHighlight
                    ? Colors.white70
                    : AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isHighlight ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              trend,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isHighlight ? AppColors.gold : AppColors.success,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Category bar — "Auctions by Category" chart in RegionReportsScreen
// ─────────────────────────────────────────────────────────────────────────────

class CategoryBar extends StatelessWidget {
  const CategoryBar({
    super.key,
    required this.label,
    required this.ratio,
    required this.count,
  });
  final String label;
  final double ratio;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: AppTextStyles.h3),
                Text('$count', style: AppTextStyles.h3),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: AppColors.surfaceGrey,
                valueColor: const AlwaysStoppedAnimation(AppColors.primaryBlue),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile — AdminInfoRow, AdminEditFieldRow, AdminPermRow
// Used by AdminProfileScreen (screen 19) in view mode and edit mode.
// ─────────────────────────────────────────────────────────────────────────────

class AdminInfoRow extends StatelessWidget {
  const AdminInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.showChevron = false,
  });
  final IconData icon;
  final String label, value;
  final Color? valueColor;
  final bool showChevron;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: valueColor ?? AppColors.textPrimary,
                    ),
                  ),
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

class AdminEditFieldRow extends StatelessWidget {
  const AdminEditFieldRow({
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
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

class AdminPermRow extends StatelessWidget {
  const AdminPermRow(this.icon, this.label, this.enabled, {super.key});
  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: enabled
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.surfaceGrey,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: enabled
                      ? AppColors.success.withValues(alpha: 0.4)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    enabled ? Icons.check_circle : Icons.cancel,
                    size: 12,
                    color: enabled
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    enabled ? context.l10n.allowed : context.l10n.denied,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color:
                          enabled ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state card — shown when a list is empty
// ─────────────────────────────────────────────────────────────────────────────

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState(this.message, {super.key, this.icon});
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
// Auction countdown — live ticker showing time remaining until endDate.
// Updates every 60 seconds. Shows warning colour when < 2 hours remain.
// ─────────────────────────────────────────────────────────────────────────────

class _AuctionCountdown extends StatefulWidget {
  const _AuctionCountdown({required this.endDate});
  final DateTime endDate;

  @override
  State<_AuctionCountdown> createState() => _AuctionCountdownState();
}

class _AuctionCountdownState extends State<_AuctionCountdown> {
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
    final color = (isExpired || isUrgent) ? AppColors.error : AppColors.textSecondary;
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
// Filter tab bar — reusable horizontal scrolling chip filter
// ─────────────────────────────────────────────────────────────────────────────

class FilterTabBar extends StatelessWidget {
  const FilterTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    this.onTabSelected,
  });
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int>? onTabSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tabs.length,
          itemBuilder: (_, i) {
            final isSel = i == selectedIndex;
            final isLocked = onTabSelected == null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: isLocked ? null : () => onTabSelected!(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryBlue
                          : (isLocked && !isSel
                              ? AppColors.border.withValues(alpha: 0.4)
                              : AppColors.border),
                    ),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSel
                          ? Colors.white
                          : (isLocked
                              ? AppColors.textHint
                              : AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}
