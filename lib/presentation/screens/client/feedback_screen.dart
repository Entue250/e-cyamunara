// lib/presentation/screens/client/feedback_screen.dart
//
// ─── SCREEN 6: FEEDBACK ───────────────────────────────────────────────────────
// Shows: RNP logo + "E-CYAMUNARA Auction Feedback" title, real auction reference
//        info (item name, region, date loaded from Supabase), star rating, tag
//        chips, additional comments textarea, Would you recommend? Yes/No, SUBMIT.
//
// Connected to: auctionWatcherProvider(auctionId) — loads real auction data
//               feedbackRepositoryProvider.submitFeedback()
//               currentUserProvider — for client info
// Navigation: On submit → home_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../app_router.dart';
import 'client_shared.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key, this.auctionId = ''});
  final String auctionId;

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _starRating = 4;
  bool? _wouldRecommend;
  bool _isLoading = false;
  final _commentController = TextEditingController();

  final Set<String> _selectedTags = {};

  List<String> _getTags(AppLocalizations l10n) => [
    l10n.tagEasyToUse,
    l10n.tagFastProcess,
    l10n.tagTransparency,
    l10n.tagCommunication,
    l10n.tagPaymentFlow,
    l10n.tagDocumentation,
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit(String itemName, String region) async {
    if (_wouldRecommend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.indicateRecommend)),
      );
      return;
    }

    setState(() => _isLoading = true);

    final user = ref.read(currentUserProvider).value;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final feedback = FeedbackModel(
      feedbackId: '',
      clientUid: user.uid,
      clientName: user.fullNames,
      auctionId: widget.auctionId,
      itemName: itemName,
      region: region,
      starRating: _starRating,
      selectedTags: _selectedTags.toList(),
      comment: _commentController.text.trim(),
      wouldRecommend: _wouldRecommend!,
      createdAt: DateTime.now(),
    );

    try {
      await ref.read(feedbackRepositoryProvider).submitFeedback(feedback);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.thankYouFeedback),
          backgroundColor: AppColors.success,
        ),
      );
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.failedToSubmit(e.toString())),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (widget.auctionId.isNotEmpty) {
      context.go('/auction/${widget.auctionId}');
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.auctionId.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(context.l10n.feedbackTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => _goBack(context),
          ),
        ),
        body: _buildGeneralForm(),
      );
    }

    final auctionAsync = ref.watch(auctionWatcherProvider(widget.auctionId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.feedbackTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => _goBack(context),
        ),
      ),
      body: auctionAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        error: (e, _) => ClientErrorCard(e.toString()),
        data: (auction) => _buildForm(auction),
      ),
    );
  }

  Widget _buildGeneralForm() {
    final l10n = context.l10n;
    final tags = _getTags(l10n);
    final ratingLabels = ['', l10n.ratingPoor, l10n.ratingFair, l10n.ratingGood, l10n.ratingVeryGood, l10n.ratingExcellent];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/RNP_logo.png',
                  width: 48,
                  height: 48,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.shield, size: 48, color: AppColors.primaryBlue),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.feedbackHeaderTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l10n.helpImprove, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.rateExperience, style: AppTextStyles.h2),
          const SizedBox(height: 6),
          Text(l10n.howSatisfied, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              ...List.generate(5, (i) => GestureDetector(
                onTap: () => setState(() => _starRating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    i < _starRating ? Icons.star : Icons.star_border,
                    color: AppColors.gold,
                    size: 36,
                  ),
                ),
              )),
              const SizedBox(width: 12),
              Text(
                ratingLabels[_starRating],
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.darkGold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l10n.whatWentWell, style: AppTextStyles.h2),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) {
              final sel = _selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => setState(() {
                  sel ? _selectedTags.remove(tag) : _selectedTags.add(tag);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primaryBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: sel ? AppColors.primaryBlue : AppColors.border,
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text(l10n.additionalComments, style: AppTextStyles.h2),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 4,
            maxLength: 250,
            decoration: InputDecoration(hintText: l10n.shareExperience),
          ),
          const SizedBox(height: 20),
          Text(l10n.wouldRecommend, style: AppTextStyles.h2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _wouldRecommend = true),
                  icon: const Icon(Icons.thumb_up_outlined, size: 18),
                  label: Text(l10n.yes),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _wouldRecommend == true ? AppColors.primaryBlue : AppColors.surface,
                    foregroundColor: _wouldRecommend == true ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _wouldRecommend = false),
                  icon: const Icon(Icons.thumb_down_outlined, size: 18),
                  label: Text(l10n.no),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _wouldRecommend == false ? AppColors.error.withValues(alpha: 0.1) : null,
                    foregroundColor: _wouldRecommend == false ? AppColors.error : AppColors.textPrimary,
                    side: BorderSide(
                      color: _wouldRecommend == false ? AppColors.error : AppColors.border,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      final user = ref.read(currentUserProvider).value;
                      _submit('General Feedback', user?.region ?? '');
                    },
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : Text(l10n.submitFeedback, style: AppTextStyles.button),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildForm(AuctionModel auction) {
    final l10n = context.l10n;
    final tags = _getTags(l10n);
    final ratingLabels = ['', l10n.ratingPoor, l10n.ratingFair, l10n.ratingGood, l10n.ratingVeryGood, l10n.ratingExcellent];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header card with RNP logo ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/RNP_logo.png',
                  width: 48,
                  height: 48,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.shield,
                    size: 48,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.auctionFeedbackTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l10n.helpImproveService, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Auction reference (real data) ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _InfoRow(l10n.auctionItem, auction.itemName),
                const Divider(height: 16, color: AppColors.border),
                _InfoRow(l10n.region, auction.region),
                const Divider(height: 16, color: AppColors.border),
                _InfoRow(l10n.date, DateHelper.formatDate(DateTime.now())),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Star rating ────────────────────────────────────────────────────
          Text(l10n.rateExperience, style: AppTextStyles.h2),
          const SizedBox(height: 6),
          Text(l10n.howSatisfiedService, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              ...List.generate(
                5,
                (i) => GestureDetector(
                  onTap: () => setState(() => _starRating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      i < _starRating ? Icons.star : Icons.star_border,
                      color: AppColors.gold,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                ratingLabels[_starRating],
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Tag chips ──────────────────────────────────────────────────────
          Text(l10n.whatWentWell, style: AppTextStyles.h2),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags.map((tag) {
              final sel = _selectedTags.contains(tag);
              return GestureDetector(
                onTap: () => setState(() {
                  sel ? _selectedTags.remove(tag) : _selectedTags.add(tag);
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primaryBlue : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: sel ? AppColors.primaryBlue : AppColors.border,
                    ),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Comment box ────────────────────────────────────────────────────
          Text(l10n.additionalComments, style: AppTextStyles.h2),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 4,
            maxLength: 250,
            decoration: InputDecoration(hintText: l10n.shareExperience),
          ),

          const SizedBox(height: 20),

          // ── Would you recommend? ────────────────────────────────────────────
          Text(l10n.wouldRecommend, style: AppTextStyles.h2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _wouldRecommend = true),
                  icon: const Icon(Icons.thumb_up_outlined, size: 18),
                  label: Text(l10n.yes),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _wouldRecommend == true
                        ? AppColors.primaryBlue
                        : AppColors.surface,
                    foregroundColor: _wouldRecommend == true
                        ? Colors.white
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _wouldRecommend = false),
                  icon: const Icon(Icons.thumb_down_outlined, size: 18),
                  label: Text(l10n.no),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _wouldRecommend == false
                        ? AppColors.error.withValues(alpha: 0.1)
                        : null,
                    foregroundColor: _wouldRecommend == false
                        ? AppColors.error
                        : AppColors.textPrimary,
                    side: BorderSide(
                      color: _wouldRecommend == false
                          ? AppColors.error
                          : AppColors.border,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => _submit(auction.itemName, auction.region),
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : Text(l10n.submitFeedback, style: AppTextStyles.button),
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              l10n.thankYouRnp,
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      );
}
