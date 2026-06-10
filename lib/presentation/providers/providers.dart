// lib/presentation/providers/providers.dart
//
// ─── ALL RIVERPOD PROVIDERS ────────────────────────────────────────────────────
// This file exports every provider used across all 23 screens.
// Import only this file in your screens — do not import repositories directly.
//
// Provider naming convention:
//   - Repository providers:  xxxRepositoryProvider
//   - Use-case providers:    xxxUseCaseProvider
//   - Data providers:        xxxProvider / xxxAsyncProvider
//   - Notifiers:             xxxNotifierProvider
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/failures.dart';
import '../../data/models/models.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/auction_repository.dart';
import '../../data/repositories/repositories.dart';
import '../../domain/usecases/usecases.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Re-export all repository providers so screens import only this file
// ─────────────────────────────────────────────────────────────────────────────
export '../../data/repositories/auth_repository.dart'
    show authRepositoryProvider, authStateProvider;
export '../../data/repositories/repositories.dart'
    show
        bidRepositoryProvider,
        userRepositoryProvider,
        adminRepositoryProvider,
        feedbackRepositoryProvider,
        reportRepositoryProvider,
        highestBidProvider,
        bidsForAuctionProvider,
        clientBidsProvider,
        currentUserProvider,
        notificationsProvider,
        unreadNotifCountProvider,
        usersByRegionProvider,
        allAdminsProvider,
        currentAdminProvider,
        regionStatsProvider,
        nationalStatsProvider,
        regionCategoryStatsProvider,
        recentClosedAuctionsProvider,
        appSettingsRepositoryProvider;
export '../../data/repositories/auction_repository.dart'
    show auctionRepositoryProvider;
export '../../data/models/models.dart';
export '../../data/models/user_model.dart';
export '../../core/localization/locale_provider.dart'
    show localeProvider, LocaleNotifier;
export '../../core/localization/language_service.dart' show LanguageService;

// ─────────────────────────────────────────────────────────────────────────────
// AUTH USE-CASE PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// Registers a new client account in Supabase Auth + users table.
/// Used by: register_screen.dart
final registerClientUseCaseProvider = Provider<RegisterClientUseCase>((ref) {
  return RegisterClientUseCase(ref.watch(authRepositoryProvider));
});

/// Logs in a client or admin. Pass isAdmin: true for admin portal.
/// Used by: login_screen.dart, admin_login_screen.dart
final loginUseCaseProvider = Provider<LoginUseCase>((ref) {
  return LoginUseCase(ref.watch(authRepositoryProvider));
});

/// Logs out the current user and clears the session.
/// Used by: profile_screen.dart
final logoutUseCaseProvider = Provider<LogoutUseCase>((ref) {
  return LogoutUseCase(ref.watch(authRepositoryProvider));
});

/// Resets a client password via phone number using the reset-client-password
/// Edge Function (no email sent → no MX-record issue).
/// Used by: login_screen.dart (Forgot Password sheet)
final forgotPasswordUseCaseProvider = Provider<ForgotPasswordUseCase>((ref) {
  return ForgotPasswordUseCase(ref.watch(authRepositoryProvider));
});

/// Logs in any user (client, region_admin, super_admin) with a single call.
/// Auto-detects role by querying all user tables in priority order.
/// Used by: login_screen.dart (unified login)
final loginUnifiedUseCaseProvider = Provider<LoginUnifiedUseCase>((ref) {
  return LoginUnifiedUseCase(ref.watch(authRepositoryProvider));
});

// ─────────────────────────────────────────────────────────────────────────────
// AUCTION PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// Streams all active auctions in a region (Realtime — live updates).
/// Used by: home_screen.dart
final auctionsByRegionProvider =
    StreamProvider.family<List<AuctionModel>, String>((ref, region) {
      return ref.watch(auctionRepositoryProvider).getAuctionsByRegion(region);
    });

/// Streams auctions filtered by region + category.
/// Used by: home_screen.dart (category tabs)
final auctionsByCategoryProvider =
    StreamProvider.family<
      List<AuctionModel>,
      ({String region, String category})
    >((ref, params) {
      return ref
          .watch(auctionRepositoryProvider)
          .getAuctionsByRegion(params.region, category: params.category);
    });

/// Streams a single auction in real-time — for bid price updates.
/// Used by: auction_detail_screen.dart, close_auction_screen.dart, view_bids_screen.dart
final auctionWatcherProvider = StreamProvider.family<AuctionModel, String>((
  ref,
  auctionId,
) {
  return ref.watch(auctionRepositoryProvider).watchAuction(auctionId);
});

/// Loads all auctions posted by the current admin (non-realtime, one-time load).
/// Used by: admin_dashboard_screen.dart, manage_auctions_screen.dart
final adminAuctionsProvider = FutureProvider.family<List<AuctionModel>, String>(
  (ref, adminUid) {
    return ref.watch(auctionRepositoryProvider).getAuctionsByAdmin(adminUid);
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// AUCTION USE-CASE PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// Posts a new auction or saves as draft.
/// Used by: post_auction_screen.dart
final postAuctionUseCaseProvider = Provider<PostAuctionUseCase>((ref) {
  return PostAuctionUseCase(ref.watch(auctionRepositoryProvider));
});

/// Updates an existing auction's metadata (no photo replacement).
/// Used by: post_auction_screen.dart (edit mode)
final updateAuctionUseCaseProvider = Provider<UpdateAuctionUseCase>((ref) {
  return UpdateAuctionUseCase(ref.watch(auctionRepositoryProvider));
});

/// Publishes a draft auction (status draft → active).
/// Used by: manage_auctions_screen.dart
final publishDraftUseCaseProvider = Provider<PublishDraftUseCase>((ref) {
  return PublishDraftUseCase(ref.watch(auctionRepositoryProvider));
});

/// Deletes an auction. Hard-deletes if no bids; soft-deletes otherwise.
/// Used by: manage_auctions_screen.dart
final deleteAuctionUseCaseProvider = Provider<DeleteAuctionUseCase>((ref) {
  return DeleteAuctionUseCase(ref.watch(auctionRepositoryProvider));
});

/// Closes an auction manually and announces the winner.
/// Used by: close_auction_screen.dart
final closeAuctionUseCaseProvider = Provider<CloseAuctionUseCase>((ref) {
  return CloseAuctionUseCase(ref.watch(adminRepositoryProvider));
});

// ─────────────────────────────────────────────────────────────────────────────
// BID STATE — BidNotifier manages the UI state of placing a bid
// ─────────────────────────────────────────────────────────────────────────────

/// Manages loading / error / success state for placing a bid.
/// Used by: auction_detail_screen.dart (bid dialog), bid_confirmation_screen.dart
final bidNotifierProvider =
    StateNotifierProvider<BidNotifier, AsyncValue<Map<String, dynamic>?>>((
      ref,
    ) {
      return BidNotifier(ref.watch(bidRepositoryProvider));
    });

class BidNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  BidNotifier(this._repo) : super(const AsyncData(null));
  final BidRepository _repo;

  /// True when the last bid was an update to an existing bid (not a new bid).
  bool get isUpdate => state.value?['is_update'] == true;

  /// True when the bidder is currently the highest bidder after the last bid.
  bool get isWinning => state.value?['is_winning'] == true;

  /// Returns null on success, Failure on error.
  Future<Failure?> placeBid({
    required String auctionId,
    required double bidAmount,
    required String bidderUid,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await _repo.placeBid(
        auctionId: auctionId,
        bidAmount: bidAmount,
        bidderUid: bidderUid,
      );
      state = AsyncData(result);
      return null;
    } catch (e, st) {
      state = AsyncError(e, st);
      return UnknownFailure(e.toString());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN USE-CASE PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a new region admin account via Edge Function.
/// Used by: add_admin_screen.dart
final createAdminUseCaseProvider = Provider<CreateAdminUseCase>((ref) {
  return CreateAdminUseCase(ref.watch(adminRepositoryProvider));
});

/// Suspend or activate a client account.
/// Used by: client_management_screen.dart
final manageUserUseCaseProvider = Provider<ManageUserUseCase>((ref) {
  return ManageUserUseCase(ref.watch(userRepositoryProvider));
});

// ─────────────────────────────────────────────────────────────────────────────
// SUPER ADMIN PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// Fetches all feedback for a specific region (for Region Admin feedback screen).
/// Used by: client_feedbacks_screen.dart
final feedbackByRegionProvider = FutureProvider.family<List<FeedbackModel>, String>(
  (ref, region) => ref.watch(feedbackRepositoryProvider).getFeedbackByRegion(region),
);

/// Fetches the single app_settings row (id = 'config').
/// Used by: app_settings_screen.dart
final appSettingsProvider = FutureProvider<AppSettingsModel>((ref) {
  return ref.watch(appSettingsRepositoryProvider).getSettings();
});

/// Loads the current logged-in super admin's data.
/// Used by: super_admin_dashboard_screen.dart
final currentSuperAdminProvider = FutureProvider<SuperAdminModel?>((ref) async {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) async {
      final uid = state.session?.user.id;
      if (uid == null) return null;
      try {
        final data = await Supabase.instance.client
            .from('super_admins')
            .select()
            .eq('id', uid)
            .single();
        return SuperAdminModel.fromMap(data);
      } catch (_) {
        return null;
      }
    },
    loading: () => null,
    error: (_, _) => null,
  );
});
