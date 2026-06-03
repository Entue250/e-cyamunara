// lib/presentation/screens/super_admin/manage_admins_screen.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
// MANAGE REGION ADMINS
// ════════════════════════════════════════════════════════════════════════════
class ManageAdminsScreen extends ConsumerStatefulWidget {
  const ManageAdminsScreen({super.key});

  @override
  ConsumerState<ManageAdminsScreen> createState() =>
      _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends ConsumerState<ManageAdminsScreen> {
  String _search = '';

  // ── Suspend via Edge Function — also bans in Supabase Auth ───────────────
  Future<void> _suspend(RegionAdminModel admin) async {
    final l10n = context.l10n;
    final confirmed = await _confirmDialog(
      context,
      title: l10n.suspendAdmin,
      message: l10n.suspendAdminMessage(admin.fullNames, admin.region),
      confirmLabel: l10n.suspend,
      destructive: true,
    );
    if (!confirmed) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _snack(l10n.sessionExpiredError, error: true);
      return;
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        SupabaseConstants.fnSuspendUser,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'uid': admin.uid,
          'reason': 'Suspended by Super Admin',
        },
      );

      if (res.status != 200) {
        final msg = (res.data as Map?)?['error'] ?? 'Failed to suspend admin';
        _snack('$msg', error: true);
        return;
      }

      ref.invalidate(superAdminAllAdminsProvider);
      _snack(l10n.adminSuspendedMsg(admin.fullNames));
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  // ── Activate via Edge Function — also lifts Auth ban ─────────────────────
  Future<void> _activate(RegionAdminModel admin) async {
    final l10n = context.l10n;
    final confirmed = await _confirmDialog(
      context,
      title: l10n.activateAdmin,
      message: l10n.activateAdminMessage(admin.fullNames, admin.region),
      confirmLabel: l10n.activate,
      destructive: false,
    );
    if (!confirmed) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _snack(l10n.sessionExpiredError, error: true);
      return;
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        SupabaseConstants.fnActivateUser,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {'uid': admin.uid},
      );

      if (res.status != 200) {
        final msg =
            (res.data as Map?)?['error'] ?? 'Failed to activate admin';
        _snack('$msg', error: true);
        return;
      }

      ref.invalidate(superAdminAllAdminsProvider);
      _snack(l10n.adminActivatedMsg(admin.fullNames));
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  void _openDetail(RegionAdminModel admin) {
    final counts = ref.read(superAdminAuctionCountsProvider).value ?? {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminDetailSheet(
        admin: admin,
        livePosted: counts[admin.uid]?['posted'],
        liveClosed: counts[admin.uid]?['closed'],
        onSuspend: () {
          Navigator.pop(context);
          _suspend(admin);
        },
        onActivate: () {
          Navigator.pop(context);
          _activate(admin);
        },
        onEdit: () {
          Navigator.pop(context);
          context.go(AppRoutes.addEditAdmin, extra: admin);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminsAsync  = ref.watch(superAdminAllAdminsProvider);
    final countsAsync  = ref.watch(superAdminAuctionCountsProvider);
    final liveCounts   = countsAsync.value ?? {};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.manageAdmins),
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => context.go(AppRoutes.addEditAdmin),
            tooltip: context.l10n.addNewAdmin,
          ),
        ],
      ),
      body: adminsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.error, size: 48),
              const SizedBox(height: 12),
              Text(context.l10n.failedToLoadAdmins,
                  style: AppTextStyles.h2,
                  textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('$e',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(superAdminAllAdminsProvider),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
        data: (admins) {
          final active    = admins.where((a) => a.accountStatus == 'active').length;
          final pending   = admins.where((a) => a.accountStatus == 'pending').length;
          final suspended = admins.where((a) => a.accountStatus == 'suspended').length;

          final filtered = _search.isEmpty
              ? admins
              : admins
                  .where((a) =>
                      a.fullNames
                          .toLowerCase()
                          .contains(_search.toLowerCase()) ||
                      a.region
                          .toLowerCase()
                          .contains(_search.toLowerCase()))
                  .toList();

          return Column(
            children: [
              // ── Stats strip ────────────────────────────────────────────
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    HeaderStatBox(
                        context.l10n.total, '${admins.length}', AppColors.textPrimary),
                    const StatDivider(),
                    HeaderStatBox(
                        context.l10n.activeBadge, '$active', AppColors.success),
                    const StatDivider(),
                    HeaderStatBox(
                        context.l10n.pendingBadge, '$pending', AppColors.warning),
                    const StatDivider(),
                    HeaderStatBox(
                        context.l10n.suspended, '$suspended', AppColors.error),
                  ],
                ),
              ),

              // ── Search ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchAdmins,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: AppColors.surfaceGrey,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () =>
                                setState(() => _search = ''),
                          )
                        : null,
                  ),
                ),
              ),

              // ── List ───────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: EmptyStateCard(
                          _search.isEmpty
                              ? context.l10n.noRegionAdmins
                              : context.l10n.noAdminsMatch(_search),
                          icon: Icons.search_off,
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _AdminManageCard(
                          admin: filtered[i],
                          livePosted: liveCounts[filtered[i].uid]?['posted'],
                          liveClosed: liveCounts[filtered[i].uid]?['closed'],
                          onTap: () => _openDetail(filtered[i]),
                          onSuspend: () => _suspend(filtered[i]),
                          onActivate: () => _activate(filtered[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 1),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admins_fab',
        onPressed: () => context.go(AppRoutes.addEditAdmin),
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.add, color: AppColors.primaryBlue),
      ),
    );
  }
}

// ── Admin manage card ─────────────────────────────────────────────────────────

class _AdminManageCard extends StatelessWidget {
  const _AdminManageCard({
    required this.admin,
    required this.onTap,
    required this.onSuspend,
    required this.onActivate,
    this.livePosted,
    this.liveClosed,
  });
  final RegionAdminModel admin;
  final VoidCallback onTap, onSuspend, onActivate;
  final int? livePosted, liveClosed;

  @override
  Widget build(BuildContext context) {
    final isActive = admin.accountStatus == 'active';
    final statusColor = switch (admin.accountStatus) {
      'active'    => AppColors.success,
      'pending'   => AppColors.warning,
      'suspended' => AppColors.error,
      _           => AppColors.textSecondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Profile photo or initials fallback
                _AdminAvatar(admin: admin, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              admin.fullNames,
                              style: AppTextStyles.h2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(
                                  AppRadius.full),
                              border: Border.all(
                                  color:
                                      statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              admin.accountStatus.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${admin.region.toUpperCase()} REGION ADMIN',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkGold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.phone_outlined,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(admin.phoneNumber, style: AppTextStyles.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                StatPill(context.l10n.postedStat, '${livePosted ?? admin.totalAuctionsPosted}'),
                const SizedBox(width: 8),
                StatPill(context.l10n.closedStat, '${liveClosed ?? admin.totalAuctionsClosed}'),
                const Spacer(),
                // Suspend / Activate button
                GestureDetector(
                  onTap: isActive ? onSuspend : onActivate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.error.withValues(alpha: 0.1)
                          : AppColors.success.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isActive
                            ? AppColors.error.withValues(alpha: 0.3)
                            : AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      isActive ? context.l10n.suspend : context.l10n.activate,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? AppColors.error
                            : AppColors.success,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Tap hint
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(context.l10n.tapToViewDetails,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
                const Icon(Icons.chevron_right,
                    size: 14, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable profile avatar for region admins ─────────────────────────────────

class _AdminAvatar extends StatelessWidget {
  const _AdminAvatar({required this.admin, required this.size});
  final RegionAdminModel admin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        admin.profilePhotoUrl != null && admin.profilePhotoUrl!.isNotEmpty;
    final initials = admin.fullNames
        .split(' ')
        .take(2)
        .map((w) => w.isEmpty ? '' : w[0])
        .join();

    if (hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          color: AppColors.surfaceGrey,
        ),
        clipBehavior: Clip.hardEdge,
        child: CachedNetworkImage(
          imageUrl: admin.profilePhotoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => _InitialsBox(initials: initials, size: size),
        ),
      );
    }

    return _InitialsBox(initials: initials, size: size);
  }
}

class _InitialsBox extends StatelessWidget {
  const _InitialsBox({required this.initials, required this.size});
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: AppColors.darkGold,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.35,
            ),
          ),
        ),
      );
}

// ── Admin detail bottom sheet ─────────────────────────────────────────────────

class _AdminDetailSheet extends StatelessWidget {
  const _AdminDetailSheet({
    required this.admin,
    required this.onSuspend,
    required this.onActivate,
    required this.onEdit,
    this.livePosted,
    this.liveClosed,
  });
  final RegionAdminModel admin;
  final VoidCallback onSuspend, onActivate, onEdit;
  final int? livePosted, liveClosed;

  @override
  Widget build(BuildContext context) {
    final isActive = admin.accountStatus == 'active';
    final statusColor = switch (admin.accountStatus) {
      'active'    => AppColors.success,
      'pending'   => AppColors.warning,
      'suspended' => AppColors.error,
      _           => AppColors.textSecondary,
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // Header
                  Row(
                    children: [
                      _AdminAvatar(admin: admin, size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(admin.fullNames, style: AppTextStyles.h1),
                            Text('${admin.region} Region',
                                style: const TextStyle(
                                  color: AppColors.darkGold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                )),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                    AppRadius.full),
                                border: Border.all(
                                    color: statusColor
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                admin.accountStatus.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Stats row
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        _DetailStat(
                            context.l10n.postedStat, '${livePosted ?? admin.totalAuctionsPosted}'),
                        const StatDivider(),
                        _DetailStat(
                            context.l10n.closedStat, '${liveClosed ?? admin.totalAuctionsClosed}'),
                        const StatDivider(),
                        _DetailStat(context.l10n.region, admin.region),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Info rows
                  _sheetInfoRow(Icons.phone_outlined, context.l10n.phone,
                      admin.phoneNumber),
                  _sheetInfoRow(Icons.badge_outlined, context.l10n.nationalIdLabel,
                      admin.nationalId.isNotEmpty
                          ? '${admin.nationalId.substring(0, 4)}••••••••••'
                          : context.l10n.notOnRecord),
                  _sheetInfoRow(Icons.calendar_today_outlined, context.l10n.joined,
                      _fmtDate(admin.createdAt)),
                  if (admin.lastLogin != null)
                    _sheetInfoRow(Icons.login_outlined, context.l10n.lastLogin,
                        _fmtDate(admin.lastLogin!)),

                  const SizedBox(height: 16),

                  // Permissions
                  Text(context.l10n.permissions,
                      style: AppTextStyles.labelGold),
                  const SizedBox(height: 8),
                  _permLine(context.l10n.postAuctionsPermission,
                      admin.permissions.postAuctions),
                  _permLine(context.l10n.manageClientsPermission,
                      admin.permissions.manageClients),
                  _permLine(context.l10n.viewReportsPermission,
                      admin.permissions.viewReports),
                  _permLine(context.l10n.closeAuctionsPermission,
                      admin.permissions.closeAuctions),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined,
                              size: 18),
                          label: Text(context.l10n.edit),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              isActive ? onSuspend : onActivate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive
                                ? AppColors.error
                                : AppColors.success,
                          ),
                          icon: Icon(
                            isActive
                                ? Icons.block
                                : Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: Text(
                              isActive ? context.l10n.suspend : context.l10n.activate),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetInfoRow(IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
                Text(value, style: AppTextStyles.h3),
              ],
            ),
          ],
        ),
      );

  Widget _permLine(String label, bool allowed) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(
              allowed ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: allowed ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 8),
            Text(label, style: AppTextStyles.bodyMedium),
          ],
        ),
      );

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year}';
}

class _DetailStat extends StatelessWidget {
  const _DetailStat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryBlue,
                )),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: AppColors.textSecondary)),
          ],
        ),
      );
}

// ── Confirmation dialog helper ────────────────────────────────────────────────

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: destructive ? AppColors.error : AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
