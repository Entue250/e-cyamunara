// lib/presentation/screens/client/notifications_screen.dart
//
// ─── SCREEN 10: NOTIFICATIONS ─────────────────────────────────────────────────
// Shows: Back button + "Notifications" title + "Mark all read" action,
//        filter tabs (All / Bids / Auctions / Results), notification tiles
//        (tapping marks individual as read), promo card at bottom.
//
// Connected to: notificationsProvider(uid) — real-time Supabase stream
//               userRepositoryProvider.markNotificationRead()
//               userRepositoryProvider.markAllNotificationsRead()
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/localization/app_localizations_ext.dart';
import '../../../core/utils/date_notification_helpers.dart';
import 'client_shared.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int _selectedTab = 0;

  void _openDetail(NotificationModel notif) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(
        notification: notif,
        onMarkRead: notif.isRead ? null : () => _markOneRead(notif.notificationId),
      ),
    );
  }

  Future<void> _markAllRead(String uid) async {
    try {
      await ref.read(userRepositoryProvider).markAllNotificationsRead(uid);
    } catch (_) {}
  }

  Future<void> _markOneRead(String notifId) async {
    try {
      await ref.read(userRepositoryProvider).markNotificationRead(notifId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final uid = userAsync.value?.uid ?? '';

    final notifsAsync = uid.isNotEmpty
        ? ref.watch(notificationsProvider(uid))
        : const AsyncData<List<NotificationModel>>([]);

    final l10n = context.l10n;
    final tabs = [l10n.all, l10n.bids, l10n.auctions, l10n.results];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        title: Text(l10n.notifications),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.go(AppRoutes.home),
        ),
        actions: [
          TextButton(
            onPressed: uid.isNotEmpty ? () => _markAllRead(uid) : null,
            child: Text(
              l10n.markAllRead,
              style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
          ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
        error: (e, _) => ClientErrorCard(e.toString()),
        data: (notifications) {
          final filtered = _selectedTab == 0
              ? notifications
              : notifications.where((n) {
                  return switch (_selectedTab) {
                    1 => n.type == 'winning' ||
                        n.type == 'outbid' ||
                        n.type == 'won',
                    2 => n.type == 'new_auction',
                    3 => n.type == 'won',
                    _ => true,
                  };
                }).toList();

          return Column(
            children: [
              // ── Filter tab bar ─────────────────────────────────────────────
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: List.generate(tabs.length, (i) {
                    final isSel = i == _selectedTab;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = i),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSel
                                ? AppColors.primaryBlue
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            tabs[i],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isSel
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              // ── Notification list ──────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyNotificationsState(tabs[_selectedTab])
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length + 1,
                        itemBuilder: (_, i) {
                          if (i == filtered.length) {
                            return _WinningStreakCard();
                          }
                          final notif = filtered[i];
                          return NotificationTile(
                            notification: notif,
                            onTap: () => _openDetail(notif),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Winning streak promo card
// ─────────────────────────────────────────────────────────────────────────────

class _WinningStreakCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.winningStreak,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.keepBidding,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => context.go(AppRoutes.home),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        context.l10n.viewAuctions,
                        style: const TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.emoji_events, size: 56, color: Colors.white24),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationDetailSheet extends StatelessWidget {
  const _NotificationDetailSheet({
    required this.notification,
    this.onMarkRead,
  });
  final NotificationModel notification;
  final VoidCallback? onMarkRead;

  static const Map<String, ({IconData icon, Color color, Color bg})>
      _typeConfig = {
    'new_auction': (
      icon: Icons.gavel,
      color: AppColors.gold,
      bg: Color(0xFFFFF9E0),
    ),
    'winning': (
      icon: Icons.emoji_events,
      color: AppColors.success,
      bg: Color(0xFFE8F5E9),
    ),
    'outbid': (
      icon: Icons.gavel,
      color: AppColors.error,
      bg: Color(0xFFFFEBEE),
    ),
    'won': (
      icon: Icons.emoji_events,
      color: AppColors.success,
      bg: Color(0xFFE8F5E9),
    ),
    'system': (
      icon: Icons.shield,
      color: AppColors.info,
      bg: Color(0xFFE3F2FD),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[notification.type] ??
        (
          icon: Icons.notifications,
          color: AppColors.textSecondary,
          bg: AppColors.surfaceGrey,
        );

    return Container(
      margin: const EdgeInsets.only(top: 64),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cfg.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(cfg.icon, color: cfg.color, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.type.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: cfg.color,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            DateHelper.formatDate(notification.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!notification.isRead)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(notification.title, style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(
                  notification.body,
                  style: AppTextStyles.bodyMedium,
                ),
                if (notification.auctionId != null &&
                    notification.auctionId!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go('/auction/${notification.auctionId}');
                    },
                    icon: const Icon(Icons.gavel_outlined, size: 16),
                    label: Text(context.l10n.viewAuction),
                  ),
                ],
                if (onMarkRead != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        onMarkRead!();
                        Navigator.pop(context);
                      },
                      child: Text(context.l10n.markAsRead),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.close),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState(this.filterName);
  final String filterName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_none,
              size: 64, color: AppColors.border),
          const SizedBox(height: 16),
          Text(
            filterName == l10n.all
                ? l10n.noNotificationsYet
                : l10n.noFilterNotifications(filterName),
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.notifyAboutBids,
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
