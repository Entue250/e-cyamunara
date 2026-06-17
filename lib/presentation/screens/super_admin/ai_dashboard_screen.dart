// lib/presentation/screens/super_admin/ai_dashboard_screen.dart
//
// Phase 9H — AI Intelligence Dashboard (super admin only)
//
// Shows the full state of the AI continuous learning pipeline:
//   • System status  — shadow mode flags, model versions, retrain pending
//   • Quality        — rolling MAPE, signal accuracy, coverage rate
//   • Candidates     — models currently under evaluation (Phase 9E/9F)
//   • Drift alerts   — latest per-model drift severity (Phase 9G)
//   • Recent events  — last 10 ai_prediction_logs entries

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'super_admin_providers.dart';
import 'super_admin_shared.dart';

// ════════════════════════════════════════════════════════════════════════════
// Screen
// ════════════════════════════════════════════════════════════════════════════

class AiDashboardScreen extends ConsumerWidget {
  const AiDashboardScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(aiDashboardOverviewProvider);
    ref.invalidate(aiCandidateModelsProvider);
    ref.invalidate(aiLatestDriftProvider);
    ref.invalidate(aiRecentEventsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync   = ref.watch(aiDashboardOverviewProvider);
    final candidatesAsync = ref.watch(aiCandidateModelsProvider);
    final driftAsync      = ref.watch(aiLatestDriftProvider);
    final eventsAsync     = ref.watch(aiRecentEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'AI Intelligence',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _refresh(ref),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── System Status ───────────────────────────────────────────
              overviewAsync.when(
                loading: () => const _SectionShimmer(),
                error:   (_, _) => const _ErrorCard('Could not load system status'),
                data:    (d) => _SystemStatusCard(data: d),
              ),
              const SizedBox(height: 10),

              // ── AI Controls (Phase 9I) ──────────────────────────────────
              overviewAsync.when(
                loading: () => const SizedBox.shrink(),
                error:   (_, _) => const SizedBox.shrink(),
                data:    (d) => _AiControlsCard(overviewData: d),
              ),
              const SizedBox(height: 12),

              // ── Quality Metrics ─────────────────────────────────────────
              overviewAsync.when(
                loading: () => const _SectionShimmer(),
                error:   (_, _) => const SizedBox.shrink(),
                data:    (d) => _QualityMetricsCard(data: d),
              ),
              const SizedBox(height: 16),

              // ── Evaluation Candidates ───────────────────────────────────
              const _SectionHeader(
                icon: Icons.science_outlined,
                label: 'Evaluation Candidates',
              ),
              const SizedBox(height: 8),
              candidatesAsync.when(
                loading: () => const _SectionShimmer(),
                error:   (_, _) => const _ErrorCard('Could not load candidates'),
                data:    (list) => list.isEmpty
                    ? const EmptyStateCard(
                        'No candidates under evaluation',
                        icon: Icons.check_circle_outline,
                      )
                    : Column(
                        children: list
                            .map((c) => _CandidateCard(candidate: c))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),

              // ── Drift Alerts ────────────────────────────────────────────
              const _SectionHeader(
                icon: Icons.monitor_heart_outlined,
                label: 'Drift Alerts',
              ),
              const SizedBox(height: 8),
              driftAsync.when(
                loading: () => const _SectionShimmer(),
                error:   (_, _) => const _ErrorCard('Could not load drift data'),
                data:    (list) => list.isEmpty
                    ? const EmptyStateCard(
                        'No drift data yet — check back after 04:00 UTC',
                        icon: Icons.sensors_outlined,
                      )
                    : Column(
                        children: list
                            .map((d) => _DriftRow(drift: d))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),

              // ── Recent Events ───────────────────────────────────────────
              const _SectionHeader(
                icon: Icons.history_outlined,
                label: 'Recent AI Events',
              ),
              const SizedBox(height: 8),
              eventsAsync.when(
                loading: () => const _SectionShimmer(),
                error:   (_, _) => const _ErrorCard('Could not load events'),
                data:    (list) => list.isEmpty
                    ? const EmptyStateCard(
                        'No AI events recorded yet',
                        icon: Icons.inbox_outlined,
                      )
                    : Column(
                        children: list
                            .map((e) => _EventRow(event: e))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 0),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// System Status card
// ════════════════════════════════════════════════════════════════════════════

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final shadowOn       = data['shadow_mode_enabled'] == 'true';
    final visibleClients = data['predictions_visible'] == 'true';
    final retrainPending = data['retrain_pending'] == 'true';
    final modelA = data['model_a_version'] as String? ?? '—';
    final modelB = data['model_b_version'] as String? ?? '—';
    final modelC = data['model_c_version'] as String? ?? '—';
    final lastRetrain = data['last_retrain_date'] as String?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.darkBlue, AppColors.primaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              const Text(
                'AI SYSTEM STATUS',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (retrainPending)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: const Text(
                    'RETRAIN PENDING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Flag pills
          Row(
            children: [
              _FlagPill(
                label: 'Shadow Mode',
                active: shadowOn,
                activeColor: AppColors.success,
              ),
              const SizedBox(width: 8),
              _FlagPill(
                label: 'Visible to Clients',
                active: visibleClients,
                activeColor: AppColors.gold,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Model versions
          const Text(
            'ACTIVE VERSIONS',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _VersionChip(label: 'Model A', version: modelA),
              const SizedBox(width: 6),
              _VersionChip(label: 'Model B', version: modelB),
              const SizedBox(width: 6),
              _VersionChip(label: 'Model C', version: modelC),
            ],
          ),

          if (lastRetrain != null && lastRetrain.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.update, color: Colors.white38, size: 12),
                const SizedBox(width: 4),
                Text(
                  'Last retrain: $lastRetrain',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FlagPill extends StatelessWidget {
  const _FlagPill({
    required this.label,
    required this.active,
    required this.activeColor,
  });
  final String label;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.2)
              : Colors.white10,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? activeColor.withValues(alpha: 0.6) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 10,
              color: active ? activeColor : Colors.white38,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? activeColor : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label, required this.version});
  final String label, version;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white54, fontSize: 9),
              ),
              const SizedBox(height: 2),
              Text(
                version,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Quality Metrics card
// ════════════════════════════════════════════════════════════════════════════

class _QualityMetricsCard extends StatelessWidget {
  const _QualityMetricsCard({required this.data});
  final Map<String, dynamic> data;

  String _pct(dynamic v) {
    if (v == null) return '—';
    final d = (v as num).toDouble();
    return '${(d * 100).toStringAsFixed(1)}%';
  }

  String _ms(dynamic v) {
    if (v == null) return '—';
    return '${(v as num).toInt()} ms';
  }

  @override
  Widget build(BuildContext context) {
    final mape     = data['rolling_mape_model_a'];
    final accuracy = data['signal_accuracy_rate'];
    final coverage = data['coverage_rate'];
    final avgMs    = data['yesterday_avg_ms'];
    final generated = data['yesterday_generated'] as int? ?? 0;
    final errors    = data['yesterday_errors'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YESTERDAY\'S QUALITY',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricCell(
                label: 'Rolling MAPE',
                value: _pct(mape),
                color: _mapeColor(mape),
              ),
              _MetricCell(
                label: 'Signal Accuracy',
                value: _pct(accuracy),
                color: AppColors.primaryBlue,
              ),
              _MetricCell(
                label: 'Coverage',
                value: _pct(coverage),
                color: _coverageColor(coverage),
              ),
              _MetricCell(
                label: 'Avg Latency',
                value: _ms(avgMs),
                color: AppColors.textPrimary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.bolt_outlined,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                '$generated predictions generated · $errors errors',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _mapeColor(dynamic v) {
    if (v == null) return AppColors.textSecondary;
    final d = (v as num).toDouble();
    if (d < 0.10) return AppColors.success;
    if (d < 0.20) return AppColors.warning;
    return AppColors.error;
  }

  Color _coverageColor(dynamic v) {
    if (v == null) return AppColors.textSecondary;
    final d = (v as num).toDouble();
    if (d >= 0.80) return AppColors.success;
    if (d >= 0.60) return AppColors.warning;
    return AppColors.error;
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Candidate card
// ════════════════════════════════════════════════════════════════════════════

class _CandidateCard extends ConsumerWidget {
  const _CandidateCard({required this.candidate});
  final Map<String, dynamic> candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls  = ref.watch(aiControlsProvider);
    final notifier  = ref.read(aiControlsProvider.notifier);
    final id        = candidate['id'] as String? ?? '';
    final modelName = candidate['model_name'] as String? ?? '—';
    final version   = candidate['candidate_version'] as String? ?? '—';
    final compared  = candidate['comparisons_count'] as int? ?? 0;
    final minNeeded = candidate['min_comparisons_needed'] as int? ?? 100;
    final candMape  = candidate['candidate_mape'] as num?;
    final activeMape = candidate['active_mape'] as num?;
    final progress  = (minNeeded > 0 ? compared / minNeeded : 0.0).clamp(0.0, 1.0);

    String? improvement;
    Color improvementColor = AppColors.textSecondary;
    if (candMape != null && activeMape != null && activeMape > 0) {
      final pct = ((activeMape - candMape) / activeMape * 100);
      improvement = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}% vs active';
      improvementColor = pct >= 3
          ? AppColors.success
          : pct >= 0
              ? AppColors.warning
              : AppColors.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  modelName.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  version,
                  style: AppTextStyles.h3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: const Text(
                  'EVALUATING',
                  style: TextStyle(
                    color: AppColors.darkGold,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceGrey,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 1.0
                          ? AppColors.success
                          : AppColors.primaryBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$compared / $minNeeded',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'comparisons collected',
            style: TextStyle(
                fontSize: 10, color: AppColors.textHint),
          ),

          if (improvement != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  improvementColor == AppColors.success
                      ? Icons.trending_up
                      : improvementColor == AppColors.error
                          ? Icons.trending_down
                          : Icons.trending_flat,
                  size: 14,
                  color: improvementColor,
                ),
                const SizedBox(width: 4),
                Text(
                  improvement,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: improvementColor,
                  ),
                ),
              ],
            ),
          ],

          // ── Manual controls (Phase 9I) ────────────────────────────────
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (controls.isLoading || id.isEmpty)
                      ? null
                      : () => _confirm(
                            context,
                            'Force Promote',
                            'Promote ${modelName.replaceAll("_", " ")} to active now, '
                            'bypassing the ${minNeeded}-comparison gate?',
                            AppColors.success,
                            () => notifier.promoteCandidate(id),
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: BorderSide(
                      color: controls.isLoading
                          ? AppColors.border
                          : AppColors.success.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Promote'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: (controls.isLoading || id.isEmpty)
                      ? null
                      : () => _confirm(
                            context,
                            'Force Reject',
                            'Reject this ${modelName.replaceAll("_", " ")} candidate '
                            'and clear its shadow slot?',
                            AppColors.error,
                            () => notifier.rejectCandidate(id),
                          ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: controls.isLoading
                          ? AppColors.border
                          : AppColors.error.withValues(alpha: 0.55),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    String message,
    Color color,
    VoidCallback onConfirm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text(
              'Confirm',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Drift row
// ════════════════════════════════════════════════════════════════════════════

class _DriftRow extends StatelessWidget {
  const _DriftRow({required this.drift});
  final Map<String, dynamic> drift;

  @override
  Widget build(BuildContext context) {
    final modelName = drift['model_name'] as String? ?? '—';
    final severity  = drift['drift_severity'] as String? ?? 'none';
    final date      = drift['metric_date'] as String? ?? '—';
    final signals   = (drift['signals_triggered'] as List?)?.cast<String>() ?? [];
    final mape7d    = drift['mape_7d'] as num?;
    final mape30d   = drift['mape_30d'] as num?;
    final retrain   = drift['early_retrain_triggered'] as bool? ?? false;

    final severityColor = switch (severity) {
      'high' => AppColors.error,
      'low'  => AppColors.warning,
      _      => AppColors.success,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: severity == 'none'
              ? AppColors.border
              : severityColor.withValues(alpha: 0.4),
          width: severity == 'none' ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          // Severity indicator
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              severity == 'high'
                  ? Icons.warning_amber_rounded
                  : severity == 'low'
                      ? Icons.info_outline
                      : Icons.check_circle_outline,
              size: 20,
              color: severityColor,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      modelName.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      date,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textHint),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (signals.isNotEmpty)
                  Text(
                    signals.join(' · '),
                    style: TextStyle(
                      fontSize: 10,
                      color: severityColor,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const Text(
                    'No signals triggered',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
                if (mape7d != null && mape30d != null)
                  Text(
                    'MAPE 7d: ${(mape7d * 100).toStringAsFixed(1)}%  '
                    '30d: ${(mape30d * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: severityColor,
                  ),
                ),
              ),
              if (retrain) ...[
                const SizedBox(height: 4),
                const Text(
                  'Retrain triggered',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Recent event row
// ════════════════════════════════════════════════════════════════════════════

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final eventType  = event['event_type'] as String? ?? '—';
    final createdAt  = event['created_at'] as String? ?? '';
    final dateStr    = createdAt.length >= 16
        ? createdAt.substring(0, 16).replaceAll('T', ' ')
        : createdAt;

    final icon  = _iconForEvent(eventType);
    final color = _colorForEvent(eventType);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelForEvent(eventType),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textHint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForEvent(String type) => switch (type) {
        'prediction_generated'    => Icons.bolt_outlined,
        'prediction_skipped'      => Icons.skip_next_outlined,
        'prediction_error'        => Icons.error_outline,
        'comparison_computed'     => Icons.compare_arrows,
        'retrain_trigger'         => Icons.model_training,
        'metrics_collected'       => Icons.analytics_outlined,
        'candidate_promoted'      => Icons.upgrade_outlined,
        'candidate_rejected'      => Icons.block_outlined,
        'early_retrain_triggered' => Icons.fast_forward_outlined,
        'drift_detected'          => Icons.warning_amber_outlined,
        'drift_resolved'          => Icons.check_circle_outline,
        _                         => Icons.info_outline,
      };

  Color _colorForEvent(String type) => switch (type) {
        'prediction_generated'    => AppColors.primaryBlue,
        'prediction_skipped'      => AppColors.textSecondary,
        'prediction_error'        => AppColors.error,
        'comparison_computed'     => AppColors.info,
        'retrain_trigger'         => AppColors.darkGold,
        'metrics_collected'       => AppColors.textSecondary,
        'candidate_promoted'      => AppColors.success,
        'candidate_rejected'      => AppColors.error,
        'early_retrain_triggered' => AppColors.warning,
        'drift_detected'          => AppColors.warning,
        'drift_resolved'          => AppColors.success,
        _                         => AppColors.textSecondary,
      };

  String _labelForEvent(String type) => switch (type) {
        'prediction_generated'    => 'Prediction Generated',
        'prediction_skipped'      => 'Prediction Skipped',
        'prediction_error'        => 'Prediction Error',
        'comparison_computed'     => 'Comparison Computed',
        'retrain_trigger'         => 'Retrain Triggered',
        'metrics_collected'       => 'Metrics Collected',
        'candidate_promoted'      => 'Candidate Promoted',
        'candidate_rejected'      => 'Candidate Rejected',
        'early_retrain_triggered' => 'Early Retrain Triggered',
        'drift_detected'          => 'Drift Detected',
        'drift_resolved'          => 'Drift Resolved',
        _                         => type.replaceAll('_', ' '),
      };
}

// ════════════════════════════════════════════════════════════════════════════
// Shared private helpers
// ════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primaryBlue),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.h1),
        ],
      );
}

// ════════════════════════════════════════════════════════════════════════════
// AI Controls card (Phase 9I)
// ════════════════════════════════════════════════════════════════════════════

class _AiControlsCard extends ConsumerWidget {
  const _AiControlsCard({required this.overviewData});
  final Map<String, dynamic> overviewData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = ref.watch(aiControlsProvider);
    final notifier = ref.read(aiControlsProvider.notifier);

    final shadowOn  = overviewData['shadow_mode_enabled'] == 'true';
    final visibleOn = overviewData['predictions_visible'] == 'true';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.tune_outlined,
                  size: 15, color: AppColors.primaryBlue),
              const SizedBox(width: 6),
              const Text(
                'CONTROLS',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              if (controls.isLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ],
            ],
          ),

          // Inline error
          if (controls.error != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.error_outline,
                    size: 12, color: AppColors.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    controls.error!,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: notifier.clearError,
                  child: const Icon(Icons.close,
                      size: 14, color: AppColors.textHint),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          _ToggleRow(
            label: 'Shadow Mode',
            subtitle: 'Run predictions silently — no client exposure',
            value: shadowOn,
            disabled: controls.isLoading,
            onChanged: (v) => notifier.toggleFlag(
              'ai.shadow_mode_enabled',
              v ? 'true' : 'false',
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          _ToggleRow(
            label: 'Visible to Clients',
            subtitle: 'Show AI insights on the auction detail screen',
            value: visibleOn,
            disabled: controls.isLoading,
            onChanged: (v) => notifier.toggleFlag(
              'ai.predictions_visible',
              v ? 'true' : 'false',
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: controls.isLoading
                  ? null
                  : () => _confirmRetrain(context, notifier),
              icon: const Icon(Icons.model_training, size: 15),
              label: const Text('Trigger Retraining Now'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(
                  color: controls.isLoading
                      ? AppColors.border
                      : AppColors.warning.withValues(alpha: 0.6),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRetrain(
    BuildContext context,
    AiControlsNotifier notifier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trigger Retraining?'),
        content: const Text(
          'This queues a full model retraining run using production data. '
          'The training worker must be online for the job to complete.\n\n'
          'If the training worker is offline, the retrain_pending flag is '
          'still set and the job will run on the next scheduled start.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning),
            child: const Text('Trigger',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) notifier.triggerRetrain();
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });
  final String label, subtitle;
  final bool value, disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: disabled ? null : onChanged,
              activeColor: AppColors.primaryBlue,
            ),
          ],
        ),
      );
}

class _SectionShimmer extends StatelessWidget {
  const _SectionShimmer();

  @override
  Widget build(BuildContext context) => Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceGrey,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
        ),
      );
}
