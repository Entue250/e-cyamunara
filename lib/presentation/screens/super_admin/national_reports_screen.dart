// lib/presentation/screens/super_admin/national_reports_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/formatters.dart';
import 'super_admin_providers.dart';
import 'super_admin_shared.dart';

// ════════════════════════════════════════════════════════════════════════════
// NATIONAL REPORTS
// ════════════════════════════════════════════════════════════════════════════
class NationalReportsScreen extends ConsumerStatefulWidget {
  const NationalReportsScreen({super.key});

  @override
  ConsumerState<NationalReportsScreen> createState() =>
      _NationalReportsScreenState();
}

class _NationalReportsScreenState
    extends ConsumerState<NationalReportsScreen> {
  // Selected range drives superAdminFilteredStatsProvider.family
  SuperAdminStatsRange _range = SuperAdminStatsRange.last30Days;
  bool _isDownloading = false;

  static const _ranges = SuperAdminStatsRange.values;

  // ── Generate & download report ────────────────────────────────────────────
  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Not authenticated');

      final start = _range.startDate.toIso8601String().substring(0, 10);
      final end   = _range.endDate.toIso8601String().substring(0, 10);

      final res = await Supabase.instance.client.functions.invoke(
        SupabaseConstants.fnGenerateReport,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        body: {
          'region':     'ALL',
          'start_date': start,
          'end_date':   end,
          'format':     'pdf', // Edge Function returns signed URL
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
        _showReportDialog(downloadUrl, start, end);
      } else {
        _snack(context.l10n.reportReadyNoUrl, error: true);
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      _snack(context.l10n.downloadFailed(e.toString()), error: true);
    }
  }

  void _showReportDialog(String url, String start, String end) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.description_outlined, color: AppColors.primaryBlue),
            const SizedBox(width: 8),
            Text(context.l10n.reportReady),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$start → $end',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 12),
            Text(context.l10n.reportCopyLinkInstruction,
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
                    tooltip: context.l10n.copyUrl,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.l10n.urlCopied)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.reportLinkValidity,
              style: AppTextStyles.bodySmall,
            ),
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

  @override
  Widget build(BuildContext context) {
    // FutureProvider.family — each range has its own cached AsyncValue
    final statsAsync  = ref.watch(superAdminFilteredStatsProvider(_range));
    final adminsAsync = ref.watch(superAdminAllAdminsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.nationalReports),
        leading: const BackButton(),
        actions: [
          _isDownloading
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_outlined),
                  tooltip: 'Export report',
                  onPressed: _download,
                ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(superAdminFilteredStatsProvider(_range));
          ref.invalidate(superAdminAllAdminsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.fiscalPerformance,
                  style: AppTextStyles.labelGold),
              Text(context.l10n.nationwideLedger,
                  style: AppTextStyles.displayLarge),
              const SizedBox(height: 12),

              // ── Range chips ─────────────────────────────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _ranges.map((r) {
                    final isSel = r == _range;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _range = r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel
                                ? AppColors.primaryBlue
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: isSel
                                  ? AppColors.primaryBlue
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            r.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSel
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // ── Stat cards — filtered by selected range ──────────────────
              statsAsync.when(
                loading: () => const _StatsGridPlaceholder(),
                error: (_, _) => _StatsGrid(
                  revenue: 0,
                  auctions: 0,
                  bids: 0,
                  clients: 0,
                  closed: 0,
                ),
                data: (stats) => _StatsGrid(
                  revenue: (stats['total_revenue'] as num?)?.toDouble() ?? 0,
                  auctions: (stats['total_auctions'] as num?)?.toInt() ?? 0,
                  bids: (stats['total_bids'] as num?)?.toInt() ?? 0,
                  clients: (stats['total_clients'] as num?)?.toInt() ?? 0,
                  closed: (stats['closed_auctions'] as num?)?.toInt() ?? 0,
                ),
              ),
              const SizedBox(height: 24),

              // ── Performance by region ────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    color: AppColors.gold,
                    margin: const EdgeInsets.only(right: 8),
                  ),
                  Text(context.l10n.performanceByRegion,
                      style: AppTextStyles.h1),
                ],
              ),
              const SizedBox(height: 14),

              statsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        color: AppColors.primaryBlue),
                  ),
                ),
                error: (_, _) =>
                    const EmptyStateCard('Failed to load region data'),
                data: (stats) {
                  final auctionsByRegion =
                      (stats['auctions_by_region'] as Map<String, int>?) ??
                          {};
                  final revenueByRegion =
                      (stats['revenue_by_region'] as Map<String, double>?) ??
                          {};

                  // Merge region data: from stats provider + admin list fallback
                  return adminsAsync.when(
                    loading: () =>
                        _RegionChart(auctionsByRegion, revenueByRegion, []),
                    error: (_, _) =>
                        _RegionChart(auctionsByRegion, revenueByRegion, []),
                    data: (admins) =>
                        _RegionChart(auctionsByRegion, revenueByRegion, admins),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 2),
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.revenue,
    required this.auctions,
    required this.bids,
    required this.clients,
    required this.closed,
  });
  final double revenue;
  final int auctions, bids, clients, closed;

  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: [
          _RCard(Icons.account_balance_wallet_outlined,
              context.l10n.totalRevenue, AppFormatters.rwfCompact(revenue)),
          _RCard(Icons.gavel_outlined, context.l10n.auctionsLabel, '$auctions'),
          _RCard(Icons.check_circle_outline, context.l10n.closedStat, '$closed'),
          _RCard(Icons.monetization_on_outlined, context.l10n.bidsLabel, '$bids'),
        ],
      );
}

class _StatsGridPlaceholder extends StatelessWidget {
  const _StatsGridPlaceholder();

  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        children: [
          _RCard(Icons.account_balance_wallet_outlined,
              context.l10n.totalRevenue, '…'),
          _RCard(Icons.gavel_outlined, context.l10n.auctionsLabel, '…'),
          _RCard(Icons.check_circle_outline, context.l10n.closedStat, '…'),
          _RCard(Icons.monetization_on_outlined, context.l10n.bidsLabel, '…'),
        ],
      );
}

class _RCard extends StatelessWidget {
  const _RCard(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppColors.primaryBlue),
            const Spacer(),
            Text(label, style: AppTextStyles.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}

// ── Region performance chart ──────────────────────────────────────────────────

class _RegionChart extends StatelessWidget {
  const _RegionChart(
    this.auctionsByRegion,
    this.revenueByRegion,
    this.admins,
  );
  final Map<String, int>    auctionsByRegion;
  final Map<String, double> revenueByRegion;
  final List admins; // List<RegionAdminModel>

  @override
  Widget build(BuildContext context) {
    // Build the set of regions to display
    final regionSet = <String>{
      ...auctionsByRegion.keys,
      ...SupabaseConstants.regions,
    };

    if (regionSet.isEmpty) {
      return EmptyStateCard(
          context.l10n.noAuctionDataForPeriod, icon: Icons.bar_chart_outlined);
    }

    final maxAuctions = auctionsByRegion.values.fold(1, (m, v) => v > m ? v : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: regionSet.indexed.map((entry) {
          final i      = entry.$1;
          final region = entry.$2;
          final count  = auctionsByRegion[region] ?? 0;
          final rev    = revenueByRegion[region] ?? 0.0;
          final ratio  = count / maxAuctions;

          return Column(
            children: [
              if (i > 0)
                const Divider(height: 24, color: AppColors.border),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.regionLabel(region), style: AppTextStyles.h3),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(context.l10n.auctionsCount(count),
                          style: AppTextStyles.bodySmall),
                      if (rev > 0)
                        Text(AppFormatters.rwfCompact(rev),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkGold,
                            )),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: LinearProgressIndicator(
                  value: count == 0 ? 0.02 : ratio,
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceGrey,
                  valueColor: AlwaysStoppedAnimation(
                    count == 0
                        ? AppColors.border
                        : AppColors.primaryBlue,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
