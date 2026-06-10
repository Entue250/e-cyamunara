// lib/core/constants/supabase_constants.dart
//
// Central place for ALL Supabase table names, storage bucket names,
// Edge Function names, and app-wide constants.
// Never type table names as raw strings in repositories — always use these.

import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConstants {
  SupabaseConstants._();

  // ── Supabase project credentials ──────────────────────────────────────────
  // Loaded at runtime from the .env asset (via flutter_dotenv).
  // Edit .env to change values — never hardcode here.
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // ── Table names ───────────────────────────────────────────────────────────
  static const String usersTable = 'users';
  static const String regionAdminsTable = 'region_admins';
  static const String superAdminsTable = 'super_admins';
  static const String auctionsTable = 'auctions';
  static const String bidsTable = 'bids';
  static const String feedbackTable = 'feedback';
  static const String districtsTable = 'districts';
  static const String appSettingsTable = 'app_settings';
  static const String notificationsTable = 'notifications';
  static const String auctionAutoCloseLogsTable = 'auction_auto_close_logs';

  // ── Storage bucket names ──────────────────────────────────────────────────
  static const String auctionPhotosBucket = 'auction-photos';
  static const String profilePhotosBucket = 'profile-photos';
  static const String nationalIdsBucket = 'national-ids';
  static const String reportsBucket = 'reports';

  // ── Edge Function names ───────────────────────────────────────────────────
  static const String fnPlaceBid = 'place-bid';
  static const String fnCreateAdmin = 'create-admin';
  static const String fnCloseAuctionManually = 'close-auction-manually';
  static const String fnSendAuctionNotification = 'send-auction-notification';
  static const String fnGetUserStats = 'get-user-stats';
  static const String fnGenerateReport = 'generate-report';
  static const String fnSuspendUser = 'suspend-user';
  static const String fnActivateUser = 'activate-user';
  static const String fnRegisterClient = 'register-client';
  static const String fnResetClientPassword = 'reset-client-password';
  static const String fnAutoCloseAuctions = 'auto-close-auctions';

  // ── OneSignal (push notifications) ───────────────────────────────────────
  static String get oneSignalAppId => dotenv.env['ONESIGNAL_APP_ID'] ?? '';

  // ── Roles ─────────────────────────────────────────────────────────────────
  static const String roleClient = 'client';
  static const String roleRegionAdmin = 'region_admin';
  static const String roleSuperAdmin = 'super_admin';

  // ── RNP Regions ───────────────────────────────────────────────────────────
  static const List<String> regions = [
    'Eastern',
    'Western',
    'Northern',
    'Southern',
    'Central',
  ];

  // ── Item categories ───────────────────────────────────────────────────────
  static const List<String> categories = ['vehicle', 'motorcycle', 'bicycle'];

  // ── Auction statuses ──────────────────────────────────────────────────────
  static const String statusDraft = 'draft';
  static const String statusActive = 'active';
  static const String statusClosed = 'closed';
  static const String statusCancelled = 'cancelled';
}
