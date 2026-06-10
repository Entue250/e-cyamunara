// lib/presentation/screens/admin/manage_auctions_screen.dart
//
// SCREEN 13 — MANAGE AUCTIONS
// Shows: search bar, filter tabs (All / Active / Closed / Draft),
//        scrollable auction card list with view/edit/delete/close actions.
//
// Providers: currentAdminProvider, adminAuctionsProvider(uid)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class ManageAuctionsScreen extends ConsumerStatefulWidget {
  const ManageAuctionsScreen({super.key});

  @override
  ConsumerState<ManageAuctionsScreen> createState() =>
      _ManageAuctionsScreenState();
}

class _ManageAuctionsScreenState extends ConsumerState<ManageAuctionsScreen> {
  String _searchQuery = '';
  int _filterIndex = 0;
  static const List<String> _statusKeys = ['', 'active', 'closed', 'draft'];

  Future<void> _confirmPublish(AuctionModel auction, String adminUid) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.publishDraft),
        content: Text(
          l10n.publishConfirmMessage(
            auction.itemName,
            auction.auctionId.substring(0, 6).toUpperCase(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.publish,
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final failure =
        await ref.read(publishDraftUseCaseProvider)(auction.auctionId);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    ref.invalidate(adminAuctionsProvider(adminUid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.auctionPublished),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _confirmDelete(AuctionModel auction, String adminUid) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deleteAuction),
        content: Text(
          l10n.deleteConfirmMessage(
            auction.itemName,
            auction.auctionId.substring(0, 6).toUpperCase(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.delete,
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final (isSoft, failure) = await ref
        .read(deleteAuctionUseCaseProvider)(auction.auctionId, adminUid);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    ref.invalidate(adminAuctionsProvider(adminUid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSoft == true
              ? context.l10n.auctionSoftDeleted
              : context.l10n.auctionDeleted,
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminAsync = ref.watch(currentAdminProvider);
    final adminUid = adminAsync.value?.uid ?? '';
    final auctionsAsync = adminUid.isNotEmpty
        ? ref.watch(adminAuctionsProvider(adminUid))
        : const AsyncData<List<AuctionModel>>([]);

    final l10n = context.l10n;
    final filters = [l10n.all, l10n.active, l10n.ended, l10n.draft];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.manageAuctions),
        leading: const BackButton(),
        // TODO(Phase 3): implement sort/filter bottom sheet
        actions: const [
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: null,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: l10n.searchAuctionLots,
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

          // ── Filter tabs ────────────────────────────────────────────────
          FilterTabBar(
            tabs: filters,
            selectedIndex: _filterIndex,
            onTabSelected: (i) => setState(() => _filterIndex = i),
          ),

          const SizedBox(height: 8),

          // ── Auction list ───────────────────────────────────────────────
          Expanded(
            child: auctionsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      l10n.failedToLoadAuctions,
                      style: AppTextStyles.h3,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () =>
                          ref.invalidate(adminAuctionsProvider(adminUid)),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              data: (auctions) {
                final filtered = auctions.where((a) {
                  final matchSearch = _searchQuery.isEmpty ||
                      a.itemName
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());
                  final matchFilter = _filterIndex == 0 ||
                      a.auctionStatus == _statusKeys[_filterIndex];
                  return matchSearch && matchFilter;
                }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: AdminEmptyState(
                      _searchQuery.isNotEmpty
                          ? l10n.noAuctionsMatch(_searchQuery)
                          : l10n.noAuctionsYet(filters[_filterIndex].toLowerCase()),
                      icon: Icons.gavel_outlined,
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(adminAuctionsProvider(adminUid)),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final a = filtered[i];
                      final canEdit = a.auctionStatus != 'closed';
                      return ManageAuctionCard(
                        auction: a,
                        onViewBids: () =>
                            context.go('/admin/bids/${a.auctionId}'),
                        onClose: () =>
                            context.go('/admin/close/${a.auctionId}'),
                        onEdit: canEdit
                            ? () => context.go(
                                AppRoutes.postAuction,
                                extra: a,
                              )
                            : null,
                        onDelete: canEdit
                            ? () => _confirmDelete(a, adminUid)
                            : null,
                        onPublish: a.auctionStatus == SupabaseConstants.statusDraft
                            ? () => _confirmPublish(a, adminUid)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go(AppRoutes.postAuction),
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.add, color: AppColors.primaryBlue),
      ),
    );
  }
}
