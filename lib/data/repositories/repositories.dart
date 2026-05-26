import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../../core/errors/exceptions.dart';
import '../models/models.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';

// ═════════════════════════════════════════════════════════════════════════════
// BidRepository
// placeBid calls the Supabase Edge Function (server-side atomic transaction).
// Live bid updates use Supabase Realtime on the auctions table.
// ═════════════════════════════════════════════════════════════════════════════

class BidRepository {
  BidRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  // ── PLACE BID — calls Edge Function ───────────────────────────────────────
  Future<Map<String, dynamic>> placeBid({
    required String auctionId,
    required double bidAmount,
    required String bidderUid,
  }) async {
    try {
      // Get bidder info from users table
      final userSnap = await _client
          .from('users')
          .select('full_names, phone_number, district')
          .eq('id', bidderUid)
          .single();

      final response = await _client.functions.invoke(
        SupabaseConstants.fnPlaceBid,
        body: {
          'auction_id': auctionId,
          'bid_amount': bidAmount,
          'bidder_uid': bidderUid,
          'bidder_name': userSnap['full_names'],
          'bidder_phone': userSnap['phone_number'],
          'bidder_district': userSnap['district'],
        },
      );

      if (response.status != 200) {
        final error = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(error ?? 'Failed to place bid');
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) {
        throw AppFunctionException(
          data['error'] as String? ?? 'Failed to place bid',
        );
      }
      return data;
    } on AppFunctionException {
      rethrow;
    } catch (e) {
      throw AppFunctionException('Bid submission failed: $e');
    }
  }

  // ── REAL-TIME BIDS STREAM for an auction ─────────────────────────────────
  Stream<List<BidModel>> getBidsForAuction(String auctionId) {
    return _client
        .from(SupabaseConstants.bidsTable)
        .stream(primaryKey: ['id'])
        .eq('auction_id', auctionId)
        .map((rows) {
          final bids = rows.map((r) => BidModel.fromMap(r)).toList();
          bids.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return bids;
        });
  }

  // ── WATCH BIDS FOR AUCTION (sorted by amount descending) ──────────────────
  Stream<List<BidModel>> watchBidsForAuction(String auctionId) {
    return _client
        .from('bids')
        .stream(primaryKey: ['id'])
        .eq('auction_id', auctionId)
        .map((rows) {
          final bids = rows.map((r) => BidModel.fromMap(r)).toList();
          bids.sort((a, b) => b.bidAmount.compareTo(a.bidAmount));
          return bids;
        });
  }

  // ── REAL-TIME HIGHEST BID (from auctions table Realtime) ─────────────────
  Stream<double> watchHighestBid(String auctionId) {
    return _client
        .from(SupabaseConstants.auctionsTable)
        .stream(primaryKey: ['id'])
        .eq('id', auctionId)
        .map((rows) {
          if (rows.isEmpty) return 0.0;
          return (rows.first['current_highest_bid'] as num?)?.toDouble() ?? 0.0;
        });
  }

  // ── GET CURRENT HIGHEST BID (one-time read) ───────────────────────────────
  Future<double> getHighestBid(String auctionId) async {
    try {
      final snap = await _client
          .from('auctions')
          .select('current_highest_bid')
          .eq('id', auctionId)
          .single();
      return (snap['current_highest_bid'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── GET SINGLE BID BY CLIENT FOR AUCTION ─────────────────────────────────
  // Returns null when the client has not yet placed a bid on this auction.
  Future<BidModel?> getClientBidForAuction(
    String auctionId,
    String clientUid,
  ) async {
    try {
      final row = await _client
          .from(SupabaseConstants.bidsTable)
          .select()
          .eq('auction_id', auctionId)
          .eq('bidder_uid', clientUid)
          .maybeSingle();
      if (row == null) return null;
      return BidModel.fromMap(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── ALL BIDS BY A CLIENT ──────────────────────────────────────────────────
  Future<List<BidModel>> getClientBids(String clientUid) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.bidsTable)
          .select()
          .eq('bidder_uid', clientUid)
          .order('created_at', ascending: false);
      return rows.map((r) => BidModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// UserRepository
// ═════════════════════════════════════════════════════════════════════════════

class UserRepository {
  UserRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<UserModel> getUserById(String uid) async {
    try {
      final data = await _client
          .from(SupabaseConstants.usersTable)
          .select()
          .eq('id', uid)
          .single();
      return UserModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── GET CURRENT LOGGED-IN USER ────────────────────────────────────────────
  Future<UserModel?> getCurrentUser() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final snap = await _client
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (snap == null) return null;
      return UserModel.fromMap(snap);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUserProfile(UserModel user) async {
    try {
      await _client
          .from(SupabaseConstants.usersTable)
          .update({
            'full_names': user.fullNames,
            'phone_number': user.phoneNumber,
            'district': user.district,
            'province': user.province,
            'region': user.region,
            'profile_photo_url': user.profilePhotoUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.uid);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<UserModel>> getUsersByRegion(String region) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.usersTable)
          .select()
          .eq('region', region)
          .eq('role', 'client')
          .order('created_at', ascending: false);
      return rows.map((r) => UserModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> suspendUser(String uid, String reason) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnSuspendUser,
        body: {'uid': uid, 'reason': reason},
      );
      if (response.status != 200) {
        throw AppFunctionException('Failed to suspend user');
      }
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Suspend failed: $e');
    }
  }

  Future<void> activateUser(String uid) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnActivateUser,
        body: {'uid': uid},
      );
      if (response.status != 200) {
        throw AppFunctionException('Failed to activate user');
      }
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Activate failed: $e');
    }
  }

  // ── NOTIFICATIONS ─────────────────────────────────────────────────────────
  Stream<List<NotificationModel>> getNotifications(String uid) {
    return _client
        .from(SupabaseConstants.notificationsTable)
        .stream(primaryKey: ['id'])
        .eq('user_uid', uid)
        .map((rows) {
          final notifs = rows.map((r) => NotificationModel.fromMap(r)).toList();
          notifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifs.take(50).toList();
        });
  }

  // ── WATCH NOTIFICATIONS (real-time stream) ────────────────────────────────
  Stream<List<NotificationModel>> watchNotifications(String uid) {
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_uid', uid)
        .map((rows) {
          final notifs = rows.map((r) => NotificationModel.fromMap(r)).toList();
          notifs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return notifs;
        });
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client
          .from(SupabaseConstants.notificationsTable)
          .update({'is_read': true})
          .eq('id', notificationId);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> markAllNotificationsRead(String uid) async {
    try {
      await _client
          .from(SupabaseConstants.notificationsTable)
          .update({'is_read': true})
          .eq('user_uid', uid)
          .eq('is_read', false);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Stream<int> getUnreadNotificationCount(String uid) {
    return _client
        .from(SupabaseConstants.notificationsTable)
        .stream(primaryKey: ['id'])
        .eq('user_uid', uid)
        .map((rows) => rows.where((r) => r['is_read'] == false).length);
  }

  // ── GET UNREAD COUNT (one-time read) ──────────────────────────────────────
  Future<int> getUnreadCount(String uid) async {
    try {
      final rows = await _client
          .from('notifications')
          .select('id')
          .eq('user_uid', uid)
          .eq('is_read', false);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // ── PROFILE PHOTO UPLOAD ──────────────────────────────────────────────────
  Future<String> uploadProfilePhoto(String uid, List<int> bytes) async {
    try {
      final fileName = '$uid/avatar.jpg';
      final uint8Bytes = Uint8List.fromList(bytes);
      await _client.storage
          .from(SupabaseConstants.profilePhotosBucket)
          .uploadBinary(
            fileName,
            uint8Bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      return _client.storage
          .from(SupabaseConstants.profilePhotosBucket)
          .getPublicUrl(fileName);
    } catch (e) {
      throw AppStorageException('Photo upload failed: $e');
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AdminRepository
// ═════════════════════════════════════════════════════════════════════════════

class AdminRepository {
  AdminRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<void> createRegionAdmin(RegionAdminModel admin) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnCreateAdmin,
        body: {
          'full_names': admin.fullNames,
          'national_id': admin.nationalId,
          'phone_number': admin.phoneNumber,
          'region': admin.region,
          'created_by': admin.createdBy,
        },
      );
      if (response.status != 200) {
        final err = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(err ?? 'Failed to create admin');
      }
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Admin creation failed: $e');
    }
  }

  // ── CREATE REGION ADMIN WITH PASSWORD ─────────────────────────────────────
  Future<void> createRegionAdminWithPassword(
    RegionAdminModel admin,
    String password,
  ) async {
    try {
      final creatorUid = _client.auth.currentUser?.id ?? '';
      final response = await _client.functions.invoke(
        SupabaseConstants.fnCreateAdmin,
        body: {
          'full_names': admin.fullNames,
          'phone_number': admin.phoneNumber,
          'region': admin.region,
          'password': password,
          'permissions': admin.permissions.toMap(),
          'created_by': creatorUid,
        },
      );
      if (response.status != 200) {
        throw AppFunctionException(
          'Failed to create admin: ${(response.data as Map?)?['error']}',
        );
      }
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Failed to create admin: $e');
    }
  }

  Future<RegionAdminModel> getAdminById(String uid) async {
    try {
      final data = await _client
          .from(SupabaseConstants.regionAdminsTable)
          .select()
          .eq('id', uid)
          .single();
      return RegionAdminModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  // ── GET CURRENT LOGGED-IN ADMIN ───────────────────────────────────────────
  Future<RegionAdminModel?> getCurrentAdmin() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return null;
      final snap = await _client
          .from('region_admins')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (snap == null) return null;
      return RegionAdminModel.fromMap(snap);
    } catch (_) {
      return null;
    }
  }

  Future<List<RegionAdminModel>> getAllAdmins() async {
    try {
      final rows = await _client
          .from(SupabaseConstants.regionAdminsTable)
          .select()
          .order('region');
      return rows.map((r) => RegionAdminModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> updateAdminPermissions(
    String uid,
    Map<String, bool> permissions,
  ) async {
    try {
      await _client
          .from(SupabaseConstants.regionAdminsTable)
          .update({
            'permissions': permissions,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> suspendAdmin(String uid) async {
    try {
      await _client
          .from(SupabaseConstants.regionAdminsTable)
          .update({
            'account_status': 'suspended',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> activateAdmin(String uid) async {
    try {
      await _client
          .from(SupabaseConstants.regionAdminsTable)
          .update({
            'account_status': 'active',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<Map<String, dynamic>> closeAuctionManually(String auctionId) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnCloseAuctionManually,
        body: {'auction_id': auctionId},
      );
      if (response.status != 200) {
        throw AppFunctionException('Failed to close auction');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Close auction failed: $e');
    }
  }

  // ── GET REGION STATS ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getRegionStats({
    required String region,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final total = await _client
          .from('auctions')
          .select('id')
          .eq('region', region);
      final active = await _client
          .from('auctions')
          .select('id')
          .eq('region', region)
          .eq('auction_status', 'active');
      final closed = await _client
          .from('auctions')
          .select('winning_amount')
          .eq('region', region)
          .eq('auction_status', 'closed')
          .gte('closed_at', start.toIso8601String())
          .lte('closed_at', end.toIso8601String());

      final revenue = (closed as List).fold<double>(
        0,
        (sum, r) => sum + ((r['winning_amount'] as num?)?.toDouble() ?? 0),
      );

      return {
        'total_auctions': (total as List).length,
        'active_auctions': (active as List).length,
        'closed_in_period': (closed as List).length,
        'total_revenue': revenue,
      };
    } catch (_) {
      return {
        'total_auctions': 0,
        'active_auctions': 0,
        'closed_in_period': 0,
        'total_revenue': 0,
      };
    }
  }

  // ── AUCTIONS GROUPED BY CATEGORY (for reports bar chart) ──────────────────
  Future<List<Map<String, dynamic>>> getAuctionCategoryStats({
    required String region,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.auctionsTable)
          .select('category')
          .eq('region', region)
          .gte('created_at', start.toIso8601String())
          .lte('created_at', end.toIso8601String());

      final counts = <String, int>{};
      for (final row in (rows as List)) {
        final cat = row['category'] as String? ?? 'other';
        counts[cat] = (counts[cat] ?? 0) + 1;
      }

      final result = counts.entries
          .map((e) => {'category': e.key, 'count': e.value})
          .toList()
        ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      return result;
    } catch (_) {
      return [];
    }
  }

  // ── RECENT CLOSED AUCTIONS (for reports list) ──────────────────────────────
  Future<List<AuctionModel>> getRecentClosedAuctions({
    required String region,
    required DateTime start,
    required DateTime end,
    int limit = 5,
  }) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.auctionsTable)
          .select()
          .eq('region', region)
          .eq('auction_status', 'closed')
          .gte('closed_at', start.toIso8601String())
          .lte('closed_at', end.toIso8601String())
          .order('closed_at', ascending: false)
          .limit(limit);
      return (rows as List).map((r) => AuctionModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── GET NATIONAL STATS ────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getNationalStats({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final total = await _client.from('auctions').select('id');
      final closed = await _client
          .from('auctions')
          .select('winning_amount')
          .eq('auction_status', 'closed')
          .gte('closed_at', start.toIso8601String())
          .lte('closed_at', end.toIso8601String());

      final revenue = (closed as List).fold<double>(
        0,
        (sum, r) => sum + ((r['winning_amount'] as num?)?.toDouble() ?? 0),
      );

      return {
        'total_auctions': (total as List).length,
        'total_revenue': revenue,
      };
    } catch (_) {
      return {'total_auctions': 0, 'total_revenue': 0};
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FeedbackRepository
// ═════════════════════════════════════════════════════════════════════════════

class FeedbackRepository {
  FeedbackRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<void> submitFeedback(FeedbackModel feedback) async {
    try {
      await _client
          .from(SupabaseConstants.feedbackTable)
          .insert(feedback.toMap());
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<FeedbackModel>> getFeedbackByRegion(String region) async {
    try {
      final rows = await _client
          .from(SupabaseConstants.feedbackTable)
          .select('*, users!client_uid(profile_photo_url)')
          .eq('region', region)
          .order('created_at', ascending: false);
      return rows.map((r) => FeedbackModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<FeedbackModel>> getAllFeedback() async {
    try {
      final rows = await _client
          .from(SupabaseConstants.feedbackTable)
          .select('*, users!client_uid(profile_photo_url)')
          .order('created_at', ascending: false);
      return rows.map((r) => FeedbackModel.fromMap(r)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> markFeedbackAsRead(String feedbackId) async {
    try {
      await _client
          .from(SupabaseConstants.feedbackTable)
          .update({'is_read': true})
          .eq('id', feedbackId);
    } catch (_) {
      // Silently ignore — is_read column may not exist in schema yet
      // Backend fix needed: ALTER TABLE feedback ADD COLUMN is_read BOOLEAN DEFAULT FALSE;
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// AppSettingsRepository
// ═════════════════════════════════════════════════════════════════════════════

class AppSettingsRepository {
  AppSettingsRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<AppSettingsModel> getSettings() async {
    try {
      final data = await _client
          .from(SupabaseConstants.appSettingsTable)
          .select()
          .eq('id', 'config')
          .single();
      return AppSettingsModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<void> updateSettings({
    required AppSettingsModel settings,
    required String updatedByUid,
  }) async {
    try {
      await _client
          .from(SupabaseConstants.appSettingsTable)
          .update({
            ...settings.toMap(),
            'updated_by': updatedByUid,
          })
          .eq('id', 'config');
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ReportRepository
// ═════════════════════════════════════════════════════════════════════════════

class ReportRepository {
  ReportRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>> getRegionStats({
    required String region,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnGenerateReport,
        body: {
          'region': region,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'format': 'json',
        },
      );
      if (response.status != 200) {
        throw const AppFunctionException('Failed to fetch stats');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('Stats fetch failed: $e');
    }
  }

  Future<Map<String, dynamic>> getNationalStats({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return getRegionStats(
      region: 'ALL',
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<String> generatePdfReport({
    required String region,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnGenerateReport,
        body: {
          'region': region,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'format': 'pdf',
        },
      );
      if (response.status != 200) {
        throw const AppFunctionException('PDF generation failed');
      }
      final url = (response.data as Map)['download_url'] as String?;
      if (url == null) throw const AppFunctionException('No download URL');
      return url;
    } catch (e) {
      if (e is AppFunctionException) rethrow;
      throw AppFunctionException('PDF generation failed: $e');
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Repository Providers
// ═════════════════════════════════════════════════════════════════════════════

final bidRepositoryProvider = Provider<BidRepository>((ref) => BidRepository());
final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(),
);
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(),
);
final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(),
);
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(),
);
final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(),
);

// ── Current user provider ─────────────────────────────────────────────────────
// Watches authStateProvider so stale data is never served after sign-out or
// forced session revocation (e.g. suspension detected at runtime).
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(userRepositoryProvider).getCurrentUser();
});

// ── Current admin provider ────────────────────────────────────────────────────
final currentAdminProvider = FutureProvider<RegionAdminModel?>((ref) async {
  ref.watch(authStateProvider);
  return ref.read(adminRepositoryProvider).getCurrentAdmin();
});

// ── All admins provider (super admin use) ─────────────────────────────────────
final allAdminsProvider = FutureProvider<List<RegionAdminModel>>((ref) {
  return ref.watch(adminRepositoryProvider).getAllAdmins();
});

// ── Bids for a specific auction (stream, sorted by amount desc) ───────────────
final bidsForAuctionProvider = StreamProvider.family<List<BidModel>, String>((
  ref,
  auctionId,
) {
  return ref.watch(bidRepositoryProvider).watchBidsForAuction(auctionId);
});

// ── All bids placed by a client ───────────────────────────────────────────────
final clientBidsProvider = FutureProvider.family<List<BidModel>, String>((
  ref,
  clientUid,
) {
  return ref.watch(bidRepositoryProvider).getClientBids(clientUid);
});

// ── Highest bid for an auction (real-time stream) ─────────────────────────────
final highestBidProvider = StreamProvider.family<double, String>((
  ref,
  auctionId,
) {
  return ref.watch(bidRepositoryProvider).watchHighestBid(auctionId);
});

// ── Notifications stream ──────────────────────────────────────────────────────
final notificationsProvider =
    StreamProvider.family<List<NotificationModel>, String>((ref, uid) {
      return ref.watch(userRepositoryProvider).watchNotifications(uid);
    });

// ── Unread notification count (stream) ───────────────────────────────────────
final unreadNotifCountProvider = StreamProvider.family<int, String>((ref, uid) {
  return ref.watch(userRepositoryProvider).getUnreadNotificationCount(uid);
});

// ── Users by region (admin client management) ─────────────────────────────────
final usersByRegionProvider = FutureProvider.family<List<UserModel>, String>((
  ref,
  region,
) {
  return ref.watch(userRepositoryProvider).getUsersByRegion(region);
});

// ── Region stats (admin reports) ──────────────────────────────────────────────
final regionStatsProvider =
    FutureProvider.family<
      Map<String, dynamic>,
      ({String region, DateTime start, DateTime end})
    >((ref, params) {
      return ref
          .watch(adminRepositoryProvider)
          .getRegionStats(
            region: params.region,
            start: params.start,
            end: params.end,
          );
    });

// ── National stats (super admin) ──────────────────────────────────────────────
final nationalStatsProvider =
    FutureProvider.family<
      Map<String, dynamic>,
      ({DateTime start, DateTime end})
    >((ref, params) {
      return ref
          .watch(adminRepositoryProvider)
          .getNationalStats(start: params.start, end: params.end);
    });

// ── Category breakdown for region reports bar chart ───────────────────────────
final regionCategoryStatsProvider =
    FutureProvider.family<
      List<Map<String, dynamic>>,
      ({String region, DateTime start, DateTime end})
    >((ref, params) {
      return ref
          .watch(adminRepositoryProvider)
          .getAuctionCategoryStats(
            region: params.region,
            start: params.start,
            end: params.end,
          );
    });

// ── Recent closed auctions for region reports list ────────────────────────────
final recentClosedAuctionsProvider =
    FutureProvider.family<
      List<AuctionModel>,
      ({String region, DateTime start, DateTime end})
    >((ref, params) {
      return ref
          .watch(adminRepositoryProvider)
          .getRecentClosedAuctions(
            region: params.region,
            start: params.start,
            end: params.end,
          );
    });
