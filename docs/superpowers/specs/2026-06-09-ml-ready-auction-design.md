# ML-Ready Auction Metadata — Design Spec

**Date:** 2026-06-09  
**Project:** E-CYAMUNARA — RNP Online Auction Platform  
**Scope:** Refactor auction posting, manage auctions, auction detail, and my bids screens to support structured ML-ready vehicle metadata. Includes Supabase migration, AuctionModel update, dynamic form, and full EN+RW localization.

---

## 1. Problem Statement

The current `auctions` table stores only free-text fields (`item_name`, `category`, `condition`, `description`). This is insufficient for:

- AI price prediction (needs year, mileage, brand, fuel type, transmission)
- AI bid forecasting (needs structured comparables)
- Vehicle valuation (needs engine size, drivetrain, condition score)
- Intelligent recommendations (needs sub-category, brand affinity)

The goal is to add 19 structured, nullable columns to `auctions` and rebuild the auction posting UI to capture them — without breaking any existing data, workflows, or RBAC.

---

## 2. Decisions

| Question | Decision |
|---|---|
| Schema strategy | Flat columns (Approach A) — ML training requires tabular rows, no JSON parsing |
| `itemName` handling | Auto-generated from `brand + model + manufacturingYear` on submit |
| Localization | Full EN + Kinyarwanda (RW) for all new field labels |
| Auction detail screen | Full specs table — show all non-null fields to clients |
| My Bids tile | Show `brand • subCategory` chip; fallback to `itemName` for legacy records |

---

## 3. Database Migration

**File:** `supabase/migrations/20260609000000_ml_ready_auction_metadata.sql`

### 3.1 New Columns

All columns are nullable to preserve backward compatibility with existing auction rows.

| Column | Type | Used by |
|---|---|---|
| `main_category` | TEXT | all |
| `sub_category` | TEXT | all |
| `brand` | TEXT | all |
| `model` | TEXT | all |
| `manufacturing_year` | INTEGER | all |
| `color` | TEXT | all |
| `mileage` | INTEGER | vehicle, motorcycle |
| `fuel_type` | TEXT | vehicle, motorcycle |
| `transmission` | TEXT | vehicle only |
| `engine_size` | NUMERIC(4,1) | vehicle only (litres) |
| `engine_cc` | INTEGER | motorcycle only |
| `drivetrain` | TEXT | vehicle only |
| `seating_capacity` | INTEGER | vehicle only |
| `frame_material` | TEXT | bicycle only |
| `gear_count` | INTEGER | bicycle only |
| `suspension_type` | TEXT | bicycle only |
| `brake_type` | TEXT | bicycle only |
| `ownership_history` | TEXT | all |
| `accident_history` | TEXT | all |
| `insurance_status` | TEXT | all |

### 3.2 Data Migration

```sql
-- Rename legacy 'car' values to 'vehicle'
UPDATE auctions SET category = 'vehicle' WHERE category = 'car';

-- Backfill main_category from existing category column
UPDATE auctions SET main_category = category WHERE main_category IS NULL;
```

### 3.3 Constants Update

`SupabaseConstants.categories` changes from `['car', 'motorcycle', 'bicycle']` to `['vehicle', 'motorcycle', 'bicycle']`.

---

## 4. AuctionModel

**File:** `lib/data/models/models.dart`

### 4.1 New Fields

All 19 new fields added as nullable (`T?`) to `AuctionModel`. Constructor, `fromMap`, `toMap`, and `copyWith` all updated.

`fromMap` uses `as T?` with null-safe defaults — old rows deserialize without errors.  
`toMap` includes all non-null new fields.  
`itemName` is kept in the DB and model but computed on save (not shown in the UI form).

### 4.2 Computed itemName

In `PostAuctionScreen._submit()`, before creating/updating the `AuctionModel`:

```dart
final autoName = [brand, model, manufacturingYear?.toString()]
    .where((s) => s != null && s.isNotEmpty)
    .join(' ');
```

Falls back to existing `itemName` if all three are null (edit mode on a legacy record).

---

## 5. Static Form Data

**New file:** `lib/presentation/screens/admin/auction_form_data.dart`

Contains only `static const` maps and lists. No state, no Riverpod. Imported by `post_auction_screen.dart`.

### 5.1 Categories & Subcategories

```
vehicle    → SUV, Sedan, Hatchback, Pickup, Truck, Van, Bus, Wagon, Coupe
motorcycle → Sport Bike, Cruiser, Touring, Scooter, Dirt Bike, Electric Motorcycle
bicycle    → Mountain Bike, Road Bike, BMX, Hybrid Bike, Electric Bicycle
```

### 5.2 Brands

```
vehicle    → Toyota, Nissan, Hyundai, Isuzu, Mitsubishi, Mercedes, BMW, Kia, Honda, Ford, Subaru
motorcycle → Yamaha, Honda, TVS, Suzuki, Kawasaki, Bajaj
bicycle    → Giant, Trek, Specialized, Phoenix, Hero
```

### 5.3 Other Lists

```
fuelTypes         → Petrol, Diesel, Hybrid, Electric
transmissions     → Automatic, Manual, CVT
conditions        → Excellent, Very Good, Good, Fair, Poor
drivetrains       → FWD, RWD, AWD, 4WD
frameMaterials    → Aluminum, Steel, Carbon Fiber, Titanium
suspensions       → Full Suspension, Front Only, Rigid
brakeTypes        → Disc, V-Brake, Drum, Hydraulic Disc
ownershipHistory  → First Owner, Second Owner, Third Owner, Fleet Vehicle
insuranceStatuses → Insured, Expired, Never Insured, Unknown
accidentHistory   → No Accidents, Minor Damage, Major Damage, Unknown
```

---

## 6. Form Architecture

**File:** `lib/presentation/screens/admin/post_auction_screen.dart`

### 6.1 Section Structure (5 collapsible ExpansionTiles)

| # | Section | Key Fields |
|---|---|---|
| 1 | Basic Information | main_category chips, sub_category, brand, model, year, color, plate |
| 2 | Technical Specifications | condition, mileage + category-specific block |
| 3 | Ownership & History | ownership_history, accident_history, insurance_status |
| 4 | Auction Details | starting_price, start_date, end_date, region (locked), description |
| 5 | Photos | upload grid (unchanged) |

Section 1 is expanded by default; sections 2–5 are collapsed. The `ExpansionTile` uses `FormSectionHeader`-style icons from `admin_shared.dart`.

### 6.2 Dynamic Field Visibility

The Technical Specifications section (§2) renders one of three blocks based on `_mainCategory`:

**Vehicle block:** condition, mileage, fuel_type, transmission, engine_size, drivetrain, seating_capacity  
**Motorcycle block:** condition, mileage, fuel_type, engine_cc  
**Bicycle block:** condition, gear_count, frame_material, suspension_type, brake_type

`plate_number` is shown for vehicle and motorcycle only.

### 6.3 Dependent Dropdowns

Selecting a `main_category` chip resets `sub_category` and `brand` to null and repopulates their dropdown items from `AuctionFormData.subcategoryMap[mainCategory]` and `AuctionFormData.brandMap[mainCategory]`.

### 6.4 Edit Mode

Edit mode pre-populates all new fields from `widget.auction`. Category chips are editable in edit mode (admin may correct a category). All existing edit-mode behaviour (photo read-only strip, `updateAuctionUseCaseProvider`) is preserved.

---

## 7. Validation Rules

**Extended in:** `lib/core/utils/validators.dart` as `AuctionValidators`

| Field | Rule |
|---|---|
| `main_category` | Required |
| `sub_category` | Required |
| `brand` | Required |
| `model` | Required, min 1 char |
| `manufacturing_year` | Required, 1900 ≤ year ≤ current year |
| `color` | Required |
| `mileage` | Required for vehicle/motorcycle, int ≥ 0 |
| `fuel_type` | Required for vehicle/motorcycle |
| `transmission` | Required for vehicle |
| `engine_size` | Required for vehicle, double > 0 |
| `engine_cc` | Required for motorcycle, int > 0 |
| `gear_count` | Required for bicycle, int > 0 |
| `plate_number` | Required for vehicle/motorcycle, hidden for bicycle |
| `starting_price` | Required, double > 0 (unchanged) |
| `start_date` | Required (unchanged) |
| `end_date` | Required, after start_date (unchanged) |
| `description` | Required, min 20 chars (unchanged) |

---

## 8. Screen-by-Screen Changes

### 8.1 post_auction_screen.dart
- Full redesign: flat form → 5 `ExpansionTile` sections
- Category chips: 3 only (vehicle / motorcycle / bicycle) replacing old `SupabaseConstants.categories` chip row
- `itemName` field removed from UI; auto-computed on submit
- All new fields added with proper validators
- Responsive: fields in single column on narrow screens, two-column `Row` only for date pickers (unchanged pattern)

### 8.2 manage_auctions_screen.dart
- No structural change
- `ManageAuctionCard` in `admin_shared.dart` updated: show `brand • subCategory` chip below `itemName`; placeholder icon switches on `mainCategory`

### 8.3 auction_detail_screen.dart
- Specs grid replaced with `_SpecsTable` widget
- `_SpecsTable` renders only non-null fields, grouped:
  - Identity: brand, model, year, color, sub_category
  - Condition & Usage: condition, mileage, ownership_history
  - Technical: fuel_type, transmission, engine_size (vehicle) / engine_cc (motorcycle) / frame_material + gear_count (bicycle)
  - History: accident_history, insurance_status
  - Auction: plate_number, posted_by, region
- `_PhotoError` placeholder switches on `mainCategory`
- Category badge in photo gallery switches on `mainCategory`

### 8.4 my_bids_screen.dart
- `BidTile` (in `client_shared.dart`) updated: show `brand • subCategory` chip below item name
- Graceful fallback: if `auction.brand == null`, show `itemName` only (legacy records)

---

## 9. Localization

**Files:** `lib/l10n/app_en.arb`, `lib/l10n/app_rw.arb`

New keys added for all new field labels, dropdown option labels, section headers, and validation messages. Both EN and RW provided for every key.

**Examples:**
```
mainCategory, subCategory, brand, model, manufacturingYear, color, mileage,
fuelType, transmission, engineSize, engineCc, drivetrain, seatingCapacity,
frameMaterial, gearCount, suspensionType, brakeType, ownershipHistory,
accidentHistory, insuranceStatus, basicInformation, technicalSpecs,
ownershipHistory, vehicleSectionLabel, motorcycleSectionLabel, bicycleSectionLabel,
validatorYearRange, validatorMileageNegative, validatorEngineCcRequired,
validatorTransmissionRequired, validatorGearCountRequired
```

---

## 10. AI-Readiness

Each auction row after this migration is a complete, flat training example for:

- **Price prediction:** `manufacturing_year`, `mileage`, `brand`, `sub_category`, `fuel_type`, `transmission`, `condition`, `region`, `starting_price` → target: `winning_amount`
- **Bid forecasting:** `total_bids`, `starting_price`, `manufacturing_year`, `brand`, `condition` → target: `current_highest_bid` trajectory
- **Demand scoring:** `sub_category`, `brand`, `region`, `manufacturing_year` → demand index
- **Depreciation scoring:** `manufacturing_year`, `mileage`, `condition`, `accident_history` → depreciation factor

Computed columns (`vehicle_age`, `condition_score`, `demand_score`, `depreciation_score`) are **not calculated in the UI**. They are reserved for a future ML pipeline (Supabase Function or external ETL) that writes back into the table. The columns are not added in this migration — their schema will be defined when the AI pipeline is designed.

---

## 11. Example AI-Ready Records

**Vehicle:**
```json
{
  "main_category": "vehicle", "sub_category": "SUV",
  "brand": "Toyota", "model": "RAV4", "manufacturing_year": 2020,
  "mileage": 45000, "fuel_type": "Petrol", "transmission": "Automatic",
  "condition": "Excellent", "color": "White", "drivetrain": "AWD",
  "seating_capacity": 5, "ownership_history": "First Owner",
  "accident_history": "No Accidents", "insurance_status": "Insured",
  "region": "Central", "starting_price": 8500000
}
```

**Motorcycle:**
```json
{
  "main_category": "motorcycle", "sub_category": "Sport Bike",
  "brand": "Yamaha", "model": "R15", "manufacturing_year": 2021,
  "engine_cc": 155, "fuel_type": "Petrol", "mileage": 12000,
  "condition": "Very Good", "color": "Blue",
  "ownership_history": "First Owner", "accident_history": "No Accidents",
  "starting_price": 1800000
}
```

**Bicycle:**
```json
{
  "main_category": "bicycle", "sub_category": "Mountain Bike",
  "brand": "Giant", "model": "Talon 3", "manufacturing_year": 2022,
  "frame_material": "Aluminum", "gear_count": 21,
  "suspension_type": "Front Only", "brake_type": "Disc",
  "condition": "Good", "color": "Red",
  "starting_price": 350000
}
```

---

## 12. Files Changed

| File | Change |
|---|---|
| `supabase/migrations/20260609000000_ml_ready_auction_metadata.sql` | New — adds 19 columns, migrates 'car'→'vehicle' |
| `lib/core/constants/supabase_constants.dart` | Update `categories` list |
| `lib/data/models/models.dart` | Add 19 fields to `AuctionModel` |
| `lib/core/utils/validators.dart` | Add `AuctionValidators` class |
| `lib/presentation/screens/admin/auction_form_data.dart` | New — static const maps/lists |
| `lib/presentation/screens/admin/post_auction_screen.dart` | Full redesign |
| `lib/presentation/screens/admin/admin_shared.dart` | Update `ManageAuctionCard`, `RecentAuctionCard` |
| `lib/presentation/screens/client/auction_detail_screen.dart` | New `_SpecsTable`, updated badge/placeholder |
| `lib/presentation/screens/client/client_shared.dart` | Update `BidTile` |
| `lib/l10n/app_en.arb` | ~35 new keys |
| `lib/l10n/app_rw.arb` | ~35 new keys (RW translations) |

---

## 13. Constraints

- No destructive schema changes — all new columns are nullable
- No breaking changes to existing providers, use cases, or repositories
- No changes to Edge Functions (`place-bid`, `close-auction-manually`, etc.)
- No changes to RBAC or navigation
- Existing `auction_detail_screen.dart` `_BidBottomSheet` is untouched
- `manage_auctions_screen.dart` screen logic is untouched (only the card widget changes)
