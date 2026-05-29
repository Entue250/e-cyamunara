// lib/presentation/screens/admin/close_auction_screen.dart
//
// SCREEN 17 — CLOSE AUCTION
// Shows: CRITICAL ACTION warning banner, Asset Registry ID + item name +
//        region + category tag, Final Bid Count, Auction Winner card
//        (name, UID excerpt, winning amount), 3-checkbox final review,
//        "CLOSE AUCTION & ANNOUNCE WINNER" button.
//
// Providers: auctionWatcherProvider(id), bidsForAuctionProvider(id),
//            closeAuctionUseCaseProvider

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class CloseAuctionScreen extends ConsumerStatefulWidget {
  const CloseAuctionScreen({super.key, required this.auctionId});
  final String auctionId;

  @override
  ConsumerState<CloseAuctionScreen> createState() =>
      _CloseAuctionScreenState();
}

class _CloseAuctionScreenState extends ConsumerState<CloseAuctionScreen> {
  final List<bool> _checked = [false, false, false];
  bool _isLoading = false;

  Future<void> _closeAuction() async {
    if (_checked.contains(false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check all verification items'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final useCase = ref.read(closeAuctionUseCaseProvider);
    final (result, failure) = await useCase(widget.auctionId);
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Refresh auction lists so closed status propagates immediately
    final admin = ref.read(currentAdminProvider).value;
    if (admin != null) {
      ref.invalidate(adminAuctionsProvider(admin.uid));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Auction closed and winner announced!'),
        backgroundColor: AppColors.success,
      ),
    );
    context.go(AppRoutes.manageAuctions);
  }

  @override
  Widget build(BuildContext context) {
    final auctionAsync =
        ref.watch(auctionWatcherProvider(widget.auctionId));
    final bidsAsync =
        ref.watch(bidsForAuctionProvider(widget.auctionId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.closeAuctionScreen),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(AppRoutes.manageAuctions),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                'E-CYAMUNARA',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
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
              Text(context.l10n.failedToLoadAuctions, style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(
                    auctionWatcherProvider(widget.auctionId)),
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
        data: (auction) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Critical warning banner ────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRITICAL ACTION REQUIRED',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Closing this auction will finalize the highest '
                            'bidder as the legal winner. This action is '
                            'irreversible once confirmed and will be logged '
                            'in the national ledger.',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Asset registry header
              Text(
                'ASSET REGISTRY ID: RNP-${widget.auctionId.substring(0, 6).toUpperCase()}-A',
                style: AppTextStyles.labelGold,
              ),
              const SizedBox(height: 6),
              Text(auction.itemName, style: AppTextStyles.displayLarge),
              const SizedBox(height: 10),
              Row(
                children: [
                  TagChip(Icons.location_on_outlined, auction.region),
                  const SizedBox(width: 8),
                  TagChip(
                    Icons.local_offer_outlined,
                    AppFormatters.titleCase(auction.category),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Final bid count
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  children: [
                    const Text(
                      'FINAL BID COUNT',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${auction.totalBids}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      auction.totalBids == 0
                          ? 'No bids placed'
                          : 'Last updated: ${auction.updatedAt.toLocal().toString().substring(0, 16)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Winner card
              bidsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const AdminEmptyState(
                  'Could not load bid data.',
                  icon: Icons.error_outline,
                ),
                data: (bids) {
                  if (bids.isEmpty) {
                    return const AdminEmptyState(
                      'No bids have been placed. Cannot close an auction with zero bids.',
                      icon: Icons.gavel_outlined,
                    );
                  }
                  final winner = bids.first;
                  final initials = winner.bidderName
                      .split(' ')
                      .take(2)
                      .where((w) => w.isNotEmpty)
                      .map((w) => w[0])
                      .join()
                      .toUpperCase();
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Winner avatar — real photo if available, else initials
                        FutureBuilder<String?>(
                          future: Supabase.instance.client
                              .from('users')
                              .select('profile_photo_url')
                              .eq('id', winner.bidderUid)
                              .maybeSingle()
                              .then((r) => r?['profile_photo_url'] as String?)
                              .onError((_, _) => null),
                          builder: (context, snap) {
                            final photoUrl = snap.data;
                            return Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.gold.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: photoUrl != null
                                    ? Image.network(
                                        photoUrl,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            _InitialsText(initials),
                                      )
                                    : _InitialsText(initials),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 14),
                        // Winner info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'AUCTION WINNER',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.darkGold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                winner.bidderName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${winner.bidderUid.substring(0, 12)}…',
                                style: AppTextStyles.bodySmall,
                              ),
                              const SizedBox(height: 2),
                              const Icon(
                                Icons.workspace_premium,
                                color: AppColors.gold,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Winning amount — Flexible prevents overflow
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                context.l10n.winningBid,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  AppFormatters.rwf(winner.bidAmount)
                                      .replaceAll('RWF ', ''),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.darkGold,
                                  ),
                                ),
                              ),
                              const Text(
                                'RWF',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkGold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Final review checkboxes
              const Text(
                'FINAL REVIEW & VERIFICATION',
                style: AppTextStyles.labelGold,
              ),
              const SizedBox(height: 12),
              ...[
                'I confirm that the bidding process adhered to all RNP auction legal frameworks.',
                "I verify that the winner's identity has been cross-referenced with the national database.",
                'I authorize the system to notify the winner and generate the electronic certificate of purchase.',
              ].asMap().entries.map(
                    (e) => CheckboxItem(
                      text: e.value,
                      checked: _checked[e.key],
                      onChanged: (v) =>
                          setState(() => _checked[e.key] = v ?? false),
                    ),
                  ),

              const SizedBox(height: 24),

              // Close & Announce button
              bidsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (bids) {
                  // Disable the close button if there are no bids
                  final hasBids = bids.isNotEmpty;
                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed:
                          (_isLoading || !hasBids) ? null : _closeAuction,
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Text(
                                    'CLOSE AUCTION & ANNOUNCE WINNER',
                                    style: AppTextStyles.button,
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.gavel, size: 18),
                                ],
                              ),
                            ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1),
    );
  }
}

class _InitialsText extends StatelessWidget {
  const _InitialsText(this.initials);
  final String initials;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: AppColors.darkGold,
          ),
        ),
      );
}
