// lib/core/services/session_service.dart
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  SessionService._();
  static final SessionService instance = SessionService._();

  static const _keyLastActive = 'session_last_active';
  static const _keyRole = 'session_role';

  static const _clientTimeout = Duration(days: 30);
  static const _adminTimeout = Duration(hours: 8);
  static const _superAdminTimeout = Duration(hours: 4);

  Timer? _timer;

  Future<void> startSession(String role) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyRole, role);
    await p.setInt(_keyLastActive, DateTime.now().millisecondsSinceEpoch);
    _startTimer(role);
  }

  Future<void> touchSession() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyLastActive, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> checkAndEnforceExpiry() async {
    final p = await SharedPreferences.getInstance();
    final role = p.getString(_keyRole);
    if (role == null) return false;
    final last = p.getInt(_keyLastActive);
    if (last == null) return false;
    final expired =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) >
        _timeoutForRole(role);
    if (expired) {
      await _forceLogout(p);
      return true;
    }
    _startTimer(role);
    return false;
  }

  Future<void> clearSession() async {
    _timer?.cancel();
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyLastActive);
    await p.remove(_keyRole);
  }

  void _startTimer(String role) {
    _timer?.cancel();
    _timer = Timer(_timeoutForRole(role), () async {
      final p = await SharedPreferences.getInstance();
      await _forceLogout(p);
    });
  }

  Future<void> _forceLogout(SharedPreferences p) async {
    await Supabase.instance.client.auth.signOut();
    await p.remove(_keyLastActive);
    await p.remove(_keyRole);
    _timer?.cancel();
  }

  Duration _timeoutForRole(String role) => switch (role) {
    'super_admin' => _superAdminTimeout,
    'region_admin' => _adminTimeout,
    _ => _clientTimeout,
  };
}
