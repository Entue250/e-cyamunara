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
