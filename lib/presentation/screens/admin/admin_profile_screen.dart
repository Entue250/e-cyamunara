// lib/presentation/screens/admin/admin_profile_screen.dart
//
// SCREEN 19 — REGION ADMIN PROFILE (Full CRUD)
// Supports: view, edit (name, phone, photo), change password, logout.
// Permissions section is always read-only (only super admin can change these).
//
// Pattern mirrors SuperAdminProfileScreen — local state drives the UI,
// _loadProfile() fetches fresh data, ref.invalidate keeps the router in sync.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart' show AppRoutes;
import '../../providers/providers.dart' show currentAdminProvider, localeProvider;
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/localization/language_service.dart';
import '../../../core/utils/date_notification_helpers.dart';
import 'admin_shared.dart';

class AdminProfileScreen extends ConsumerStatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  ConsumerState<AdminProfileScreen> createState() =>
      _AdminProfileScreenState();
}

class _AdminProfileScreenState extends ConsumerState<AdminProfileScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _cfmPwCtrl = TextEditingController();

  // ── UI state ────────────────────────────────────────────────────────────────
  bool _editMode   = false;
  bool _changingPw = false;
  bool _isSaving   = false;
  bool _isSavingPw = false;
  bool _obscureNew = true;
  bool _obscureCfm = true;
  bool _loadError  = false;

  // ── Display data (local state — loaded once, mutated on save) ───────────────
  String  _displayName   = '';
  String  _displayPhone  = '';
  String  _displayRegion = '';
  String  _displayStatus = '';
  int     _displayPosted = 0;
  int     _displayClosed = 0;
  String? _photoUrl;
  String? _localPhotoPath;

  // ── Permissions (read-only) ─────────────────────────────────────────────────
  bool _canPostAuctions  = true;
  bool _canManageClients = true;
  bool _canViewReports   = true;
  bool _canCloseAuctions = true;

  // ── Dates ───────────────────────────────────────────────────────────────────
  DateTime? _createdAt;
  DateTime? _lastLogin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _newPwCtrl.dispose();
    _cfmPwCtrl.dispose();
    super.dispose();
  }

  // ── Fetch profile from Supabase ─────────────────────────────────────────────
  Future<void> _loadProfile() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Run profile + actual auction counts in parallel
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from(SupabaseConstants.regionAdminsTable)
            .select()
            .eq('id', uid)
            .maybeSingle(),
        Supabase.instance.client
            .from(SupabaseConstants.auctionsTable)
            .select('id')
            .eq('posted_by_admin_uid', uid),
        Supabase.instance.client
            .from(SupabaseConstants.auctionsTable)
            .select('id')
            .eq('posted_by_admin_uid', uid)
            .eq('auction_status', SupabaseConstants.statusClosed),
      ]);

      final data   = results[0] as Map<String, dynamic>?;
      if (data == null || !mounted) return;

      final posted = (results[1] as List).length;
      final closed = (results[2] as List).length;

      final perms = (data['permissions'] as Map<String, dynamic>?) ?? {};
      setState(() {
        _displayName   = data['full_names']    as String? ?? '';
        _displayPhone  = data['phone_number']  as String? ?? '';
        _displayRegion = data['region']        as String? ?? '';
        _displayStatus = (data['account_status'] as String? ?? 'active')
            .toUpperCase();
        _displayPosted = posted;
        _displayClosed = closed;
        _photoUrl      = data['profile_photo_url'] as String?;

        _canPostAuctions  = perms['post_auctions']  as bool? ?? true;
        _canManageClients = perms['manage_clients'] as bool? ?? true;
        _canViewReports   = perms['view_reports']   as bool? ?? true;
        _canCloseAuctions = perms['close_auctions'] as bool? ?? true;

        final rawCreated   = data['created_at']  as String?;
        final rawLastLogin = data['last_login']  as String?;
        _createdAt = rawCreated   != null ? DateTime.parse(rawCreated)   : null;
        _lastLogin = rawLastLogin != null ? DateTime.parse(rawLastLogin) : null;

        _nameCtrl.text  = _displayName;
        _phoneCtrl.text = _displayPhone;
        _loadError = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
  }

  // ── Save profile (name + phone + optional photo) ────────────────────────────
  //
  // Photo upload is isolated: a storage failure shows a warning but does NOT
  // abort the text-field update. DB update is the single atomic commit.
  // upsert:true on the storage upload means retry is safe — same file path.
  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack(context.l10n.fullNameEmpty, error: true);
      return;
    }
    setState(() => _isSaving = true);

    String? newPhotoUrl;
    String? photoError;

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      // Step 1 — upload photo (isolated failure)
      if (_localPhotoPath != null) {
        try {
          final bytes    = await File(_localPhotoPath!).readAsBytes();
          final fileName = '$uid/avatar.jpg';
          await Supabase.instance.client.storage
              .from(SupabaseConstants.profilePhotosBucket)
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          final baseUrl = Supabase.instance.client.storage
              .from(SupabaseConstants.profilePhotosBucket)
              .getPublicUrl(fileName);
          // Cache-bust so Image.network shows the new photo immediately.
          newPhotoUrl =
              '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        } catch (e) {
          photoError = e.toString();
        }
      }

      // Step 2 — commit to DB
      await Supabase.instance.client
          .from(SupabaseConstants.regionAdminsTable)
          .update({
            'full_names':   _nameCtrl.text.trim(),
            'phone_number': _phoneCtrl.text.trim(),
            'updated_at':   DateTime.now().toIso8601String(),
            'profile_photo_url': ?newPhotoUrl,
          })
          .eq('id', uid);

      if (!mounted) return;
      setState(() {
        _displayName  = _nameCtrl.text.trim();
        _displayPhone = _phoneCtrl.text.trim();
        if (newPhotoUrl != null) _photoUrl = newPhotoUrl;
        _localPhotoPath = null;
        _editMode       = false;
        _isSaving       = false;
      });

      // Keep router redirect and other screens in sync.
      ref.invalidate(currentAdminProvider);

      if (photoError != null) {
        _snack(context.l10n.profileUpdatedPhotoFailed, error: true);
      } else {
        _snack(context.l10n.profileUpdatedSuccess);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack(context.l10n.updateFailed(e.toString()), error: true);
    }
  }

  // ── Change password ─────────────────────────────────────────────────────────
  Future<void> _changePassword() async {
    final newPw = _newPwCtrl.text;
    if (newPw != _cfmPwCtrl.text) {
      _snack(context.l10n.validatorPasswordsNoMatch, error: true);
      return;
    }
    if (newPw.length < 8) {
      _snack(context.l10n.validatorPasswordTooShort, error: true);
      return;
    }
    setState(() => _isSavingPw = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newPw));
      _newPwCtrl.clear();
      _cfmPwCtrl.clear();
      if (!mounted) return;
      setState(() {
        _changingPw = false;
        _isSavingPw = false;
      });
      _snack(context.l10n.passwordChangedSuccess);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingPw = false);
      _snack(context.l10n.passwordChangeFailed(e.toString()), error: true);
    }
  }

  // ── Pick photo from gallery ─────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 80,
    );
    if (f != null && mounted) setState(() => _localPhotoPath = f.path);
  }

  void _cancelEdit() {
    _nameCtrl.text  = _displayName;
    _phoneCtrl.text = _displayPhone;
    setState(() {
      _editMode       = false;
      _localPhotoPath = null;
    });
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) {
        final current = ref.read(localeProvider);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.selectLanguage, style: AppTextStyles.h1),
              const SizedBox(height: 16),
              ...LanguageService.supportedLocales.map((locale) {
                final isSelected = locale.languageCode == current.languageCode;
                return ListTile(
                  leading: Icon(
                    Icons.language,
                    color: isSelected
                        ? AppColors.primaryBlue
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    LanguageService.languageNames[locale.languageCode] ?? locale.languageCode,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primaryBlue
                          : AppColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primaryBlue)
                      : null,
                  onTap: () {
                    ref.read(localeProvider.notifier).setLocale(locale);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Avatar widget ──────────────────────────────────────────────────────────
  Widget _avatarWidget() {
    if (_localPhotoPath != null) {
      return Image.file(File(_localPhotoPath!), fit: BoxFit.cover);
    }
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return Image.network(
        _photoUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _initialsWidget(),
        errorBuilder: (context, _, stack) => _initialsWidget(),
      );
    }
    return _initialsWidget();
  }

  Widget _initialsWidget() {
    final initials = _displayName
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0] : '')
        .join()
        .toUpperCase();
    return Container(
      color: AppColors.gold,
      child: Center(
        child: Text(
          initials.isEmpty ? 'A' : initials,
          style: const TextStyle(
            color: AppColors.primaryBlue,
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // ── Logout confirmation ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.logoutTitle),
        content: Text(context.l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.logoutTitle,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go(AppRoutes.adminLogin);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _displayStatus == 'SUSPENDED'
        ? AppColors.error
        : AppColors.success;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentAdminProvider);
          await _loadProfile();
        },
        child: CustomScrollView(
          slivers: [
            // ── Expandable gradient header ─────────────────────────────────
            SliverAppBar(
              expandedHeight: 260,
              pinned: true,
              backgroundColor: AppColors.primaryBlue,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new,
                    color: Colors.white),
                onPressed: () => context.go(AppRoutes.adminDashboard),
              ),
              title: Text(
                _editMode ? context.l10n.editProfile : context.l10n.adminProfile,
                style: const TextStyle(color: Colors.white),
              ),
              actions: _editMode
                  ? [
                      TextButton(
                        onPressed: _cancelEdit,
                        child: Text(context.l10n.cancel,
                            style: const TextStyle(color: Colors.white70)),
                      ),
                      TextButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                context.l10n.save,
                                style: const TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ]
                  : [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            color: Colors.white),
                        onPressed: () => setState(() => _editMode = true),
                        tooltip: context.l10n.editProfile,
                      ),
                    ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF001040), AppColors.primaryBlue],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 56),

                        // Avatar with camera overlay in edit mode
                        Stack(
                          children: [
                            GestureDetector(
                              onTap: _editMode ? _pickPhoto : null,
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.gold, width: 3),
                                ),
                                child:
                                    ClipOval(child: _avatarWidget()),
                              ),
                            ),
                            if (_editMode)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _pickPhoto,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: AppColors.gold,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt,
                                        size: 16,
                                        color: AppColors.primaryBlue),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Name — inline TextField in edit mode
                        _editMode
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 48),
                                child: TextField(
                                  controller: _nameCtrl,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  decoration: const InputDecoration(
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: AppColors.gold),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: AppColors.gold, width: 2),
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                _displayName.isEmpty
                                    ? 'Loading…'
                                    : _displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                        const SizedBox(height: 4),
                        Text(
                          _displayPhone,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),

                        // Region badge
                        if (_displayRegion.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              '${_displayRegion.toUpperCase()} REGION ADMIN',
                              style: const TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Error banner (load failed, data may be stale) ──────
                    if (_loadError)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color:
                                  AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined,
                                size: 18, color: AppColors.error),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.l10n.profileLoadError,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.error),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadProfile,
                              child: Text(context.l10n.retry.toUpperCase()),
                            ),
                          ],
                        ),
                      ),

                    // ── Stats strip ────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            _ProfileStat(
                                '$_displayPosted', context.l10n.postedStat,
                                AppColors.primaryBlue),
                            _StatDivider(),
                            _ProfileStat(
                                '$_displayClosed', context.l10n.closedStat,
                                AppColors.darkGold),
                            _StatDivider(),
                            _ProfileStat(
                              _displayStatus.isEmpty
                                  ? '—'
                                  : _displayStatus,
                              context.l10n.statusStat,
                              statusColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Account information ────────────────────────────────
                    Text(context.l10n.accountInformation,
                        style: AppTextStyles.labelGold),
                    const SizedBox(height: 12),
                    if (_editMode)
                      Column(
                        children: [
                          AdminEditFieldRow(
                            icon: Icons.person_outline,
                            label: context.l10n.fullNames,
                            controller: _nameCtrl,
                          ),
                          AdminEditFieldRow(
                            icon: Icons.phone_outlined,
                            label: context.l10n.phoneNumber,
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          AdminInfoRow(
                            icon: Icons.person_outline,
                            label: context.l10n.fullNames,
                            value: _displayName.isEmpty ? '—' : _displayName,
                          ),
                          AdminInfoRow(
                            icon: Icons.phone_outlined,
                            label: context.l10n.phoneNumber,
                            value: _displayPhone.isEmpty
                                ? '—'
                                : _displayPhone,
                          ),
                          AdminInfoRow(
                            icon: Icons.map_outlined,
                            label: context.l10n.region,
                            value: _displayRegion.isEmpty
                                ? '—'
                                : context.l10n.regionLabel(_displayRegion),
                          ),
                          AdminInfoRow(
                            icon: Icons.badge_outlined,
                            label: context.l10n.roleLabel,
                            value: context.l10n.regionAdmin,
                          ),
                          AdminInfoRow(
                            icon: Icons.verified_user_outlined,
                            label: context.l10n.accountStatusLabel,
                            value: _displayStatus.isEmpty
                                ? '—'
                                : _displayStatus,
                            valueColor: _displayStatus.isEmpty
                                ? null
                                : statusColor,
                          ),
                          if (_createdAt != null)
                            AdminInfoRow(
                              icon: Icons.calendar_today_outlined,
                              label: context.l10n.memberSince,
                              value: DateHelper.formatDate(_createdAt!),
                            ),
                          AdminInfoRow(
                            icon: Icons.login_outlined,
                            label: context.l10n.lastLogin,
                            value: _lastLogin != null
                                ? DateHelper.formatDateTime(_lastLogin!)
                                : context.l10n.neverRecorded,
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    // ── Permissions (read-only) ────────────────────────────
                    Text(context.l10n.permissions,
                        style: AppTextStyles.labelGold),
                    const SizedBox(height: 12),
                    AdminPermRow(Icons.gavel_outlined,
                        context.l10n.postAuctionsPermission, _canPostAuctions),
                    AdminPermRow(Icons.group_outlined,
                        context.l10n.manageClientsPermission, _canManageClients),
                    AdminPermRow(Icons.bar_chart_outlined,
                        context.l10n.viewReportsPermission, _canViewReports),
                    AdminPermRow(Icons.lock_outline,
                        context.l10n.closeAuctionsPermission, _canCloseAuctions),
                    const SizedBox(height: 20),

                    // ── Security / password ────────────────────────────────
                    Text(context.l10n.security, style: AppTextStyles.labelGold),
                    const SizedBox(height: 12),
                    if (!_changingPw)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _changingPw = true),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border:
                                Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline,
                                  size: 18,
                                  color: AppColors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(context.l10n.changePassword,
                                        style: AppTextStyles.bodyLarge),
                                    Text(
                                        context.l10n.updatePasswordDesc,
                                        style: AppTextStyles.bodySmall),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _newPwCtrl,
                              obscureText: _obscureNew,
                              decoration: InputDecoration(
                                labelText: context.l10n.newPassword,
                                prefixIcon:
                                    const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureNew
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureNew = !_obscureNew),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _cfmPwCtrl,
                              obscureText: _obscureCfm,
                              decoration: InputDecoration(
                                labelText: context.l10n.confirmNewPassword,
                                prefixIcon:
                                    const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureCfm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureCfm = !_obscureCfm),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      _newPwCtrl.clear();
                                      _cfmPwCtrl.clear();
                                      setState(
                                          () => _changingPw = false);
                                    },
                                    child: Text(context.l10n.cancel),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isSavingPw
                                        ? null
                                        : _changePassword,
                                    child: _isSavingPw
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(context.l10n.update),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),

                    // ── Language ───────────────────────────────────────────
                    Text(context.l10n.language, style: AppTextStyles.labelGold),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showLanguagePicker,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.language,
                                size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                LanguageService.languageNames[
                                    ref.watch(localeProvider).languageCode] ??
                                    context.l10n.language,
                                style: AppTextStyles.bodyLarge,
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Logout ─────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout,
                            color: AppColors.error),
                        label: Text(
                          context.l10n.logout,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 4),
    );
  }
}

// ── Local stat widgets — used only within this screen ─────────────────────────

class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.value, this.label, this.color);
  final String value, label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: AppColors.border);
}
