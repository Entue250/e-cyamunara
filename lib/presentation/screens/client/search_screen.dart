// lib/presentation/screens/client/search_screen.dart
//
// Phase 9O — Auction Search & Filter Screen
//
// Lets clients search active (or all) auctions by:
//   • Free-text (item name) with 400 ms debounce
//   • Category chip: All / Vehicle / Motorcycle / Bicycle
//   • Region chip: All + 5 RNP regions
//   • Status toggle: Active only / All
//   • Starting-price range (min / max RWF)
//
// Results reuse AuctionCard so AI value badges (Phase 9N) appear automatically.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'client_providers.dart';
import 'client_shared.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchCtrl = TextEditingController();
  final _minCtrl    = TextEditingController();
  final _maxCtrl    = TextEditingController();
  Timer? _debounce;

  String  _query      = '';
  String? _region;      // null = all
  String? _category;    // null = all
  bool    _activeOnly  = true;
  double? _minPrice;
  double? _maxPrice;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _clearAll() {
    _searchCtrl.clear();
    _minCtrl.clear();
    _maxCtrl.clear();
    setState(() {
      _query     = '';
      _region    = null;
      _category  = null;
      _activeOnly = true;
      _minPrice  = null;
      _maxPrice  = null;
    });
  }

  AuctionSearchQuery get _q => (
        text:       _query,
        region:     _region,
        category:   _category,
        activeOnly: _activeOnly,
        minPrice:   _minPrice,
        maxPrice:   _maxPrice,
      );

  bool get _hasActiveFilters =>
      _query.isNotEmpty ||
      _region != null ||
      _category != null ||
      !_activeOnly ||
      _minPrice != null ||
      _maxPrice != null;

  @override
  Widget build(BuildContext context) {
    final l10n       = context.l10n;
    final resultsAsync = ref.watch(searchAuctionsProvider(_q));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: TextField(
          controller: _searchCtrl,
          onChanged: _onTextChanged,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          cursorColor: AppColors.gold,
          decoration: InputDecoration(
            hintText: l10n.searchAuctions,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          if (_hasActiveFilters)
            TextButton(
              onPressed: _clearAll,
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filter section ───────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category row
                _FilterLabel(l10n.category),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(l10n.all,              selected: _category == null,     onTap: () => setState(() => _category = null)),
                      _Chip(l10n.vehicleLabel,     selected: _category == 'car',    onTap: () => setState(() => _category = 'car')),
                      _Chip(l10n.motorcycleLabel,  selected: _category == 'motorcycle', onTap: () => setState(() => _category = 'motorcycle')),
                      _Chip(l10n.bicycleLabel,     selected: _category == 'bicycle',    onTap: () => setState(() => _category = 'bicycle')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Region row
                _FilterLabel(l10n.region),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(l10n.all, selected: _region == null, onTap: () => setState(() => _region = null)),
                      ...SupabaseConstants.regions.map(
                        (r) => _Chip(
                          r,
                          selected: _region == r,
                          onTap: () => setState(() => _region = r),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Status + price range row
                Row(
                  children: [
                    // Active only toggle
                    GestureDetector(
                      onTap: () => setState(() => _activeOnly = !_activeOnly),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 20,
                            child: Switch(
                              value: _activeOnly,
                              onChanged: (v) => setState(() => _activeOnly = v),
                              activeThumbColor: AppColors.primaryBlue,
                              activeTrackColor: AppColors.primaryBlue.withValues(alpha: 0.4),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.active,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Min price
                    Expanded(
                      child: TextField(
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Min (RWF)',
                          hintStyle: TextStyle(fontSize: 11),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {
                          _minPrice = v.isEmpty ? null : double.tryParse(v);
                        }),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('–',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),

                    // Max price
                    Expanded(
                      child: TextField(
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Max (RWF)',
                          hintStyle: TextStyle(fontSize: 11),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() {
                          _maxPrice = v.isEmpty ? null : double.tryParse(v);
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),

          // ── Results ──────────────────────────────────────────────────────
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue),
              ),
              error: (_, _) => Center(
                child: Text(
                  l10n.noAuctionsAvailable,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
              data: (auctions) => auctions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_outlined,
                              size: 48, color: AppColors.border),
                          const SizedBox(height: 12),
                          Text(
                            l10n.noAuctionsAvailable,
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.primaryBlue,
                      onRefresh: () async =>
                          ref.invalidate(searchAuctionsProvider(_q)),
                      child: ListView.builder(
                        itemCount: auctions.length,
                        itemBuilder: (_, i) => AuctionCard(
                          auction: auctions[i],
                          onBidTap: () =>
                              context.go('/auction/${auctions[i].auctionId}'),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const ClientBottomNav(currentIndex: 1),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.6,
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );
}
