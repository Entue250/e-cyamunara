import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_constants.dart';
import 'core/services/encryption_service.dart';
import 'core/services/notification_service.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Load .env ──────────────────────────────────────────────────────────
  // .env is bundled as a Flutter asset (see pubspec.yaml assets section).
  // This must run before anything else reads SupabaseConstants.
  await dotenv.load(fileName: '.env');

  // ── 2. Sentry crash reporting ─────────────────────────────────────────────
  // SENTRY_DSN comes from .env. When empty (dev builds without a DSN),
  // Sentry is skipped entirely and the app starts via _initializeApp() directly.
  final sentryDsn = dotenv.env['SENTRY_DSN'] ?? '';

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.2;
        options.environment = dotenv.env['ENV'] ?? 'production';
        options.attachScreenshot = false; // no screenshots (PII risk)
        // ignore: experimental_member_use
        options.attachViewHierarchy = false;
      },
      appRunner: _initializeApp,
    );
  } else {
    await _initializeApp();
  }
}

/// All startup initialization lives here so it runs identically whether
/// Sentry wraps it (production) or not (development/CI).
/// dotenv is already loaded by the time this runs.
Future<void> _initializeApp() async {
  // ── 1. Validate credentials before handing them to Supabase ──────────────
  // An empty URL produces "No host specified in URI /auth/v1/token?grant_type=password".
  // Fail fast with a clear message instead.
  final supabaseUrl = SupabaseConstants.supabaseUrl;
  final supabaseAnonKey = SupabaseConstants.supabaseAnonKey;

  if (supabaseUrl.isEmpty || !supabaseUrl.startsWith('https://')) {
    throw StateError(
      'SUPABASE_URL is missing or invalid ("$supabaseUrl"). '
      'Check that .env exists at the project root and contains SUPABASE_URL=https://...',
    );
  }
  if (supabaseAnonKey.isEmpty) {
    throw StateError(
      'SUPABASE_ANON_KEY is missing. '
      'Check that .env exists at the project root and contains SUPABASE_ANON_KEY=...',
    );
  }

  // ── 2. Initialize Supabase ────────────────────────────────────────────────
  // Must complete before runApp — every provider and repository depends on it.
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.error,
    ),
  );

  // ── 3. Run app immediately ────────────────────────────────────────────────
  // Call runApp() right after Supabase so Flutter can render the splash screen
  // on the very next Choreographer tick. Any initialization that blocks the
  // Android main thread (platform channels, Keystore, OneSignal) MUST NOT
  // happen before this line — doing so delays the first rendered frame and
  // produces a black screen on Android 7 devices.
  runApp(const ProviderScope(child: EcyamunaraApp()));

  // ── 4. Defer non-critical services to after first frame ───────────────────
  // addPostFrameCallback fires once the splash screen has been rendered.
  // By then Flutter's Choreographer is running, so even if these services
  // momentarily block the Android main thread the splash is already visible.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // AES key stored via flutter_secure_storage (Keystore + plain XML).
    // Only needed for National ID display in ProfileScreen.
    EncryptionService.instance.initialize().catchError((_) {});

    // OneSignal push notifications — network-bound, non-critical for core UX.
    NotificationService.instance.initialize().catchError((_) {});
  });
}

// Global Supabase client accessor — use anywhere in the app:
// final supabase = Supabase.instance.client;
