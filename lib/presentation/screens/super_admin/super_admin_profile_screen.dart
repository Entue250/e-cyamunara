// lib/presentation/screens/super_admin/super_admin_profile_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart' show AppRoutes;
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/localization/language_service.dart';
import 'super_admin_providers.dart';
import '../../providers/providers.dart' show localeProvider;
import 'super_admin_shared.dart';

// ════════════════════════════════════════════════════════════════════════════
// SUPER ADMIN PROFILE — Full CRUD with photo and password management
// ════════════════════════════════════════════════════════════════════════════
class SuperAdminProfileScreen extends ConsumerStatefulWidget {
  const SuperAdminProfileScreen({super.key});

  @override
  ConsumerState<SuperAdminProfileScreen> createState() =>
      _SuperAdminProfileScreenState();
}

class _SuperAdminProfileScreenState
    extends ConsumerState<SuperAdminProfileScreen> {
  // ── Controllers
  final _nameCtrl      = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _newPwCtrl     = TextEditingController();
  final _confirmPwCtrl = TextEditingController();

  // ── UI state
  bool _editMode    = false;
  bool _changingPw  = false;
  bool _isSaving    = false;
  bool _isSavingPw  = false;
  bool _obscureNew  = true;
  bool _obscureCfm  = true;

  // ── Loaded data
  String  _displayName   = '';
  String  _displayPhone  = '';
  String  _displayStatus = 'ACTIVE';
  String? _photoUrl;
  String? _localPhotoPath;

  @override
  void initState() {
    super.initState();
    // Load profile data once after the first frame — safe to call in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _newPwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  // ── Load profile from Supabase ────────────────────────────────────────────
  Future<void> _loadProfile() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from(SupabaseConstants.superAdminsTable)
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _displayName   = data['full_names']    as String? ?? 'Super Admin';
          _displayPhone  = data['phone_number']  as String? ?? '';
          _displayStatus = (data['account_status'] as String? ?? 'active')
              .toUpperCase();
          _photoUrl      = data['photo_url']     as String?;
          _nameCtrl.text  = _displayName;
          _phoneCtrl.text = _displayPhone;
        });
      }
    } catch (_) {
      // Silently ignore — display defaults remain in place
    }
  }

  // ── Save profile changes ──────────────────────────────────────────────────
  //
  // Design:
  //   • Photo upload is isolated — a storage failure shows a specific message
  //     but does NOT abort the text-field update.
  //   • DB update is the single atomic commit: text fields + photo URL together.
  //   • If the DB update itself fails, _isSaving is reset and the user can retry
  //     without the photo being re-uploaded (file already exists in storage at
  //     the same path; upsert: true means the next retry just overwrites it).
  //   • Cache-busting via a timestamp query param ensures Image.network shows
  //     the freshly uploaded photo instead of its cached predecessor.
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

      // ── Step 1: Upload photo (isolated — failure does not abort text update)
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
          // Store the clean URL in DB; add a cache-buster for immediate display.
          final baseUrl = Supabase.instance.client.storage
              .from(SupabaseConstants.profilePhotosBucket)
              .getPublicUrl(fileName);
          newPhotoUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        } catch (e) {
          photoError = e.toString();
        }
      }

      // ── Step 2: Commit to DB (text fields + photo URL if upload succeeded)
      //    Both photo_url and updated_at exist after migration 20260427000000.
      await Supabase.instance.client
          .from(SupabaseConstants.superAdminsTable)
          .update({
            'full_names':   _nameCtrl.text.trim(),
            'phone_number': _phoneCtrl.text.trim(),
            'updated_at':   DateTime.now().toIso8601String(),
            'photo_url':    ?newPhotoUrl,
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

  // ── Change password ───────────────────────────────────────────────────────
  Future<void> _changePassword() async {
    final newPw = _newPwCtrl.text;
    if (newPw != _confirmPwCtrl.text) {
      _snack(context.l10n.validatorPasswordsNoMatch, error: true);
      return;
    }
    if (newPw.length < 8) {
      _snack(context.l10n.validatorPasswordTooShort, error: true);
      return;
    }
    final successMsg = context.l10n.passwordChangedSuccess;
    final failMsg    = context.l10n.passwordChangeFailed;
    setState(() => _isSavingPw = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: newPw));
      _newPwCtrl.clear();
      _confirmPwCtrl.clear();
      setState(() {
        _changingPw = false;
        _isSavingPw = false;
      });
      _snack(successMsg);
    } catch (e) {
      setState(() => _isSavingPw = false);
      _snack(failMsg(e.toString()), error: true);
    }
  }

  // ── Pick avatar photo ─────────────────────────────────────────────────────
  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      imageQuality: 80,
    );
    if (f != null) setState(() => _localPhotoPath = f.path);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(context.l10n.selectLanguage,
                style: AppTextStyles.h1),
            const Divider(),
            ...LanguageService.supportedLocales.map((locale) {
              final name = LanguageService.languageNames[locale.languageCode]
                  ?? locale.languageCode;
              final isCurrent =
                  ref.read(localeProvider).languageCode == locale.languageCode;
              return ListTile(
                title: Text(name),
                trailing: isCurrent
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
      ),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final adminsAsync = ref.watch(superAdminAllAdminsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Collapsible blue header ───────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primaryBlue,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white),
              onPressed: () => context.go(AppRoutes.superDashboard),
            ),
            title: Text(
              _editMode ? context.l10n.editProfile : context.l10n.superAdminProfile,
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
                          : Text(context.l10n.save,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                              )),
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 56),
                    // Avatar
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
                            child: ClipOval(child: _avatarChild()),
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
                    // Name (inline edit in edit mode)
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
                            _displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    const SizedBox(height: 6),
                    const SuperAdminBadge(),
                    const SizedBox(height: 4),
                    Text(
                      _displayPhone,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Stats strip ─────────────────────────────────────────
                  adminsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (admins) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          ProfileStatCell(
                              context.l10n.adminsBadge, '${admins.length}'),
                          const StatDivider(),
                          ProfileStatCell(
                            context.l10n.activeBadge,
                            '${admins.where((a) => a.isActive).length}',
                          ),
                          const StatDivider(),
                          ProfileStatCell(context.l10n.regionsCount, '5'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Account information ─────────────────────────────────
                  Text(context.l10n.accountInformation,
                      style: AppTextStyles.labelGold),
                  const SizedBox(height: 12),
                  if (_editMode)
                    Column(
                      children: [
                        EditFieldRow(
                          icon: Icons.person_outline,
                          label: context.l10n.fullNames,
                          controller: _nameCtrl,
                        ),
                        EditFieldRow(
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
                        InfoDisplayRow(
                          icon: Icons.person_outline,
                          label: context.l10n.fullNames,
                          value: _displayName,
                        ),
                        InfoDisplayRow(
                          icon: Icons.phone_outlined,
                          label: context.l10n.phoneNumber,
                          value: _displayPhone,
                        ),
                        InfoDisplayRow(
                          icon: Icons.verified_user_outlined,
                          label: context.l10n.roleLabel,
                          value: context.l10n.superAdministrator,
                          showChevron: false,
                        ),
                        InfoDisplayRow(
                          icon: Icons.shield_outlined,
                          label: context.l10n.authorityLabel,
                          value: context.l10n.nationalLevelRnp,
                          showChevron: false,
                        ),
                        InfoDisplayRow(
                          icon: Icons.circle,
                          label: context.l10n.accountStatusLabel,
                          value: _displayStatus,
                          showChevron: false,
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // ── System access ───────────────────────────────────────
                  Text(context.l10n.systemAccess,
                      style: AppTextStyles.labelGold),
                  const SizedBox(height: 12),
                  PermissionDisplayRow(
                      context.l10n.manageRegionAdminsPermission, true),
                  PermissionDisplayRow(
                      context.l10n.viewAllRegionsPermission, true),
                  PermissionDisplayRow(context.l10n.nationalReports, true),
                  PermissionDisplayRow(
                      context.l10n.systemConfigPermission, true),
                  PermissionDisplayRow(context.l10n.auditLogsPermission, true),
                  const SizedBox(height: 20),

                  // ── Security / password ─────────────────────────────────
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
                          border: Border.all(color: AppColors.border),
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
                                  Text(context.l10n.updatePasswordDesc,
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
                        borderRadius: BorderRadius.circular(AppRadius.lg),
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
                                icon: Icon(_obscureNew
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(
                                    () => _obscureNew = !_obscureNew),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmPwCtrl,
                            obscureText: _obscureCfm,
                            decoration: InputDecoration(
                              labelText: context.l10n.confirmNewPassword,
                              prefixIcon:
                                  const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureCfm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
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
                                    _confirmPwCtrl.clear();
                                    setState(() =>
                                        _changingPw = false);
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
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
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

                  // ── Language ────────────────────────────────────────────
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
                            child: Text(context.l10n.selectLanguage,
                                style: AppTextStyles.bodyLarge),
                          ),
                          Text(
                            LanguageService.languageNames[
                                    ref.watch(localeProvider).languageCode] ??
                                ref.watch(localeProvider).languageCode,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Logout ──────────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(),
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
                        side: const BorderSide(color: AppColors.error),
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
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 3),
    );
  }

  // ── Avatar widget helper ──────────────────────────────────────────────────
  Widget _avatarChild() {
    if (_localPhotoPath != null) {
      return Image.file(File(_localPhotoPath!), fit: BoxFit.cover);
    }
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return Image.network(
        _photoUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _defaultAvatar(),
        errorBuilder: (_, _, _) => _defaultAvatar(),
      );
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() => Container(
        color: AppColors.gold,
        child: const Icon(Icons.star,
            color: AppColors.primaryBlue, size: 40),
      );

  // ── Logout confirmation ───────────────────────────────────────────────────
  Future<void> _confirmLogout() async {
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
    if (ok != true) return;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    context.go(AppRoutes.adminLogin);
  }
}
