// lib/core/utils/date_notification_helpers.dart
import 'package:intl/intl.dart';

class DateHelper {
  DateHelper._();

  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, HH:mm');
  static final _time = DateFormat('HH:mm');

  static String formatDate(DateTime dt) => _date.format(dt);
  static String formatDateTime(DateTime dt) => _dateTime.format(dt);
  static String formatTime(DateTime dt) => _time.format(dt);

  static String formatCountdown(DateTime endDate) {
    final diff = endDate.difference(DateTime.now());
    if (diff.isNegative) return 'Ended';
    final d = diff.inDays;
    final h = diff.inHours.remainder(24);
    final m = diff.inMinutes.remainder(60);
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static bool isExpired(DateTime endDate) => DateTime.now().isAfter(endDate);

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(dt);
  }
}

class NotificationHelper {
  NotificationHelper._();

  static String? getNavigationRoute(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final auctionId = data['auction_id'] as String?;
    return switch (type) {
      'new_auction' when auctionId != null => '/auction/$auctionId',
      'winning' => '/my-bids',
      'outbid' when auctionId != null => '/auction/$auctionId',
      'won' => '/bid-confirmation',
      'system' => '/notifications',
      _ => null,
    };
  }

  static String typeLabel(String type) => switch (type) {
    'new_auction' => 'New Auction',
    'winning' => 'Winning Bid',
    'outbid' => 'Outbid',
    'won' => 'Auction Won',
    'system' => 'System',
    _ => 'Notification',
  };
}
