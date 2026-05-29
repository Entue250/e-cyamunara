// lib/presentation/screens/admin/client_feedbacks_screen.dart
//
// SCREEN — CLIENT FEEDBACKS (Region Admin)
// Fetches and displays all feedback submitted by clients in the admin's region.
// Supports: loading, empty, error states, expandable detail bottom sheet,
//           mark-as-read (local state), pull-to-refresh.
//
// Providers: currentAdminProvider, feedbackByRegionProvider

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart' show AppRoutes;
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class ClientFeedbacksScreen extends ConsumerStatefulWidget {
  const ClientFeedbacksScreen({super.key});

  @override
  ConsumerState<ClientFeedbacksScreen> createState() =>
      _ClientFeedbacksScreenState();
}

class _ClientFeedbacksScreenState
    extends ConsumerState<ClientFeedbacksScreen> {
  // Local read-state — persists for the session (not across restarts).
  // Full persistence needs: ALTER TABLE feedback ADD COLUMN is_read BOOLEAN DEFAULT FALSE;
  final Set<String> _locallyRead = {};

  Future<void> _markRead(FeedbackModel feedback) async {
    if (_locallyRead.contains(feedback.feedbackId)) return;
    setState(() => _locallyRead.add(feedback.feedbackId));
    await ref
        .read(feedbackRepositoryProvider)
        .markFeedbackAsRead(feedback.feedbackId);
  }

  void _showDetail(BuildContext context, FeedbackModel feedback) {
    _markRead(feedback);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeedbackDetailSheet(feedback: feedback),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminAsync = ref.watch(currentAdminProvider);
    final adminRegion = adminAsync.value?.region ?? '';

    if (adminAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(context.l10n.adminFeedback),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go(AppRoutes.adminDashboard),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      );
    }

    final feedbackAsync = adminRegion.isNotEmpty
        ? ref.watch(feedbackByRegionProvider(adminRegion))
        : const AsyncData<List<FeedbackModel>>([]);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('CLIENT FEEDBACK'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.adminDashboard),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              if (adminRegion.isNotEmpty) {
                ref.invalidate(feedbackByRegionProvider(adminRegion));
              }
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Region badge
          if (adminRegion.isNotEmpty)
            Container(
              color: AppColors.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AppColors.primaryBlue),
                  const SizedBox(width: 6),
                  const Text('REGION:', style: AppTextStyles.label),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      adminRegion.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: feedbackAsync.when(
              loading: () => const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primaryBlue),
              ),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load feedback.\n$e',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => ref
                            .invalidate(feedbackByRegionProvider(adminRegion)),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(context.l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (feedbacks) {
                if (feedbacks.isEmpty) {
                  return AdminEmptyState(
                    context.l10n.noFeedbackYet,
                    icon: Icons.rate_review_outlined,
                  );
                }

                final unread = feedbacks
                    .where((f) =>
                        !f.isRead && !_locallyRead.contains(f.feedbackId))
                    .length;

                return RefreshIndicator(
                  color: AppColors.primaryBlue,
                  onRefresh: () async {
                    ref.invalidate(feedbackByRegionProvider(adminRegion));
                  },
                  child: Column(
                    children: [
                      if (unread > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: AppColors.primaryBlue.withValues(alpha: 0.05),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  '$unread',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'unread feedback',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: feedbacks.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final f = feedbacks[i];
                            final isRead = f.isRead ||
                                _locallyRead.contains(f.feedbackId);
                            return _FeedbackCard(
                              feedback: f,
                              isRead: isRead,
                              onTap: () => _showDetail(context, f),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 2),
    );
  }
}

// ── Feedback summary card ─────────────────────────────────────────────────────
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.feedback,
    required this.isRead,
    required this.onTap,
  });
  final FeedbackModel feedback;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = feedback.clientName.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppColors.surface : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isRead ? AppColors.border : AppColors.primaryBlue.withValues(alpha: 0.3),
            width: isRead ? 1 : 1.5,
          ),
          boxShadow: isRead
              ? null
              : [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar — real photo if available, else initials
            ClipOval(
              child: feedback.clientPhotoUrl != null
                  ? Image.network(
                      feedback.clientPhotoUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _InitialsAvatar(
                        initials: initials,
                        size: 44,
                        fontSize: 16,
                      ),
                    )
                  : _InitialsAvatar(
                      initials: initials,
                      size: 44,
                      fontSize: 16,
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
                          feedback.clientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Stars
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < feedback.starRating
                            ? Icons.star
                            : Icons.star_border,
                        color: AppColors.gold,
                        size: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (feedback.comment.isNotEmpty)
                    Text(
                      feedback.comment,
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (feedback.selectedTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: feedback.selectedTags
                            .take(3)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateHelper.timeAgo(feedback.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (feedback.auctionId.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.gavel_outlined,
                                size: 11, color: AppColors.textSecondary),
                            const SizedBox(width: 3),
                            Text(
                              feedback.itemName.isNotEmpty
                                  ? feedback.itemName
                                  : 'Auction',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── All predefined "What Went Well" tags ─────────────────────────────────────
const _kAllTags = [
  'Easy to Use',
  'Fast Process',
  'Transparency',
  'Communication',
  'Payment Flow',
  'Documentation',
];

// ── Initials avatar helper ────────────────────────────────────────────────────
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.initials,
    required this.size,
    required this.fontSize,
  });
  final String initials;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        color: AppColors.primaryBlue.withValues(alpha: 0.12),
        child: Center(
          child: Text(
            initials.isEmpty ? 'C' : initials,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
}

// ── Feedback detail bottom sheet ──────────────────────────────────────────────
class _FeedbackDetailSheet extends StatelessWidget {
  const _FeedbackDetailSheet({required this.feedback});
  final FeedbackModel feedback;

  @override
  Widget build(BuildContext context) {
    final initials = feedback.clientName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      ClipOval(
                        child: feedback.clientPhotoUrl != null
                            ? Image.network(
                                feedback.clientPhotoUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _InitialsAvatar(
                                  initials: initials,
                                  size: 52,
                                  fontSize: 20,
                                ),
                              )
                            : _InitialsAvatar(
                                initials: initials,
                                size: 52,
                                fontSize: 20,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              feedback.clientName,
                              style: AppTextStyles.displayMedium,
                            ),
                            Text(
                              DateHelper.formatDate(feedback.createdAt),
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: feedback.wouldRecommend
                              ? AppColors.success.withValues(alpha: 0.1)
                              : AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: feedback.wouldRecommend
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                        child: Text(
                          feedback.wouldRecommend ? 'Recommends' : "Won't Recommend",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: feedback.wouldRecommend
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),

                  // Star rating
                  const Text('RATING', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (i) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            i < feedback.starRating
                                ? Icons.star
                                : Icons.star_border,
                            color: AppColors.gold,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        [
                          '',
                          context.l10n.ratingPoor,
                          context.l10n.ratingFair,
                          context.l10n.ratingGood,
                          context.l10n.ratingVeryGood,
                          context.l10n.ratingExcellent,
                        ][feedback.starRating],
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  // Auction info
                  if (feedback.auctionId.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('RELATED AUCTION', style: AppTextStyles.label),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceGrey,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.gavel_outlined,
                              size: 16, color: AppColors.primaryBlue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feedback.itemName.isNotEmpty
                                  ? feedback.itemName
                                  : 'Auction',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // What went well — always show all 6 tags
                  const SizedBox(height: 16),
                  const Text('WHAT WENT WELL', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _kAllTags.map((tag) {
                      final selected = feedback.selectedTags.contains(tag);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primaryBlue.withValues(alpha: 0.1)
                              : AppColors.surfaceGrey,
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: selected
                                ? AppColors.primaryBlue
                                    .withValues(alpha: 0.5)
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (selected)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.check_circle,
                                    size: 12,
                                    color: AppColors.primaryBlue),
                              ),
                            Text(
                              tag,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? AppColors.primaryBlue
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  // Comment
                  if (feedback.comment.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('COMMENT', style: AppTextStyles.label),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceGrey,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        feedback.comment,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.close),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
