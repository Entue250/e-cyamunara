// lib/presentation/screens/admin/region_reports_screen.dart
//
// SCREEN 18 — REGION REPORTS
// Shows: geographic region tab chips (locked to admin's own region),
//        interactive REPORTING PERIOD row with date-range picker,
//        4 stat cards (Active Lots, Total Auctions, Closed in Period, Revenue),
//        Auctions by Category bar chart (real DB data),
//        Recent Closed Auctions list.
//
// Providers: currentAdminProvider, regionStatsProvider,
//            regionCategoryStatsProvider, recentClosedAuctionsProvider

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';

class RegionReportsScreen extends ConsumerStatefulWidget {
  const RegionReportsScreen({super.key});

  @override
  ConsumerState<RegionReportsScreen> createState() =>
      _RegionReportsScreenState();
}

class _RegionReportsScreenState extends ConsumerState<RegionReportsScreen> {
  // Dates stored in state — only change on explicit user picker action.
  // Never use DateTime.now() directly in build() or it creates a new
  // provider instance every frame (infinite loading loop).
  late DateTime _end;
  late DateTime _start;
  bool _isDownloading = false;

  static const Map<String, String> _categoryLabels = {
    'car':        'Motor Vehicles',
    'motorcycle': 'Motorcycles',
    'bicycle':    'Bicycles',
  };

  @override
  void initState() {
    super.initState();
    _end = DateTime.now();
    _start = DateTime(_end.year, _end.month - 1, 1);
  }

  // ── PDF export ─────────────────────────────────────────────────────────────
  Future<void> _download(String adminRegion) async {
    setState(() => _isDownloading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not authenticated');

      final start = _start.toIso8601String().substring(0, 10);
      final end   = _end.toIso8601String().substring(0, 10);

      final res = await Supabase.instance.client.functions.invoke(
        SupabaseConstants.fnGenerateReport,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'region':     adminRegion,
          'start_date': start,
          'end_date':   end,
          'format':     'pdf',
        },
      );

      setState(() => _isDownloading = false);

      if (res.status != 200) {
        final err = (res.data as Map?)?['error'] ?? 'Report generation failed';
        _snack('$err', error: true);
        return;
      }

      final downloadUrl = (res.data as Map?)?['download_url'] as String?;
      if (!mounted) return;

      if (downloadUrl != null) {
        _showReportDialog(downloadUrl, start, end, adminRegion);
      } else {
        _snack('Report generated but no download URL returned', error: true);
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      _snack('Download failed: $e', error: true);
    }
  }

  void _showReportDialog(String url, String start, String end, String region) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.description_outlined, color: AppColors.primaryBlue),
            SizedBox(width: 8),
            Text('Report Ready'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Region: $region  |  $start → $end',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 12),
            const Text('Copy the link below and open it in your browser:',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceGrey,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy URL',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('URL copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('Link is valid for 7 days.',
                style: AppTextStyles.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
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

  // ── Date range picker ──────────────────────────────────────────────────────
  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryBlue,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _start = picked.start;
      _end = picked.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    final adminAsync = ref.watch(currentAdminProvider);
    final adminRegion = adminAsync.value?.region ?? '';

    // Show loading while admin data is fetching
    if (adminAsync.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(context.l10n.regionReports),
          leading: const BackButton(),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        bottomNavigationBar: const AdminBottomNav(currentIndex: 3),
      );
    }

    final params = (region: adminRegion, start: _start, end: _end);

    final statsAsync    = ref.watch(regionStatsProvider(params));
    final categoryAsync = ref.watch(regionCategoryStatsProvider(params));
    final recentAsync   = ref.watch(recentClosedAuctionsProvider(params));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.regionReports),
        leading: const BackButton(),
        actions: [
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_outlined, color: Colors.white),
              onPressed: adminRegion.isEmpty
                  ? null
                  : () => _download(adminRegion),
              tooltip: 'Export PDF',
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Region header (auto-assigned, read-only) ───────────────────
          if (adminRegion.isNotEmpty)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                  const Text('GEOGRAPHIC SCOPE', style: AppTextStyles.label),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      adminRegion.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Scrollable content ─────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(regionStatsProvider(params));
                ref.invalidate(regionCategoryStatsProvider(params));
                ref.invalidate(recentClosedAuctionsProvider(params));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Reporting period banner (tappable) ───────────────
                    GestureDetector(
                      onTap: _pickDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 10),
                            const Text('REPORTING PERIOD',
                                style: AppTextStyles.label),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${DateHelper.formatDate(_start)} – ${DateHelper.formatDate(_end)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.edit_calendar_outlined,
                                size: 16,
                                color: AppColors.primaryBlue),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── 4 stat cards ─────────────────────────────────────
                    statsAsync.when(
                      loading: () => const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator(
                            color: AppColors.primaryBlue)),
                      ),
                      error: (e, _) => _StatError(
                        message: 'Could not load statistics.',
                        onRetry: () => ref.invalidate(
                            regionStatsProvider(params)),
                      ),
                      data: (stats) {
                        final total       = stats['total_auctions'] as int? ?? 0;
                        final active      = stats['active_auctions'] as int? ?? 0;
                        final closedCount = stats['closed_in_period'] as int? ?? 0;
                        final revenue     = (stats['total_revenue'] as num?)
                                               ?.toDouble() ?? 0;
                        final completion  = total > 0
                            ? '${((closedCount / total) * 100).toStringAsFixed(1)}%'
                            : '0%';

                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.3,
                          children: [
                            ReportStatCard(
                              icon: Icons.gavel_outlined,
                              label: context.l10n.activeAuctionsCount,
                              value: '$active',
                              trend: 'Currently live',
                              isHighlight: false,
                            ),
                            ReportStatCard(
                              icon: Icons.inventory_2_outlined,
                              label: context.l10n.totalAuctions,
                              value: '$total',
                              trend: 'All-time',
                              isHighlight: false,
                            ),
                            ReportStatCard(
                              icon: Icons.check_circle_outline,
                              label: context.l10n.closedAuctions,
                              value: '$closedCount',
                              trend: 'Completion $completion',
                              isHighlight: false,
                            ),
                            ReportStatCard(
                              icon: Icons.account_balance_wallet_outlined,
                              label: context.l10n.nationalRevenue,
                              value: AppFormatters.rwfCompact(revenue),
                              trend: 'This period',
                              isHighlight: true,
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── Auctions by category ──────────────────────────────
                    const Text('Auctions by Category',
                        style: AppTextStyles.h1),
                    const SizedBox(height: 12),

                    categoryAsync.when(
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.primaryBlue),
                      error: (e, _) => const _InlineError(
                          'Could not load category data.'),
                      data: (categories) {
                        if (categories.isEmpty) {
                          return const AdminEmptyState(
                            'No auction data for this period.',
                            icon: Icons.bar_chart_outlined,
                          );
                        }
                        final maxCount = categories.fold<int>(
                          1,
                          (m, c) => (c['count'] as int) > m
                              ? c['count'] as int
                              : m,
                        );
                        return Column(
                          children: categories.map((c) {
                            final raw   = c['category'] as String;
                            final label = _categoryLabels[raw] ??
                                raw[0].toUpperCase() + raw.substring(1);
                            final count = c['count'] as int;
                            final ratio = count / maxCount;
                            return CategoryBar(
                              label: label,
                              ratio: ratio,
                              count: count,
                            );
                          }).toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── Recent closed auctions ────────────────────────────
                    Text(context.l10n.recentAuctions,
                        style: AppTextStyles.h1),
                    const SizedBox(height: 8),

                    recentAsync.when(
                      loading: () => const LinearProgressIndicator(
                          color: AppColors.primaryBlue),
                      error: (e, _) => const _InlineError(
                          'Could not load recent auctions.'),
                      data: (auctions) {
                        if (auctions.isEmpty) {
                          return const AdminEmptyState(
                            'No closed auctions in this period.',
                            icon: Icons.history_outlined,
                          );
                        }
                        return Column(
                          children: auctions
                              .map(
                                (a) => RecentAuctionCard(
                                  auction: a,
                                  onManage: () => context.go(
                                      '/admin/bids/${a.auctionId}'),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 3),
    );
  }
}

// ── Small private helpers ─────────────────────────────────────────────────────

class _StatError extends StatelessWidget {
  const _StatError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            Text(message, style: AppTextStyles.bodySmall),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined,
                size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(message, style: AppTextStyles.bodySmall),
          ],
        ),
      );
}
