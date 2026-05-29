// lib/presentation/screens/admin/client_management_screen.dart
//
// SCREEN 16 — CLIENT MANAGEMENT
// Shows: 3 stat bars (Total / Active / Suspended), search field,
//        filter tabs (All Clients / Verified / Pending / Suspended),
//        client cards with suspend/activate actions.
//
// Providers: currentAdminProvider, usersByRegionProvider(region),
//            manageUserUseCaseProvider

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class ClientManagementScreen extends ConsumerStatefulWidget {
  const ClientManagementScreen({super.key});

  @override
  ConsumerState<ClientManagementScreen> createState() =>
      _ClientManagementScreenState();
}

class _ClientManagementScreenState
    extends ConsumerState<ClientManagementScreen> {
  String _search = '';
  int _tabIndex = 0;
  final Set<String> _loadingUids = {};

  @override
  Widget build(BuildContext context) {
    final adminAsync = ref.watch(currentAdminProvider);
    final region = adminAsync.value?.region ?? '';
    final clientsAsync = region.isNotEmpty
        ? ref.watch(usersByRegionProvider(region))
        : const AsyncData<List<UserModel>>([]);

    final l10n = context.l10n;
    final tabs = [l10n.all, l10n.activeBadge, l10n.suspended];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.clientManagement),
        leading: const BackButton(),
        actions: const [
          // TODO(Phase 3): implement inline search toggle
          IconButton(icon: Icon(Icons.search), onPressed: null),
          IconButton(icon: Icon(Icons.more_vert), onPressed: null),
        ],
      ),
      body: Column(
        children: [
          // Stats strip — always visible (shows live counts once data loads,
          // zeros while loading so the layout never jumps).
          _StatsStrip(clients: clientsAsync.value ?? const []),

          // Search field — always visible
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: l10n.searchClients,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surfaceGrey,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          FilterTabBar(
            tabs: tabs,
            selectedIndex: _tabIndex,
            onTabSelected: (i) => setState(() => _tabIndex = i),
          ),

          const SizedBox(height: 8),

          // List — loading / error / data states
          Expanded(
            child: clientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    Text(l10n.failedToLoadClients, style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () =>
                          ref.invalidate(usersByRegionProvider(region)),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              data: (clients) {
                final filtered = clients.where((c) {
                  final matchSearch = _search.isEmpty ||
                      c.fullNames
                          .toLowerCase()
                          .contains(_search.toLowerCase());
                  final matchTab = _tabIndex == 0 ||
                      (_tabIndex == 1 && c.isActive) ||
                      (_tabIndex == 2 && c.isSuspended);
                  return matchSearch && matchTab;
                }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: AdminEmptyState(
                      _search.isNotEmpty
                          ? l10n.noClientsMatch(_search)
                          : l10n.noClientsYet(tabs[_tabIndex].toLowerCase()),
                      icon: Icons.group_outlined,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(usersByRegionProvider(region)),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => ClientCard(
                      user: filtered[i],
                      isLoading: _loadingUids.contains(filtered[i].uid),
                      onView: () => _showClientDetails(filtered[i]),
                      onSuspend: () =>
                          _confirmSuspend(filtered[i].uid, region),
                      onActivate: () =>
                          _confirmActivate(filtered[i].uid, region),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 2),
    );
  }

  Future<void> _confirmSuspend(String uid, String region) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.suspendClient),
        content: Text(l10n.suspendClientMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.suspend,
              style: const TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _handleSuspend(uid, region);
  }

  Future<void> _confirmActivate(String uid, String region) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.activateClient),
        content: Text(l10n.activateClientMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.activate,
              style: const TextStyle(
                  color: AppColors.success, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _handleActivate(uid, region);
  }

  Future<void> _handleSuspend(String uid, String region) async {
    setState(() => _loadingUids.add(uid));
    final useCase = ref.read(manageUserUseCaseProvider);
    final failure = await useCase.suspend(uid, 'Admin action');
    setState(() => _loadingUids.remove(uid));
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(failure.message), backgroundColor: AppColors.error),
      );
      return;
    }
    ref.invalidate(usersByRegionProvider(region));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.clientSuspended),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _handleActivate(String uid, String region) async {
    setState(() => _loadingUids.add(uid));
    final useCase = ref.read(manageUserUseCaseProvider);
    final failure = await useCase.activate(uid);
    setState(() => _loadingUids.remove(uid));
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(failure.message), backgroundColor: AppColors.error),
      );
      return;
    }
    ref.invalidate(usersByRegionProvider(region));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.clientActivated),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showClientDetails(UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClientDetailSheet(user: user),
    );
  }
}

// ── Stats strip widget — compact horizontal row to avoid vertical overflow ──────
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.clients});
  final List<UserModel> clients;

  @override
  Widget build(BuildContext context) {
    final active    = clients.where((c) => c.accountStatus == 'active').length;
    final suspended = clients.where((c) => c.accountStatus == 'suspended').length;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _StatCell(context.l10n.total, '${clients.length}', AppColors.textPrimary),
          Container(width: 1, height: 36, color: AppColors.border),
          _StatCell(context.l10n.activeBadge, '$active', AppColors.success),
          Container(width: 1, height: 36, color: AppColors.border),
          _StatCell(
            context.l10n.suspended,
            '$suspended',
            suspended > 0 ? AppColors.error : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, this.value, this.color);
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(label, style: AppTextStyles.label),
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
      );
}

// ── Client detail bottom sheet ─────────────────────────────────────────────────

class _ClientDetailSheet extends StatelessWidget {
  const _ClientDetailSheet({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty;
    final isActive = user.accountStatus == 'active';
    final statusColor = isActive ? AppColors.success : AppColors.error;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          children: [
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
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceGrey,
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: hasPhoto
                            ? CachedNetworkImage(
                                imageUrl: user.profilePhotoUrl!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.person,
                                  color: AppColors.textSecondary,
                                  size: 32,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                color: AppColors.textSecondary,
                                size: 32,
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullNames, style: AppTextStyles.h1),
                            Text(
                              '${user.district}, ${user.region}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                                border: Border.all(
                                    color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                user.accountStatus.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
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
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        _DetailStat(context.l10n.bidsCount, '${user.totalBidsPlaced}'),
                        Container(
                            width: 1, height: 36, color: AppColors.border),
                        _DetailStat(context.l10n.winsCount, '${user.totalAuctionsWon}'),
                        Container(
                            width: 1, height: 36, color: AppColors.border),
                        _DetailStat(context.l10n.region, user.region),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _infoRow(Icons.phone_outlined, context.l10n.phone, user.phoneNumber),
                  _infoRow(Icons.location_on_outlined, context.l10n.districtLabel,
                      user.district),
                  _infoRow(Icons.map_outlined, context.l10n.province, user.province),
                  _infoRow(Icons.calendar_today_outlined, context.l10n.joined,
                      _fmtDate(user.createdAt)),
                  if (user.lastLogin != null)
                    _infoRow(Icons.login_outlined, context.l10n.lastLogin,
                        _fmtDate(user.lastLogin!)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.close),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
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

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
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
