import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/supabase_constants.dart';
import '../../core/errors/exceptions.dart';
import '../models/models.dart';

class AuctionRepository {
  AuctionRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  // ── REAL-TIME STREAM: active auctions by region ───────────────────────────
  // Supabase Realtime replaces Firestore's .snapshots()
  Stream<List<AuctionModel>> getAuctionsByRegion(
    String region, {
    String? category,
  }) {
    // Start with current data, then stream changes
    return _client
        .from(SupabaseConstants.auctionsTable)
        .stream(primaryKey: ['id'])
        .eq('region', region)
        .map((rows) {
          final now = DateTime.now();
          var auctions = rows
              .map((r) => AuctionModel.fromMap(r))
              .where((a) =>
                  a.auctionStatus == 'active' && a.endDate.isAfter(now))
              .toList();
          if (category != null) {
            auctions = auctions.where((a) => a.category == category).toList();
          }
          auctions.sort((a, b) => a.endDate.compareTo(b.endDate));
          return auctions;
        });
  }

  // ── REAL-TIME STREAM: single auction (for item detail + live bid updates) ──
  Stream<AuctionModel> watchAuction(String auctionId) {
    return _client
        .from(SupabaseConstants.auctionsTable)
        .stream(primaryKey: ['id'])
        .eq('id', auctionId)
        .map((rows) {
          if (rows.isEmpty) throw const DatabaseException('Auction not found');
          return AuctionModel.fromMap(rows.first);
        });
  }

  // ── ONE-SHOT: get auction by ID ───────────────────────────────────────────
  Future<AuctionModel> getAuctionById(String auctionId) async {
    try {
      final data = await _client
          .from(SupabaseConstants.auctionsTable)
          .select()
          .eq('id', auctionId)
          .single();
      return AuctionModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── POST AUCTION with photo upload ───────────────────────────────────────
  Future<AuctionModel> postAuction(
    AuctionModel auction,
    List<File> photos,
  ) async {
    try {
      if (photos.length > 5) {
        throw const ValidationException('Maximum 5 photos allowed');
      }

      final adminUid = auction.postedByAdminUid;
      if (adminUid.isEmpty) {
        throw const ValidationException('Admin UID is required to post an auction');
      }

      // A pre-generated ID is required so the storage folder and the DB row
      // use the same UUID. PostAuctionScreen passes auctionId: '' because
      // the ID does not exist yet; without this fix photos land at //uuid.jpg.
      final auctionId = auction.auctionId.isNotEmpty
          ? auction.auctionId
          : const Uuid().v4();

      // 1. Upload photos to Supabase Storage.
      // Path: $adminUid/$auctionId/$uuid.jpg — adminUid prefix satisfies the
      // standard RLS policy: auth.uid() = split_part(name, '/', 1).
      final photoUrls = await _uploadPhotos(photos, adminUid, auctionId);

      // 2. Insert auction row with the explicit ID that matches the photo folder
      final now = DateTime.now().toIso8601String();
      final insertData = {
        'id': auctionId,
        ...auction.toMap(),
        'photo_urls': photoUrls,
        'current_highest_bid': auction.startingPrice,
        'total_bids': 0,
        'auction_status': auction.auctionStatus,
        'created_at': now,
        'updated_at': now,
      };

      final result = await _client
          .from(SupabaseConstants.auctionsTable)
          .insert(insertData)
          .select()
          .single();

      // 3. Edge Function on-new-auction fires via a Supabase Database Webhook
      // (configured in Supabase Dashboard → Database → Webhooks)
      // It sends push notifications to all clients in the region.

      return AuctionModel.fromMap(result);
    } on ValidationException {
      rethrow;
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    } catch (e) {
      throw DatabaseException('Failed to post auction: $e');
    }
  }

  // ── UPDATE AUCTION ────────────────────────────────────────────────────────
  Future<void> updateAuction(AuctionModel auction) async {
    try {
      await _client
          .from(SupabaseConstants.auctionsTable)
          .update({
            ...auction.toMap(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', auction.auctionId);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── UPDATE STATUS ONLY ────────────────────────────────────────────────────
  Future<void> updateAuctionStatus(String auctionId, String status) async {
    try {
      await _client
          .from(SupabaseConstants.auctionsTable)
          .update({
            'auction_status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', auctionId);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── DELETE AUCTION ────────────────────────────────────────────────────────
  Future<void> deleteAuction(String auctionId) async {
    try {
      // Fetch the auction first to get the admin UID needed for the storage path.
      AuctionModel? auction;
      try {
        auction = await getAuctionById(auctionId);
      } catch (_) {
        // If fetch fails, skip photo cleanup (best-effort).
      }
      if (auction != null) {
        await _deletePhotos(auction.postedByAdminUid, auctionId);
      }
      await _client
          .from(SupabaseConstants.auctionsTable)
          .delete()
          .eq('id', auctionId);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── ADMIN'S OWN AUCTIONS ──────────────────────────────────────────────────
  Future<List<AuctionModel>> getAdminAuctions(String adminUid) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.auctionsTable)
          .select()
          .eq('posted_by_admin_uid', adminUid)
          .order('created_at', ascending: false);
      return rows.map((r) => AuctionModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── PRIVATE: upload photos to Supabase Storage ────────────────────────────
  // Path: $adminUid/$auctionId/$uuid.jpg
  // The adminUid prefix lets the standard RLS policy verify ownership via
  // auth.uid() = split_part(name, '/', 1).
  Future<List<String>> _uploadPhotos(
    List<File> photos,
    String adminUid,
    String auctionId,
  ) async {
    final urls = <String>[];
    final uuid = const Uuid();

    for (final file in photos) {
      final fileName = '$adminUid/$auctionId/${uuid.v4()}.jpg';
      final bytes = await file.readAsBytes();

      await _client.storage
          .from(SupabaseConstants.auctionPhotosBucket)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final url = _client.storage
          .from(SupabaseConstants.auctionPhotosBucket)
          .getPublicUrl(fileName);

      urls.add(url);
    }

    return urls;
  }

  Future<void> _deletePhotos(String adminUid, String auctionId) async {
    try {
      final prefix = '$adminUid/$auctionId';
      final files = await _client.storage
          .from(SupabaseConstants.auctionPhotosBucket)
          .list(path: prefix);
      if (files.isEmpty) return;
      final paths = files.map((f) => '$prefix/${f.name}').toList();
      await _client.storage
          .from(SupabaseConstants.auctionPhotosBucket)
          .remove(paths);
    } catch (_) {
      // Best-effort — storage cleanup failure should not block auction deletion
    }
  }

  // Alias so providers.dart can call getAuctionsByAdmin
  Future<List<AuctionModel>> getAuctionsByAdmin(String adminUid) =>
      getAdminAuctions(adminUid);
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────
final auctionRepositoryProvider = Provider<AuctionRepository>(
  (ref) => AuctionRepository(),
);

final auctionsByRegionProvider =
    StreamProvider.family<List<AuctionModel>, String>((ref, region) {
      return ref.watch(auctionRepositoryProvider).getAuctionsByRegion(region);
    });

final auctionsByCategoryProvider =
    StreamProvider.family<
      List<AuctionModel>,
      ({String region, String category})
    >((ref, params) {
      return ref
          .watch(auctionRepositoryProvider)
          .getAuctionsByRegion(params.region, category: params.category);
    });

final auctionWatcherProvider = StreamProvider.family<AuctionModel, String>((
  ref,
  auctionId,
) {
  return ref.watch(auctionRepositoryProvider).watchAuction(auctionId);
});

final adminAuctionsProvider = FutureProvider.family<List<AuctionModel>, String>(
  (ref, adminUid) {
    return ref.watch(auctionRepositoryProvider).getAdminAuctions(adminUid);
  },
);
