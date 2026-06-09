# ML-Ready Auction Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 19 structured nullable columns to the `auctions` table and rebuild the auction posting, detail, manage, and my-bids screens to capture and display ML-ready vehicle metadata across all three asset categories (vehicle, motorcycle, bicycle).

**Architecture:** Flat-column schema on Supabase (Approach A) — each auction row is a self-contained tabular training record. A new `AuctionFormData` static-data file drives all category-dependent dropdown logic in `PostAuctionScreen`. `AuctionModel` gains 19 nullable fields with fully backward-compatible `fromMap`/`toMap`. All display strings are localized in EN + RW; stored values are always English for ML consistency.

**Tech Stack:** Flutter 3.x · Riverpod · Supabase PostgreSQL · `flutter_localizations` (ARB) · GoRouter

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `supabase/migrations/20260609000000_ml_ready_auction_metadata.sql` | Create | Adds 19 columns; migrates 'car'→'vehicle' |
| `lib/core/constants/supabase_constants.dart` | Modify | Updates `categories` list |
| `lib/data/models/models.dart` | Modify | Adds 19 nullable fields to `AuctionModel` |
| `lib/l10n/app_en.arb` | Modify | ~52 new keys (field labels, options, validators) |
| `lib/l10n/app_rw.arb` | Modify | Same ~52 keys in Kinyarwanda |
| `lib/core/utils/validators.dart` | Modify | Adds `AuctionValidators` class |
| `lib/presentation/screens/admin/auction_form_data.dart` | Create | Static const maps, lists, label-lookup helpers |
| `lib/presentation/screens/admin/post_auction_screen.dart` | Modify | Full redesign — 5 collapsible sections |
| `lib/presentation/screens/admin/admin_shared.dart` | Modify | `ManageAuctionCard` + `RecentAuctionCard` show brand chip |
| `lib/presentation/screens/client/auction_detail_screen.dart` | Modify | Replaces spec grid with `_SpecsTable`; updates badge/placeholder |
| `lib/presentation/screens/client/client_shared.dart` | Modify | `BidTile` brand chip; fixes `AuctionPhotoPlaceholder` 'car'→'vehicle' |
| `test/auction_model_test.dart` | Create | AuctionModel backward-compat + new-field round-trip tests |
| `test/auction_validators_test.dart` | Create | AuctionValidators unit tests |

---

## Task 1: Create SQL Migration

> **GUIDANCE — Run this migration FIRST before writing any Flutter code.** Open your Supabase project dashboard → SQL Editor → paste the file contents and run. Alternatively: `supabase db push` if using the CLI. Verify the new columns appear in the `auctions` table schema viewer before proceeding.

**Files:**
- Create: `supabase/migrations/20260609000000_ml_ready_auction_metadata.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/20260609000000_ml_ready_auction_metadata.sql
-- ML-ready auction metadata — adds 19 nullable columns to auctions.
-- All columns are nullable so existing rows are unaffected.

ALTER TABLE auctions
  ADD COLUMN IF NOT EXISTS main_category      TEXT,
  ADD COLUMN IF NOT EXISTS sub_category       TEXT,
  ADD COLUMN IF NOT EXISTS brand              TEXT,
  ADD COLUMN IF NOT EXISTS model              TEXT,
  ADD COLUMN IF NOT EXISTS manufacturing_year INTEGER,
  ADD COLUMN IF NOT EXISTS color              TEXT,
  ADD COLUMN IF NOT EXISTS mileage            INTEGER,
  ADD COLUMN IF NOT EXISTS fuel_type          TEXT,
  ADD COLUMN IF NOT EXISTS transmission       TEXT,
  ADD COLUMN IF NOT EXISTS engine_size        NUMERIC(4,1),
  ADD COLUMN IF NOT EXISTS engine_cc          INTEGER,
  ADD COLUMN IF NOT EXISTS drivetrain         TEXT,
  ADD COLUMN IF NOT EXISTS seating_capacity   INTEGER,
  ADD COLUMN IF NOT EXISTS frame_material     TEXT,
  ADD COLUMN IF NOT EXISTS gear_count         INTEGER,
  ADD COLUMN IF NOT EXISTS suspension_type    TEXT,
  ADD COLUMN IF NOT EXISTS brake_type         TEXT,
  ADD COLUMN IF NOT EXISTS ownership_history  TEXT,
  ADD COLUMN IF NOT EXISTS accident_history   TEXT,
  ADD COLUMN IF NOT EXISTS insurance_status   TEXT;

-- Rename legacy 'car' category to 'vehicle'
UPDATE auctions SET category = 'vehicle' WHERE category = 'car';

-- Backfill main_category from the existing category column
UPDATE auctions SET main_category = category WHERE main_category IS NULL;
```

- [ ] **Step 2: Run migration in Supabase Dashboard**

Open Supabase Dashboard → SQL Editor → paste and execute.
Expected: `ALTER TABLE` success message, no errors.

Verify with:
```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'auctions'
  AND column_name IN ('main_category','brand','manufacturing_year','engine_cc')
ORDER BY column_name;
```
Expected: 4 rows returned.

- [ ] **Step 3: Commit the migration file**

```bash
git add supabase/migrations/20260609000000_ml_ready_auction_metadata.sql
git commit -m "feat(db): add 19 ML-ready columns to auctions table"
```

---

## Task 2: Update SupabaseConstants

**Files:**
- Modify: `lib/core/constants/supabase_constants.dart`

- [ ] **Step 1: Replace the categories list**

In `lib/core/constants/supabase_constants.dart`, change line 64:

```dart
// Before:
static const List<String> categories = ['car', 'motorcycle', 'bicycle'];

// After:
static const List<String> categories = ['vehicle', 'motorcycle', 'bicycle'];
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/constants/supabase_constants.dart
git commit -m "feat: rename category 'car' to 'vehicle' in constants"
```

---

## Task 3: Update AuctionModel

**Files:**
- Modify: `lib/data/models/models.dart` (lines 193–368)

- [ ] **Step 1: Replace the entire AuctionModel class**

Replace from `// ─── AuctionModel ───` to the end of the `AuctionModel` class (line 368) with:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// AuctionModel
// ─────────────────────────────────────────────────────────────────────────────
class AuctionModel {
  final String auctionId;
  final String itemName;
  final String category;
  final String plateNumber;
  final String condition;
  final String description;
  final List<String> photoUrls;
  final double startingPrice;
  final double currentHighestBid;
  final String? currentWinnerUid;
  final String? currentWinnerName;
  final int totalBids;
  final String region;
  final String postedByAdminUid;
  final String postedByAdminName;
  final String auctionStatus;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? closedAt;
  final String? winnerUid;
  final String? winnerName;
  final double? winningAmount;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ML-ready structured metadata
  final String? mainCategory;
  final String? subCategory;
  final String? brand;
  final String? model;
  final int? manufacturingYear;
  final String? color;
  final int? mileage;
  final String? fuelType;
  final String? transmission;
  final double? engineSize;
  final int? engineCc;
  final String? drivetrain;
  final int? seatingCapacity;
  final String? frameMaterial;
  final int? gearCount;
  final String? suspensionType;
  final String? brakeType;
  final String? ownershipHistory;
  final String? accidentHistory;
  final String? insuranceStatus;

  const AuctionModel({
    required this.auctionId,
    required this.itemName,
    required this.category,
    required this.plateNumber,
    required this.condition,
    required this.description,
    required this.photoUrls,
    required this.startingPrice,
    required this.currentHighestBid,
    this.currentWinnerUid,
    this.currentWinnerName,
    required this.totalBids,
    required this.region,
    required this.postedByAdminUid,
    required this.postedByAdminName,
    required this.auctionStatus,
    required this.startDate,
    required this.endDate,
    this.closedAt,
    this.winnerUid,
    this.winnerName,
    this.winningAmount,
    required this.createdAt,
    required this.updatedAt,
    this.mainCategory,
    this.subCategory,
    this.brand,
    this.model,
    this.manufacturingYear,
    this.color,
    this.mileage,
    this.fuelType,
    this.transmission,
    this.engineSize,
    this.engineCc,
    this.drivetrain,
    this.seatingCapacity,
    this.frameMaterial,
    this.gearCount,
    this.suspensionType,
    this.brakeType,
    this.ownershipHistory,
    this.accidentHistory,
    this.insuranceStatus,
  });

  factory AuctionModel.fromMap(Map<String, dynamic> map) => AuctionModel(
    auctionId:          map['id'] as String? ?? '',
    itemName:           map['item_name'] as String? ?? '',
    category:           map['category'] as String? ?? '',
    plateNumber:        map['plate_number'] as String? ?? '',
    condition:          map['condition'] as String? ?? '',
    description:        map['description'] as String? ?? '',
    photoUrls:          List<String>.from(map['photo_urls'] as List? ?? []),
    startingPrice:      (map['starting_price'] as num?)?.toDouble() ?? 0,
    currentHighestBid:  (map['current_highest_bid'] as num?)?.toDouble() ?? 0,
    currentWinnerUid:   map['current_winner_uid'] as String?,
    currentWinnerName:  map['current_winner_name'] as String?,
    totalBids:          (map['total_bids'] as num?)?.toInt() ?? 0,
    region:             map['region'] as String? ?? '',
    postedByAdminUid:   map['posted_by_admin_uid'] as String? ?? '',
    postedByAdminName:  map['posted_by_admin_name'] as String? ?? '',
    auctionStatus:      map['auction_status'] as String? ?? 'draft',
    startDate: DateTime.parse(
      map['start_date'] as String? ?? DateTime.now().toIso8601String(),
    ),
    endDate: DateTime.parse(
      map['end_date'] as String? ?? DateTime.now().toIso8601String(),
    ),
    closedAt: map['closed_at'] != null
        ? DateTime.parse(map['closed_at'] as String)
        : null,
    winnerUid:      map['winner_uid'] as String?,
    winnerName:     map['winner_name'] as String?,
    winningAmount:  (map['winning_amount'] as num?)?.toDouble(),
    createdAt: DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: DateTime.parse(
      map['updated_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    mainCategory:     map['main_category'] as String?,
    subCategory:      map['sub_category'] as String?,
    brand:            map['brand'] as String?,
    model:            map['model'] as String?,
    manufacturingYear:(map['manufacturing_year'] as num?)?.toInt(),
    color:            map['color'] as String?,
    mileage:          (map['mileage'] as num?)?.toInt(),
    fuelType:         map['fuel_type'] as String?,
    transmission:     map['transmission'] as String?,
    engineSize:       (map['engine_size'] as num?)?.toDouble(),
    engineCc:         (map['engine_cc'] as num?)?.toInt(),
    drivetrain:       map['drivetrain'] as String?,
    seatingCapacity:  (map['seating_capacity'] as num?)?.toInt(),
    frameMaterial:    map['frame_material'] as String?,
    gearCount:        (map['gear_count'] as num?)?.toInt(),
    suspensionType:   map['suspension_type'] as String?,
    brakeType:        map['brake_type'] as String?,
    ownershipHistory: map['ownership_history'] as String?,
    accidentHistory:  map['accident_history'] as String?,
    insuranceStatus:  map['insurance_status'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'item_name':            itemName,
    'category':             category,
    'plate_number':         plateNumber,
    'condition':            condition,
    'description':          description,
    'photo_urls':           photoUrls,
    'starting_price':       startingPrice,
    'current_highest_bid':  currentHighestBid,
    'current_winner_uid':   currentWinnerUid,
    'current_winner_name':  currentWinnerName,
    'total_bids':           totalBids,
    'region':               region,
    'posted_by_admin_uid':  postedByAdminUid,
    'posted_by_admin_name': postedByAdminName,
    'auction_status':       auctionStatus,
    'start_date':           startDate.toIso8601String(),
    'end_date':             endDate.toIso8601String(),
    'closed_at':            closedAt?.toIso8601String(),
    'winner_uid':           winnerUid,
    'winner_name':          winnerName,
    'winning_amount':       winningAmount,
    'updated_at':           updatedAt.toIso8601String(),
    if (mainCategory != null)     'main_category':      mainCategory,
    if (subCategory != null)      'sub_category':       subCategory,
    if (brand != null)            'brand':              brand,
    if (model != null)            'model':              model,
    if (manufacturingYear != null)'manufacturing_year': manufacturingYear,
    if (color != null)            'color':              color,
    if (mileage != null)          'mileage':            mileage,
    if (fuelType != null)         'fuel_type':          fuelType,
    if (transmission != null)     'transmission':       transmission,
    if (engineSize != null)       'engine_size':        engineSize,
    if (engineCc != null)         'engine_cc':          engineCc,
    if (drivetrain != null)       'drivetrain':         drivetrain,
    if (seatingCapacity != null)  'seating_capacity':   seatingCapacity,
    if (frameMaterial != null)    'frame_material':     frameMaterial,
    if (gearCount != null)        'gear_count':         gearCount,
    if (suspensionType != null)   'suspension_type':    suspensionType,
    if (brakeType != null)        'brake_type':         brakeType,
    if (ownershipHistory != null) 'ownership_history':  ownershipHistory,
    if (accidentHistory != null)  'accident_history':   accidentHistory,
    if (insuranceStatus != null)  'insurance_status':   insuranceStatus,
  };

  AuctionModel copyWith({
    String? itemName,
    String? category,
    String? plateNumber,
    String? condition,
    String? description,
    List<String>? photoUrls,
    double? startingPrice,
    double? currentHighestBid,
    String? currentWinnerUid,
    String? currentWinnerName,
    int? totalBids,
    String? region,
    String? postedByAdminUid,
    String? postedByAdminName,
    String? auctionStatus,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? closedAt,
    String? winnerUid,
    String? winnerName,
    double? winningAmount,
    DateTime? updatedAt,
    String? mainCategory,
    String? subCategory,
    String? brand,
    String? model,
    int? manufacturingYear,
    String? color,
    int? mileage,
    String? fuelType,
    String? transmission,
    double? engineSize,
    int? engineCc,
    String? drivetrain,
    int? seatingCapacity,
    String? frameMaterial,
    int? gearCount,
    String? suspensionType,
    String? brakeType,
    String? ownershipHistory,
    String? accidentHistory,
    String? insuranceStatus,
  }) => AuctionModel(
    auctionId:          auctionId,
    itemName:           itemName ?? this.itemName,
    category:           category ?? this.category,
    plateNumber:        plateNumber ?? this.plateNumber,
    condition:          condition ?? this.condition,
    description:        description ?? this.description,
    photoUrls:          photoUrls ?? this.photoUrls,
    startingPrice:      startingPrice ?? this.startingPrice,
    currentHighestBid:  currentHighestBid ?? this.currentHighestBid,
    currentWinnerUid:   currentWinnerUid ?? this.currentWinnerUid,
    currentWinnerName:  currentWinnerName ?? this.currentWinnerName,
    totalBids:          totalBids ?? this.totalBids,
    region:             region ?? this.region,
    postedByAdminUid:   postedByAdminUid ?? this.postedByAdminUid,
    postedByAdminName:  postedByAdminName ?? this.postedByAdminName,
    auctionStatus:      auctionStatus ?? this.auctionStatus,
    startDate:          startDate ?? this.startDate,
    endDate:            endDate ?? this.endDate,
    closedAt:           closedAt ?? this.closedAt,
    winnerUid:          winnerUid ?? this.winnerUid,
    winnerName:         winnerName ?? this.winnerName,
    winningAmount:      winningAmount ?? this.winningAmount,
    createdAt:          createdAt,
    updatedAt:          updatedAt ?? this.updatedAt,
    mainCategory:       mainCategory ?? this.mainCategory,
    subCategory:        subCategory ?? this.subCategory,
    brand:              brand ?? this.brand,
    model:              model ?? this.model,
    manufacturingYear:  manufacturingYear ?? this.manufacturingYear,
    color:              color ?? this.color,
    mileage:            mileage ?? this.mileage,
    fuelType:           fuelType ?? this.fuelType,
    transmission:       transmission ?? this.transmission,
    engineSize:         engineSize ?? this.engineSize,
    engineCc:           engineCc ?? this.engineCc,
    drivetrain:         drivetrain ?? this.drivetrain,
    seatingCapacity:    seatingCapacity ?? this.seatingCapacity,
    frameMaterial:      frameMaterial ?? this.frameMaterial,
    gearCount:          gearCount ?? this.gearCount,
    suspensionType:     suspensionType ?? this.suspensionType,
    brakeType:          brakeType ?? this.brakeType,
    ownershipHistory:   ownershipHistory ?? this.ownershipHistory,
    accidentHistory:    accidentHistory ?? this.accidentHistory,
    insuranceStatus:    insuranceStatus ?? this.insuranceStatus,
  );

  bool get isActive => auctionStatus == 'active';
  bool get isClosed => auctionStatus == 'closed';
  bool get isExpired => DateTime.now().isAfter(endDate);

  // Resolved main category — falls back to legacy 'category' field for old records
  String get resolvedMainCategory =>
      mainCategory?.isNotEmpty == true ? mainCategory! : category;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuctionModel && other.auctionId == auctionId);
  @override
  int get hashCode => auctionId.hashCode;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/data/models/models.dart
git commit -m "feat(model): add 19 ML-ready nullable fields to AuctionModel"
```

---

## Task 4: Write Model Tests

**Files:**
- Create: `test/auction_model_test.dart`

- [ ] **Step 1: Create the test file**

```dart
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
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/auction_model_test.dart -v
```

Expected: 4 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/auction_model_test.dart
git commit -m "test: add AuctionModel backward-compat and new-field round-trip tests"
```

---

## Task 5: Add Localization Keys — English

**Files:**
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: Add new keys before the closing `}`**

Open `lib/l10n/app_en.arb`. Before the final `}`, add a comma after the last existing entry, then append:

```json
  "basicInformation": "BASIC INFORMATION",
  "technicalSpecs": "TECHNICAL SPECIFICATIONS",
  "ownershipSection": "OWNERSHIP & HISTORY",

  "mainCategoryLabel": "MAIN CATEGORY",
  "subCategoryLabel": "SUB-CATEGORY",
  "brandLabel": "BRAND",
  "modelField": "MODEL",
  "manufacturingYearLabel": "MANUFACTURING YEAR",
  "colorField": "COLOR",
  "mileageField": "MILEAGE (KM)",
  "fuelTypeField": "FUEL TYPE",
  "transmissionField": "TRANSMISSION",
  "engineSizeField": "ENGINE SIZE (L)",
  "engineCcField": "ENGINE CC",
  "drivetrainField": "DRIVETRAIN",
  "seatingCapacityField": "SEATING CAPACITY",
  "frameMaterialField": "FRAME MATERIAL",
  "gearCountField": "GEAR COUNT",
  "suspensionTypeField": "SUSPENSION TYPE",
  "brakeTypeField": "BRAKE TYPE",
  "ownershipHistoryField": "OWNERSHIP HISTORY",
  "accidentHistoryField": "ACCIDENT HISTORY",
  "insuranceStatusField": "INSURANCE STATUS",

  "optionPetrol": "Petrol",
  "optionDiesel": "Diesel",
  "optionHybrid": "Hybrid",
  "optionElectric": "Electric",

  "optionAutomatic": "Automatic",
  "optionManual": "Manual",
  "optionCvt": "CVT",

  "optionExcellent": "Excellent",
  "optionVeryGood": "Very Good",
  "optionGood": "Good",
  "optionFair": "Fair",
  "optionPoor": "Poor",

  "optionFirstOwner": "First Owner",
  "optionSecondOwner": "Second Owner",
  "optionThirdOwner": "Third Owner",
  "optionFleetVehicle": "Fleet Vehicle",

  "optionInsured": "Insured",
  "optionExpiredInsurance": "Expired",
  "optionNeverInsured": "Never Insured",
  "optionUnknown": "Unknown",

  "optionNoAccidents": "No Accidents",
  "optionMinorDamage": "Minor Damage",
  "optionMajorDamage": "Major Damage",

  "validatorYearRange": "Year must be between 1900 and {year}",
  "@validatorYearRange": {
    "placeholders": { "year": { "type": "int" } }
  },
  "validatorMileageNegative": "Mileage cannot be negative",
  "validatorEngineCcRequired": "Engine CC is required for motorcycles",
  "validatorEngineSizeRequired": "Engine size is required for vehicles",
  "validatorTransmissionRequired": "Transmission is required for vehicles",
  "validatorGearCountRequired": "Gear count is required for bicycles",
  "validatorFuelTypeRequired": "Fuel type is required",
  "validatorSubCategoryRequired": "Sub-category is required",
  "validatorBrandRequired": "Brand is required",
  "validatorModelRequired": "Model name is required",
  "validatorColorRequired": "Color is required",
  "validatorYearRequired": "Manufacturing year is required",
  "validatorMileageRequired": "Mileage is required",
  "selectSubCategory": "Select sub-category",
  "selectBrand": "Select brand",
  "selectFuelType": "Select fuel type",
  "selectTransmission": "Select transmission",
  "selectDrivetrain": "Select drivetrain",
  "selectCondition": "Select condition",
  "selectFrameMaterial": "Select frame material",
  "selectSuspension": "Select suspension type",
  "selectBrakeType": "Select brake type",
  "selectOwnershipHistory": "Select ownership history",
  "selectAccidentHistory": "Select accident history",
  "selectInsuranceStatus": "Select insurance status",
  "vehicleLabel": "Vehicle",
  "motorcycleLabel": "Motorcycle",
  "bicycleLabel": "Bicycle",
  "brandSubcategoryChip": "{brand} • {subcategory}",
  "@brandSubcategoryChip": {
    "placeholders": {
      "brand": { "type": "String" },
      "subcategory": { "type": "String" }
    }
  }
```

- [ ] **Step 2: Run code generation**

```bash
flutter pub get
```

Expected: `app_localizations.dart` regenerates with new keys. No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/l10n/app_en.arb
git commit -m "feat(l10n): add EN localization keys for ML-ready auction form"
```

---

## Task 6: Add Localization Keys — Kinyarwanda

**Files:**
- Modify: `lib/l10n/app_rw.arb`

- [ ] **Step 1: Add same keys with Kinyarwanda translations before the closing `}`**

```json
  "basicInformation": "AMAKURU ASANZWE",
  "technicalSpecs": "IBISOBANURO BY'IMYIRONDORO",
  "ownershipSection": "UBUTENGANYI N'AMATEKA",

  "mainCategoryLabel": "UBWOKO BUKURU",
  "subCategoryLabel": "UBWOKO BUNINI",
  "brandLabel": "MAKA",
  "modelField": "MODELI",
  "manufacturingYearLabel": "UMWAKA W'UBUREMANE",
  "colorField": "IBARA",
  "mileageField": "KILOMETERI ZAGENZE",
  "fuelTypeField": "UBWOKO BW'INKORANA",
  "transmissionField": "INGIRISHI",
  "engineSizeField": "INGANO YA MOTERI (L)",
  "engineCcField": "CC YA MOTERI",
  "drivetrainField": "UBURYO BUGUKANDAGIRA",
  "seatingCapacityField": "IMYANYA YO KWICARA",
  "frameMaterialField": "IBIKORESHO BY'INZIZI",
  "gearCountField": "UMUBARE W'INGIRISHI",
  "suspensionTypeField": "UBWOKO BW'INZIRA",
  "brakeTypeField": "UBWOKO BW'AMAFARASHI",
  "ownershipHistoryField": "AMATEKA Y'UBUTENGANYI",
  "accidentHistoryField": "AMATEKA Y'IMPANUKA",
  "insuranceStatusField": "IMIMERERE Y'UBWISHINGIZI",

  "optionPetrol": "Benzini",
  "optionDiesel": "Mazutu",
  "optionHybrid": "Hybrid",
  "optionElectric": "Amashanyarazi",

  "optionAutomatic": "Otomatike",
  "optionManual": "Maniyeli",
  "optionCvt": "CVT",

  "optionExcellent": "Byiza cyane",
  "optionVeryGood": "Byiza",
  "optionGood": "Bifatika",
  "optionFair": "Bisanzwe",
  "optionPoor": "Bibi",

  "optionFirstOwner": "Nyir'wibanze",
  "optionSecondOwner": "Nyir'inshuro ya kabiri",
  "optionThirdOwner": "Nyir'inshuro ya gatatu",
  "optionFleetVehicle": "Imodoka ya Filote",

  "optionInsured": "Ifite ubwishingizi",
  "optionExpiredInsurance": "Ubwishingizi bwarangiye",
  "optionNeverInsured": "Ntabwo yigeze ifata ubwishingizi",
  "optionUnknown": "Ntizwi",

  "optionNoAccidents": "Nta mpanuka",
  "optionMinorDamage": "Ingaruka nto",
  "optionMajorDamage": "Ingaruka nini",

  "validatorYearRange": "Umwaka ugomba kuba hagati ya 1900 na {year}",
  "@validatorYearRange": {
    "placeholders": { "year": { "type": "int" } }
  },
  "validatorMileageNegative": "Kilometeri ntishobora kuba nke y'ubusa",
  "validatorEngineCcRequired": "CC ya moteri birakenewe ku moto",
  "validatorEngineSizeRequired": "Ingano ya moteri birakenewe ku modoka",
  "validatorTransmissionRequired": "Ingirishi birakenewe ku modoka",
  "validatorGearCountRequired": "Umubare w'ingirishi birakenewe ku igare",
  "validatorFuelTypeRequired": "Ubwoko bw'inkorana burakenewe",
  "validatorSubCategoryRequired": "Ubwoko bunini burakenewe",
  "validatorBrandRequired": "Maka irakenewe",
  "validatorModelRequired": "Izina rya modeli rirakenewe",
  "validatorColorRequired": "Ibara birakenewe",
  "validatorYearRequired": "Umwaka w'uburemane urakenewe",
  "validatorMileageRequired": "Kilometeri zagenze zirakenewe",
  "selectSubCategory": "Hitamo ubwoko bunini",
  "selectBrand": "Hitamo maka",
  "selectFuelType": "Hitamo ubwoko bw'inkorana",
  "selectTransmission": "Hitamo ingirishi",
  "selectDrivetrain": "Hitamo uburyo bugukandagira",
  "selectCondition": "Hitamo imimerere",
  "selectFrameMaterial": "Hitamo ibikoresho by'inzizi",
  "selectSuspension": "Hitamo ubwoko bw'inzira",
  "selectBrakeType": "Hitamo ubwoko bw'amafarashi",
  "selectOwnershipHistory": "Hitamo amateka y'ubutenganyi",
  "selectAccidentHistory": "Hitamo amateka y'impanuka",
  "selectInsuranceStatus": "Hitamo imimerere y'ubwishingizi",
  "vehicleLabel": "Imodoka",
  "motorcycleLabel": "Moto",
  "bicycleLabel": "Igare",
  "brandSubcategoryChip": "{brand} • {subcategory}",
  "@brandSubcategoryChip": {
    "placeholders": {
      "brand": { "type": "String" },
      "subcategory": { "type": "String" }
    }
  }
```

- [ ] **Step 2: Regenerate l10n**

```bash
flutter pub get
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/l10n/app_rw.arb
git commit -m "feat(l10n): add RW localization keys for ML-ready auction form"
```

---

## Task 7: Add AuctionValidators

**Files:**
- Modify: `lib/core/utils/validators.dart`

- [ ] **Step 1: Append AuctionValidators class at the end of validators.dart**

After the closing `}` of the `AppValidators` class, add:

```dart
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/utils/validators.dart
git commit -m "feat(validators): add AuctionValidators class for ML-ready form"
```

---

## Task 8: Write Validator Tests

**Files:**
- Create: `test/auction_validators_test.dart`

- [ ] **Step 1: Create the test file**

```dart
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
```

- [ ] **Step 2: Run tests**

```bash
flutter test test/auction_validators_test.dart -v
```

Expected: 11 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/auction_validators_test.dart
git commit -m "test: add AuctionValidators unit tests"
```

---

## Task 9: Create AuctionFormData

**Files:**
- Create: `lib/presentation/screens/admin/auction_form_data.dart`

- [ ] **Step 1: Create the file**

```dart
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
```

- [ ] **Step 2: Commit**

```bash
git add lib/presentation/screens/admin/auction_form_data.dart
git commit -m "feat: add AuctionFormData static config for ML-ready auction form"
```

---

## Task 10: Redesign PostAuctionScreen

> **GUIDANCE:** This is the largest task. After implementation, manually test the full flow: post a vehicle, post a motorcycle, post a bicycle, and edit an existing auction. Verify all required-field validators fire correctly and that changing main_category resets dependent dropdowns.

**Files:**
- Modify: `lib/presentation/screens/admin/post_auction_screen.dart`

- [ ] **Step 1: Replace the entire file with the redesigned implementation**

```dart
// lib/presentation/screens/admin/post_auction_screen.dart
//
// SCREEN 14 — POST NEW AUCTION (redesigned for ML-ready metadata)
// 5 collapsible sections: Basic Info, Technical Specs, Ownership & History,
// Auction Details, Photos.
// Category-dependent fields shown/hidden based on _selectedMainCategory.
// itemName auto-computed from brand + model + year on submit.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../app_router.dart';
import '../../../core/constants/supabase_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_notification_helpers.dart';
import '../../../core/utils/validators.dart';
import '../../../core/localization/app_localizations_ext.dart';
import 'admin_shared.dart';
import 'auction_form_data.dart';

class PostAuctionScreen extends ConsumerStatefulWidget {
  const PostAuctionScreen({super.key, this.auction});
  final AuctionModel? auction;

  @override
  ConsumerState<PostAuctionScreen> createState() => _PostAuctionScreenState();
}

class _PostAuctionScreenState extends ConsumerState<PostAuctionScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _plateCtrl          = TextEditingController();
  final _priceCtrl          = TextEditingController();
  final _descriptionCtrl    = TextEditingController();
  final _modelCtrl          = TextEditingController();
  final _colorCtrl          = TextEditingController();
  final _mileageCtrl        = TextEditingController();
  final _engineSizeCtrl     = TextEditingController();
  final _engineCcCtrl       = TextEditingController();
  final _seatingCtrl        = TextEditingController();
  final _gearCountCtrl      = TextEditingController();

  // Dropdown state
  String  _selectedMainCategory   = 'vehicle';
  String? _selectedSubCategory;
  String? _selectedBrand;
  int?    _selectedYear;
  String? _selectedFuelType;
  String? _selectedTransmission;
  String? _selectedDrivetrain;
  String? _selectedFrameMaterial;
  String? _selectedSuspension;
  String? _selectedBrake;
  String? _selectedOwnershipHistory;
  String? _selectedAccidentHistory;
  String? _selectedInsuranceStatus;
  String  _selectedCondition      = 'Excellent';

  DateTime? _startDate, _endDate;
  List<XFile> _photos = [];
  bool _isLoading = false;

  bool get _isEditMode => widget.auction != null;

  @override
  void initState() {
    super.initState();
    if (widget.auction case final a?) {
      _priceCtrl.text        = a.startingPrice.toStringAsFixed(0);
      _plateCtrl.text        = a.plateNumber;
      _descriptionCtrl.text  = a.description;
      _modelCtrl.text        = a.model ?? '';
      _colorCtrl.text        = a.color ?? '';
      _mileageCtrl.text      = a.mileage?.toString() ?? '';
      _engineSizeCtrl.text   = a.engineSize?.toString() ?? '';
      _engineCcCtrl.text     = a.engineCc?.toString() ?? '';
      _seatingCtrl.text      = a.seatingCapacity?.toString() ?? '';
      _gearCountCtrl.text    = a.gearCount?.toString() ?? '';

      _selectedMainCategory   = a.resolvedMainCategory.isNotEmpty
          ? a.resolvedMainCategory
          : 'vehicle';
      _selectedSubCategory    = a.subCategory;
      _selectedBrand          = a.brand;
      _selectedYear           = a.manufacturingYear;
      _selectedFuelType       = a.fuelType;
      _selectedTransmission   = a.transmission;
      _selectedDrivetrain     = a.drivetrain;
      _selectedFrameMaterial  = a.frameMaterial;
      _selectedSuspension     = a.suspensionType;
      _selectedBrake          = a.brakeType;
      _selectedOwnershipHistory = a.ownershipHistory;
      _selectedAccidentHistory  = a.accidentHistory;
      _selectedInsuranceStatus  = a.insuranceStatus;
      _selectedCondition = a.condition.isNotEmpty ? a.condition : 'Excellent';
      _startDate = a.startDate;
      _endDate   = a.endDate;
    }
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _mileageCtrl.dispose();
    _engineSizeCtrl.dispose();
    _engineCcCtrl.dispose();
    _seatingCtrl.dispose();
    _gearCountCtrl.dispose();
    super.dispose();
  }

  void _onMainCategoryChanged(String newCategory) {
    setState(() {
      _selectedMainCategory   = newCategory;
      _selectedSubCategory    = null;
      _selectedBrand          = null;
      _selectedFuelType       = null;
      _selectedTransmission   = null;
      _selectedDrivetrain     = null;
      _selectedFrameMaterial  = null;
      _selectedSuspension     = null;
      _selectedBrake          = null;
      _engineSizeCtrl.clear();
      _engineCcCtrl.clear();
      _seatingCtrl.clear();
      _gearCountCtrl.clear();
    });
  }

  String _computeItemName() {
    final parts = <String>[
      if (_selectedBrand != null) _selectedBrand!,
      if (_modelCtrl.text.trim().isNotEmpty) _modelCtrl.text.trim(),
      if (_selectedYear != null) _selectedYear.toString(),
    ];
    if (parts.isEmpty) return widget.auction?.itemName ?? '';
    return parts.join(' ');
  }

  Future<void> _pickPhotos() async {
    final imgs = await ImagePicker().pickMultiImage(limit: 5);
    if (imgs.isNotEmpty) setState(() => _photos = imgs);
  }

  Future<void> _pickDate(bool isStart) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(Duration(days: isStart ? 0 : 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => isStart ? _startDate = date : _endDate = date);
    }
  }

  Future<void> _submit(bool isDraft) async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectDatesError)),
      );
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.endDateAfterStartError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final admin = ref.read(currentAdminProvider).value;
    if (admin == null) { setState(() => _isLoading = false); return; }

    final price = double.tryParse(
            _priceCtrl.text.trim().replaceAll(',', '')) ?? 0;
    final computedName = _computeItemName();

    if (_isEditMode) {
      final updated = widget.auction!.copyWith(
        itemName:         computedName.isNotEmpty ? computedName : null,
        category:         _selectedMainCategory,
        mainCategory:     _selectedMainCategory,
        subCategory:      _selectedSubCategory,
        brand:            _selectedBrand,
        model:            _modelCtrl.text.trim().isNotEmpty
                              ? _modelCtrl.text.trim() : null,
        manufacturingYear: _selectedYear,
        color:            _colorCtrl.text.trim().isNotEmpty
                              ? _colorCtrl.text.trim() : null,
        plateNumber:      _plateCtrl.text.trim(),
        condition:        _selectedCondition,
        mileage:          int.tryParse(_mileageCtrl.text.trim()),
        fuelType:         _selectedFuelType,
        transmission:     _selectedTransmission,
        engineSize:       double.tryParse(_engineSizeCtrl.text.trim()),
        engineCc:         int.tryParse(_engineCcCtrl.text.trim()),
        drivetrain:       _selectedDrivetrain,
        seatingCapacity:  int.tryParse(_seatingCtrl.text.trim()),
        frameMaterial:    _selectedFrameMaterial,
        gearCount:        int.tryParse(_gearCountCtrl.text.trim()),
        suspensionType:   _selectedSuspension,
        brakeType:        _selectedBrake,
        ownershipHistory: _selectedOwnershipHistory,
        accidentHistory:  _selectedAccidentHistory,
        insuranceStatus:  _selectedInsuranceStatus,
        description:      _descriptionCtrl.text.trim(),
        startingPrice:    price,
        startDate:        _startDate!,
        endDate:          _endDate!,
        updatedAt:        DateTime.now(),
      );

      final failure = await ref.read(updateAuctionUseCaseProvider)(updated);
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (failure != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ));
        return;
      }
      ref.invalidate(adminAuctionsProvider(admin.uid));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.l10n.auctionUpdatedSuccess),
        backgroundColor: AppColors.success,
      ));
      context.go(AppRoutes.manageAuctions);
      return;
    }

    // Create mode
    final auction = AuctionModel(
      auctionId:        '',
      itemName:         computedName,
      category:         _selectedMainCategory,
      mainCategory:     _selectedMainCategory,
      subCategory:      _selectedSubCategory,
      brand:            _selectedBrand,
      model:            _modelCtrl.text.trim().isNotEmpty
                            ? _modelCtrl.text.trim() : null,
      manufacturingYear: _selectedYear,
      color:            _colorCtrl.text.trim().isNotEmpty
                            ? _colorCtrl.text.trim() : null,
      plateNumber:      _plateCtrl.text.trim(),
      condition:        _selectedCondition,
      mileage:          int.tryParse(_mileageCtrl.text.trim()),
      fuelType:         _selectedFuelType,
      transmission:     _selectedTransmission,
      engineSize:       double.tryParse(_engineSizeCtrl.text.trim()),
      engineCc:         int.tryParse(_engineCcCtrl.text.trim()),
      drivetrain:       _selectedDrivetrain,
      seatingCapacity:  int.tryParse(_seatingCtrl.text.trim()),
      frameMaterial:    _selectedFrameMaterial,
      gearCount:        int.tryParse(_gearCountCtrl.text.trim()),
      suspensionType:   _selectedSuspension,
      brakeType:        _selectedBrake,
      ownershipHistory: _selectedOwnershipHistory,
      accidentHistory:  _selectedAccidentHistory,
      insuranceStatus:  _selectedInsuranceStatus,
      description:      _descriptionCtrl.text.trim(),
      photoUrls:        [],
      startingPrice:    price,
      currentHighestBid: price,
      totalBids:        0,
      region:           admin.region,
      postedByAdminUid: admin.uid,
      postedByAdminName: admin.fullNames,
      auctionStatus:    isDraft ? 'draft' : 'active',
      startDate:        _startDate!,
      endDate:          _endDate!,
      createdAt:        DateTime.now(),
      updatedAt:        DateTime.now(),
    );

    final files   = _photos.map((x) => File(x.path)).toList();
    final (_, failure) = await ref.read(postAuctionUseCaseProvider)(auction, files);
    setState(() => _isLoading = false);
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failure.message),
        backgroundColor: AppColors.error,
      ));
      return;
    }
    ref.invalidate(adminAuctionsProvider(admin.uid));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isDraft
          ? context.l10n.auctionSavedDraft
          : context.l10n.auctionPostedSuccess),
      backgroundColor: AppColors.success,
    ));
    context.go(AppRoutes.manageAuctions);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(currentAdminProvider).value;
    final l10n  = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditMode ? l10n.editAuction : l10n.postNewAuction),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sovereignLedger, style: AppTextStyles.labelGold),
              Text(l10n.registerAssets,  style: AppTextStyles.displayMedium),
              Text(l10n.formalDocumentation, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 20),

              _buildSection1(context, l10n),
              const SizedBox(height: 6),
              _buildSection2(context, l10n),
              const SizedBox(height: 6),
              _buildSection3(context, l10n),
              const SizedBox(height: 6),
              _buildSection4(context, l10n, admin),
              const SizedBox(height: 6),
              _buildSection5(context, l10n),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () => _submit(false),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditMode
                              ? l10n.saveChangesButton
                              : l10n.postAuction,
                          style: AppTextStyles.button,
                        ),
                ),
              ),
              if (!_isEditMode) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: _isLoading ? null : () => _submit(true),
                    child: Text(
                      l10n.saveAsDraft,
                      style: const TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AdminBottomNav(currentIndex: 1),
    );
  }

  // ── Section 1: Basic Information ─────────────────────────────────────────────
  Widget _buildSection1(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.info_outline,
      title: l10n.basicInformation,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main category chips
          FormLabel(l10n.mainCategoryLabel),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AuctionFormData.mainCategories.map((cat) {
              final isSel = _selectedMainCategory == cat;
              return GestureDetector(
                onTap: () => _onMainCategoryChanged(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSel
                        ? AppColors.primaryBlue
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: isSel
                          ? AppColors.primaryBlue
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        AuctionFormData.categoryIcon(cat),
                        size: 14,
                        color: isSel
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AuctionFormData.mainCategoryLabel(context, cat),
                        style: TextStyle(
                          color: isSel
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Sub-category
          _buildDropdown<String>(
            label: l10n.subCategoryLabel,
            value: _selectedSubCategory,
            hint: l10n.selectSubCategory,
            items: AuctionFormData.subcategoryMap[_selectedMainCategory] ?? [],
            labelBuilder: (v) => v,
            onChanged: (v) => setState(() => _selectedSubCategory = v),
            validator: (v) => AuctionValidators.validateRequiredDropdown(
                v, l10n.validatorSubCategoryRequired),
          ),

          const SizedBox(height: 12),

          // Brand
          _buildDropdown<String>(
            label: l10n.brandLabel,
            value: _selectedBrand,
            hint: l10n.selectBrand,
            items: AuctionFormData.brandMap[_selectedMainCategory] ?? [],
            labelBuilder: (v) => v,
            onChanged: (v) => setState(() => _selectedBrand = v),
            validator: (v) => AuctionValidators.validateRequiredDropdown(
                v, l10n.validatorBrandRequired),
          ),

          const SizedBox(height: 12),

          // Model
          _buildTextField(
            label: l10n.modelField,
            controller: _modelCtrl,
            hint: 'e.g. RAV4 / R15 / Talon 3',
            validator: (v) => AuctionValidators.validateRequired(
                v, l10n.validatorModelRequired),
          ),

          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDropdown<int>(
                  label: l10n.manufacturingYearLabel,
                  value: _selectedYear,
                  hint: 'YYYY',
                  items: AuctionFormData.years,
                  labelBuilder: (v) => v.toString(),
                  onChanged: (v) => setState(() => _selectedYear = v),
                  validator: (v) =>
                      AuctionValidators.validateYear(v, l10n),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
                  label: l10n.colorField,
                  controller: _colorCtrl,
                  hint: 'e.g. White',
                  validator: (v) => AuctionValidators.validateRequired(
                      v, l10n.validatorColorRequired),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Plate number — hidden for bicycle
          if (_selectedMainCategory != 'bicycle')
            _buildTextField(
              label: l10n.plateNumberField,
              controller: _plateCtrl,
              hint: 'RAD 000 A',
              validator: (v) => AuctionValidators.validateRequired(
                  v, l10n.required),
            ),

          if (_selectedMainCategory == 'bicycle')
            // Plate is irrelevant; clear silently
            Builder(builder: (_) {
              WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _plateCtrl.clear());
              return const SizedBox.shrink();
            }),
        ],
      ),
    );
  }

  // ── Section 2: Technical Specifications ──────────────────────────────────────
  Widget _buildSection2(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.settings_outlined,
      title: l10n.technicalSpecs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Condition — all categories
          _buildDropdown<String>(
            label: l10n.conditionField,
            value: _selectedCondition,
            hint: l10n.selectCondition,
            items: AuctionFormData.conditions,
            labelBuilder: (v) =>
                AuctionFormData.conditionLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedCondition = v ?? 'Excellent'),
            validator: (_) => null,
          ),

          const SizedBox(height: 12),

          // Mileage — vehicle + motorcycle
          if (_selectedMainCategory != 'bicycle') ...[
            _buildTextField(
              label: l10n.mileageField,
              controller: _mileageCtrl,
              hint: '45000',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => AuctionValidators.validateMileage(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
          ],

          // Vehicle-specific fields
          if (_selectedMainCategory == 'vehicle') ...[
            _buildDropdown<String>(
              label: l10n.fuelTypeField,
              value: _selectedFuelType,
              hint: l10n.selectFuelType,
              items: AuctionFormData.fuelTypes,
              labelBuilder: (v) =>
                  AuctionFormData.fuelTypeLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedFuelType = v),
              validator: (v) => AuctionValidators.validateFuelType(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            _buildDropdown<String>(
              label: l10n.transmissionField,
              value: _selectedTransmission,
              hint: l10n.selectTransmission,
              items: AuctionFormData.transmissions,
              labelBuilder: (v) =>
                  AuctionFormData.transmissionLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedTransmission = v),
              validator: (v) => AuctionValidators.validateTransmission(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    label: l10n.engineSizeField,
                    controller: _engineSizeCtrl,
                    hint: '2.5',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) =>
                        AuctionValidators.validateEngineSize(
                            v, _selectedMainCategory, l10n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown<String>(
                    label: l10n.drivetrainField,
                    value: _selectedDrivetrain,
                    hint: l10n.selectDrivetrain,
                    items: AuctionFormData.drivetrains,
                    labelBuilder: (v) => v,
                    onChanged: (v) =>
                        setState(() => _selectedDrivetrain = v),
                    validator: (_) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: l10n.seatingCapacityField,
              controller: _seatingCtrl,
              hint: '5',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (_) => null,
            ),
          ],

          // Motorcycle-specific fields
          if (_selectedMainCategory == 'motorcycle') ...[
            _buildDropdown<String>(
              label: l10n.fuelTypeField,
              value: _selectedFuelType,
              hint: l10n.selectFuelType,
              items: AuctionFormData.fuelTypes,
              labelBuilder: (v) =>
                  AuctionFormData.fuelTypeLabel(context, v),
              onChanged: (v) =>
                  setState(() => _selectedFuelType = v),
              validator: (v) => AuctionValidators.validateFuelType(
                  v, _selectedMainCategory, l10n),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              label: l10n.engineCcField,
              controller: _engineCcCtrl,
              hint: '155',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => AuctionValidators.validateEngineCc(
                  v, _selectedMainCategory, l10n),
            ),
          ],

          // Bicycle-specific fields
          if (_selectedMainCategory == 'bicycle') ...[
            _buildDropdown<String>(
              label: l10n.frameMaterialField,
              value: _selectedFrameMaterial,
              hint: l10n.selectFrameMaterial,
              items: AuctionFormData.frameMaterials,
              labelBuilder: (v) => v,
              onChanged: (v) =>
                  setState(() => _selectedFrameMaterial = v),
              validator: (_) => null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildTextField(
                    label: l10n.gearCountField,
                    controller: _gearCountCtrl,
                    hint: '21',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    validator: (v) =>
                        AuctionValidators.validateGearCount(
                            v, _selectedMainCategory, l10n),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown<String>(
                    label: l10n.suspensionTypeField,
                    value: _selectedSuspension,
                    hint: l10n.selectSuspension,
                    items: AuctionFormData.suspensions,
                    labelBuilder: (v) => v,
                    onChanged: (v) =>
                        setState(() => _selectedSuspension = v),
                    validator: (_) => null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDropdown<String>(
              label: l10n.brakeTypeField,
              value: _selectedBrake,
              hint: l10n.selectBrakeType,
              items: AuctionFormData.brakeTypes,
              labelBuilder: (v) => v,
              onChanged: (v) => setState(() => _selectedBrake = v),
              validator: (_) => null,
            ),
          ],
        ],
      ),
    );
  }

  // ── Section 3: Ownership & History ───────────────────────────────────────────
  Widget _buildSection3(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.history_outlined,
      title: l10n.ownershipSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDropdown<String>(
            label: l10n.ownershipHistoryField,
            value: _selectedOwnershipHistory,
            hint: l10n.selectOwnershipHistory,
            items: AuctionFormData.ownershipOptions,
            labelBuilder: (v) =>
                AuctionFormData.ownershipLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedOwnershipHistory = v),
            validator: (_) => null,
          ),
          const SizedBox(height: 12),
          _buildDropdown<String>(
            label: l10n.accidentHistoryField,
            value: _selectedAccidentHistory,
            hint: l10n.selectAccidentHistory,
            items: AuctionFormData.accidentOptions,
            labelBuilder: (v) =>
                AuctionFormData.accidentLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedAccidentHistory = v),
            validator: (_) => null,
          ),
          const SizedBox(height: 12),
          _buildDropdown<String>(
            label: l10n.insuranceStatusField,
            value: _selectedInsuranceStatus,
            hint: l10n.selectInsuranceStatus,
            items: AuctionFormData.insuranceOptions,
            labelBuilder: (v) =>
                AuctionFormData.insuranceLabel(context, v),
            onChanged: (v) =>
                setState(() => _selectedInsuranceStatus = v),
            validator: (_) => null,
          ),
        ],
      ),
    );
  }

  // ── Section 4: Auction Details ────────────────────────────────────────────────
  Widget _buildSection4(
      BuildContext context, AppLocalizations l10n, dynamic admin) {
    return _SectionTile(
      icon: Icons.gavel_outlined,
      title: l10n.auctionDetailsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormLabel(l10n.startingPrice),
          TextFormField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '5,000,000',
              suffixText: 'RWF',
            ),
            validator: (v) =>
                AuctionValidators.validateRequired(v, l10n.required),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(child: _buildDatePicker(
                  context, l10n.startDate, _startDate, () => _pickDate(true))),
              const SizedBox(width: 12),
              Expanded(child: _buildDatePicker(
                  context, l10n.endDate, _endDate, () => _pickDate(false))),
            ],
          ),

          const SizedBox(height: 16),

          FormLabel(l10n.storageRegion),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Text(
                  '${admin?.region ?? ''} Region',
                  style: AppTextStyles.bodyLarge,
                ),
                const Spacer(),
                const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),

          const SizedBox(height: 16),

          FormLabel(l10n.descriptionField),
          TextFormField(
            controller: _descriptionCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: l10n.formalDocumentation,
            ),
            validator: AppValidators.validateDescription,
          ),
        ],
      ),
    );
  }

  // ── Section 5: Photos ──────────────────────────────────────────────────────
  Widget _buildSection5(BuildContext context, AppLocalizations l10n) {
    return _SectionTile(
      icon: Icons.photo_camera_outlined,
      title: l10n.itemPhotos,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 90,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (!_isEditMode)
                  GestureDetector(
                    onTap: _pickPhotos,
                    child: Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primaryBlue),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.upload_outlined,
                              color: AppColors.primaryBlue),
                          Text(
                            l10n.upload,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isEditMode)
                  ...widget.auction!.photoUrls.map((url) => Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: DecorationImage(
                            image: NetworkImage(url),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
                if (!_isEditMode)
                  ..._photos.map((f) => Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          image: DecorationImage(
                            image: FileImage(File(f.path)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      )),
              ],
            ),
          ),
          if (_isEditMode)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.photosCannotChange,
                  style: AppTextStyles.bodySmall),
            ),
          if (!_isEditMode && _photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l10n.photosSelected(_photos.length),
                  style: AppTextStyles.bodySmall),
            ),
        ],
      ),
    );
  }

  // ── Shared field builders ────────────────────────────────────────────────────

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
    FormFieldValidator<T?>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        DropdownButtonFormField<T>(
          value: value,
          decoration: InputDecoration(hintText: hint),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      labelBuilder(item),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    FormFieldValidator<String>? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(hintText: hint),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    String label,
    DateTime? date,
    VoidCallback onTap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormLabel(label),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceGrey,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              date != null
                  ? DateHelper.formatDate(date)
                  : 'mm/dd/yyyy',
              style: TextStyle(
                color: date != null
                    ? AppColors.textPrimary
                    : AppColors.textHint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionTile — styled ExpansionTile matching RNP brand
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            leading: Icon(icon, size: 18, color: AppColors.primaryBlue),
            title: Text(title, style: AppTextStyles.labelGold),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [child],
          ),
        ),
      );
}
```

- [ ] **Step 2: Run flutter analyze on the file**

```bash
flutter analyze lib/presentation/screens/admin/post_auction_screen.dart
```

Expected: No errors. Warnings about unused imports may appear if any — remove them.

- [ ] **Step 3: Commit**

```bash
git add lib/presentation/screens/admin/post_auction_screen.dart
git commit -m "feat(ui): redesign PostAuctionScreen with 5-section ML-ready form"
```

---

## Task 11: Update admin_shared.dart

**Files:**
- Modify: `lib/presentation/screens/admin/admin_shared.dart`

- [ ] **Step 1: Update ManageAuctionCard — add brand+subcategory chip**

In `ManageAuctionCard.build()`, after the `Text(auction.itemName, style: AppTextStyles.h2)` line (~line 383), add:

```dart
if (auction.brand != null || auction.subCategory != null) ...[
  const SizedBox(height: 4),
  Row(
    children: [
      Icon(
        _categoryIcon(auction.resolvedMainCategory),
        size: 12,
        color: AppColors.textSecondary,
      ),
      const SizedBox(width: 4),
      Text(
        [
          if (auction.brand != null) auction.brand!,
          if (auction.subCategory != null) auction.subCategory!,
        ].join(' • '),
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
],
```

- [ ] **Step 2: Add `_categoryIcon` helper to ManageAuctionCard**

At the bottom of `ManageAuctionCard` (before the closing `}` of the class), add:

```dart
IconData _categoryIcon(String category) => switch (category) {
  'motorcycle' => Icons.motorcycle_outlined,
  'bicycle'    => Icons.pedal_bike_outlined,
  _            => Icons.directions_car_outlined,
};
```

- [ ] **Step 3: Update `_auctionPhotoPlaceholder` to use resolvedMainCategory**

In `ManageAuctionCard._auctionPhotoPlaceholder()`, replace:

```dart
// Before:
child: const Center(
  child: Icon(Icons.directions_car, size: 56, color: AppColors.border),
),
```

With:

```dart
// After:
child: Center(
  child: Icon(
    _categoryIcon(auction.resolvedMainCategory),
    size: 56,
    color: AppColors.border,
  ),
),
```

- [ ] **Step 4: Update RecentAuctionCard `_photoPlaceholder` similarly**

In `RecentAuctionCard._photoPlaceholder()`, replace:

```dart
// Before:
child: const Icon(Icons.directions_car, color: AppColors.border),
```

With:

```dart
// After:
child: Icon(
  switch (auction.resolvedMainCategory) {
    'motorcycle' => Icons.motorcycle_outlined,
    'bicycle'    => Icons.pedal_bike_outlined,
    _            => Icons.directions_car_outlined,
  },
  color: AppColors.border,
),
```

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/screens/admin/admin_shared.dart
git commit -m "feat(ui): show brand/subcategory chip in ManageAuctionCard + RecentAuctionCard"
```

---

## Task 12: Update auction_detail_screen.dart

**Files:**
- Modify: `lib/presentation/screens/client/auction_detail_screen.dart`

- [ ] **Step 1: Replace `_PhotoError` to use resolvedMainCategory**

Replace the entire `_PhotoError` class:

```dart
class _PhotoError extends StatelessWidget {
  const _PhotoError(this.auction);
  final AuctionModel auction;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceGrey,
        child: Icon(
          switch (auction.resolvedMainCategory) {
            'motorcycle' => Icons.motorcycle,
            'bicycle'    => Icons.pedal_bike,
            _            => Icons.directions_car,
          },
          size: 80,
          color: AppColors.border,
        ),
      );
}
```

- [ ] **Step 2: Update category badge icon in SliverAppBar**

In `AuctionDetailScreen`, find the `Icon` inside the category badge `Positioned` widget. Replace:

```dart
// Before:
Icon(
  auction.category == 'car'
      ? Icons.directions_car
      : auction.category == 'motorcycle'
          ? Icons.motorcycle
          : Icons.pedal_bike,
  size: 14,
  color: AppColors.primaryBlue,
),
const SizedBox(width: 4),
Text(
  auction.category.toUpperCase(),
```

With:

```dart
// After:
Icon(
  switch (auction.resolvedMainCategory) {
    'motorcycle' => Icons.motorcycle,
    'bicycle'    => Icons.pedal_bike,
    _            => Icons.directions_car,
  },
  size: 14,
  color: AppColors.primaryBlue,
),
const SizedBox(width: 4),
Text(
  auction.resolvedMainCategory.toUpperCase(),
```

- [ ] **Step 3: Update PageView errorBuilder to pass auction**

Find `errorBuilder: (_, _, _) => _PhotoError(auction.category)` and update to:

```dart
errorBuilder: (_, _, _) => _PhotoError(auction),
```

Also update the fallback: `_PhotoError(auction.category)` → `_PhotoError(auction)`.

- [ ] **Step 4: Replace specs grid with `_SpecsTable`**

Remove the existing `GridView.count` specs grid (the one with condition, plateNumber, startDate, endDate). Replace it and the Vehicle Specifications section below with:

```dart
const SizedBox(height: 16),
_SpecsTable(auction: auction),
const SizedBox(height: 16),
```

- [ ] **Step 5: Add `_SpecsTable` and `_SpecsRow` classes at the bottom of the file**

After the `_InfoRow` class, add:

```dart
// ─────────────────────────────────────────────────────────────────────────────
// Full specs table — renders only non-null fields grouped by category
// ─────────────────────────────────────────────────────────────────────────────

class _SpecsTable extends StatelessWidget {
  const _SpecsTable({required this.auction});
  final AuctionModel auction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cat  = auction.resolvedMainCategory;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.vehicleSpecs, style: AppTextStyles.h1),
          const SizedBox(height: 12),

          // Identity
          if (auction.brand != null)
            _SpecsRow(Icons.local_offer_outlined, l10n.brandLabel, auction.brand!),
          if (auction.model != null)
            _SpecsRow(Icons.confirmation_number_outlined, l10n.modelField, auction.model!),
          if (auction.manufacturingYear != null)
            _SpecsRow(Icons.calendar_today_outlined, l10n.manufacturingYearLabel,
                auction.manufacturingYear.toString()),
          if (auction.subCategory != null)
            _SpecsRow(Icons.category_outlined, l10n.subCategoryLabel, auction.subCategory!),
          if (auction.color != null)
            _SpecsRow(Icons.palette_outlined, l10n.colorField, auction.color!),

          const Divider(height: 24, color: AppColors.border),

          // Condition & usage
          _SpecsRow(Icons.star_outline, l10n.conditionLabel, auction.condition),
          if (auction.mileage != null && cat != 'bicycle')
            _SpecsRow(Icons.speed_outlined, l10n.mileageField,
                '${auction.mileage} km'),
          if (auction.plateNumber.isNotEmpty && cat != 'bicycle')
            _SpecsRow(Icons.badge_outlined, l10n.plateNumberLabel, auction.plateNumber),

          const Divider(height: 24, color: AppColors.border),

          // Technical (category-specific)
          if (cat == 'vehicle') ...[
            if (auction.fuelType != null)
              _SpecsRow(Icons.local_gas_station_outlined, l10n.fuelTypeField,
                  auction.fuelType!),
            if (auction.transmission != null)
              _SpecsRow(Icons.settings_outlined, l10n.transmissionField,
                  auction.transmission!),
            if (auction.engineSize != null)
              _SpecsRow(Icons.engineering_outlined, l10n.engineSizeField,
                  '${auction.engineSize}L'),
            if (auction.drivetrain != null)
              _SpecsRow(Icons.rotate_right_outlined, l10n.drivetrainField,
                  auction.drivetrain!),
            if (auction.seatingCapacity != null)
              _SpecsRow(Icons.airline_seat_recline_normal_outlined,
                  l10n.seatingCapacityField,
                  '${auction.seatingCapacity} seats'),
          ],

          if (cat == 'motorcycle') ...[
            if (auction.fuelType != null)
              _SpecsRow(Icons.local_gas_station_outlined, l10n.fuelTypeField,
                  auction.fuelType!),
            if (auction.engineCc != null)
              _SpecsRow(Icons.engineering_outlined, l10n.engineCcField,
                  '${auction.engineCc} cc'),
          ],

          if (cat == 'bicycle') ...[
            if (auction.frameMaterial != null)
              _SpecsRow(Icons.build_outlined, l10n.frameMaterialField,
                  auction.frameMaterial!),
            if (auction.gearCount != null)
              _SpecsRow(Icons.settings_outlined, l10n.gearCountField,
                  '${auction.gearCount} gears'),
            if (auction.suspensionType != null)
              _SpecsRow(Icons.merge_outlined, l10n.suspensionTypeField,
                  auction.suspensionType!),
            if (auction.brakeType != null)
              _SpecsRow(Icons.stop_circle_outlined, l10n.brakeTypeField,
                  auction.brakeType!),
          ],

          const Divider(height: 24, color: AppColors.border),

          // History
          if (auction.ownershipHistory != null)
            _SpecsRow(Icons.person_outline, l10n.ownershipHistoryField,
                auction.ownershipHistory!),
          if (auction.accidentHistory != null)
            _SpecsRow(Icons.warning_amber_outlined, l10n.accidentHistoryField,
                auction.accidentHistory!),
          if (auction.insuranceStatus != null)
            _SpecsRow(Icons.security_outlined, l10n.insuranceStatusField,
                auction.insuranceStatus!),

          const Divider(height: 24, color: AppColors.border),

          // Auction metadata
          _SpecsRow(Icons.description_outlined, l10n.description,
              auction.description),
          _SpecsRow(Icons.location_on_outlined, l10n.region,
              auction.region),
          _SpecsRow(Icons.person_outline, l10n.postedBy,
              auction.postedByAdminName),
          _SpecsRow(Icons.event_outlined, l10n.startDate,
              DateHelper.formatDate(auction.startDate)),
          _SpecsRow(Icons.event_available_outlined, l10n.endDate,
              DateHelper.formatDate(auction.endDate)),
        ],
      ),
    );
  }
}

class _SpecsRow extends StatelessWidget {
  const _SpecsRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: AppTextStyles.bodyMedium),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
}
```

- [ ] **Step 6: Remove old `_SpecCard` and `_SpecRow` classes** (now replaced by `_SpecsTable` and `_SpecsRow`).

- [ ] **Step 7: Commit**

```bash
git add lib/presentation/screens/client/auction_detail_screen.dart
git commit -m "feat(ui): replace spec grid with full _SpecsTable in AuctionDetailScreen"
```

---

## Task 13: Update client_shared.dart

**Files:**
- Modify: `lib/presentation/screens/client/client_shared.dart`

- [ ] **Step 1: Fix AuctionPhotoPlaceholder — 'car' → 'vehicle'**

In `AuctionPhotoPlaceholder.build()`, replace:

```dart
// Before:
Icon(
  category == 'car'
      ? Icons.directions_car
      : category == 'motorcycle'
          ? Icons.motorcycle
          : Icons.pedal_bike,
  size: 56,
  color: AppColors.border,
),
```

With:

```dart
// After:
Icon(
  switch (category) {
    'motorcycle' => Icons.motorcycle,
    'bicycle'    => Icons.pedal_bike,
    _            => Icons.directions_car,
  },
  size: 56,
  color: AppColors.border,
),
```

- [ ] **Step 2: Update AuctionCard category badge text**

In `AuctionCard.build()`, find `_Badge(auction.category.toUpperCase())` and replace with:

```dart
_Badge(auction.resolvedMainCategory.toUpperCase()),
```

- [ ] **Step 3: Update BidTile — add brand+subcategory chip**

In `BidTile.build()`, find the line:

```dart
final category = auction?.category ?? 'car';
```

Replace with:

```dart
final category = auction?.resolvedMainCategory ?? 'vehicle';
```

Then after the existing `Row` that shows location (the one with `Icons.location_on_outlined`), add:

```dart
if (auction?.brand != null || auction?.subCategory != null) ...[
  const SizedBox(height: 4),
  Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.label_outline,
          size: 11, color: AppColors.darkGold),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          [
            if (auction!.brand != null) auction!.brand!,
            if (auction!.subCategory != null) auction!.subCategory!,
          ].join(' • '),
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.darkGold,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  ),
],
```

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/screens/client/client_shared.dart
git commit -m "feat(ui): add brand chip to BidTile; fix AuctionPhotoPlaceholder category"
```

---

## Task 14: Full Analysis Pass + Final Fixes

> **GUIDANCE:** This final task runs `flutter analyze` across the entire project and fixes every reported issue. Do not skip this step before testing.

**Files:**
- Modify: any files with analyzer issues

- [ ] **Step 1: Run full analyze**

```bash
flutter analyze
```

Expected: `No issues found!` or only info-level hints.

Common issues to expect and how to fix:

| Issue | Fix |
|---|---|
| `unused_import` | Remove the import |
| `deprecated_member_use` (DropdownButtonFormField) | Already using standard API; if lint fires, suppress with `// ignore: deprecated_member_use` on that line only |
| `_PhotoError` constructor call still passing `String` | Ensure all callsites pass `auction` object, not `auction.category` |
| `_SpecCard` / `_SpecRow` still referenced | Verify old classes are fully removed |
| Missing `resolvedMainCategory` on old `auction.category == 'car'` checks | Replace with `auction.resolvedMainCategory` |

- [ ] **Step 2: Run all tests**

```bash
flutter test
```

Expected: All tests PASS.

- [ ] **Step 3: Run on device**

```bash
flutter run --dart-define-from-file=.env.json
```

Test checklist:
- [ ] Post a new **vehicle** auction — all vehicle fields visible, bicycle/motorcycle fields hidden
- [ ] Post a new **motorcycle** auction — engine CC visible, frame material hidden
- [ ] Post a new **bicycle** auction — plate number hidden, gear count visible
- [ ] Change main category while filling a form — verify dependent dropdowns reset
- [ ] Edit an existing auction — verify all new fields pre-populate correctly
- [ ] View auction detail as client — verify full specs table renders
- [ ] Check My Bids — verify brand chip shows on new auctions, falls back gracefully on legacy
- [ ] Verify images still upload correctly

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve flutter analyze issues after ML-ready auction refactor"
```

---

## Task 15: Deploy Supabase Edge Functions (if needed)

> **GUIDANCE:** The Edge Functions (`place-bid`, `close-auction-manually`) do not read the new ML columns so they do NOT need redeployment. The new columns are only written by the Flutter client and read for display. Skip this task unless you modified an Edge Function.

If you edited any Edge Function during this feature:

```bash
supabase functions deploy place-bid
supabase functions deploy close-auction-manually
```

---

## Summary of Execution Order

1. **Task 1** — Run SQL migration in Supabase (infrastructure first)
2. **Task 2** — Update constants
3. **Task 3** — Update AuctionModel
4. **Task 4** — Write model tests → verify pass
5. **Task 5** — Add EN l10n keys → `flutter pub get`
6. **Task 6** — Add RW l10n keys → `flutter pub get`
7. **Task 7** — Add AuctionValidators
8. **Task 8** — Write validator tests → verify pass
9. **Task 9** — Create AuctionFormData
10. **Task 10** — Redesign PostAuctionScreen
11. **Task 11** — Update admin_shared.dart
12. **Task 12** — Update auction_detail_screen.dart
13. **Task 13** — Update client_shared.dart
14. **Task 14** — `flutter analyze` + full device test
15. **Task 15** — Deploy Edge Functions if needed
