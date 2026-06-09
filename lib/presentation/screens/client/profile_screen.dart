// lib/presentation/screens/client/profile_screen.dart
//
// ─── SCREEN 9: MY PROFILE ─────────────────────────────────────────────────────
// Shows: Dark blue SliverAppBar with avatar + name + ACTIVE CLIENT badge + phone,
//        stats row (Total Bids, Won, Joined year), Account Information section,
//        Preferences section (Notifications toggle, Language, Auction Region),
//        Change Password, Support links, LOGOUT button.
//
// Edit: tapping the pencil icon opens _EditProfileSheet (name, phone, photo).
// Stats: real counts from clientStatsProvider (not denormalized columns).
// National ID: decrypted + masked from DB.
// Support: Privacy Policy, Help Center, About show dialogs.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../app_router.dart';
import 'client_shared.dart';
import 'client_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _notificationsEnabled = true;

  // ── Logout ─────────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.logoutTitle),
        content: Text(l10n.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.logout,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final failure = await ref.read(logoutUseCaseProvider).call();
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    } else {
      context.go(AppRoutes.login);
    }
  }

  // ── Change Password bottom sheet ────────────────────────────────────────────
  void _showChangePasswordSheet(String phoneNumber) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangePasswordSheet(phoneNumber: phoneNumber),
    );
  }

  // ── Edit Profile bottom sheet ───────────────────────────────────────────────
  void _showEditProfileSheet(UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(user: user),
    );
  }

  // ── Language picker ──────────────────────────────────────────────────────────
  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l10n.language, style: AppTextStyles.h2),
            const SizedBox(height: 16),
            ...LanguageService.supportedLocales.map((locale) {
              final name = LanguageService.languageNames[locale.languageCode] ?? locale.languageCode;
              final isCurrent = ref.read(localeProvider).languageCode == locale.languageCode;
              return ListTile(
                leading: Icon(
                  isCurrent ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: AppColors.primaryBlue,
                ),
                title: Text(name, style: AppTextStyles.bodyLarge),
                onTap: () {
                  ref.read(localeProvider.notifier).setLocale(locale);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Support dialogs ─────────────────────────────────────────────────────────
  void _showPrivacyPolicy() => _showInfoDialog(
        'Privacy Policy',
        'E-Cyamunara collects and processes your personal information '
            '(name, phone number, National ID) solely for the purpose of '
            'managing auction participation on behalf of Rwanda National Police.\n\n'
            'Your data is stored securely in an encrypted database and is never '
            'sold or shared with third parties. National IDs are encrypted with '
            'AES-256 before storage.\n\n'
            'You may request account deletion by contacting support.',
      );

  void _showHelpCenter() => _showInfoDialog(
        'Help Center',
        'For assistance with your account or auctions, contact us:\n\n'
            '📞 Phone: +250 788 311 009\n'
            '📧 Email: support@rnp.gov.rw\n'
            '🏛️ Office: Rwanda National Police HQ, Kigali\n\n'
            'Operating hours: Monday–Friday, 08:00–17:00 (CAT)',
      );

  void _showAbout() => _showInfoDialog(
        'About E-Cyamunara',
        'E-Cyamunara is the official vehicle auction platform of the '
            'Rwanda National Police (RNP).\n\n'
            'Version 1.0.0\n\n'
            'The platform enables transparent online bidding for impounded, '
            'confiscated, and state vehicles across all five regions of Rwanda.\n\n'
            '© 2026 Rwanda National Police. All rights reserved.',
      );

  void _showInfoDialog(String title, String content) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: AppTextStyles.h2),
          content: SingleChildScrollView(
            child: Text(content, style: AppTextStyles.bodyMedium),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.close.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  // ── Mask National ID for display ────────────────────────────────────────────
  String _maskedNationalId(String encrypted) {
    if (encrypted.isEmpty) return '••••••••••••••••';
    try {
      final plain = EncryptionService.instance.decrypt(encrypted);
      if (plain.isEmpty) return '••••••••••••••••';
      if (plain.length <= 6) return plain;
      final visible = plain.substring(0, 4);
      final last2   = plain.substring(plain.length - 2);
      final masked  = '•' * (plain.length - 6);
      return '$visible$masked$last2';
    } catch (_) {
      return '••••••••••••••••';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;
    final uid = user?.uid ?? '';

    // Real stats — falls back to user model values while loading
    final statsAsync = uid.isNotEmpty
        ? ref.watch(clientStatsProvider(uid))
        : const AsyncData<Map<String, int>>({'bids': 0, 'won': 0});
    final totalBids = statsAsync.value?['bids'] ?? user?.totalBidsPlaced ?? 0;
    final totalWon  = statsAsync.value?['won']  ?? user?.totalAuctionsWon ?? 0;

    final l10n = context.l10n;
    final locale = ref.watch(localeProvider);
    final currentLangName = LanguageService.languageNames[locale.languageCode] ?? locale.languageCode;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: user == null
          ? const Center(child: RnpLoadingWidget())
          : CustomScrollView(
              slivers: [
                // ── Blue collapsible header ─────────────────────────────────
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: AppColors.primaryBlue,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white),
                    onPressed: () => context.go(AppRoutes.home),
                  ),
                  title: Text(l10n.myProfile,
                      style: const TextStyle(color: Colors.white)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white),
                      tooltip: l10n.editProfile,
                      onPressed: () => _showEditProfileSheet(user),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.darkBlue, AppColors.primaryBlue],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 60),
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.white24,
                                backgroundImage: user.profilePhotoUrl != null
                                    ? NetworkImage(user.profilePhotoUrl!)
                                    : null,
                                child: user.profilePhotoUrl == null
                                    ? const Icon(Icons.person,
                                        size: 40, color: Colors.white)
                                    : null,
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            user.fullNames,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              l10n.activeClient,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppFormatters.phone(user.phoneNumber),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Profile content ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Stats row ────────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              _ProfileStat(l10n.totalBids,
                                  '$totalBids',
                                  AppColors.textPrimary),
                              Container(
                                  width: 1,
                                  height: 40,
                                  color: AppColors.border),
                              _ProfileStat(l10n.won, '$totalWon',
                                  AppColors.darkGold,
                                  highlight: true),
                              Container(
                                  width: 1,
                                  height: 40,
                                  color: AppColors.border),
                              _ProfileStat(l10n.joined,
                                  '${user.createdAt.year}',
                                  AppColors.textPrimary),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Account Information ──────────────────────────────
                        Text(l10n.accountInformation,
                            style: AppTextStyles.labelGold),
                        const SizedBox(height: 12),

                        _InfoItem(Icons.person_outline, l10n.fullNames,
                            user.fullNames),
                        _InfoItem(Icons.badge_outlined, l10n.nationalId,
                            _maskedNationalId(user.nationalId)),
                        _InfoItem(Icons.phone_outlined, l10n.phoneNumber,
                            AppFormatters.phone(user.phoneNumber)),
                        _InfoItem(Icons.location_on_outlined, l10n.districtLabel,
                            '${user.district}, ${user.province}'),

                        const SizedBox(height: 24),

                        // ── Preferences ──────────────────────────────────────
                        Text(l10n.preferences,
                            style: AppTextStyles.labelGold),
                        const SizedBox(height: 12),

                        // Notifications toggle
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.notifications_outlined,
                                  size: 20, color: AppColors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(l10n.notifications,
                                    style: AppTextStyles.bodyLarge),
                              ),
                              Switch(
                                value: _notificationsEnabled,
                                activeThumbColor: AppColors.primaryBlue,
                                onChanged: (v) =>
                                    setState(() => _notificationsEnabled = v),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        _TapPrefItem(
                          Icons.language_outlined,
                          l10n.language,
                          currentLangName,
                          onTap: () => _showLanguagePicker(context, ref),
                        ),
                        // Tapping region navigates to region select
                        _TapPrefItem(
                          Icons.location_city_outlined,
                          l10n.auctionRegion,
                          user.region,
                          onTap: () => context.go(AppRoutes.regionSelect),
                        ),

                        const SizedBox(height: 24),

                        // ── Security ──────────────────────────────────────────
                        Text(l10n.security, style: AppTextStyles.labelGold),
                        const SizedBox(height: 12),

                        GestureDetector(
                          onTap: () =>
                              _showChangePasswordSheet(user.phoneNumber),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
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
                                  child: Text(l10n.changePassword,
                                      style: AppTextStyles.bodyLarge),
                                ),
                                const Icon(Icons.chevron_right,
                                    color: AppColors.textSecondary, size: 20),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── Support ──────────────────────────────────────────
                        Text(l10n.support, style: AppTextStyles.labelGold),
                        const SizedBox(height: 12),

                        _TapPrefItem(
                          Icons.privacy_tip_outlined,
                          l10n.privacyPolicy,
                          '',
                          onTap: _showPrivacyPolicy,
                        ),
                        _TapPrefItem(
                          Icons.help_outline,
                          l10n.helpCenter,
                          '',
                          onTap: _showHelpCenter,
                        ),
                        _TapPrefItem(
                          Icons.info_outline,
                          l10n.aboutApp,
                          '',
                          onTap: _showAbout,
                        ),

                        const SizedBox(height: 24),

                        // ── LOGOUT button ────────────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _handleLogout,
                            icon: const Icon(Icons.logout,
                                color: AppColors.error),
                            label: Text(
                              l10n.logout,
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.error, width: 1.5),
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
      bottomNavigationBar: const ClientBottomNav(currentIndex: 3),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit Profile bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.user});
  final UserModel user;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  String? _localPhotoPath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.user.fullNames);
    _phoneCtrl = TextEditingController(text: widget.user.phoneNumber);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      imageQuality: 80,
    );
    if (img == null) return;
    setState(() => _localPhotoPath = img.path);
  }

  Future<void> _save() async {
    final name  = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Full name cannot be empty', error: true);
      return;
    }
    setState(() => _isSaving = true);

    String? newPhotoUrl;
    String? photoError;
    final uid = widget.user.uid;

    try {
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
          final base = Supabase.instance.client.storage
              .from(SupabaseConstants.profilePhotosBucket)
              .getPublicUrl(fileName);
          newPhotoUrl = '$base?t=${DateTime.now().millisecondsSinceEpoch}';
        } catch (e) {
          photoError = e.toString();
        }
      }

      // Step 2 — commit to DB
      await Supabase.instance.client
          .from(SupabaseConstants.usersTable)
          .update({
            'full_names':   name,
            'phone_number': phone,
            'updated_at':   DateTime.now().toIso8601String(),
            'profile_photo_url': ?newPhotoUrl,
          })
          .eq('id', uid);

      // Refresh providers
      ref.invalidate(currentUserProvider);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(photoError != null
              ? context.l10n.profileUpdatedPhotoFailed
              : context.l10n.profileUpdatedSuccess),
          backgroundColor:
              photoError != null ? AppColors.warning : AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack('Update failed: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(context.l10n.editProfile, style: AppTextStyles.h1),
              ),
              const SizedBox(height: 20),

              // Avatar pick row
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: AppColors.surfaceGrey,
                        backgroundImage: _localPhotoPath != null
                            ? FileImage(File(_localPhotoPath!))
                            : (widget.user.profilePhotoUrl != null
                                ? NetworkImage(widget.user.profilePhotoUrl!)
                                    as ImageProvider
                                : null),
                        child: (_localPhotoPath == null &&
                                widget.user.profilePhotoUrl == null)
                            ? const Icon(Icons.person,
                                size: 44, color: AppColors.textSecondary)
                            : null,
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Name field
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.fullName,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),

              // Phone field
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.l10n.phoneNumberLabel,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(context.l10n.saveChanges,
                          style: AppTextStyles.button),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Change Password bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet({required this.phoneNumber});
  final String phoneNumber;

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newPw   = _newPasswordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    final pwError = AppValidators.validatePassword(newPw);
    if (pwError != null) {
      _showError(pwError);
      return;
    }
    if (newPw != confirm) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    final failure = await ref.read(forgotPasswordUseCaseProvider).call(
          phoneNumber: widget.phoneNumber,
          newPassword: newPw,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (failure != null) {
      _showError(failure.message);
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.passwordChangedSuccess),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(context.l10n.changePassword, style: AppTextStyles.h1),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  context.l10n.enterConfirmNewPassword,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _newPasswordCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: context.l10n.newPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: context.l10n.confirmNewPassword,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text(context.l10n.changePasswordButton,
                          style: AppTextStyles.button),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileStat extends StatelessWidget {
  const _ProfileStat(this.label, this.value, this.color,
      {this.highlight = false});
  final String label, value;
  final Color color;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          color: highlight ? AppColors.gold.withValues(alpha: 0.08) : null,
          child: Column(
            children: [
              Text(label, style: AppTextStyles.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
}

class _InfoItem extends StatelessWidget {
  const _InfoItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.bodySmall),
                  const SizedBox(height: 2),
                  Text(value, style: AppTextStyles.h3),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TapPrefItem extends StatelessWidget {
  const _TapPrefItem(this.icon, this.label, this.value,
      {required this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppTextStyles.bodyLarge)),
              if (value.isNotEmpty)
                Text(value, style: AppTextStyles.bodyMedium),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      );
}
