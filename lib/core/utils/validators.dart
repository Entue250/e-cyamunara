// ════════════════════════════════════════════════════════════════════
// lib/core/utils/validators.dart
// ════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../localization/app_localizations_ext.dart';

class AppValidators {
  AppValidators._();

  // ── Localized factory validators ─────────────────────────────────────────

  static FormFieldValidator<String> phone(AppLocalizations l10n) =>
      (value) => _validatePhone(value, l10n);

  static FormFieldValidator<String> nationalId(AppLocalizations l10n) =>
      (value) => _validateNationalId(value, l10n);

  static FormFieldValidator<String> password(AppLocalizations l10n) =>
      (value) => _validatePassword(value, l10n);

  static FormFieldValidator<String> confirmPassword(
    AppLocalizations l10n,
    String Function() getPassword,
  ) =>
      (value) => _validateConfirmPassword(value, getPassword(), l10n);

  static FormFieldValidator<String> fullName(AppLocalizations l10n) =>
      (value) => _validateFullName(value, l10n);

  static FormFieldValidator<String> bidAmount(
    AppLocalizations l10n,
    double currentHighest,
  ) =>
      (value) => _validateBidAmount(value, currentHighest, l10n);

  static FormFieldValidator<String> description(AppLocalizations l10n) =>
      (value) => _validateDescription(value, l10n);

  static FormFieldValidator<String> feedbackComment(AppLocalizations l10n) =>
      (value) => _validateFeedbackComment(value, l10n);

  // ── Non-localized helpers (still needed for places without context) ───────

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) return 'Phone number is required';
    final regex = RegExp(r'^(07[2389]\d{7}|\+2507[2389]\d{7})$');
    if (!regex.hasMatch(value.trim())) {
      return 'Enter a valid Rwanda phone number (e.g. 0782345678)';
    }
    return null;
  }

  static String? validateNationalId(String? value) {
    if (value == null || value.trim().isEmpty) return 'National ID is required';
    final id = value.trim().replaceAll(' ', '');
    if (id.length != 16) return 'National ID must be exactly 16 digits';
    if (!RegExp(r'^\d{16}$').hasMatch(id)) {
      return 'National ID must contain digits only';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Add at least one uppercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add at least one number';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Add at least one special character (!@#\$...)';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Full name is required';
    if (value.trim().length < 3) return 'Name is too short';
    return null;
  }

  static String? validateBidAmount(String? value, double currentHighest) {
    if (value == null || value.trim().isEmpty) return 'Bid amount is required';
    final amount = double.tryParse(value.trim().replaceAll(',', ''));
    if (amount == null) return 'Enter a valid amount';
    if (amount <= 0) return 'Bid must be greater than zero';
    if (amount <= currentHighest) {
      return 'Bid must be higher than RWF ${formatRWF(currentHighest)}';
    }
    return null;
  }

  static String? validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) return 'Description is required';
    if (value.trim().length < 20) {
      return 'Description must be at least 20 characters';
    }
    return null;
  }

  static String? validateFeedbackComment(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 250) {
      return 'Comment must not exceed 250 characters';
    }
    return null;
  }

  static String? validateEndDate(DateTime? endDate, DateTime? startDate) {
    if (endDate == null) return 'End date is required';
    if (startDate != null && endDate.isBefore(startDate)) {
      return 'End date must be after start date';
    }
    if (endDate.isBefore(DateTime.now())) {
      return 'End date must be in the future';
    }
    return null;
  }

  static String? validateEndDateL10n(
    DateTime? endDate,
    DateTime? startDate,
    AppLocalizations l10n,
  ) {
    if (endDate == null) return l10n.validatorEndDateRequired;
    if (startDate != null && endDate.isBefore(startDate)) {
      return l10n.validatorEndDateBeforeStart;
    }
    if (endDate.isBefore(DateTime.now())) {
      return l10n.validatorEndDatePast;
    }
    return null;
  }

  static String formatRWF(double amount) =>
      'RWF ${NumberFormat('#,###', 'en_US').format(amount.toInt())}';

  static double? parseAmount(String value) =>
      double.tryParse(value.trim().replaceAll(',', '').replaceAll(' ', ''));

  static String normalizePhone(String phone) {
    final cleaned = phone.trim().replaceAll(' ', '');
    if (cleaned.startsWith('+250')) return '0${cleaned.substring(4)}';
    return cleaned;
  }

  // ── Private localized implementations ────────────────────────────────────

  static String? _validatePhone(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorPhoneRequired;
    }
    final regex = RegExp(r'^(07[2389]\d{7}|\+2507[2389]\d{7})$');
    if (!regex.hasMatch(value.trim())) return l10n.validatorPhoneInvalid;
    return null;
  }

  static String? _validateNationalId(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorNationalIdRequired;
    }
    final id = value.trim().replaceAll(' ', '');
    if (id.length != 16) return l10n.validatorNationalIdLength;
    if (!RegExp(r'^\d{16}$').hasMatch(id)) {
      return l10n.validatorNationalIdDigitsOnly;
    }
    return null;
  }

  static String? _validatePassword(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.validatorPasswordRequired;
    if (value.length < 8) return l10n.validatorPasswordTooShort;
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return l10n.validatorPasswordUppercase;
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) return l10n.validatorPasswordNumber;
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return l10n.validatorPasswordSpecial;
    }
    return null;
  }

  static String? _validateConfirmPassword(
    String? value,
    String password,
    AppLocalizations l10n,
  ) {
    if (value == null || value.isEmpty) return l10n.validatorConfirmRequired;
    if (value != password) return l10n.validatorPasswordsNoMatch;
    return null;
  }

  static String? _validateFullName(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorFullNameRequired;
    }
    if (value.trim().length < 3) return l10n.validatorNameTooShort;
    return null;
  }

  static String? _validateBidAmount(
    String? value,
    double currentHighest,
    AppLocalizations l10n,
  ) {
    if (value == null || value.trim().isEmpty) return l10n.validatorBidRequired;
    final amount = double.tryParse(value.trim().replaceAll(',', ''));
    if (amount == null) return l10n.validatorBidInvalid;
    if (amount <= 0) return l10n.validatorBidZero;
    if (amount <= currentHighest) {
      return l10n.validatorBidTooLow(formatRWF(currentHighest));
    }
    return null;
  }

  static String? _validateDescription(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) {
      return l10n.validatorDescriptionRequired;
    }
    if (value.trim().length < 20) return l10n.validatorDescriptionTooShort;
    return null;
  }

  static String? _validateFeedbackComment(
    String? value,
    AppLocalizations l10n,
  ) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.trim().length > 250) return l10n.validatorCommentTooLong;
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════
// AuctionValidators — category-aware validators for the ML-ready form
// ════════════════════════════════════════════════════════════════════
class AuctionValidators {
  AuctionValidators._();

  static final int _currentYear = DateTime.now().year;

  static String? validateYear(int? year, AppLocalizations l10n) {
    if (year == null) return l10n.validatorYearRequired;
    if (year < 1900 || year > _currentYear) {
      return l10n.validatorYearRange(_currentYear);
    }
    return null;
  }

  static String? validateMileage(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory == 'bicycle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorMileageRequired;
    final v = int.tryParse(value.trim());
    if (v == null) return l10n.validatorMileageRequired;
    if (v < 0) return l10n.validatorMileageNegative;
    return null;
  }

  static String? validateEngineCc(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory != 'motorcycle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorEngineCcRequired;
    final v = int.tryParse(value.trim());
    if (v == null || v <= 0) return l10n.validatorEngineCcRequired;
    return null;
  }

  static String? validateEngineSize(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory != 'vehicle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorEngineSizeRequired;
    final v = double.tryParse(value.trim());
    if (v == null || v <= 0) return l10n.validatorEngineSizeRequired;
    return null;
  }

  static String? validateTransmission(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory != 'vehicle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorTransmissionRequired;
    return null;
  }

  static String? validateGearCount(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory != 'bicycle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorGearCountRequired;
    final v = int.tryParse(value.trim());
    if (v == null || v <= 0) return l10n.validatorGearCountRequired;
    return null;
  }

  static String? validateFuelType(
      String? value, String mainCategory, AppLocalizations l10n) {
    if (mainCategory == 'bicycle') return null;
    if (value == null || value.trim().isEmpty) return l10n.validatorFuelTypeRequired;
    return null;
  }

  static String? validateRequired(String? value, String errorMessage) {
    if (value == null || value.trim().isEmpty) return errorMessage;
    return null;
  }

  static String? validateRequiredDropdown(String? value, String errorMessage) {
    if (value == null) return errorMessage;
    return null;
  }

  // Non-localized versions for unit testing
  static String? validateYearRaw(int? year) {
    if (year == null) return 'Year required';
    if (year < 1900 || year > DateTime.now().year) {
      return 'Year out of range';
    }
    return null;
  }

  static String? validateMileageRaw(String? value, String mainCategory) {
    if (mainCategory == 'bicycle') return null;
    if (value == null || value.trim().isEmpty) return 'Mileage required';
    final v = int.tryParse(value.trim());
    if (v == null) return 'Invalid mileage';
    if (v < 0) return 'Mileage cannot be negative';
    return null;
  }

  static String? validateEngineCcRaw(String? value, String mainCategory) {
    if (mainCategory != 'motorcycle') return null;
    if (value == null || value.trim().isEmpty) return 'Engine CC required';
    final v = int.tryParse(value.trim());
    if (v == null || v <= 0) return 'Engine CC must be positive';
    return null;
  }
}
