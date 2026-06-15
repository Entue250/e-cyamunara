// test/ai/ai_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ecyamunara/data/models/models.dart';
import 'package:ecyamunara/data/repositories/ai_repository.dart';

// Builds a minimal AuctionModel for testing. Only set the fields relevant to
// each test — all others default to safe values.
AuctionModel _makeAuction({
  String? mainCategory,
  String category = 'vehicle',
  String? brand,
  String condition = 'good',
  String region = 'Central',
  double startingPrice = 5_000_000,
  String? fuelType,
  String? transmission,
  int? mileage,
  String? ownershipHistory,
  String? accidentHistory,
  String? insuranceStatus,
  int? manufacturingYear,
  String description = 'A test vehicle',
  List<String> photoUrls = const ['photo.jpg'],
  int totalBids = 3,
  int viewsCount = 30,
  int uniqueBidderCount = 2,
  DateTime? timeOfFirstBid,
  DateTime? startDate,
  DateTime? endDate,
}) {
  final anchor = DateTime(2026, 6, 15, 12, 0);
  return AuctionModel(
    auctionId: 'test-001',
    itemName: 'Test Vehicle',
    category: category,
    plateNumber: 'RAC 000 A',
    condition: condition,
    description: description,
    photoUrls: photoUrls,
    startingPrice: startingPrice,
    currentHighestBid: startingPrice,
    totalBids: totalBids,
    region: region,
    postedByAdminUid: 'admin-1',
    postedByAdminName: 'Test Admin',
    auctionStatus: 'active',
    startDate: startDate ?? anchor.subtract(const Duration(days: 1)),
    endDate: endDate ?? anchor.add(const Duration(hours: 72)),
    createdAt: anchor,
    updatedAt: anchor,
    mainCategory: mainCategory,
    brand: brand,
    fuelType: fuelType,
    transmission: transmission,
    mileage: mileage,
    ownershipHistory: ownershipHistory,
    accidentHistory: accidentHistory,
    insuranceStatus: insuranceStatus,
    manufacturingYear: manufacturingYear,
    viewsCount: viewsCount,
    uniqueBidderCount: uniqueBidderCount,
    timeOfFirstBid: timeOfFirstBid,
  );
}

void main() {
  // ── AiFeatures.base ────────────────────────────────────────────────────────

  group('AiFeatures.base — category resolution', () {
    test('uses mainCategory when set', () {
      final a = _makeAuction(mainCategory: 'Vehicle', category: 'vehicle');
      expect(AiFeatures.base(a)['main_category'], 'Vehicle');
    });

    test('falls back to category when mainCategory is null', () {
      final a = _makeAuction(mainCategory: null, category: 'motorcycle');
      expect(AiFeatures.base(a)['main_category'], 'motorcycle');
    });
  });

  group('AiFeatures.base — known flags', () {
    test('is_mileage_known is false when mileage is null', () {
      expect(AiFeatures.base(_makeAuction(mileage: null))['is_mileage_known'], false);
    });

    test('is_mileage_known is true when mileage is set', () {
      expect(AiFeatures.base(_makeAuction(mileage: 80000))['is_mileage_known'], true);
    });

    test('is_manufacturing_year_known is false when null', () {
      expect(
        AiFeatures.base(_makeAuction(manufacturingYear: null))['is_manufacturing_year_known'],
        false,
      );
    });

    test('is_manufacturing_year_known is true when set', () {
      expect(
        AiFeatures.base(_makeAuction(manufacturingYear: 2020))['is_manufacturing_year_known'],
        true,
      );
    });

    test('is_accident_history_known is false when null', () {
      expect(
        AiFeatures.base(_makeAuction(accidentHistory: null))['is_accident_history_known'],
        false,
      );
    });

    test('is_accident_history_known is true when set', () {
      expect(
        AiFeatures.base(_makeAuction(accidentHistory: 'none'))['is_accident_history_known'],
        true,
      );
    });

    test('is_insurance_status_known is false when null', () {
      expect(
        AiFeatures.base(_makeAuction(insuranceStatus: null))['is_insurance_status_known'],
        false,
      );
    });

    test('has_description is false when description is empty', () {
      expect(AiFeatures.base(_makeAuction(description: ''))['has_description'], false);
    });

    test('has_description is true when description is non-empty', () {
      expect(AiFeatures.base(_makeAuction(description: 'Good car'))['has_description'], true);
    });

    test('has_images is false when photoUrls is empty', () {
      expect(AiFeatures.base(_makeAuction(photoUrls: []))['has_images'], false);
    });

    test('has_images is true when photoUrls is non-empty', () {
      expect(AiFeatures.base(_makeAuction(photoUrls: ['url1']))['has_images'], true);
    });
  });

  // ── AiFeatures.assetAge ────────────────────────────────────────────────────

  group('AiFeatures.assetAge', () {
    test('returns 5 when manufacturingYear is null', () {
      expect(AiFeatures.assetAge(_makeAuction(manufacturingYear: null)), 5);
    });

    test('computes age correctly from manufacturingYear', () {
      const year = 2020;
      final expected = DateTime.now().toUtc().year - year;
      expect(AiFeatures.assetAge(_makeAuction(manufacturingYear: year)), expected);
    });
  });

  // ── AiFeatures.durationHours ───────────────────────────────────────────────

  group('AiFeatures.durationHours', () {
    test('computes hours between startDate and endDate', () {
      final start = DateTime(2026, 6, 14, 10, 0);
      final end = DateTime(2026, 6, 17, 10, 0); // 72 hours later
      final a = _makeAuction(startDate: start, endDate: end);
      expect(AiFeatures.durationHours(a), closeTo(72.0, 0.01));
    });
  });

  // ── AiFeatures.forecast ────────────────────────────────────────────────────

  group('AiFeatures.forecast — price_tier', () {
    test('low when startingPrice < 2,000,000', () {
      expect(AiFeatures.forecast(_makeAuction(startingPrice: 1_500_000))['price_tier'], 'low');
    });

    test('medium when startingPrice between 2M and 8M', () {
      expect(AiFeatures.forecast(_makeAuction(startingPrice: 5_000_000))['price_tier'], 'medium');
    });

    test('high when startingPrice >= 8,000,000', () {
      expect(AiFeatures.forecast(_makeAuction(startingPrice: 10_000_000))['price_tier'], 'high');
    });

    test('medium when startingPrice == 2,000,000', () {
      expect(AiFeatures.forecast(_makeAuction(startingPrice: 2_000_000))['price_tier'], 'medium');
    });

    test('high when startingPrice == 8,000,000', () {
      expect(AiFeatures.forecast(_makeAuction(startingPrice: 8_000_000))['price_tier'], 'high');
    });
  });

  group('AiFeatures.forecast — days_until_close', () {
    test('is 0.0 when auction already ended', () {
      final past = DateTime(2026, 1, 1);
      final result = AiFeatures.forecast(_makeAuction(endDate: past))['days_until_close'] as double;
      expect(result, closeTo(0.0, 0.01));
    });
  });

  group('AiFeatures.forecast — bid_momentum', () {
    test('is 0.0 when no bids placed', () {
      final a = _makeAuction(totalBids: 0, timeOfFirstBid: null);
      expect(AiFeatures.forecast(a)['bid_momentum'], 0.0);
    });
  });

  group('AiFeatures.forecast — time_to_first_bid_hours', () {
    test('computes hours from startDate to timeOfFirstBid', () {
      final start = DateTime(2026, 6, 14, 10, 0);
      final firstBid = DateTime(2026, 6, 14, 12, 30); // 2.5 hours later
      final a = _makeAuction(startDate: start, timeOfFirstBid: firstBid);
      expect(AiFeatures.forecast(a)['time_to_first_bid_hours'], closeTo(2.5, 0.01));
    });

    test('is 0.0 when timeOfFirstBid is null', () {
      final a = _makeAuction(timeOfFirstBid: null);
      expect(AiFeatures.forecast(a)['time_to_first_bid_hours'], 0.0);
    });
  });

  group('AiFeatures.forecast — view_to_bid_ratio', () {
    test('equals viewsCount when totalBids is 0', () {
      final a = _makeAuction(totalBids: 0, viewsCount: 50);
      expect(AiFeatures.forecast(a)['view_to_bid_ratio'], 50.0);
    });

    test('is viewsCount / totalBids when totalBids > 0', () {
      final a = _makeAuction(totalBids: 5, viewsCount: 50);
      expect(AiFeatures.forecast(a)['view_to_bid_ratio'], closeTo(10.0, 0.01));
    });
  });

  group('AiFeatures.forecast — is_first_bid_quick', () {
    test('true when first bid arrived within 2 hours of start', () {
      final start = DateTime(2026, 6, 14, 10, 0);
      final firstBid = DateTime(2026, 6, 14, 11, 0); // 1 hour later
      final a = _makeAuction(startDate: start, timeOfFirstBid: firstBid);
      expect(AiFeatures.forecast(a)['is_first_bid_quick'], true);
    });

    test('false when first bid arrived after 2 hours from start', () {
      final start = DateTime(2026, 6, 14, 10, 0);
      final firstBid = DateTime(2026, 6, 14, 13, 0); // 3 hours later
      final a = _makeAuction(startDate: start, timeOfFirstBid: firstBid);
      expect(AiFeatures.forecast(a)['is_first_bid_quick'], false);
    });

    test('false when no first bid recorded', () {
      final a = _makeAuction(timeOfFirstBid: null);
      expect(AiFeatures.forecast(a)['is_first_bid_quick'], false);
    });
  });

  group('AiFeatures.forecast — bid_acceleration', () {
    test('always 0.5 (static default)', () {
      expect(AiFeatures.forecast(_makeAuction())['bid_acceleration'], 0.5);
    });
  });
}
