import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/notification_service.dart';
import '../models/user_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthRepository — Supabase
//
// Phone → Email conversion:
//   0782345678  →  rw0782345678@ecyamunara.rw
//   +250782345678 →  rw0782345678@ecyamunara.rw
//
// The 'rw' prefix is required because Supabase rejects email local-parts
// that start with digits (RFC 5321 is technically permissive, but Supabase's
// validation layer is stricter). Adding 'rw' makes it unambiguously valid.
// ─────────────────────────────────────────────────────────────────────────────

class AuthRepository {
  AuthRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  // ── Auth state stream ──────────────────────────────────────────────────────
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  // ── CLIENT REGISTRATION ────────────────────────────────────────────────────
  //
  // Uses the register-client Edge Function instead of client-side signUp().
  //
  // Root cause of the original failure:
  //   GoTrue v2.188.1 validates MX records for the email domain before sending
  //   a confirmation email.  ecyamunara.rw has no MX records, so client-side
  //   signUp() is rejected with "Email address is invalid".
  //
  //   admin.createUser({ email_confirm: true }) in the Edge Function marks the
  //   account confirmed without sending any email, bypassing MX validation —
  //   exactly the same pattern create-admin already uses for region admins.
  Future<UserModel> registerClient({
    required String fullNames,
    required String nationalId, // already AES-256 encrypted
    required String phoneNumber, // normalised to 07XXXXXXXX
    required String district,
    required String province,
    required String region,
    required String password,
  }) async {
    try {
      // 1. Collect OneSignal player ID before the Edge Function call so it is
      //    included in the users table insert performed server-side.
      final playerId = await NotificationService.instance.refreshPlayerId();

      // 2. Register via Edge Function (service role, email_confirm:true,
      //    no confirmation email → no MX-record validation).
      final response = await _client.functions.invoke(
        SupabaseConstants.fnRegisterClient,
        body: {
          'phone_number': phoneNumber,
          'password': password,
          'full_names': fullNames,
          'national_id': nationalId,
          'district': district,
          'province': province,
          'region': region,
          'onesignal_player_id': playerId,
        },
      );

      final resData = response.data;
      if (response.status != 200 ||
          resData is! Map<String, dynamic> ||
          resData['success'] != true) {
        final rawError = resData is Map<String, dynamic>
            ? resData['error'] as String? ?? 'Registration failed'
            : 'Registration failed';
        final userMsg = rawError.toLowerCase().contains('already exists')
            ? 'An account with this phone number already exists'
            : rawError;
        throw AppAuthException(userMsg);
      }

      // 3. The Edge Function has created + confirmed the auth user and inserted
      //    the users row.  Sign in immediately to establish a Flutter session.
      final signIn = await _client.auth.signInWithPassword(
        email: _phoneToEmail(phoneNumber),
        password: password,
      );

      if (signIn.user == null) {
        // Account created successfully but auto-login failed (rare transient
        // error).  The user can log in manually on the login screen.
        throw const AppAuthException(
          'Account created. Please log in with your phone number and password.',
        );
      }

      final uid = signIn.user!.id;

      // 4. Fetch the profile row the Edge Function inserted.
      final userRow = await _client
          .from(SupabaseConstants.usersTable)
          .select()
          .eq('id', uid)
          .single();

      // 5. Subscribe to push-notification topics.
      await NotificationService.instance.subscribeToRegion(region);
      await NotificationService.instance.setUserRole('client');

      debugPrint('[AUTH] registerClient: success uid=$uid');
      return UserModel.fromMap(userRow);
    } on AppAuthException {
      rethrow;
    } on AuthException catch (e) {
      throw mapSupabaseAuthError(e);
    } catch (e) {
      throw AppAuthException('Registration failed: $e');
    }
  }

  // ── CLIENT LOGIN ───────────────────────────────────────────────────────────
  Future<String> loginClient({
    required String phoneNumber,
    required String password,
  }) async {
    bool signedIn = false;
    try {
      await _client.auth.signInWithPassword(
        email: _phoneToEmail(phoneNumber),
        password: password,
      );
      signedIn = true;

      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const AppAuthException('Login failed — session not established');
      }

      final row = await _client
          .from(SupabaseConstants.usersTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();

      if (row == null) {
        debugPrint('[AUTH] loginClient: no profile found for uid=$uid');
        throw const AppAuthException('Account record not found');
      }

      final status = row['account_status'] as String?;
      if (status != 'active') {
        debugPrint('[AUTH] loginClient: rejected — account_status=$status uid=$uid');
        throw const AppAuthException(
          'Your account has been suspended. Please contact support.',
        );
      }

      final playerId = await NotificationService.instance.refreshPlayerId();
      await _client
          .from(SupabaseConstants.usersTable)
          .update({
            'last_login': DateTime.now().toIso8601String(),
            'onesignal_player_id': playerId,
          })
          .eq('id', uid);

      debugPrint('[AUTH] loginClient: success uid=$uid');
      return 'client';
    } on AppAuthException {
      if (signedIn) await _safeSignOut();
      rethrow;
    } on AuthException catch (e) {
      throw mapSupabaseAuthError(e);
    } catch (e) {
      if (signedIn) await _safeSignOut();
      throw AppAuthException('Login failed: $e');
    }
  }

  // ── ADMIN LOGIN ────────────────────────────────────────────────────────────
  //
  // Queries admin tables directly (not via getUserRole) so that role + status
  // are resolved in a single round-trip per table, and suspension produces a
  // specific error message rather than the generic "not an admin account".
  Future<String> loginAdmin({
    required String phoneNumber,
    required String password,
  }) async {
    bool signedIn = false;
    try {
      await _client.auth.signInWithPassword(
        email: _phoneToEmail(phoneNumber),
        password: password,
      );
      signedIn = true;

      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const AppAuthException('Login failed — session not established');
      }

      // Check super_admins first (most privileged)
      final superSnap = await _client
          .from(SupabaseConstants.superAdminsTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();

      if (superSnap != null) {
        final superStatus = superSnap['account_status'] as String?;
        if (superStatus != 'active') {
          debugPrint('[AUTH] loginAdmin: super_admin suspended uid=$uid status=$superStatus');
          throw const AppAuthException(
            'Your admin account has been suspended. Contact the system administrator.',
          );
        }
        final playerId = await NotificationService.instance.refreshPlayerId();
        await _client
            .from(SupabaseConstants.superAdminsTable)
            .update({
              'last_login': DateTime.now().toIso8601String(),
              'onesignal_player_id': playerId,
            })
            .eq('id', uid);
        debugPrint('[AUTH] loginAdmin: success role=super_admin uid=$uid');
        return 'super_admin';
      }

      // Check region_admins
      final adminSnap = await _client
          .from(SupabaseConstants.regionAdminsTable)
          .select('role, account_status')
          .eq('id', uid)
          .maybeSingle();

      if (adminSnap != null) {
        final adminStatus = adminSnap['account_status'] as String?;
        if (adminStatus != 'active') {
          debugPrint('[AUTH] loginAdmin: region_admin suspended uid=$uid status=$adminStatus');
          throw const AppAuthException(
            'Your admin account has been suspended. Contact the system administrator.',
          );
        }
        final role = adminSnap['role'] as String? ?? 'region_admin';
        final playerId = await NotificationService.instance.refreshPlayerId();
        await _client
            .from(SupabaseConstants.regionAdminsTable)
            .update({
              'last_login': DateTime.now().toIso8601String(),
              'onesignal_player_id': playerId,
            })
            .eq('id', uid);
        debugPrint('[AUTH] loginAdmin: success role=$role uid=$uid');
        return role;
      }

      debugPrint('[AUTH] loginAdmin: rejected — uid=$uid not in any admin table');
      throw const AppAuthException('This account is not an admin account');
    } on AppAuthException {
      if (signedIn) await _safeSignOut();
      rethrow;
    } on AuthException catch (e) {
      throw mapSupabaseAuthError(e);
    } catch (e) {
      if (signedIn) await _safeSignOut();
      throw AppAuthException('Login failed: $e');
    }
  }

  // ── UNIFIED LOGIN (auto-detects role: super_admin → region_admin → client) ──
  Future<String> loginUnified({
    required String phoneNumber,
    required String password,
  }) async {
    bool signedIn = false;
    try {
      await _client.auth.signInWithPassword(
        email: _phoneToEmail(phoneNumber),
        password: password,
      );
      signedIn = true;

      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw const AppAuthException('Login failed — session not established');
      }

      final superSnap = await _client
          .from(SupabaseConstants.superAdminsTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();

      if (superSnap != null) {
        if ((superSnap['account_status'] as String?) != 'active') {
          throw const AppAuthException(
            'Your admin account has been suspended. Contact the system administrator.',
          );
        }
        await _updateLastLoginAndPlayerId(uid, SupabaseConstants.superAdminsTable);
        debugPrint('[AUTH] loginUnified: super_admin uid=$uid');
        return 'super_admin';
      }

      final adminSnap = await _client
          .from(SupabaseConstants.regionAdminsTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();

      if (adminSnap != null) {
        if ((adminSnap['account_status'] as String?) != 'active') {
          throw const AppAuthException(
            'Your admin account has been suspended. Contact the system administrator.',
          );
        }
        await _updateLastLoginAndPlayerId(uid, SupabaseConstants.regionAdminsTable);
        debugPrint('[AUTH] loginUnified: region_admin uid=$uid');
        return 'region_admin';
      }

      final userSnap = await _client
          .from(SupabaseConstants.usersTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();

      if (userSnap != null) {
        if ((userSnap['account_status'] as String?) != 'active') {
          throw const AppAuthException(
            'Your account has been suspended. Please contact support.',
          );
        }
        await _updateLastLoginAndPlayerId(uid, SupabaseConstants.usersTable);
        debugPrint('[AUTH] loginUnified: client uid=$uid');
        return 'client';
      }

      throw const AppAuthException('Account not found. Please register first.');
    } on AppAuthException {
      if (signedIn) await _safeSignOut();
      rethrow;
    } on AuthException catch (e) {
      throw mapSupabaseAuthError(e);
    } catch (e) {
      if (signedIn) await _safeSignOut();
      throw AppAuthException('Login failed: $e');
    }
  }

  Future<void> _updateLastLoginAndPlayerId(String uid, String table) async {
    try {
      final playerId = await NotificationService.instance.refreshPlayerId();
      await _client.from(table).update({
        'last_login': DateTime.now().toIso8601String(),
        'onesignal_player_id': playerId,
      }).eq('id', uid);
    } catch (_) {}
  }

  // ── LOGOUT ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      await _client.auth.signOut();
    } catch (e) {
      throw AppAuthException('Logout failed: $e');
    }
  }

  // ── SAFE SIGN-OUT (internal) ───────────────────────────────────────────────
  // Used in login error paths where cleanup must never cascade into another
  // exception. Supabase's server-side expiry handles sessions that can't be
  // invalidated due to connectivity issues.
  Future<void> _safeSignOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }

  // ── GET ROLE ───────────────────────────────────────────────────────────────
  //
  // Return values: 'super_admin' | 'region_admin' | 'client' |
  //                'suspended'   | 'unknown'
  //
  // 'suspended': account exists but account_status != 'active'. Signs out the
  //   session immediately so the caller (router redirect, splash) can redirect
  //   to login without needing to call signOut itself.
  // 'unknown':   no profile row found in any table (data-integrity issue).
  Future<String> getUserRole() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return 'unknown';

      // Check super_admins first (most privileged)
      final superSnap = await _client
          .from(SupabaseConstants.superAdminsTable)
          .select('account_status')
          .eq('id', uid)
          .maybeSingle();
      if (superSnap != null) {
        if ((superSnap['account_status'] as String?) != 'active') {
          debugPrint('[AUTH] getUserRole: super_admin suspended uid=$uid — signing out');
          await _safeSignOut();
          return 'suspended';
        }
        return 'super_admin';
      }

      // Check region_admins
      final adminSnap = await _client
          .from(SupabaseConstants.regionAdminsTable)
          .select('role, account_status')
          .eq('id', uid)
          .maybeSingle();
      if (adminSnap != null) {
        if ((adminSnap['account_status'] as String?) != 'active') {
          debugPrint('[AUTH] getUserRole: region_admin suspended uid=$uid — signing out');
          await _safeSignOut();
          return 'suspended';
        }
        return adminSnap['role'] as String? ?? 'region_admin';
      }

      // Check users (clients)
      final userSnap = await _client
          .from(SupabaseConstants.usersTable)
          .select('role, account_status')
          .eq('id', uid)
          .maybeSingle();
      if (userSnap != null) {
        if ((userSnap['account_status'] as String?) != 'active') {
          debugPrint('[AUTH] getUserRole: client suspended uid=$uid — signing out');
          await _safeSignOut();
          return 'suspended';
        }
        return userSnap['role'] as String? ?? 'client';
      }

      debugPrint('[AUTH] getUserRole: no profile for uid=$uid — returning unknown');
      return 'unknown';
    } catch (e) {
      throw AppAuthException('Failed to get user role: $e');
    }
  }

  // ── REGION SELECTION ───────────────────────────────────────────────────────
  Future<void> updateRegionSelection(String region) async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) throw const AppAuthException('Not authenticated');
      await _client
          .from(SupabaseConstants.usersTable)
          .update({
            'region': region,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', uid);
      await NotificationService.instance.subscribeToRegion(region);
    } catch (e) {
      throw DatabaseException('Failed to update region: $e');
    }
  }

  // ── PASSWORD RESET ─────────────────────────────────────────────────────────
  //
  // resetPasswordForEmail() would fail for the same reason client-side signUp()
  // does — GoTrue tries to send an email to @ecyamunara.rw (no MX records).
  // Instead the reset-client-password Edge Function calls admin.updateUserById()
  // directly, which never sends any email.
  Future<void> resetClientPassword({
    required String phoneNumber,
    required String newPassword,
  }) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnResetClientPassword,
        body: {
          'phone_number': phoneNumber,
          'new_password': newPassword,
        },
      );

      final resData = response.data;
      if (response.status != 200 ||
          resData is! Map<String, dynamic> ||
          resData['success'] != true) {
        final rawError = resData is Map<String, dynamic>
            ? resData['error'] as String? ?? 'Password reset failed'
            : 'Password reset failed';
        throw AppAuthException(rawError);
      }
    } on AppAuthException {
      rethrow;
    } catch (e) {
      throw AppAuthException('Password reset failed: $e');
    }
  }

  // ── UPDATE PLAYER ID ───────────────────────────────────────────────────────
  Future<void> updatePlayerId(String playerId) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;
      final role = await getUserRole();
      final table = switch (role) {
        'super_admin' => SupabaseConstants.superAdminsTable,
        'region_admin' => SupabaseConstants.regionAdminsTable,
        _ => SupabaseConstants.usersTable,
      };
      await _client
          .from(table)
          .update({
            'onesignal_player_id': playerId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (_) {
      // Non-fatal
    }
  }

  // ── PHONE → EMAIL ──────────────────────────────────────────────────────────
  // THE FIX: prefix with 'rw' so the local part never starts with a digit.
  //
  // Examples:
  //   0791396400    → rw0791396400@ecyamunara.rw  ✅
  //   +250791396400 → rw0791396400@ecyamunara.rw  ✅
  //   250791396400  → rw0791396400@ecyamunara.rw  ✅
  String _phoneToEmail(String phone) {
    // Remove all non-digit characters
    String digits = phone.trim().replaceAll(RegExp(r'[^\d]'), '');

    // Remove country code 250 if present
    if (digits.startsWith('250') && digits.length > 9) {
      digits = digits.substring(3);
    }

    // Ensure leading zero
    if (!digits.startsWith('0')) digits = '0$digits';

    // 'rw' prefix makes it a valid email local part
    return 'rw$digits@ecyamunara.rw';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});
