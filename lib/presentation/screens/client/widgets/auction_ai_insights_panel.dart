// lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations_ext.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/ai_repository.dart';
import '../../../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget — inserted into AuctionDetailScreen after the bid stats box.
// Fires both AI calls once in initState via Future.wait.
// Any failure (network error, shadow mode, null result) → SizedBox.shrink().
// The bid flow below is NEVER blocked.
// ─────────────────────────────────────────────────────────────────────────────

class AuctionAiInsightsPanel extends ConsumerStatefulWidget {
  const AuctionAiInsightsPanel({
    super.key,
    required this.auctionId,
    required this.auction,
  });

  final String auctionId;
  final AuctionModel auction;

  @override
  ConsumerState<AuctionAiInsightsPanel> createState() =>
      _AuctionAiInsightsPanelState();
}

class _AuctionAiInsightsPanelState
    extends ConsumerState<AuctionAiInsightsPanel> {
  late final Future<List<Map<String, dynamic>?>> _combinedFuture;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(aiRepositoryProvider);
    _combinedFuture = Future.wait<Map<String, dynamic>?>([
      repo.fetchPriceInsight(widget.auction).catchError((_) => null),
      repo.fetchBidForecast(widget.auction).catchError((_) => null),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: _combinedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AiInsightsShimmer();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final insight = snapshot.data?[0];
        final forecast = snapshot.data?[1];

        if (insight == null && forecast == null) return const SizedBox.shrink();
        if (insight?['shadow_mode'] == true) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _AiInsightsCard(
            insight: insight,
            forecast: forecast,
            startingPrice: widget.auction.startingPrice,
          ),
        );
      },
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class _AiInsightsShimmer extends StatefulWidget {
  const _AiInsightsShimmer();

  @override
  State<_AiInsightsShimmer> createState() => _AiInsightsShimmerState();
}

class _AiInsightsShimmerState extends State<_AiInsightsShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBar(120, 14),
              const SizedBox(height: 12),
              _shimmerBar(double.infinity, 12),
              const SizedBox(height: 8),
              _shimmerBar(double.infinity, 12),
              const SizedBox(height: 8),
              _shimmerBar(180, 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      );
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _AiInsightsCard extends StatelessWidget {
  const _AiInsightsCard({
    required this.insight,
    required this.forecast,
    required this.startingPrice,
  });

  final Map<String, dynamic>? insight;
  final Map<String, dynamic>? forecast;
  final double startingPrice;

  @override
  Widget build(BuildContext context) {
    final signal = insight?['value_signal'] as String? ?? 'fair_value';
    final marketPrice =
        (insight?['expected_auction_price'] as num?)?.toDouble();
    final modelVersion = insight?['model_version'] as String? ??
        forecast?['model_b_version'] as String?;

    double? clampedBid;
    bool isAtFloor = false;
    final rawBid = (forecast?['predicted_winning_bid'] as num?)?.toDouble();
    if (rawBid != null) {
      clampedBid = max(rawBid, startingPrice);
      isAtFloor = clampedBid <= startingPrice * 1.05;
    }

    double? probability =
        (forecast?['predicted_probability'] as num?)?.toDouble();
    if (probability != null) probability = probability.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(
                context.l10n.aiInsights,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (modelVersion != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    modelVersion,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          _ValueSignalBadge(signal: signal),

          if (marketPrice != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PriceRow(
              label: context.l10n.aiEstMarketValue,
              amount: marketPrice,
            ),
          ],

          if (clampedBid != null) ...[
            const Divider(height: AppSpacing.lg),
            _PriceRow(
              label: context.l10n.aiPredictedWinBid,
              amount: clampedBid,
              prefix: isAtFloor ? context.l10n.aiAtLeast : null,
            ),
          ],

          if (probability != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ProbabilityRow(probability: probability),
          ],
        ],
      ),
    );
  }
}

// ── Value signal badge ────────────────────────────────────────────────────────

class _ValueSignalBadge extends StatelessWidget {
  const _ValueSignalBadge({required this.signal});
  final String signal;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (signal) {
      'undervalued' => (context.l10n.aiValueSignalUnder, AppColors.success),
      'overvalued' => (context.l10n.aiValueSignalOver, AppColors.warning),
      _ => (context.l10n.aiValueSignalFair, AppColors.primaryBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Price row ─────────────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.prefix,
  });
  final String label;
  final double amount;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final formatted = prefix != null
        ? '$prefix ${AppFormatters.rwf(amount)}'
        : AppFormatters.rwf(amount);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          formatted,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Probability row ───────────────────────────────────────────────────────────

class _ProbabilityRow extends StatelessWidget {
  const _ProbabilityRow({required this.probability});
  final double probability;

  @override
  Widget build(BuildContext context) {
    final pct = (probability * 100).round();
    final barColor = probability >= 0.6
        ? AppColors.success
        : probability >= 0.3
            ? AppColors.warning
            : AppColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.aiWinProbability,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: probability,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          minHeight: 6,
        ),
      ],
    );
  }
}
