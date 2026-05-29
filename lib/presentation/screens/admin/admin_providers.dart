// lib/presentation/screens/admin/admin_providers.dart
//
// Region Admin — dedicated Riverpod providers.
//
// Screens continue to import '../../providers/providers.dart' for shared
// providers (currentAdminProvider, adminAuctionsProvider, etc.).
// This file holds admin-module-specific providers introduced during the
// refactor or prepared for future phases.
//
// Phase 1: Skeleton — imports and structure only.
// Phase 2: adminAuctionsProvider will be upgraded to StreamProvider here.
// Phase 3: Additional async providers for stats, categories, and exports.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';
import '../../../data/models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Date-range enum for region reports — mirrors SuperAdminStatsRange pattern
// ─────────────────────────────────────────────────────────────────────────────

enum AdminReportRange {
  last30Days,
  last3Months,
  thisYear,
  allTime,
}

extension AdminReportRangeExt on AdminReportRange {
  String get label => switch (this) {
        AdminReportRange.last30Days => 'Last 30 Days',
        AdminReportRange.last3Months => 'Last 3 Months',
        AdminReportRange.thisYear => 'This Year',
        AdminReportRange.allTime => 'All Time',
      };

  DateTime get startDate {
    final now = DateTime.now();
    return switch (this) {
      AdminReportRange.last30Days =>
        now.subtract(const Duration(days: 30)),
      AdminReportRange.last3Months =>
        DateTime(now.year, now.month - 3, now.day),
      AdminReportRange.thisYear => DateTime(now.year, 1, 1),
      AdminReportRange.allTime => DateTime(2000, 1, 1),
    };
  }

  DateTime get endDate => DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin dashboard stats — parallel queries for the 4 stat cards
//
// TODO(Phase 2): Replace adminAuctionsProvider (FutureProvider) from
// providers.dart with a StreamProvider version here so the dashboard and
// ManageAuctionsScreen update in real-time when bids arrive or auctions close.
// ─────────────────────────────────────────────────────────────────────────────

/// Aggregates quick stats for the admin dashboard (4 stat cards).
/// Each query runs independently so a single RLS failure does not zero
/// the entire dashboard — partial data is always better than all zeros.
final adminDashboardStatsProvider =
    FutureProvider.family<
      Map<String, dynamic>,
      ({String adminUid, String region})
    >((ref, params) async {
  final client = Supabase.instance.client;
  final today = DateTime.now();
  final startOfToday =
      DateTime(today.year, today.month, today.day).toIso8601String();

  // ── Auctions posted by this admin (always accessible via RLS) ────────────
  List<Map<String, dynamic>> auctions = [];
  try {
    final rows = await client
        .from(SupabaseConstants.auctionsTable)
        .select('id, auction_status')
        .eq('posted_by_admin_uid', params.adminUid);
    auctions = List<Map<String, dynamic>>.from(rows as List);
  } catch (_) {}

  final active =
      auctions.where((a) => a['auction_status'] == 'active').length;
  final closed =
      auctions.where((a) => a['auction_status'] == 'closed').length;

  // ── Client count for this admin's region ─────────────────────────────────
  int clientCount = 0;
  if (params.region.isNotEmpty) {
    try {
      final clients = await client
          .from(SupabaseConstants.usersTable)
          .select('id')
          .eq('region', params.region)
          .eq('role', SupabaseConstants.roleClient);
      clientCount = (clients as List).length;
    } catch (_) {}
  }

  // ── Bids placed today across this admin's auctions ───────────────────────
  int bidsToday = 0;
  final auctionIds = auctions.map((a) => a['id'] as String).toList();
  if (auctionIds.isNotEmpty) {
    try {
      final bidsResult = await client
          .from(SupabaseConstants.bidsTable)
          .select('id')
          .inFilter('auction_id', auctionIds)
          .gte('created_at', startOfToday);
      bidsToday = (bidsResult as List).length;
    } catch (_) {}
  }

  return {
    'active_auctions': active,
    'closed_auctions': closed,
    'bids_today': bidsToday,
    'registered_clients': clientCount,
  };
});

// ─────────────────────────────────────────────────────────────────────────────
// Client count for admin's region — feeds "REGISTERED CLIENTS" stat card
//
// TODO(Phase 2): Connect this to the dashboard stat card.
// ─────────────────────────────────────────────────────────────────────────────

/// Total clients in a region — used by AdminDashboardScreen stat card.
final adminRegionClientCountProvider =
    FutureProvider.family<int, String>((ref, region) async {
  if (region.isEmpty) return 0;
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.usersTable)
        .select('id')
        .eq('region', region)
        .eq('role', SupabaseConstants.roleClient);
    return (rows as List).length;
  } catch (_) {
    return 0;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Region category stats — for the RegionReportsScreen category bars
//
// TODO(Phase 3): Connect to RegionReportsScreen to replace hardcoded bars.
// ─────────────────────────────────────────────────────────────────────────────

/// Per-category auction counts for a region within a date range.
/// Returns a map of category → count, e.g. {'car': 12, 'motorcycle': 4}.
final adminCategoryStatsProvider =
    FutureProvider.family<
      Map<String, int>,
      ({String region, DateTime start, DateTime end})
    >((ref, params) async {
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.auctionsTable)
        .select('category')
        .eq('region', params.region)
        .gte('created_at', params.start.toIso8601String())
        .lte('created_at', params.end.toIso8601String());

    final Map<String, int> counts = {};
    for (final row in (rows as List)) {
      final cat = (row as Map)['category'] as String? ?? 'other';
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    return counts;
  } catch (_) {
    return {};
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Recent closed auctions for a region — RegionReportsScreen list
//
// TODO(Phase 3): Replace placeholder text in RegionReportsScreen.
// ─────────────────────────────────────────────────────────────────────────────

/// Last 5 closed auctions in the given region, newest first.
final adminRecentClosedAuctionsProvider =
    FutureProvider.family<List<AuctionModel>, String>((ref, region) async {
  if (region.isEmpty) return [];
  try {
    final rows = await Supabase.instance.client
        .from(SupabaseConstants.auctionsTable)
        .select()
        .eq('region', region)
        .eq('auction_status', SupabaseConstants.statusClosed)
        .order('closed_at', ascending: false)
        .limit(5);
    return (rows as List)
        .map((r) => AuctionModel.fromMap(r as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return [];
  }
});
