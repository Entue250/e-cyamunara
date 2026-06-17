// lib/presentation/app_router.dart
//
// ─── GOROUTER WITH FULL RBAC ─────────────────────────────────────────────────
// Route protection rules:
//   client       → /home, /auction/*, /my-bids, /profile, /notifications ...
//   region_admin → /admin/* routes + /admin/profile
//   super_admin  → /super/* + /super/profile
//   unauthenticated → /login, /register, /admin/login only
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/app_theme.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/region_select_screen.dart';
import 'screens/client/client_screens.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/super_admin/super_admin_screens.dart';

import '../data/models/models.dart' show AuctionModel, RegionAdminModel;

// ─────────────────────────────────────────────────────────────────────────────
// Route constants
// ─────────────────────────────────────────────────────────────────────────────
class AppRoutes {
  AppRoutes._();

  // Public
  static const splash        = '/';
  static const login         = '/login';
  static const register      = '/register';
  static const regionSelect  = '/region-select';
  static const adminLogin    = '/admin/login';
  static const unauthorized  = '/unauthorized';

  // Client
  static const home            = '/home';
  static const search          = '/search';
  static const auctionDetail   = '/auction/:id';
  static const myBids          = '/my-bids';
  static const bidConfirmation = '/bid-confirmation';
  static const feedback        = '/feedback/:auction_id';
  static const feedbackGeneral = '/feedback-general';  // No auction ID (bottom nav)
  static const profile         = '/profile';           // Client profile
  static const notifications   = '/notifications';

  // Region Admin
  static const adminDashboard    = '/admin/dashboard';
  static const postAuction       = '/admin/post-auction';
  static const manageAuctions    = '/admin/auctions';
  static const viewBids          = '/admin/bids/:auction_id';
  static const closeAuction      = '/admin/close/:auction_id';
  static const userManagement    = '/admin/clients';
  static const regionReports     = '/admin/reports';
  static const adminFeedbacks    = '/admin/feedbacks';
  static const adminProfile      = '/admin/profile';       // Admin profile
  static const adminNotifications = '/admin/notifications'; // Admin notifications

  // Super Admin
  static const superDashboard  = '/super/dashboard';
  static const manageAdmins    = '/super/admins';
  static const addEditAdmin    = '/super/add-admin';
  static const nationalReports = '/super/reports';
  static const superProfile         = '/super/profile';        // Super admin profile
  static const superSettings        = '/super/settings';       // App settings
  static const superNotifications   = '/super/notifications';  // Super admin notifications
  static const superAiDashboard    = '/super/ai-dashboard';   // AI Intelligence dashboard
}

// ─────────────────────────────────────────────────────────────────────────────
// Role resolver — with 5-second cache
//
// WHY THE CACHE EXISTS:
//   GoRouter's async redirect fires on EVERY non-public navigation. Without a
//   cache, _getUserRole() makes 3 sequential Supabase round-trips on each
//   navigation event. On Android 7 over mobile data that means 6–15 s of black
//   screen because GoRouter renders nothing while awaiting an async redirect.
//
//   The cache is keyed by UID and expires after 5 seconds. This covers the
//   common pattern where _SplashScreen._navigate() fetches the role (populating
//   the cache) and then calls context.go(), which triggers the redirect again
//   within milliseconds — a guaranteed cache hit with zero network overhead.
//
//   After the 5-second window the role is re-fetched on the next navigation,
//   which keeps the suspension check live (suspended accounts are caught within
//   5 s of their next tap).
// ─────────────────────────────────────────────────────────────────────────────
const _roleCacheTtl = Duration(seconds: 5);
String? _cachedRole;
String? _cachedUid;
DateTime? _roleLastFetched;

Future<String> _getUserRole() async {
  final client = Supabase.instance.client;
  final uid    = client.auth.currentUser?.id;

  if (uid == null) {
    _cachedRole = null;
    _cachedUid  = null;
    _roleLastFetched = null;
    return 'unauthenticated';
  }

  // Serve from cache when the same UID was resolved within the last 5 seconds.
  final now = DateTime.now();
  if (uid == _cachedUid &&
      _cachedRole != null &&
      _roleLastFetched != null &&
      now.difference(_roleLastFetched!) < _roleCacheTtl) {
    debugPrint('[ROUTER] role cache hit: $_cachedRole');
    return _cachedRole!;
  }

  try {
    debugPrint('[ROUTER] resolving role for uid=$uid');
    // Wrap the three sequential queries in a single 15-second deadline so a
    // hung Supabase connection can never block the router indefinitely.
    final role = await _resolveRoleFromDb(client, uid).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('[ROUTER] role resolution timed out for uid=$uid');
        return 'unauthenticated';
      },
    );

    if (role != 'suspended' && role != 'unknown' && role != 'unauthenticated') {
      _cachedRole      = role;
      _cachedUid       = uid;
      _roleLastFetched = now;
    } else {
      _cachedRole      = null;
      _cachedUid       = null;
      _roleLastFetched = null;
    }

    debugPrint('[ROUTER] role resolved: $role');
    return role;
  } catch (e) {
    debugPrint('[ROUTER] _getUserRole error: $e');
    return 'unauthenticated';
  }
}

/// Pure DB query — called by [_getUserRole] inside a timeout.
Future<String> _resolveRoleFromDb(SupabaseClient client, String uid) async {
  final superSnap = await client
      .from('super_admins')
      .select('id, account_status')
      .eq('id', uid)
      .maybeSingle();
  if (superSnap != null) {
    if (superSnap['account_status'] != 'active') {
      debugPrint('[ROUTER] super_admin suspended uid=$uid');
      return 'suspended';
    }
    return 'super_admin';
  }

  final adminSnap = await client
      .from('region_admins')
      .select('id, account_status')
      .eq('id', uid)
      .maybeSingle();
  if (adminSnap != null) {
    if (adminSnap['account_status'] != 'active') {
      debugPrint('[ROUTER] region_admin suspended uid=$uid');
      return 'suspended';
    }
    return 'region_admin';
  }

  final userSnap = await client
      .from('users')
      .select('id, account_status')
      .eq('id', uid)
      .maybeSingle();
  if (userSnap != null) {
    if (userSnap['account_status'] != 'active') {
      debugPrint('[ROUTER] client suspended uid=$uid');
      return 'suspended';
    }
    return 'client';
  }

  return 'unknown';
}

// ─────────────────────────────────────────────────────────────────────────────
// Router provider
// ─────────────────────────────────────────────────────────────────────────────
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,

    // ── Global RBAC redirect ───────────────────────────────────────────────
    redirect: (context, state) async {
      final path    = state.uri.path;
      final session = Supabase.instance.client.auth.currentSession;

      final isPublic = path == AppRoutes.splash      ||
                       path == AppRoutes.login        ||
                       path == AppRoutes.register     ||
                       path == AppRoutes.adminLogin   ||
                       path == AppRoutes.unauthorized;

      // No session → only public routes
      if (session == null) return isPublic ? null : AppRoutes.login;

      // Public while logged in → splash handles routing
      if (isPublic) return null;

      final role = await _getUserRole();

      // Suspended → force logout
      if (role == 'suspended') {
        debugPrint('[ROUTER] suspended account navigating to $path — signing out');
        await Supabase.instance.client.auth.signOut();
        return AppRoutes.login;
      }

      // Unknown role (no DB profile) → sign out to prevent stuck sessions
      if (role == 'unknown') {
        debugPrint('[ROUTER] unknown role for authenticated uid — signing out');
        await Supabase.instance.client.auth.signOut();
        return AppRoutes.login;
      }

      // ── Client routes ────────────────────────────────────────────────────
      final isClientRoute =
          path.startsWith('/home')             ||
          path.startsWith('/search')           ||
          path.startsWith('/auction')          ||
          path.startsWith('/my-bids')          ||
          path.startsWith('/bid-confirmation') ||
          path.startsWith('/feedback')         ||
          path == AppRoutes.profile            ||
          path.startsWith('/notifications')    ||
          path.startsWith('/region-select');

      if (isClientRoute && role != 'client') {
        if (role == 'super_admin')  return AppRoutes.superDashboard;
        if (role == 'region_admin') return AppRoutes.adminDashboard;
        return AppRoutes.unauthorized;
      }

      // ── Admin routes ─────────────────────────────────────────────────────
      final isAdminRoute = path.startsWith('/admin/');

      if (isAdminRoute) {
        if (role == 'super_admin' || role == 'region_admin') return null;
        if (role == 'client') return AppRoutes.home;
        return AppRoutes.unauthorized;
      }

      // ── Super admin routes ───────────────────────────────────────────────
      final isSuperRoute = path.startsWith('/super/');

      if (isSuperRoute && role != 'super_admin') {
        if (role == 'region_admin') return AppRoutes.adminDashboard;
        if (role == 'client')       return AppRoutes.home;
        return AppRoutes.unauthorized;
      }

      return null; // Allow
    },

    routes: [
      // ── Public ────────────────────────────────────────────────────────────
      GoRoute(path: AppRoutes.splash,
          builder: (_, s) => const _SplashScreen()),
      GoRoute(path: AppRoutes.unauthorized,
          builder: (_, s) => const _UnauthorizedScreen()),
      GoRoute(path: AppRoutes.login,
          builder: (_, s) => const LoginScreen()),
      GoRoute(path: AppRoutes.register,
          builder: (_, s) => const RegisterScreen()),
      GoRoute(path: AppRoutes.adminLogin,
          builder: (_, s) => const LoginScreen()),
      GoRoute(path: AppRoutes.regionSelect,
          builder: (_, s) => const RegionSelectScreen()),

      // ── Client ────────────────────────────────────────────────────────────
      GoRoute(path: AppRoutes.home,
          builder: (_, s) => const HomeScreen()),
      GoRoute(path: AppRoutes.search,
          builder: (_, s) => const SearchScreen()),
      GoRoute(path: AppRoutes.auctionDetail,
          builder: (_, s) => AuctionDetailScreen(
              auctionId: s.pathParameters['id']!)),
      GoRoute(path: AppRoutes.myBids,
          builder: (_, s) => const MyBidsScreen()),
      GoRoute(path: AppRoutes.bidConfirmation,
          builder: (_, s) => BidConfirmationScreen(
              auction: s.extra as AuctionModel?)),
      GoRoute(path: AppRoutes.feedback,
          builder: (_, s) => FeedbackScreen(
              auctionId: s.pathParameters['auction_id']!)),
      GoRoute(path: AppRoutes.feedbackGeneral,
          builder: (_, s) => const FeedbackScreen()),
      GoRoute(path: AppRoutes.profile,
          builder: (_, s) => const ProfileScreen()),         // Client profile
      GoRoute(path: AppRoutes.notifications,
          builder: (_, s) => const NotificationsScreen()),

      // ── Region Admin ──────────────────────────────────────────────────────
      GoRoute(path: AppRoutes.adminDashboard,
          builder: (_, s) => const AdminDashboardScreen()),
      GoRoute(path: AppRoutes.postAuction,
          builder: (_, s) => PostAuctionScreen(
              auction: s.extra as AuctionModel?)),
      GoRoute(path: AppRoutes.manageAuctions,
          builder: (_, s) => const ManageAuctionsScreen()),
      GoRoute(path: AppRoutes.viewBids,
          builder: (_, s) => ViewBidsScreen(
              auctionId: s.pathParameters['auction_id']!)),
      GoRoute(path: AppRoutes.closeAuction,
          builder: (_, s) => CloseAuctionScreen(
              auctionId: s.pathParameters['auction_id']!)),
      GoRoute(path: AppRoutes.userManagement,
          builder: (_, s) => const ClientManagementScreen()),
      GoRoute(path: AppRoutes.regionReports,
          builder: (_, s) => const RegionReportsScreen()),
      GoRoute(path: AppRoutes.adminFeedbacks,
          builder: (_, s) => const ClientFeedbacksScreen()),
      GoRoute(path: AppRoutes.adminProfile,
          builder: (_, s) => const AdminProfileScreen()),    // Admin profile
      GoRoute(path: AppRoutes.adminNotifications,
          builder: (_, s) => const AdminNotificationsScreen()),

      // ── Super Admin ───────────────────────────────────────────────────────
      GoRoute(path: AppRoutes.superDashboard,
          builder: (_, s) => const SuperAdminDashboardScreen()),
      GoRoute(path: AppRoutes.manageAdmins,
          builder: (_, s) => const ManageAdminsScreen()),
      GoRoute(path: AppRoutes.addEditAdmin,
          builder: (_, s) => AddAdminScreen(
              adminToEdit: s.extra as RegionAdminModel?)),
      GoRoute(path: AppRoutes.nationalReports,
          builder: (_, s) => const NationalReportsScreen()),
      GoRoute(path: AppRoutes.superProfile,
          builder: (_, s) => const SuperAdminProfileScreen()), // Super profile
      GoRoute(path: AppRoutes.superSettings,
          builder: (_, s) => const AppSettingsScreen()),       // App settings
      GoRoute(path: AppRoutes.superNotifications,
          builder: (_, s) => const SuperAdminNotificationsScreen()),
      GoRoute(path: AppRoutes.superAiDashboard,
          builder: (_, s) => const AiDashboardScreen()),
    ],

    // ── Error page ─────────────────────────────────────────────────────────
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48,
                color: Color(0xFFC62828)),
            const SizedBox(height: 12),
            Text('Page not found: ${state.uri.path}'),
            const SizedBox(height: 16),
            ElevatedButton(
              // context IS available here because errorBuilder provides it
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen — routes to correct dashboard based on role
// ─────────────────────────────────────────────────────────────────────────────
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Hard deadline: if _navigate() hasn't resolved in 20 s (1.5 s delay +
    // up to 15 s for role fetch + buffer), force-redirect to login so the
    // user never sees an infinite spinner.
    _navigate().timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        debugPrint('[SPLASH] navigate timeout — falling back to login');
        if (mounted) context.go(AppRoutes.login);
      },
    ).catchError((e) {
      debugPrint('[SPLASH] navigate error: $e — falling back to login');
      if (mounted) context.go(AppRoutes.login);
    });
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) { context.go(AppRoutes.login); return; }

    final role = await _getUserRole();
    if (!mounted) return;

    switch (role) {
      case 'super_admin':  context.go(AppRoutes.superDashboard);
      case 'region_admin': context.go(AppRoutes.adminDashboard);
      case 'client':       context.go(AppRoutes.home);
      case 'suspended':
        await Supabase.instance.client.auth.signOut();
        if (mounted) context.go(AppRoutes.login);
      default:             context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.primaryBlue,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'E-CYAMUNARA',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'ONLINE AUCTION PLATFORM',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 32),
          RnpLoadingWidget(size: 64),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Unauthorized screen
// ─────────────────────────────────────────────────────────────────────────────
class _UnauthorizedScreen extends StatelessWidget {
  const _UnauthorizedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F7FA),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE), shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFC62828).withValues(alpha: 0.3),
                    width: 2)),
              child: const Icon(Icons.lock_outline,
                  size: 44, color: Color(0xFFC62828)),
            ),
            const SizedBox(height: 24),
            const Text('Access Denied',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                  color: Color(0xFF003087))),
            const SizedBox(height: 12),
            const Text(
              'You do not have permission to access this area.\n'
              'Please contact your administrator.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280),
                  height: 1.6)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                await Supabase.instance.client.auth.signOut();
                if (context.mounted) context.go(AppRoutes.login);
              },
              icon: const Icon(Icons.logout),
              label: const Text('BACK TO LOGIN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003087),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14)),
            ),
          ],
        ),
      ),
    ),
  );
}

// AdminProfileScreen now lives in screens/admin/admin_profile_screen.dart
// and is exported via admin_screens.dart (imported above at line 25).

