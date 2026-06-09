// test/auction_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ecyamunara/data/models/models.dart';

void main() {
  group('AuctionModel.fromMap — backward compatibility', () {
    test('deserializes legacy row (no new columns) without error', () {
      final map = <String, dynamic>{
        'id': 'abc123',
        'item_name': 'Toyota Hilux 2018',
        'category': 'vehicle',
        'plate_number': 'RAD 000 A',
        'condition': 'good',
        'description': 'Good condition vehicle',
        'photo_urls': <String>[],
        'starting_price': 5000000,
        'current_highest_bid': 5000000,
        'total_bids': 0,
        'region': 'Central',
        'posted_by_admin_uid': 'uid1',
        'posted_by_admin_name': 'Admin',
        'auction_status': 'active',
        'start_date': '2026-06-01T00:00:00.000Z',
        'end_date': '2026-06-15T00:00:00.000Z',
        'created_at': '2026-06-01T00:00:00.000Z',
        'updated_at': '2026-06-01T00:00:00.000Z',
      };

      final auction = AuctionModel.fromMap(map);

      expect(auction.itemName, 'Toyota Hilux 2018');
      expect(auction.mainCategory, isNull);
      expect(auction.brand, isNull);
      expect(auction.manufacturingYear, isNull);
      expect(auction.resolvedMainCategory, 'vehicle');
    });

    test('deserializes new row with all ML fields', () {
      final map = <String, dynamic>{
        'id': 'def456',
        'item_name': 'Toyota RAV4 2020',
        'category': 'vehicle',
        'plate_number': 'RAD 001 B',
        'condition': 'Excellent',
        'description': 'ML-ready vehicle record',
        'photo_urls': <String>[],
        'starting_price': 8500000,
        'current_highest_bid': 8500000,
        'total_bids': 0,
        'region': 'Central',
        'posted_by_admin_uid': 'uid2',
        'posted_by_admin_name': 'Admin2',
        'auction_status': 'active',
        'start_date': '2026-06-01T00:00:00.000Z',
        'end_date': '2026-06-15T00:00:00.000Z',
        'created_at': '2026-06-01T00:00:00.000Z',
        'updated_at': '2026-06-01T00:00:00.000Z',
        'main_category': 'vehicle',
        'sub_category': 'SUV',
        'brand': 'Toyota',
        'model': 'RAV4',
        'manufacturing_year': 2020,
        'color': 'White',
        'mileage': 45000,
        'fuel_type': 'Petrol',
        'transmission': 'Automatic',
        'engine_size': 2.5,
        'drivetrain': 'AWD',
        'seating_capacity': 5,
        'ownership_history': 'First Owner',
        'accident_history': 'No Accidents',
        'insurance_status': 'Insured',
      };

      final auction = AuctionModel.fromMap(map);

      expect(auction.mainCategory, 'vehicle');
      expect(auction.subCategory, 'SUV');
      expect(auction.brand, 'Toyota');
      expect(auction.model, 'RAV4');
      expect(auction.manufacturingYear, 2020);
      expect(auction.mileage, 45000);
      expect(auction.fuelType, 'Petrol');
      expect(auction.transmission, 'Automatic');
      expect(auction.engineSize, 2.5);
      expect(auction.drivetrain, 'AWD');
      expect(auction.seatingCapacity, 5);
      expect(auction.ownershipHistory, 'First Owner');
    });

    test('toMap includes new fields when non-null, omits when null', () {
      final auction = AuctionModel(
        auctionId: 'g789',
        itemName: 'Yamaha R15 2021',
        category: 'motorcycle',
        plateNumber: 'RAD 002 C',
        condition: 'Very Good',
        description: 'Sport motorcycle',
        photoUrls: [],
        startingPrice: 1800000,
        currentHighestBid: 1800000,
        totalBids: 0,
        region: 'Eastern',
        postedByAdminUid: 'uid3',
        postedByAdminName: 'Admin3',
        auctionStatus: 'active',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 15),
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
        mainCategory: 'motorcycle',
        subCategory: 'Sport Bike',
        brand: 'Yamaha',
        model: 'R15',
        manufacturingYear: 2021,
        engineCc: 155,
      );

      final map = auction.toMap();

      expect(map['main_category'], 'motorcycle');
      expect(map['sub_category'], 'Sport Bike');
      expect(map['brand'], 'Yamaha');
      expect(map['engine_cc'], 155);
      expect(map.containsKey('engine_size'), isFalse);
      expect(map.containsKey('frame_material'), isFalse);
    });

    test('resolvedMainCategory falls back to category for legacy records', () {
      final legacy = AuctionModel(
        auctionId: 'h000',
        itemName: 'Old Car',
        category: 'vehicle',
        plateNumber: 'X',
        condition: 'good',
        description: 'Legacy record',
        photoUrls: [],
        startingPrice: 1,
        currentHighestBid: 1,
        totalBids: 0,
        region: 'Central',
        postedByAdminUid: 'u',
        postedByAdminName: 'a',
        auctionStatus: 'closed',
        startDate: DateTime(2026),
        endDate: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      expect(legacy.mainCategory, isNull);
      expect(legacy.resolvedMainCategory, 'vehicle');
    });
  });
}
