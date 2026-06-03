// lib/presentation/screens/super_admin/add_edit_admin_screen.dart
//
// Handles BOTH create and edit mode:
//   Create: adminToEdit == null  → calls create-admin Edge Function
//   Edit:   adminToEdit != null  → updates region_admins table directly
//
// KEY FIX: national_id field added (was causing 400 on every creation).
// KEY FIX: temp_password shown in dialog after successful creation.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_router.dart' show AppRoutes;
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../data/models/models.dart';
import 'super_admin_providers.dart';
import 'super_admin_shared.dart';

// ════════════════════════════════════════════════════════════════════════════
// ADD / EDIT REGION ADMIN
// ════════════════════════════════════════════════════════════════════════════
class AddAdminScreen extends ConsumerStatefulWidget {
  const AddAdminScreen({super.key, this.adminToEdit});

  /// When non-null this screen operates in edit mode.
  final RegionAdminModel? adminToEdit;

  @override
  ConsumerState<AddAdminScreen> createState() => _AddAdminScreenState();
}

class _AddAdminScreenState extends ConsumerState<AddAdminScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _natIdCtrl   = TextEditingController();
  bool _isLoading    = false;
  String? _selectedRegion;

  // Permissions
  bool _canPostAuctions   = true;
  bool _canManageClients  = true;
  bool _canViewReports    = true;
  bool _canCloseAuctions  = true;

  bool get _isEdit => widget.adminToEdit != null;

  static const _regions = [
    (region: 'Central',  label: 'KIGALI CITY', icon: Icons.location_city_outlined),
    (region: 'Eastern',  label: 'EAST',         icon: Icons.explore_outlined),
    (region: 'Western',  label: 'WEST',         icon: Icons.arrow_back_outlined),
    (region: 'Northern', label: 'NORTH',         icon: Icons.arrow_upward_outlined),
    (region: 'Southern', label: 'SOUTH',         icon: Icons.arrow_downward_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (_isEdit) _prefill(widget.adminToEdit!);
  }

  void _prefill(RegionAdminModel admin) {
    _nameCtrl.text       = admin.fullNames;
    _phoneCtrl.text      = admin.phoneNumber;
    _natIdCtrl.text      = admin.nationalId;
    _selectedRegion      = admin.region;
    _canPostAuctions     = admin.permissions.postAuctions;
    _canManageClients    = admin.permissions.manageClients;
    _canViewReports      = admin.permissions.viewReports;
    _canCloseAuctions    = admin.permissions.closeAuctions;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _natIdCtrl.dispose();
    super.dispose();
  }

  // ── CREATE — calls Edge Function ──────────────────────────────────────────
  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRegion == null) {
      _snack(context.l10n.pleaseSelectRegion, error: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not authenticated — please log in again');

      final callerUid = session.user.id;

      final response = await Supabase.instance.client.functions.invoke(
        SupabaseConstants.fnCreateAdmin,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: {
          'full_names':   _nameCtrl.text.trim(),
          'national_id':  _natIdCtrl.text.trim(),
          'phone_number': _phoneCtrl.text.trim(),
          'region':       _selectedRegion!,
          'created_by':   callerUid,
          'permissions': {
            'post_auctions':   _canPostAuctions,
            'manage_clients':  _canManageClients,
            'view_reports':    _canViewReports,
            'close_auctions':  _canCloseAuctions,
          },
        },
      );

      setState(() => _isLoading = false);

      if (response.status != 200) {
        final errMsg = (response.data as Map?)?['error'] ??
            (response.data as Map?)?['message'] ??
            'Server returned ${response.status}';
        throw Exception(errMsg);
      }

      // Read the server-generated temporary password and show it
      final tempPassword =
          (response.data as Map?)?['temp_password'] as String?;

      if (!mounted) return;

      ref.invalidate(superAdminAllAdminsProvider);
      await _showTempPasswordDialog(
          _nameCtrl.text.trim(), _selectedRegion!, tempPassword);

      if (mounted) context.go(AppRoutes.manageAdmins);
    } catch (e) {
      setState(() => _isLoading = false);
      _snack(context.l10n.creationFailed(e.toString()), error: true);
    }
  }

  // ── EDIT — updates DB directly (no Edge Function needed) ─────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final admin = widget.adminToEdit!;
      await Supabase.instance.client
          .from(SupabaseConstants.regionAdminsTable)
          .update({
            'full_names':   _nameCtrl.text.trim(),
            'phone_number': _phoneCtrl.text.trim(),
            'permissions': {
              'post_auctions':   _canPostAuctions,
              'manage_clients':  _canManageClients,
              'view_reports':    _canViewReports,
              'close_auctions':  _canCloseAuctions,
            },
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', admin.uid);

      setState(() => _isLoading = false);
      if (!mounted) return;
      ref.invalidate(superAdminAllAdminsProvider);
      _snack(context.l10n.adminUpdatedSuccess);
      context.go(AppRoutes.manageAdmins);
    } catch (e) {
      setState(() => _isLoading = false);
      _snack(context.l10n.failedToUpdateAdmin(e.toString()), error: true);
    }
  }

  Future<void> _submit() => _isEdit ? _save() : _create();

  // ── Show temp password dialog ─────────────────────────────────────────────
  Future<void> _showTempPasswordDialog(
    String name,
    String region,
    String? tempPassword,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            Text(context.l10n.adminCreated),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.adminCreatedFor(name, region)),
            const SizedBox(height: 16),
            if (tempPassword != null) ...[
              Text(
                context.l10n.temporaryPassword,
                style: AppTextStyles.labelGold,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tempPassword,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: context.l10n.copyPassword,
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: tempPassword));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(context.l10n.passwordCopied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.savePasswordWarning,
                style: AppTextStyles.bodySmall,
              ),
            ] else
              Text(
                context.l10n.temporaryPasswordNote,
                style: AppTextStyles.bodySmall,
              ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.done),
          ),
        ],
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(_isEdit ? context.l10n.editRegionAdmin : context.l10n.addRegionAdmin),
          leading: BackButton(
            // GoRouter uses go() for navigation so Navigator.pop() has nothing
            // to pop. Explicitly navigate back to manage admins instead.
            onPressed: () => context.go(AppRoutes.manageAdmins),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.adminInformation,
                    style: AppTextStyles.labelGold),
                const SizedBox(height: 12),

                // ── Info fields ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full name
                      Text(context.l10n.fullNames, style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Jean Damascene Uwimana',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Full name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // National ID
                      Text(context.l10n.nationalIdLabel, style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _natIdCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_isEdit, // ID is immutable after creation
                        decoration: InputDecoration(
                          hintText: '1 XXXX X XXXXXXX X XX',
                          prefixIcon:
                              const Icon(Icons.badge_outlined),
                          helperText: _isEdit
                              ? 'National ID cannot be changed after creation'
                              : null,
                          filled: _isEdit,
                          fillColor: _isEdit
                              ? AppColors.surfaceGrey
                              : null,
                        ),
                        validator: (v) {
                          if (_isEdit) { return null; }
                          if (v == null || v.trim().isEmpty) {
                            return 'National ID is required';
                          }
                          if (v.replaceAll(' ', '').length < 16) {
                            return 'National ID must be at least 16 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Phone number
                      Text(context.l10n.phoneNumber, style: AppTextStyles.h3),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '07XXXXXXXX',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          final digits = v.replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 10) {
                            return 'Enter a valid Rwandan phone number';
                          }
                          return null;
                        },
                      ),

                      // Password notice — only for create mode
                      if (!_isEdit) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color:
                                    AppColors.info.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: AppColors.info),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'A secure temporary password will be generated automatically. '
                                  'You will see it after creation.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.info,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Region assignment ────────────────────────────────────
                Text(context.l10n.regionAssignment,
                    style: AppTextStyles.labelGold),
                const SizedBox(height: 4),
                if (_isEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.l10n.regionCannotChange,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.6,
                  children: _regions.map((r) {
                    final isSel = _selectedRegion == r.region;
                    final locked = _isEdit; // can't change region on edit
                    return GestureDetector(
                      onTap: locked
                          ? null
                          : () => setState(() => _selectedRegion = r.region),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: locked
                              ? AppColors.surfaceGrey
                              : isSel
                                  ? AppColors.primaryBlue
                                      .withValues(alpha: 0.08)
                                  : AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isSel
                                ? AppColors.primaryBlue
                                : AppColors.border,
                            width: isSel ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              r.icon,
                              size: 24,
                              color: locked
                                  ? AppColors.textSecondary
                                  : isSel
                                      ? AppColors.primaryBlue
                                      : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: locked
                                    ? AppColors.textSecondary
                                    : isSel
                                        ? AppColors.primaryBlue
                                        : AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // ── Permissions ──────────────────────────────────────────
                Text(context.l10n.permissions, style: AppTextStyles.labelGold),
                const SizedBox(height: 12),
                PermissionToggleRow(
                  title: context.l10n.postAuctionsPermission,
                  subtitle: context.l10n.createNewLots,
                  value: _canPostAuctions,
                  onChanged: (v) =>
                      setState(() => _canPostAuctions = v),
                ),
                PermissionToggleRow(
                  title: context.l10n.manageClientsPermission,
                  subtitle: context.l10n.reviewBidderDocs,
                  value: _canManageClients,
                  onChanged: (v) =>
                      setState(() => _canManageClients = v),
                ),
                PermissionToggleRow(
                  title: context.l10n.viewReportsPermission,
                  subtitle: context.l10n.accessRegionalStats,
                  value: _canViewReports,
                  onChanged: (v) =>
                      setState(() => _canViewReports = v),
                ),
                PermissionToggleRow(
                  title: context.l10n.closeAuctionsPermission,
                  subtitle: context.l10n.manuallyCloseAndAward,
                  value: _canCloseAuctions,
                  onChanged: (v) =>
                      setState(() => _canCloseAuctions = v),
                ),
                const SizedBox(height: 28),

                // ── Submit ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            _isEdit ? context.l10n.saveChangesButton : context.l10n.createAdmin,
                            style: AppTextStyles.button,
                          ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 1),
      );
}
