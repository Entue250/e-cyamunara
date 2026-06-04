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
