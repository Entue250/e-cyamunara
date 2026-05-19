# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run app (Android emulator or connected device)
flutter run --dart-define-from-file=.env.json

# Build APK
flutter build apk --dart-define-from-file=.env.json

# Run all tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze code
flutter analyze

# Get dependencies
flutter pub get

# Deploy a Supabase Edge Function
supabase functions deploy <function-name>
# e.g. supabase functions deploy place-bid

# Push Edge Function secrets to Supabase
supabase secrets set --env-file supabase/.env
```

## Environment Setup

All secrets live outside source control:

| File | Purpose | Committed? |
|------|---------|-----------|
| `.env.json` | Flutter build-time keys (Supabase URL/anon key, OneSignal, Sentry) | No — gitignored |
| `env.example.json` | Template — copy to `.env.json` and fill in values | Yes |
| `supabase/.env` | Edge Function secrets (OneSignal REST key) | No — gitignored |
| `supabase/.env.example` | Template for edge function secrets | Yes |

Keys are injected at **compile time** via `--dart-define-from-file=.env.json` — they are NOT bundled inside the APK binary. Inside Dart code they are accessed via `String.fromEnvironment('KEY')`.

## Architecture

This is **E-CYAMUNARA**, a Flutter mobile app for online vehicle auctions managed by Rwanda National Police. The backend is entirely Supabase (PostgreSQL + Auth + Storage + Realtime + Edge Functions).

### Three-role system

| Role | Tables | Entry point |
|------|--------|-------------|
| `client` | `users` | `/login` → `/home` |
| `region_admin` | `region_admins` | `/admin/login` → `/admin/dashboard` |
| `super_admin` | `super_admins` | `/admin/login` → `/super/dashboard` |

Route protection happens in `lib/presentation/app_router.dart` via GoRouter's `redirect` callback, which resolves the role by querying Supabase directly. Suspended accounts are signed out on every navigation.

### Layer structure (`lib/`)

```
core/
  constants/supabase_constants.dart  ← ALL table names, bucket names, Edge Function names, regions, categories
  errors/                            ← AppException subtypes + Failure types (AuthFailure, DatabaseFailure, …)
  services/                          ← EncryptionService (AES-256 for National ID), NotificationService (OneSignal), SessionService
  utils/                             ← validators, formatters, date helpers

data/
  models/models.dart       ← All Supabase row models (AuctionModel, BidModel, RegionAdminModel, etc.)
  models/user_model.dart   ← UserModel (client)
  repositories/            ← Direct Supabase SDK calls; bid placement calls Edge Function place-bid

domain/
  entities/entities.dart   ← thin wrappers (mirrors models, kept for clean-arch convention)
  usecases/usecases.dart   ← all use cases; return (T?, Failure?) tuples

presentation/
  app.dart                 ← MaterialApp.router wired to appRouterProvider
  app_router.dart          ← GoRouter + RBAC redirect + AdminProfileScreen + SuperAdminProfileScreen (profile screens live here, not in screens/)
  providers/providers.dart ← single import point for ALL Riverpod providers; re-exports everything
  screens/auth/            ← LoginScreen, RegisterScreen, AdminLoginScreen, RegionSelectScreen
  screens/client/          ← HomeScreen, AuctionDetailScreen, MyBidsScreen, BidConfirmationScreen, FeedbackScreen, ProfileScreen, NotificationsScreen
  screens/admin/           ← AdminDashboardScreen, PostAuctionScreen, ManageAuctionsScreen, ViewBidsScreen, CloseAuctionScreen, ClientManagementScreen, RegionReportsScreen
  screens/super_admin/     ← SuperAdminDashboardScreen, ManageAdminsScreen, AddAdminScreen, NationalReportsScreen
  theme/app_theme.dart     ← AppColors (RNP Blue #003087 + Gold #FFD700), AppTextStyles, spacing constants
```

### State management pattern

All screens use `flutter_riverpod`. The canonical import is:
```dart
import '../../providers/providers.dart';
```
Never import repositories directly in screens — `providers.dart` re-exports everything.

Provider naming: `xxxRepositoryProvider`, `xxxUseCaseProvider`, `xxxProvider` / `xxxAsyncProvider`, `xxxNotifierProvider`.

Auction lists use `StreamProvider.family` backed by Supabase Realtime. One-time loads use `FutureProvider.family`. Bid placement state is managed by `BidNotifier` (a `StateNotifier`).

### Supabase tables

`users`, `region_admins`, `super_admins`, `auctions`, `bids`, `feedback`, `districts`, `app_settings`, `notifications`

Storage buckets: `auction-photos`, `profile-photos`, `national-ids`, `reports`

### Edge Functions (`supabase/functions/`)

Critical business logic runs server-side as Deno Edge Functions to prevent client-side manipulation:

- `place-bid` — atomic bid placement (validates amount > current highest, updates auction, notifies outbid user)
- `close-auction-manually` — announces winner, updates statuses
- `create-admin` — creates `region_admin` via service role (bypasses RLS)
- `suspend-user` / `activate-user` — account management
- `send-auction-notification` — OneSignal push dispatch
- `generate-report` — PDF report generation
- `auto-close-auctions` / `on-new-auction` / `get-user-stats` / `cleanup-notifications` — scheduled/trigger functions

Always use `SupabaseConstants.fnXxx` constants when calling `_client.functions.invoke(...)`.

### Security notes

- National IDs are encrypted with AES-256 CBC via `EncryptionService` (key stored in `flutter_secure_storage`). Call `EncryptionService.instance.initialize()` before encrypt/decrypt.
- Raw strings for table names are forbidden — always use `SupabaseConstants.*Table` constants.
- Admin creation must go through the `create-admin` Edge Function (service role needed).

### Theme

Brand colors are in `AppColors` (RNP Blue `0xFF003087`, Gold `0xFFFFD700`). Use `AppColors.*` constants, not inline hex values, to stay consistent with the RNP brand.
