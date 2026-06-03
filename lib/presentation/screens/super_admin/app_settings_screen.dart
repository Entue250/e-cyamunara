// lib/presentation/screens/super_admin/app_settings_screen.dart
//
// APP SETTINGS — Super Admin
// Displays and edits the single config row from the app_settings table.
// Fields: app_version, maintenance_mode, max_bid_increment,
//         auction_auto_close, notification_enabled, updated_at, updated_by.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_router.dart' show AppRoutes;
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import 'super_admin_shared.dart';

class AppSettingsScreen extends ConsumerStatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  ConsumerState<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends ConsumerState<AppSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Local editable state — loaded from DB
  final _versionCtrl = TextEditingController();
  final _maxBidCtrl = TextEditingController();

  bool _maintenanceMode = false;
  bool _auctionAutoClose = true;
  bool _notificationEnabled = true;
  bool _dirty = false;
  bool _saving = false;
  bool _initialized = false;
  String? _saveError;

  @override
  void dispose() {
    _versionCtrl.dispose();
    _maxBidCtrl.dispose();
    super.dispose();
  }

  void _loadFromModel(AppSettingsModel s) {
    _initialized = true;
    _versionCtrl.text = s.appVersion;
    _maxBidCtrl.text = s.maxBidIncrement.toInt().toString();
    _maintenanceMode = s.maintenanceMode;
    _auctionAutoClose = s.auctionAutoClose;
    _notificationEnabled = s.notificationEnabled;
    _dirty = false;
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentSuperAdminProvider).valueOrNull?.uid;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final updated = AppSettingsModel(
        appVersion: _versionCtrl.text.trim(),
        maintenanceMode: _maintenanceMode,
        maxBidIncrement: double.tryParse(_maxBidCtrl.text) ?? 10000,
        auctionAutoClose: _auctionAutoClose,
        notificationEnabled: _notificationEnabled,
        updatedAt: DateTime.now(),
        updatedBy: uid,
      );

      await ref
          .read(appSettingsRepositoryProvider)
          .updateSettings(settings: updated, updatedByUid: uid);

      ref.invalidate(appSettingsProvider);
      if (mounted) {
        setState(() {
          _dirty = false;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _showUnsavedDialog();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('APP SETTINGS'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () {
              if (_dirty) {
                _showUnsavedDialog();
              } else {
                context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.superDashboard);
              }
            },
          ),
          actions: [
            if (_dirty)
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'SAVE',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
              ),
          ],
        ),
        body: settingsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primaryBlue),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load settings.\n$e',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(appSettingsProvider),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (settings) {
            // Populate local state once on first load
            if (!_initialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _loadFromModel(settings));
              });
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Section: App Info ─────────────────────────────────
                    _SectionHeader('App Information'),
                    const SizedBox(height: 12),

                    _SettingsCard(
                      child: Column(
                        children: [
                          _FieldRow(
                            label: 'App Version',
                            icon: Icons.info_outline,
                            child: SizedBox(
                              width: 120,
                              child: TextFormField(
                                controller: _versionCtrl,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty) ? 'Required' : null,
                                onChanged: (_) => _markDirty(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Section: Auction Config ───────────────────────────
                    _SectionHeader('Auction Configuration'),
                    const SizedBox(height: 12),

                    _SettingsCard(
                      child: Column(
                        children: [
                          _FieldRow(
                            label: 'Max Bid Increment (RWF)',
                            icon: Icons.trending_up,
                            child: SizedBox(
                              width: 130,
                              child: TextFormField(
                                controller: _maxBidCtrl,
                                textAlign: TextAlign.end,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Required';
                                  final n = int.tryParse(v);
                                  if (n == null || n <= 0) return 'Must be > 0';
                                  return null;
                                },
                                onChanged: (_) => _markDirty(),
                              ),
                            ),
                          ),
                          const Divider(color: AppColors.border, height: 1),
                          _ToggleRow(
                            label: 'Auto-Close Auctions',
                            icon: Icons.timer_outlined,
                            description:
                                'Auctions close automatically at end time',
                            value: _auctionAutoClose,
                            onChanged: (v) {
                              setState(() => _auctionAutoClose = v);
                              _markDirty();
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Section: System ───────────────────────────────────
                    _SectionHeader('System'),
                    const SizedBox(height: 12),

                    _SettingsCard(
                      child: Column(
                        children: [
                          _ToggleRow(
                            label: 'Maintenance Mode',
                            icon: Icons.build_outlined,
                            description:
                                'Disables new bids and auction submissions',
                            value: _maintenanceMode,
                            activeColor: AppColors.warning,
                            onChanged: (v) {
                              setState(() => _maintenanceMode = v);
                              _markDirty();
                            },
                          ),
                          const Divider(color: AppColors.border, height: 1),
                          _ToggleRow(
                            label: 'Push Notifications',
                            icon: Icons.notifications_outlined,
                            description: 'Send alerts for bids and auctions',
                            value: _notificationEnabled,
                            onChanged: (v) {
                              setState(() => _notificationEnabled = v);
                              _markDirty();
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Section: Last Updated ─────────────────────────────
                    _SectionHeader('Last Updated'),
                    const SizedBox(height: 12),

                    _SettingsCard(
                      child: Column(
                        children: [
                          _InfoRow(
                            label: 'Updated At',
                            icon: Icons.schedule,
                            value: DateFormat('dd MMM yyyy, HH:mm')
                                .format(settings.updatedAt.toLocal()),
                          ),
                          if (settings.updatedBy case final byId?) ...[
                            const Divider(color: AppColors.border, height: 1),
                            _InfoRow(
                              label: 'Updated By',
                              icon: Icons.person_outline,
                              value: '${byId.substring(0, 8)}…',
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (_saveError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 16, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _saveError!,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_dirty) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('SAVE CHANGES',
                                  style: AppTextStyles.button),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
        bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 0),
      ),
    );
  }

  Future<void> _showUnsavedDialog() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
            'You have unsaved changes. Discard them and go back?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      context.canPop() ? context.pop() : context.go(AppRoutes.superDashboard);
    }
  }
}

// ── Layout helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 1,
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.icon,
    required this.child,
  });
  final String label;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            child,
          ],
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.icon,
    required this.description,
    required this.value,
    required this.onChanged,
    this.activeColor = AppColors.primaryBlue,
  });
  final String label;
  final IconData icon;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: value ? activeColor : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: activeColor,
              activeTrackColor: activeColor.withValues(alpha: 0.4),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.icon,
    required this.value,
  });
  final String label;
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
