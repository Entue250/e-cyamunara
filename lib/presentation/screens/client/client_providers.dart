// lib/presentation/screens/client/client_providers.dart
//
// Client-module-specific Riverpod providers.
// Screens import '../../providers/providers.dart' for shared providers;
// this file holds providers that are only relevant to the client module.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';
import '../../../data/models/models.dart';
import '../../../data/repositories/repositories.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Real bid/won counts from bids table — bypasses denormalized columns
// ─────────────────────────────────────────────────────────────────────────────

final clientStatsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, uid) async {
  if (uid.isEmpty) return {'bids': 0, 'won': 0};
  final client = Supabase.instance.client;
  try {
    final results = await Future.wait([
      client
          .from(SupabaseConstants.bidsTable)
          .select('id')
          .eq('bidder_uid', uid),
      client
          .from(SupabaseConstants.bidsTable)
          .select('id')
          .eq('bidder_uid', uid)
          .eq('bid_status', 'won'),
    ]);
    return {
      'bids': (results[0] as List).length,
      'won':  (results[1] as List).length,
    };
  } catch (_) {
    return {'bids': 0, 'won': 0};
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// My Bids filter tab
// 0 = All  1 = Active  2 = Won  3 = Lost
// ─────────────────────────────────────────────────────────────────────────────

final myBidsFilterProvider = StateProvider<int>((ref) => 0);

// ─────────────────────────────────────────────────────────────────────────────
// Existing bid for the current client on a specific auction.
// Returns null when the client has not yet placed a bid on this auction.
// autoDispose so the value is re-fetched each time the detail screen opens
// and after a successful bid placement (ref.invalidate).
// ─────────────────────────────────────────────────────────────────────────────

final clientBidForAuctionProvider = FutureProvider.autoDispose
    .family<BidModel?, ({String auctionId, String clientUid})>(
  (ref, params) async {
    if (params.auctionId.isEmpty || params.clientUid.isEmpty) return null;
    final repo = ref.watch(bidRepositoryProvider);
    return repo.getClientBidForAuction(params.auctionId, params.clientUid);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Bids enriched with auction data — one round-trip using inFilter.
//
// Returns a list of records sorted newest-first. Each record is a
// (BidModel, AuctionModel?) pair. AuctionModel is null only if the
// auction row can't be found (data-integrity edge case).
// ─────────────────────────────────────────────────────────────────────────────

final clientBidsWithAuctionsProvider =
    FutureProvider.family<List<(BidModel, AuctionModel?)>, String>(
  (ref, uid) async {
    if (uid.isEmpty) return [];
    final client = Supabase.instance.client;

    // 1. Fetch all bids for this client, newest first.
    final bidRows = await client
        .from(SupabaseConstants.bidsTable)
        .select()
        .eq('bidder_uid', uid)
        .order('created_at', ascending: false);

    if (bidRows.isEmpty) return [];

    final bids = bidRows
        .map((r) => BidModel.fromMap(r))
        .toList();

    // 2. Collect unique auction IDs and batch-fetch auction rows.
    final auctionIds = bids.map((b) => b.auctionId).toSet().toList();

    final auctionRows = await client
        .from(SupabaseConstants.auctionsTable)
        .select()
        .inFilter('id', auctionIds);

    // 3. Build lookup map auctionId → AuctionModel.
    final auctionMap = <String, AuctionModel>{};
    for (final row in auctionRows) {
      try {
        final a = AuctionModel.fromMap(row);
        auctionMap[a.auctionId] = a;
      } catch (_) {}
    }

    // 4. Join — correct bid status from live auction state so winners
    //    aren't shown as "Lost" and active leaders show as "Winning".
    return bids.map((bid) {
      final auction = auctionMap[bid.auctionId];
      if (auction == null) return (bid, null as AuctionModel?);

      String correctedStatus = bid.bidStatus;
      if (auction.auctionStatus == 'closed') {
        correctedStatus =
            (auction.winnerUid == bid.bidderUid) ? 'won' : 'outbid';
      } else if (auction.auctionStatus == 'active') {
        if (auction.currentWinnerUid == bid.bidderUid) {
          correctedStatus = 'winning';
        }
      }

      if (correctedStatus == bid.bidStatus) return (bid, auction);

      final correctedBid = BidModel(
        bidId: bid.bidId,
        auctionId: bid.auctionId,
        bidderUid: bid.bidderUid,
        bidderName: bid.bidderName,
        bidderPhone: bid.bidderPhone,
        bidderDistrict: bid.bidderDistrict,
        bidAmount: bid.bidAmount,
        bidStatus: correctedStatus,
        createdAt: bid.createdAt,
      );
      return (correctedBid, auction);
    }).toList();
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// AI bid insights — win probability + value signal per auction (Phase 9M)
// ─────────────────────────────────────────────────────────────────────────────

/// Returns AI insights for one auction or null if:
///   • `ai.predictions_visible_to_clients` flag is not 'true'
///   • No predictions exist for this auction yet
///
/// Keyed on auctionId so Riverpod caches one result per tile.
/// Only called for active auctions — won/lost tiles skip the watch entirely.
final aiBidInsightsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, auctionId) async {
  if (auctionId.isEmpty) return null;
  final client = Supabase.instance.client;

  final flagRow = await client
      .from(SupabaseConstants.aiFeatureFlagsTable)
      .select('value')
      .eq('key', 'ai.predictions_visible_to_clients')
      .maybeSingle();
  if ((flagRow)?['value'] != 'true') return null;

  final rows = await client
      .from(SupabaseConstants.aiPredictionsTable)
      .select('prediction_type, predicted_value')
      .eq('auction_id', auctionId)
      .eq('model_stage', 'shadow')
      .inFilter('prediction_type',
          ['auction_price_estimate', 'bid_probability']);

  if (rows.isEmpty) return null;

  double? priceEstimate;
  double? winProbability;
  for (final row in rows) {
    final type = row['prediction_type'] as String?;
    final val  = (row['predicted_value'] as num?)?.toDouble();
    if (type == 'auction_price_estimate') priceEstimate = val;
    if (type == 'bid_probability')        winProbability = val;
  }

  if (priceEstimate == null && winProbability == null) return null;
  return {'price_estimate': priceEstimate, 'win_probability': winProbability};
});

// ─────────────────────────────────────────────────────────────────────────────
// AI auction value badge — UNDER / FAIR / OVER for home-screen cards (Phase 9N)
// ─────────────────────────────────────────────────────────────────────────────

/// Compares the AI auction_price_estimate against the auction's starting_price
/// (the bid floor set by the region admin — no client can bid below this).
///
/// Signal:
///   UNDER → estimate > startingPrice × 1.15  (market value well above minimum)
///   OVER  → estimate < startingPrice × 0.95  (AI thinks floor is too high)
///   FAIR  → everything in between
///
/// Returns null when predictions_visible_to_clients is false, no prediction
/// exists, or startingPrice is zero.
final aiAuctionBadgeProvider =
    FutureProvider.family<String?, ({String auctionId, double startingPrice})>(
        (ref, args) async {
  if (args.auctionId.isEmpty || args.startingPrice <= 0) return null;
  final client = Supabase.instance.client;

  final flagRow = await client
      .from(SupabaseConstants.aiFeatureFlagsTable)
      .select('value')
      .eq('key', 'ai.predictions_visible_to_clients')
      .maybeSingle();
  if ((flagRow)?['value'] != 'true') return null;

  final row = await client
      .from(SupabaseConstants.aiPredictionsTable)
      .select('predicted_value')
      .eq('auction_id', args.auctionId)
      .eq('prediction_type', 'auction_price_estimate')
      .eq('model_stage', 'shadow')
      .maybeSingle();

  final estimate = (row?['predicted_value'] as num?)?.toDouble();
  if (estimate == null) return null;

  final floor = args.startingPrice;
  if (estimate > floor * 1.15) return 'UNDER';
  if (estimate < floor * 0.95) return 'OVER';
  return 'FAIR';
});

// ─────────────────────────────────────────────────────────────────────────────
// Auction search with filters (Phase 9O)
// ─────────────────────────────────────────────────────────────────────────────

typedef AuctionSearchQuery = ({
  String text,
  String? region,
  String? category,
  bool activeOnly,
  double? minPrice,
  double? maxPrice,
});

final searchAuctionsProvider =
    FutureProvider.family<List<AuctionModel>, AuctionSearchQuery>(
        (ref, q) async {
  final client = Supabase.instance.client;

  // Filters must be applied before order/limit (PostgREST builder type chain)
  var query = client
      .from(SupabaseConstants.auctionsTable)
      .select();

  if (q.text.isNotEmpty) {
    query = query.ilike('item_name', '%${q.text}%');
  }
  if (q.region != null)   query = query.eq('region', q.region!);
  if (q.category != null) query = query.eq('main_category', q.category!);
  if (q.activeOnly)       query = query.eq('auction_status', 'active');
  if (q.minPrice != null) query = query.gte('starting_price', q.minPrice!);
  if (q.maxPrice != null) query = query.lte('starting_price', q.maxPrice!);

  final rows = await query.order('created_at', ascending: false).limit(60);
  return (rows as List)
      .map((r) => AuctionModel.fromMap(r as Map<String, dynamic>))
      .toList();
});
