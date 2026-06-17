// lib/presentation/screens/super_admin/super_admin_providers.dart
//
// Shared Riverpod providers for ALL Super Admin screens.
// Exported via super_admin_screens.dart — import that barrel file, not this one.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';
import '../../../data/models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Date-range enum used by NationalReportsScreen
// ─────────────────────────────────────────────────────────────────────────────

enum SuperAdminStatsRange {
  last30Days,
  last3Months,
  thisYear,
  allTime,
}

extension SuperAdminStatsRangeExt on SuperAdminStatsRange {
  String get label => switch (this) {
    SuperAdminStatsRange.last30Days  => 'Last 30 Days',
    SuperAdminStatsRange.last3Months => 'Last 3 Months',
    SuperAdminStatsRange.thisYear    => 'This Year',
    SuperAdminStatsRange.allTime     => 'All Time',
  };

  DateTime get startDate {
    final now = DateTime.now();
    return switch (this) {
      SuperAdminStatsRange.last30Days  => now.subtract(const Duration(days: 30)),
      SuperAdminStatsRange.last3Months =>
          DateTime(now.year, now.month - 3, now.day),
      SuperAdminStatsRange.thisYear    => DateTime(now.year, 1, 1),
      SuperAdminStatsRange.allTime     => DateTime(2000, 1, 1),
    };
  }

  DateTime get endDate => DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// All region admins — ordered by region
// ─────────────────────────────────────────────────────────────────────────────

/// Reads all region admins from Supabase. Returns [] on any error so screens
/// never show an infinite spinner. Invalidate via ref.invalidate() to refresh.
final superAdminAllAdminsProvider =
    FutureProvider<List<RegionAdminModel>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.regionAdminsTable)
        .select()
        .order('region');
    return (rows as List)
        .map((r) => RegionAdminModel.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// All-time national statistics — Dashboard & Profile
// ─────────────────────────────────────────────────────────────────────────────

/// National aggregates across all time. Uses Future.wait to run 3 DB queries
/// in parallel — cuts latency compared to sequential awaits.
final superAdminStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final results = await Future.wait([
      client
          .from(SupabaseConstants.auctionsTable)
          .select('auction_status, current_highest_bid, winning_amount'),
      client.from(SupabaseConstants.bidsTable).select('id'),
      client.from(SupabaseConstants.usersTable).select('id'),
    ]);

    final auctions  = results[0] as List;
    final totalBids = (results[1] as List).length;
    final totalClients = (results[2] as List).length;

    final closedAuctions = auctions
        .where((a) => (a as Map)['auction_status'] == 'closed')
        .toList();
    final activeAuctions = auctions
        .where((a) => (a as Map)['auction_status'] == 'active')
        .toList();

    // Prefer winning_amount (set on close), fall back to current_highest_bid
    final totalRevenue = closedAuctions.fold<double>(0, (sum, a) {
      final m = a as Map;
      return sum +
          ((m['winning_amount'] as num?)?.toDouble() ??
              (m['current_highest_bid'] as num?)?.toDouble() ??
              0.0);
    });

    return {
      'total_auctions':  auctions.length,
      'active_auctions': activeAuctions.length,
      'closed_auctions': closedAuctions.length,
      'total_revenue':   totalRevenue,
      'total_bids':      totalBids,
      'total_clients':   totalClients,
    };
  } catch (_) {
    return {
      'total_auctions':  0,
      'active_auctions': 0,
      'closed_auctions': 0,
      'total_revenue':   0.0,
      'total_bids':      0,
      'total_clients':   0,
    };
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Actual auction counts per admin — bypasses stale denormalized columns
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a map of adminUid to posted/closed counts queried live from auctions table.
final superAdminAuctionCountsProvider =
    FutureProvider<Map<String, Map<String, int>>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final rows = await client
        .from(SupabaseConstants.auctionsTable)
        .select('posted_by_admin_uid, auction_status');

    final Map<String, Map<String, int>> counts = {};
    for (final row in rows as List) {
      final uid = row['posted_by_admin_uid'] as String?;
      if (uid == null || uid.isEmpty) continue;
      counts.putIfAbsent(uid, () => {'posted': 0, 'closed': 0});
      counts[uid]!['posted'] = (counts[uid]!['posted'] ?? 0) + 1;
      if (row['auction_status'] == SupabaseConstants.statusClosed) {
        counts[uid]!['closed'] = (counts[uid]!['closed'] ?? 0) + 1;
      }
    }
    return counts;
  } catch (_) {
    return {};
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
// AI Intelligence providers — AiDashboardScreen (Phase 9H)
// ─────────────────────────────────────────────────────────────────────────────

/// Single-row summary from v_ai_shadow_dashboard (super-admin view).
/// Contains model versions, shadow mode flags, latest daily quality metrics,
/// and all-time prediction totals.
final aiDashboardOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final row = await Supabase.instance.client
        .from(SupabaseConstants.vAiShadowDashboard)
        .select()
        .maybeSingle();
    return (row as Map<String, dynamic>?) ?? {};
  } catch (_) {
    return {};
  }
});

/// All candidate models currently under evaluation (status = 'evaluating').
final aiCandidateModelsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.aiCandidateModelsTable)
        .select(
          'id, model_name, candidate_version, active_version_at_registration, '
          'registered_at, comparisons_count, min_comparisons_needed, '
          'candidate_mape, active_mape, status',
        )
        .eq('status', 'evaluating')
        .order('registered_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});

/// Latest drift row per model from the last 7 days.
/// Returns at most 3 rows (one per model_a / model_b / model_c).
final aiLatestDriftProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.aiDriftMetricsTable)
        .select(
          'model_name, metric_date, drift_severity, drift_detected, '
          'signals_triggered, mape_7d, mape_30d, early_retrain_triggered',
        )
        .gte('metric_date', cutoff)
        .order('metric_date', ascending: false);

    // Keep only the most recent row per model_name.
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      if (seen.add(row['model_name'] as String)) result.add(row);
    }
    return result;
  } catch (_) {
    return [];
  }
});

/// Most recent 10 AI prediction log entries for the events timeline.
final aiRecentEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.aiPredictionLogsTable)
        .select('event_type, created_at, metadata, error_message')
        .order('created_at', ascending: false)
        .limit(10);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});

/// Single-row overall pipeline health from v_ai_pipeline_health (Phase 9J).
/// Returns null if the view returns no rows (e.g. empty database).
final aiPipelineHealthProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final row = await Supabase.instance.client
        .from(SupabaseConstants.vAiPipelineHealth)
        .select()
        .maybeSingle();
    return row as Map<String, dynamic>?;
  } catch (_) {
    return null;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Graduation readiness — Phase 9K
// ─────────────────────────────────────────────────────────────────────────────

/// Aggregates all data needed to decide whether the AI system is ready to
/// graduate from shadow mode to live (predictions_visible_to_clients = true).
///
/// Returns a map with the keys:
///   coverage_rate          double?  — latest coverage from ai_shadow_metrics
///   rolling_mape           double?  — rolling MAPE from ai_shadow_metrics
///   shadow_days            int      — number of days with metrics rows (proxy for age)
///   comparisons_count      int      — total rows in ai_prediction_comparisons
///   has_high_drift         bool     — any high-drift in last 7 days
///   predictions_visible    bool     — current value of predictions_visible_to_clients
///   coverage_ok            bool     — coverage_rate >= 0.80
///   mape_ok                bool     — rolling_mape <= 0.25 (or null data)
///   shadow_age_ok          bool     — shadow_days >= 7
///   comparisons_ok         bool     — comparisons_count >= 50
///   drift_ok               bool     — !has_high_drift
///   ready                  bool     — all five checks pass
final aiGraduationReadinessProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  try {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 7))
        .toIso8601String()
        .substring(0, 10);

    final results = await Future.wait([
      // Latest shadow metrics row
      client
          .from(SupabaseConstants.aiShadowMetricsTable)
          .select('coverage_rate, rolling_mape_model_a')
          .order('metric_date', ascending: false)
          .limit(1),
      // Count of total shadow metrics rows (= days in shadow mode)
      client
          .from(SupabaseConstants.aiShadowMetricsTable)
          .select('metric_date'),
      // Total prediction comparisons
      client
          .from(SupabaseConstants.aiPredictionComparisonsTable)
          .select('id'),
      // High drift in last 7 days
      client
          .from(SupabaseConstants.aiDriftMetricsTable)
          .select('drift_severity')
          .gte('metric_date', cutoff)
          .eq('drift_severity', 'high'),
      // Current visibility flag
      client
          .from(SupabaseConstants.aiFeatureFlagsTable)
          .select('value')
          .eq('key', 'ai.predictions_visible_to_clients')
          .maybeSingle(),
    ]);

    final latestMetrics  = (results[0] as List).isNotEmpty
        ? (results[0] as List).first as Map<String, dynamic>
        : null;
    final shadowDays     = (results[1] as List).length;
    final comparisons    = (results[2] as List).length;
    final highDriftRows  = (results[3] as List).length;
    final flagRow        = results[4] as Map<String, dynamic>?;

    final coverageRate  = (latestMetrics?['coverage_rate'] as num?)?.toDouble();
    final rollingMape   = (latestMetrics?['rolling_mape_model_a'] as num?)?.toDouble();
    final predictionsVisible = flagRow?['value'] == 'true';

    final coverageOk    = (coverageRate ?? 0) >= 0.80;
    final mapeOk        = rollingMape == null || rollingMape <= 0.25;
    final shadowAgeOk   = shadowDays >= 7;
    final comparisonsOk = comparisons >= 50;
    final driftOk       = highDriftRows == 0;

    return {
      'coverage_rate':       coverageRate,
      'rolling_mape':        rollingMape,
      'shadow_days':         shadowDays,
      'comparisons_count':   comparisons,
      'has_high_drift':      highDriftRows > 0,
      'predictions_visible': predictionsVisible,
      'coverage_ok':         coverageOk,
      'mape_ok':             mapeOk,
      'shadow_age_ok':       shadowAgeOk,
      'comparisons_ok':      comparisonsOk,
      'drift_ok':            driftOk,
      'ready': coverageOk && mapeOk && shadowAgeOk && comparisonsOk && driftOk,
    };
  } catch (_) {
    return {
      'coverage_rate': null, 'rolling_mape': null, 'shadow_days': 0,
      'comparisons_count': 0, 'has_high_drift': false,
      'predictions_visible': false,
      'coverage_ok': false, 'mape_ok': false, 'shadow_age_ok': false,
      'comparisons_ok': false, 'drift_ok': false, 'ready': false,
    };
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// AI Manual Controls — AiDashboardScreen (Phase 9I)
// ─────────────────────────────────────────────────────────────────────────────

/// Holds the in-flight / error state for super-admin AI write operations.
/// All methods are single-lock: only one operation runs at a time.
class AiControlsState {
  final bool isLoading;
  final String? error;
  const AiControlsState({this.isLoading = false, this.error});
}

class AiControlsNotifier extends StateNotifier<AiControlsState> {
  AiControlsNotifier(this._ref) : super(const AiControlsState());
  final Ref _ref;

  /// Toggles `ai.shadow_mode_enabled` or `ai.predictions_visible`.
  Future<bool> toggleFlag(String key, String value) =>
      _run(SupabaseConstants.fnToggleAiFlag, {'key': key, 'value': value}, [
        aiDashboardOverviewProvider,
      ]);

  /// Force-promotes a candidate to active without waiting for the comparison gate.
  Future<bool> promoteCandidate(String candidateId) =>
      _run(SupabaseConstants.fnForcePromoteCandidate, {'candidate_id': candidateId}, [
        aiCandidateModelsProvider,
        aiDashboardOverviewProvider,
        aiRecentEventsProvider,
      ]);

  /// Force-rejects an evaluating candidate and clears its shadow slot.
  Future<bool> rejectCandidate(String candidateId) =>
      _run(SupabaseConstants.fnForceRejectCandidate, {'candidate_id': candidateId}, [
        aiCandidateModelsProvider,
        aiRecentEventsProvider,
      ]);

  /// Manually triggers an early retraining run (calls trigger-early-retraining).
  Future<bool> triggerRetrain() =>
      _run(SupabaseConstants.fnTriggerEarlyRetraining, {'trigger': 'manual'}, [
        aiDashboardOverviewProvider,
        aiRecentEventsProvider,
      ]);

  /// Rolls back [modelName] to its previous deprecated version via ai-model-rollback.
  Future<bool> rollbackModel(String modelName) =>
      _run(SupabaseConstants.fnAiModelRollback, {'model_name': modelName}, [
        aiDashboardOverviewProvider,
        aiRecentEventsProvider,
        aiPipelineHealthProvider,
      ]);

  /// Acknowledges (clears) drift for [modelName] via resolve-model-drift.
  Future<bool> resolveModelDrift(String modelName) =>
      _run(SupabaseConstants.fnResolveDrift, {'model_name': modelName}, [
        aiLatestDriftProvider,
        aiRecentEventsProvider,
        aiPipelineHealthProvider,
      ]);

  /// Triggers an on-demand backfill of predictions for auctions without any.
  Future<bool> backfillPredictions({bool includeClosed = false}) =>
      _run(
        SupabaseConstants.fnBackfillAiPredictions,
        {'include_closed': includeClosed},
        [aiRecentEventsProvider, aiGraduationReadinessProvider],
      );

  /// Graduates shadow mode to live: sets predictions_visible_to_clients = true.
  Future<bool> goLive() =>
      _run(
        SupabaseConstants.fnToggleAiFlag,
        {'key': 'ai.predictions_visible_to_clients', 'value': 'true'},
        [
          aiDashboardOverviewProvider,
          aiGraduationReadinessProvider,
          aiPipelineHealthProvider,
        ],
      );

  void clearError() => state = const AiControlsState();

  Future<bool> _run(
    String fnName,
    Map<String, dynamic> body,
    List<ProviderOrFamily> toInvalidate,
  ) async {
    state = const AiControlsState(isLoading: true);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        fnName,
        body: body,
      );
      // Supabase SDK throws FunctionsException on 4xx/5xx; check status anyway
      // for edge cases where the SDK doesn't throw.
      final data = res.data as Map<String, dynamic>?;
      if (res.status != null && res.status! >= 400) {
        throw Exception(data?['error'] ?? 'Server error ${res.status}');
      }
      for (final p in toInvalidate) {
        _ref.invalidate(p);
      }
      state = const AiControlsState();
      return true;
    } catch (e) {
      state = AiControlsState(error: e.toString().replaceFirst('Exception: ', ''));
      return false;
    }
  }
}

final aiControlsProvider =
    StateNotifierProvider<AiControlsNotifier, AiControlsState>(
  (ref) => AiControlsNotifier(ref),
);

// ─────────────────────────────────────────────────────────────────────────────
// Date-range filtered stats — NationalReportsScreen only
// ─────────────────────────────────────────────────────────────────────────────

/// Filtered stats for the selected date range. FutureProvider.family means
/// each range gets its own cached AsyncValue — switching tabs is instant once
/// data is loaded and the cache is still warm.
final superAdminFilteredStatsProvider =
    FutureProvider.family<Map<String, dynamic>, SuperAdminStatsRange>(
        (ref, range) async {
  final client = Supabase.instance.client;
  final start  = range.startDate.toIso8601String();
  final end    = range.endDate.toIso8601String();

  try {
    final results = await Future.wait([
      client
          .from(SupabaseConstants.auctionsTable)
          .select(
              'auction_status, current_highest_bid, winning_amount, region')
          .gte('created_at', start)
          .lte('created_at', end),
      client
          .from(SupabaseConstants.bidsTable)
          .select('id')
          .gte('created_at', start)
          .lte('created_at', end),
      client
          .from(SupabaseConstants.usersTable)
          .select('id')
          .gte('created_at', start)
          .lte('created_at', end),
    ]);

    final auctions     = results[0] as List;
    final totalBids    = (results[1] as List).length;
    final totalClients = (results[2] as List).length;

    final closedAuctions = auctions
        .where((a) => (a as Map)['auction_status'] == 'closed')
        .toList();
    final activeAuctions = auctions
        .where((a) => (a as Map)['auction_status'] == 'active')
        .toList();

    final totalRevenue = closedAuctions.fold<double>(0, (sum, a) {
      final m = a as Map;
      return sum +
          ((m['winning_amount'] as num?)?.toDouble() ??
              (m['current_highest_bid'] as num?)?.toDouble() ??
              0.0);
    });

    // Per-region breakdown for the performance chart
    final Map<String, int>    auctionsByRegion = {};
    final Map<String, double> revenueByRegion  = {};

    for (final raw in auctions) {
      final a      = raw as Map;
      final region = a['region'] as String? ?? 'Unknown';
      auctionsByRegion[region] = (auctionsByRegion[region] ?? 0) + 1;
      if (a['auction_status'] == 'closed') {
        final amount = (a['winning_amount'] as num?)?.toDouble() ??
            (a['current_highest_bid'] as num?)?.toDouble() ??
            0.0;
        revenueByRegion[region] = (revenueByRegion[region] ?? 0) + amount;
      }
    }

    return {
      'total_auctions':    auctions.length,
      'active_auctions':   activeAuctions.length,
      'closed_auctions':   closedAuctions.length,
      'total_revenue':     totalRevenue,
      'total_bids':        totalBids,
      'total_clients':     totalClients,
      'auctions_by_region': auctionsByRegion,
      'revenue_by_region':  revenueByRegion,
    };
  } catch (_) {
    return {
      'total_auctions':    0,
      'active_auctions':   0,
      'closed_auctions':   0,
      'total_revenue':     0.0,
      'total_bids':        0,
      'total_clients':     0,
      'auctions_by_region': <String, int>{},
      'revenue_by_region':  <String, double>{},
    };
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// AI Metrics History — last 14 days from ai_shadow_metrics (Phase 9L)
// ─────────────────────────────────────────────────────────────────────────────

/// Fetches the last 14 rows from ai_shadow_metrics ordered by date descending.
/// Each row contains: metric_date, mape, coverage_rate, predictions_generated,
/// prediction_errors. Used by _MetricsHistoryCard in AiDashboardScreen.
final aiMetricsHistoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.aiShadowMetricsTable)
        .select(
          'metric_date, mape, coverage_rate, predictions_generated, prediction_errors',
        )
        .order('metric_date', ascending: false)
        .limit(14);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});
