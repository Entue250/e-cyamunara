// lib/presentation/screens/admin/auction_form_data.dart
//
// Static const data for the ML-ready auction form.
// All stored values are English strings (ML consistency).
// Label helpers translate for display using BuildContext.

import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations_ext.dart';

class AuctionFormData {
  AuctionFormData._();

  static const List<String> mainCategories = ['vehicle', 'motorcycle', 'bicycle'];

  static const Map<String, List<String>> subcategoryMap = {
    'vehicle':    ['SUV','Sedan','Hatchback','Pickup','Truck','Van','Bus','Wagon','Coupe'],
    'motorcycle': ['Sport Bike','Cruiser','Touring','Scooter','Dirt Bike','Electric Motorcycle'],
    'bicycle':    ['Mountain Bike','Road Bike','BMX','Hybrid Bike','Electric Bicycle'],
  };

  static const Map<String, List<String>> brandMap = {
    'vehicle':    ['Toyota','Nissan','Hyundai','Isuzu','Mitsubishi','Mercedes','BMW','Kia','Honda','Ford','Subaru'],
    'motorcycle': ['Yamaha','Honda','TVS','Suzuki','Kawasaki','Bajaj'],
    'bicycle':    ['Giant','Trek','Specialized','Phoenix','Hero'],
  };

  static const List<String> fuelTypes     = ['Petrol','Diesel','Hybrid','Electric'];
  static const List<String> transmissions = ['Automatic','Manual','CVT'];
  static const List<String> conditions    = ['Excellent','Very Good','Good','Fair','Poor'];
  static const List<String> drivetrains   = ['FWD','RWD','AWD','4WD'];
  static const List<String> frameMaterials = ['Aluminum','Steel','Carbon Fiber','Titanium'];
  static const List<String> suspensions   = ['Full Suspension','Front Only','Rigid'];
  static const List<String> brakeTypes    = ['Disc','V-Brake','Drum','Hydraulic Disc'];
  static const List<String> ownershipOptions = [
    'First Owner','Second Owner','Third Owner','Fleet Vehicle',
  ];
  static const List<String> insuranceOptions = [
    'Insured','Expired','Never Insured','Unknown',
  ];
  static const List<String> accidentOptions  = [
    'No Accidents','Minor Damage','Major Damage','Unknown',
  ];

  static List<int> get years {
    final current = DateTime.now().year;
    return List.generate(current - 1900 + 1, (i) => current - i);
  }

  // ── Label helpers (stored English → localized display) ────────────────────

  static String mainCategoryLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'vehicle'    => l10n.vehicleLabel,
      'motorcycle' => l10n.motorcycleLabel,
      'bicycle'    => l10n.bicycleLabel,
      _            => value,
    };
  }

  static String fuelTypeLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'Petrol'   => l10n.optionPetrol,
      'Diesel'   => l10n.optionDiesel,
      'Hybrid'   => l10n.optionHybrid,
      'Electric' => l10n.optionElectric,
      _          => value,
    };
  }

  static String transmissionLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'Automatic' => l10n.optionAutomatic,
      'Manual'    => l10n.optionManual,
      'CVT'       => l10n.optionCvt,
      _           => value,
    };
  }

  static String conditionLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'Excellent'  => l10n.optionExcellent,
      'Very Good'  => l10n.optionVeryGood,
      'Good'       => l10n.optionGood,
      'Fair'       => l10n.optionFair,
      'Poor'       => l10n.optionPoor,
      _            => value,
    };
  }

  static String ownershipLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'First Owner'   => l10n.optionFirstOwner,
      'Second Owner'  => l10n.optionSecondOwner,
      'Third Owner'   => l10n.optionThirdOwner,
      'Fleet Vehicle' => l10n.optionFleetVehicle,
      _               => value,
    };
  }

  static String insuranceLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'Insured'       => l10n.optionInsured,
      'Expired'       => l10n.optionExpiredInsurance,
      'Never Insured' => l10n.optionNeverInsured,
      'Unknown'       => l10n.optionUnknown,
      _               => value,
    };
  }

  static String accidentLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'No Accidents' => l10n.optionNoAccidents,
      'Minor Damage' => l10n.optionMinorDamage,
      'Major Damage' => l10n.optionMajorDamage,
      'Unknown'      => l10n.optionUnknown,
      _              => value,
    };
  }

  // Icon per main category
  static IconData categoryIcon(String category) => switch (category) {
    'vehicle'    => Icons.directions_car_outlined,
    'motorcycle' => Icons.motorcycle_outlined,
    'bicycle'    => Icons.pedal_bike_outlined,
    _            => Icons.directions_car_outlined,
  };
}
