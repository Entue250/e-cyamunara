// lib/presentation/screens/super_admin/super_admin_notifications_screen.dart
//
// SCREEN — SUPER ADMIN NOTIFICATIONS
// Real-time notification stream for the logged-in super admin.
// Providers: currentSuperAdminProvider, notificationsProvider(uid)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/date_notification_helpers.dart';
import 'super_admin_shared.dart';

class SuperAdminNotificationsScreen extends ConsumerWidget {
  const SuperAdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final superAsync = ref.watch(currentSuperAdminProvider);
    final uid = superAsync.value?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('NOTIFICATIONS'),
        leading: const BackButton(),
        actions: [
          if (uid.isNotEmpty)
            TextButton(
              onPressed: () async {
                final repo = ref.read(userRepositoryProvider);
                try {
                  await repo.markAllNotificationsRead(uid);
                } catch (_) {}
              },
              child: const Text(
                'MARK ALL READ',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
        ],
      ),
      body: uid.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _NotificationsList(uid: uid),
      bottomNavigationBar: const SuperAdminBottomNav(currentIndex: 0),
    );
  }
}

class _NotificationsList extends ConsumerWidget {
  const _NotificationsList({required this.uid});
  final String uid;

  void _showDetail(BuildContext context, WidgetRef ref, NotificationModel notif) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotifDetailSheet(
        notification: notif,
        onMarkRead: notif.isRead
            ? null
            : () async {
                try {
                  await ref
                      .read(userRepositoryProvider)
                      .markNotificationRead(notif.notificationId);
                } catch (_) {}
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsProvider(uid));

    return notifsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            const Text('Failed to load notifications'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(notificationsProvider(uid)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (notifs) {
        if (notifs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_outlined,
                    size: 56, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text('No notifications yet.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(notificationsProvider(uid)),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifs.length,
            itemBuilder: (ctx, i) => _NotifTile(
              notif: notifs[i],
              onTap: () => _showDetail(ctx, ref, notifs[i]),
            ),
          ),
        );
      },
    );
  }
}

class _NotifDetailSheet extends StatelessWidget {
  const _NotifDetailSheet({required this.notification, this.onMarkRead});
  final NotificationModel notification;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final cfg = _notifTypeConfig(notification.type);
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
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: notification.isRead
                            ? AppColors.surfaceGrey
                            : cfg.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        cfg.icon,
                        size: 22,
                        color: notification.isRead
                            ? AppColors.textSecondary
                            : cfg.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.type.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkGold,
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
                        decoration: BoxDecoration(
                          color: cfg.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(notification.title, style: AppTextStyles.h2),
                const SizedBox(height: 8),
                Text(notification.body, style: AppTextStyles.bodyMedium),
                const SizedBox(height: 20),
                if (onMarkRead != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        onMarkRead!();
                        Navigator.pop(context);
                      },
                      child: const Text('Mark as Read'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Returns type-specific icon + accent colour for a notification type.
// AI pipeline types get distinct visuals so super admins can triage at a glance.
({IconData icon, Color color}) _notifTypeConfig(String type) => switch (type) {
  'ai_drift'    => (icon: Icons.warning_amber_outlined, color: const Color(0xFFFF8F00)),
  'ai_rollback' => (icon: Icons.history,                color: AppColors.primaryBlue),
  'ai_retrain'  => (icon: Icons.science_outlined,       color: const Color(0xFF7B1FA2)),
  _             => (icon: Icons.notifications_outlined,  color: AppColors.primaryBlue),
};

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.notif, required this.onTap});
  final NotificationModel notif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRead = notif.isRead;
    final cfg = _notifTypeConfig(notif.type);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? AppColors.surface
              : cfg.color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isRead
                ? AppColors.border
                : cfg.color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isRead
                    ? AppColors.surfaceGrey
                    : cfg.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                cfg.icon,
                size: 20,
                color: isRead ? AppColors.textSecondary : cfg.color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notif.title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (notif.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notif.body,
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    DateHelper.timeAgo(notif.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 8),
                decoration: BoxDecoration(
                  color: cfg.color,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
