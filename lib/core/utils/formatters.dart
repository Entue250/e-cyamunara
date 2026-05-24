// ════════════════════════════════════════════════════════
// lib/core/utils/formatters.dart
// ════════════════════════════════════════════════════════
import 'package:intl/intl.dart';

class AppFormatters {
  AppFormatters._();
  static final _rwf = NumberFormat('#,###', 'en_US');

  static String rwf(double amount) => 'RWF ${_rwf.format(amount.toInt())}';
  static String rwfFromInt(int amount) => 'RWF ${_rwf.format(amount)}';
  static String rwfCompact(double amount) {
    if (amount >= 1_000_000) {
      return 'RWF ${(amount / 1_000_000).toStringAsFixed(1)}M';
    }
    if (amount >= 1_000) return 'RWF ${(amount / 1_000).toStringAsFixed(0)}K';
    return rwf(amount);
  }

  static String phone(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) {
      return '${d.substring(0, 4)} ${d.substring(4, 7)} ${d.substring(7)}';
    }
    return raw;
  }

  static String titleCase(String s) => s
      .split(' ')
      .map(
        (w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
      )
      .join(' ');

  static String categoryLabel(String cat) => titleCase(cat);

  static String conditionColor(String condition) => switch (condition) {
    'excellent' => '#2E7D32',
    'good' => '#1565C0',
    'fair' => '#E65100',
    'poor' => '#C62828',
    _ => '#757575',
  };
}
