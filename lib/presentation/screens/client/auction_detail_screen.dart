// lib/presentation/screens/client/auction_detail_screen.dart
//
// ─── SCREEN 5: AUCTION DETAILS ────────────────────────────────────────────────
// Shows: Swipeable full-width photo gallery with counter + category badge,
//        Region label, item name, specs grid, bid stats box (minimum price,
//        total bidders, current highest bid, countdown), bid button,
//        Vehicle Specifications section.
//
// Bid button label: "UPDATE YOUR BID" when client already has a bid,
//                   "PLACE YOUR BID" otherwise.
//
// Connected to: auctionWatcherProvider(id)        — live Realtime stream
//               highestBidProvider(id)            — live bid price
//               bidNotifierProvider               — place/update bid
//               currentUserProvider               — bidder info
//               clientBidForAuctionProvider       — existing bid (if any)
// Navigation: bid button → bottom sheet → bid_confirmation_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/utils/validators.dart';
import '../../app_router.dart';
import 'client_providers.dart';

class AuctionDetailScreen extends ConsumerStatefulWidget {
  const AuctionDetailScreen({super.key, required this.auctionId});
  final String auctionId;

  @override
  ConsumerState<AuctionDetailScreen> createState() =>
      _AuctionDetailScreenState();
}

class _AuctionDetailScreenState extends ConsumerState<AuctionDetailScreen> {
  late final PageController _pageController;
  int _currentPhotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showBidDialog(AuctionModel auction, double currentHighest) {
    final userState = ref.read(currentUserProvider);
    if (userState.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.loadingAccount)),
      );
      return;
    }
    final user = userState.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.pleaseLogin)),
      );
      return;
    }

    // Read the existing bid (may be null if user hasn't bid yet)
    final existingBidAsync = ref.read(
      clientBidForAuctionProvider(
        (auctionId: auction.auctionId, clientUid: user.uid),
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BidBottomSheet(
        auction:        auction,
        bidderUid:      user.uid,
        currentHighest: currentHighest,
        existingBid:    existingBidAsync.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auctionAsync    = ref.watch(auctionWatcherProvider(widget.auctionId));
    final highestBidAsync = ref.watch(highestBidProvider(widget.auctionId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: auctionAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(context.l10n.failedToLoadAuction(e.toString())),
              TextButton(
                onPressed: () => context.pop(),
                child: Text(context.l10n.goBack),
              ),
            ],
          ),
        ),
        data: (auction) {
          final currentBid =
              highestBidAsync.value ?? auction.currentHighestBid;
          final countdown = DateHelper.formatCountdown(auction.endDate);
          final isExpired = DateHelper.isExpired(auction.endDate);
          final isClosed  = auction.auctionStatus == 'closed';
          final photos    = auction.photoUrls;

          return CustomScrollView(
            slivers: [
              // ── Photo gallery header ──────────────────────────────────────
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                backgroundColor: AppColors.primaryBlue,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white),
                  onPressed: () => context.pop(),
                ),
                title: Text(context.l10n.auctionDetails,
                    style: const TextStyle(color: Colors.white)),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      photos.isNotEmpty
                          ? PageView.builder(
                              controller: _pageController,
                              itemCount: photos.length,
                              onPageChanged: (i) =>
                                  setState(() => _currentPhotoIndex = i),
                              itemBuilder: (_, i) => Image.network(
                                photos[i],
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    _PhotoError(auction.category),
                              ),
                            )
                          : _PhotoError(auction.category),

                      // Category badge
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                auction.category == 'car'
                                    ? Icons.directions_car
                                    : auction.category == 'motorcycle'
                                        ? Icons.motorcycle
                                        : Icons.pedal_bike,
                                size: 14,
                                color: AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                auction.category.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Photo counter pill (only when multiple photos)
                      if (photos.length > 1)
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              '${_currentPhotoIndex + 1} / ${photos.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),

                      // Dot indicators (only when multiple photos)
                      if (photos.length > 1)
                        Positioned(
                          bottom: 16,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              photos.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 3),
                                width:  i == _currentPhotoIndex ? 16 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: i == _currentPhotoIndex
                                      ? Colors.white
                                      : Colors.white54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Content ───────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${auction.region.toUpperCase()} REGION — RWANDA NATIONAL POLICE',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(auction.itemName, style: AppTextStyles.displayLarge),
                      const SizedBox(height: 16),

                      // ── Specs grid ─────────────────────────────────────────
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.5,
                        children: [
                          _SpecCard(context.l10n.conditionLabel, auction.condition),
                          _SpecCard(context.l10n.plateNumberLabel, auction.plateNumber),
                          _SpecCard(context.l10n.startDate,
                              DateHelper.formatDate(auction.startDate)),
                          _SpecCard(context.l10n.endDate,
                              DateHelper.formatDate(auction.endDate)),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ── Bid stats box ──────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context.l10n.minimumPrice,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textSecondary,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppFormatters.rwf(
                                            auction.startingPrice),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  children: [
                                    Text(
                                      context.l10n.totalBidders,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.group,
                                            size: 16,
                                            color: AppColors.info),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${auction.totalBids}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const Divider(
                                height: 24, color: AppColors.border),

                            Row(
                              children: [
                                Text(context.l10n.currentHighestBid,
                                    style: AppTextStyles.bodyMedium),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'RWF',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.darkGold,
                                      ),
                                    ),
                                    Text(
                                      AppFormatters.rwf(currentBid)
                                          .replaceAll('RWF ', ''),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.darkGold,
                                        height: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ── Countdown ──────────────────────────────────
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 16),
                              decoration: BoxDecoration(
                                color: (isExpired || isClosed)
                                    ? AppColors.error.withValues(alpha: 0.1)
                                    : AppColors.warning
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    AppRadius.full),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 16,
                                    color: (isExpired || isClosed)
                                        ? AppColors.error
                                        : AppColors.warning,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    (isExpired || isClosed)
                                        ? context.l10n.auctionEnded
                                        : context.l10n.countdownRemaining(countdown),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: (isExpired || isClosed)
                                          ? AppColors.error
                                          : AppColors.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Bid / update button ────────────────────────────────
                      if (!isExpired && !isClosed)
                        Consumer(
                          builder: (context, cRef, _) {
                            final user =
                                cRef.watch(currentUserProvider).value;
                            final existingBid = user == null
                                ? null
                                : cRef
                                    .watch(clientBidForAuctionProvider((
                                      auctionId: auction.auctionId,
                                      clientUid: user.uid,
                                    )))
                                    .value;
                            final hasExisting = existingBid != null;
                            return SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showBidDialog(auction, currentBid),
                                icon: Icon(hasExisting
                                    ? Icons.edit_outlined
                                    : Icons.gavel),
                                label: Text(
                                  hasExisting
                                      ? context.l10n.updateYourBid
                                      : context.l10n.placeYourBid,
                                  style: AppTextStyles.button,
                                ),
                              ),
                            );
                          },
                        ),

                      if (isExpired || isClosed)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: AppColors.error
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Center(
                            child: Text(
                              context.l10n.auctionHasEnded,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          context.l10n.biddingAgreement,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ),

                      const SizedBox(height: 24),

                      Text(context.l10n.vehicleSpecs, style: AppTextStyles.h1),
                      const SizedBox(height: 12),
                      _SpecRow(Icons.description_outlined, context.l10n.description,
                          auction.description),
                      _SpecRow(Icons.local_offer_outlined, context.l10n.category,
                          AppFormatters.titleCase(auction.category)),
                      _SpecRow(Icons.star_outline, context.l10n.condition,
                          auction.condition),
                      _SpecRow(
                          Icons.confirmation_number_outlined,
                          context.l10n.plateNumber,
                          auction.plateNumber),
                      _SpecRow(Icons.person_outline, context.l10n.postedBy,
                          auction.postedByAdminName),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo error / placeholder
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoError extends StatelessWidget {
  const _PhotoError(this.category);
  final String category;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceGrey,
        child: Icon(
          category == 'car'
              ? Icons.directions_car
              : category == 'motorcycle'
                  ? Icons.motorcycle
                  : Icons.pedal_bike,
          size: 80,
          color: AppColors.border,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec grid card
// ─────────────────────────────────────────────────────────────────────────────

class _SpecCard extends StatelessWidget {
  const _SpecCard(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Spec list row
// ─────────────────────────────────────────────────────────────────────────────

class _SpecRow extends StatelessWidget {
  const _SpecRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bid placement / update bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _BidBottomSheet extends ConsumerStatefulWidget {
  const _BidBottomSheet({
    required this.auction,
    required this.bidderUid,
    required this.currentHighest,
    this.existingBid,
  });
  final AuctionModel auction;
  final String bidderUid;
  final double currentHighest;
  final BidModel? existingBid;

  @override
  ConsumerState<_BidBottomSheet> createState() => _BidBottomSheetState();
}

class _BidBottomSheetState extends ConsumerState<_BidBottomSheet> {
  final _bidController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing bid amount when updating
    if (widget.existingBid != null) {
      _bidController.text =
          widget.existingBid!.bidAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  void _validate(String text) {
    final amount = AppValidators.parseAmount(text);
    setState(() {
      if (amount == null) {
        _validationError = context.l10n.validatorBidInvalid;
      } else if (amount < widget.auction.startingPrice) {
        _validationError = context.l10n.validatorBidTooLow(
            AppFormatters.rwf(widget.auction.startingPrice));
      } else {
        _validationError = null;
      }
    });
  }

  Future<void> _submit() async {
    final amount = AppValidators.parseAmount(_bidController.text);
    if (amount == null || amount < widget.auction.startingPrice) {
      setState(() => _validationError = context.l10n.validatorBidTooLow(
          AppFormatters.rwf(widget.auction.startingPrice)));
      return;
    }

    final failure = await ref.read(bidNotifierProvider.notifier).placeBid(
          auctionId: widget.auction.auctionId,
          bidAmount: amount,
          bidderUid: widget.bidderUid,
        );

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      // Invalidate so the button label and pre-fill refresh on next open.
      // Also invalidate My Bids list so it shows the updated bid immediately.
      ref.invalidate(
        clientBidForAuctionProvider((
          auctionId: widget.auction.auctionId,
          clientUid: widget.bidderUid,
        )),
      );
      ref.invalidate(clientBidsWithAuctionsProvider(widget.bidderUid));
      Navigator.pop(context);
      context.go(AppRoutes.bidConfirmation, extra: widget.auction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bidState = ref.watch(bidNotifierProvider);
    final isUpdate = widget.existingBid != null;
    final minPrice = widget.auction.startingPrice;

    return Container(
      padding: EdgeInsets.only(
        left:   24,
        right:  24,
        top:    24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              isUpdate ? context.l10n.updateBidTitle : context.l10n.placeBidTitle,
              style: AppTextStyles.h1,
            ),
          ),
          const SizedBox(height: 16),

          // ── Bid info rows ──────────────────────────────────────────────────
          _InfoRow(
            label: context.l10n.minimumPrice,
            value: AppFormatters.rwf(minPrice),
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            label: context.l10n.currentHighestBid,
            value: AppFormatters.rwf(widget.currentHighest),
            color: AppColors.darkGold,
          ),
          if (isUpdate) ...[
            const SizedBox(height: 6),
            _InfoRow(
              label: context.l10n.yourCurrentBid,
              value: AppFormatters.rwf(widget.existingBid!.bidAmount),
              color: AppColors.primaryBlue,
            ),
          ],

          const SizedBox(height: 16),

          TextField(
            controller: _bidController,
            keyboardType: TextInputType.number,
            onChanged: _validate,
            decoration: InputDecoration(
              labelText: context.l10n.yourBidAmount,
              prefixIcon: const Icon(Icons.monetization_on_outlined),
              errorText: _validationError,
              helperText: 'Min: ${AppFormatters.rwf(minPrice)}',
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: bidState.isLoading ? null : _submit,
              child: bidState.isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : Text(
                      isUpdate ? context.l10n.updateBidButton : context.l10n.placeBidButton,
                      style: AppTextStyles.button,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      );
}
