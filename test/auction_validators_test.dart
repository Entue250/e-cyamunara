// test/auction_validators_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ecyamunara/core/utils/validators.dart';

void main() {
  group('AuctionValidators.validateYearRaw', () {
    test('null returns error', () {
      expect(AuctionValidators.validateYearRaw(null), isNotNull);
    });

    test('1899 returns error', () {
      expect(AuctionValidators.validateYearRaw(1899), isNotNull);
    });

    test('future year returns error', () {
      expect(
        AuctionValidators.validateYearRaw(DateTime.now().year + 1),
        isNotNull,
      );
    });

    test('1900 is valid', () {
      expect(AuctionValidators.validateYearRaw(1900), isNull);
    });

    test('current year is valid', () {
      expect(AuctionValidators.validateYearRaw(DateTime.now().year), isNull);
    });

    test('2020 is valid', () {
      expect(AuctionValidators.validateYearRaw(2020), isNull);
    });
  });

  group('AuctionValidators.validateMileageRaw', () {
    test('null returns error for vehicle', () {
      expect(AuctionValidators.validateMileageRaw(null, 'vehicle'), isNotNull);
    });

    test('negative returns error', () {
      expect(AuctionValidators.validateMileageRaw('-1', 'vehicle'), isNotNull);
    });

    test('zero is valid', () {
      expect(AuctionValidators.validateMileageRaw('0', 'vehicle'), isNull);
    });

    test('valid mileage passes', () {
      expect(AuctionValidators.validateMileageRaw('45000', 'motorcycle'), isNull);
    });

    test('bicycle always passes', () {
      expect(AuctionValidators.validateMileageRaw(null, 'bicycle'), isNull);
      expect(AuctionValidators.validateMileageRaw('-999', 'bicycle'), isNull);
    });
  });

  group('AuctionValidators.validateEngineCcRaw', () {
    test('null returns error for motorcycle', () {
      expect(AuctionValidators.validateEngineCcRaw(null, 'motorcycle'), isNotNull);
    });

    test('zero returns error', () {
      expect(AuctionValidators.validateEngineCcRaw('0', 'motorcycle'), isNotNull);
    });

    test('valid CC passes', () {
      expect(AuctionValidators.validateEngineCcRaw('155', 'motorcycle'), isNull);
    });

    test('null is fine for vehicle', () {
      expect(AuctionValidators.validateEngineCcRaw(null, 'vehicle'), isNull);
    });

    test('null is fine for bicycle', () {
      expect(AuctionValidators.validateEngineCcRaw(null, 'bicycle'), isNull);
    });
  });
}
