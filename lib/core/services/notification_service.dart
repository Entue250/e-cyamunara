import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../constants/supabase_constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService — OneSignal (100% free, no credit card required)
//
// OneSignal replaces Firebase Cloud Messaging (FCM).
// Free plan includes: unlimited push notifications, unlimited devices.
//
// Setup:
//   1. Go to https://onesignal.com → Create free account
//   2. New App → name it "ecyamunara-rnp"
//   3. Platform: Google Android → paste your Firebase Server Key
//      (Get from: Firebase Console → Project Settings → Cloud Messaging)
//      OR use the OneSignal Android setup which needs no Firebase at all.
//   4. Copy the App ID → paste into SupabaseConstants.oneSignalAppId
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  String? _playerId; // OneSignal player/subscription ID

  // ── INITIALIZE ────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      OneSignal.initialize(SupabaseConstants.oneSignalAppId);
      await OneSignal.Notifications.requestPermission(true);

      final deviceState = await OneSignal.User.getOnesignalId();
      _playerId = deviceState;

      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        event.notification.display();
      });

      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data != null) {
          _handleNotificationTap(data);
        }
      });
    } catch (e) {
      // OneSignal not supported on this platform (web) — skip silently
      debugPrint('NotificationService: skipping OneSignal init — $e');
    }
  }
  // ── GET PLAYER ID (save this to the user's row in Supabase) ───────────────
  String? get playerId => _playerId;

  Future<String?> refreshPlayerId() async {
    _playerId = await OneSignal.User.getOnesignalId();
    return _playerId;
  }

  // ── SUBSCRIBE TO REGION TOPIC ─────────────────────────────────────────────
  /// Clients subscribe to their region so region admins can send bulk notifications.
  Future<void> subscribeToRegion(String region) async {
    await OneSignal.User.addTagWithKey('region', region.toLowerCase());
  }

  Future<void> unsubscribeFromRegion() async {
    await OneSignal.User.removeTag('region');
  }

  // ── SET USER ROLE TAG ─────────────────────────────────────────────────────
  Future<void> setUserRole(String role) async {
    await OneSignal.User.addTagWithKey('role', role);
  }

  // ── NAVIGATION ON TAP ─────────────────────────────────────────────────────
  // Stored so the router can consume it on next build
  String? _pendingRoute;
  String? get pendingRoute => _pendingRoute;
  void clearPendingRoute() => _pendingRoute = null;

  void _handleNotificationTap(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final auctionId = data['auction_id'] as String?;

    _pendingRoute = switch (type) {
      'new_auction' when auctionId != null => '/auction/$auctionId',
      'winning' => '/my-bids',
      'outbid' when auctionId != null => '/auction/$auctionId',
      'won' => '/bid-confirmation',
      'system' => '/notifications',
      _ => null,
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
