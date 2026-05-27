import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_constants.dart';
import 'core/services/encryption_service.dart';
import 'core/services/notification_service.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Sentry crash reporting ────────────────────────────────────────────────
  // DSN is injected at build time:
  //   flutter build apk --release --dart-define=SENTRY_DSN=https://...@sentry.io/...
  // When SENTRY_DSN is empty (dev builds, CI), Sentry is skipped entirely
  // and the app starts via _initializeApp() directly — no behavior change.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        // Sample 20% of sessions for performance tracing. Errors are always sent.
        options.tracesSampleRate = 0.2;
        // Override with --dart-define=ENV=staging for staging builds.
        options.environment = const String.fromEnvironment(
          'ENV',
          defaultValue: 'production',
        );
        // Attach device/OS context to every event for triage.
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
Future<void> _initializeApp() async {
  // ── 1. Initialize Supabase ────────────────────────────────────────────────
  // Must complete before runApp — every provider and repository depends on it.
  await Supabase.initialize(
    url: SupabaseConstants.supabaseUrl,
    anonKey: SupabaseConstants.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(
      logLevel: RealtimeLogLevel.error,
    ),
  );

  // ── 2. Run app immediately ────────────────────────────────────────────────
  // Call runApp() right after Supabase so Flutter can render the splash screen
  // on the very next Choreographer tick. Any initialization that blocks the
  // Android main thread (platform channels, Keystore, OneSignal) MUST NOT
  // happen before this line — doing so delays the first rendered frame and
  // produces a black screen on Android 7 devices.
  runApp(const ProviderScope(child: EcyamunaraApp()));

  // ── 3. Defer non-critical services to after first frame ───────────────────
  // addPostFrameCallback fires once the splash screen has been rendered and
  // displayed. By then Flutter's Choreographer is running, so even if these
  // services momentarily block the Android main thread the splash is already
  // visible — the user sees a brief pause in animation, never a black screen.
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
