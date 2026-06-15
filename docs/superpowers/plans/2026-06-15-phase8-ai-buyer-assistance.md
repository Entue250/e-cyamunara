# Phase 8 — AI Buyer-Assistance Flutter Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface AI price insights and bid forecasts to buyers in `AuctionDetailScreen` via a silent, collapsible `AuctionAiInsightsPanel` that calls only `ai-predict-price` and `ai-bid-forecast` Edge Functions.

**Architecture:** `AuctionAiInsightsPanel` is a `ConsumerStatefulWidget` that fires both Edge Function calls via `AiRepository` in `initState` using `Future.wait`, then renders with `FutureBuilder`. Any failure collapses the panel to `SizedBox.shrink()` — the bid flow is never blocked. `AiRepository` is an abstract interface; `AiRepositoryImpl` is the concrete Supabase client implementation; `AiFeatures` is a pure static utility for feature extraction (testable without Supabase).

**Tech Stack:** Flutter 3, Riverpod 2.5, Supabase Edge Functions (`ai-predict-price`, `ai-bid-forecast`), `flutter gen-l10n` for EN+RW strings, `flutter_test` for unit + widget tests.

---

## File Map

| Action | File |
|--------|------|
| Modify | `lib/core/constants/supabase_constants.dart` |
| Create | `lib/data/repositories/ai_repository.dart` |
| Create | `test/ai/ai_repository_test.dart` |
| Modify | `lib/l10n/app_en.arb` |
| Modify | `lib/l10n/app_rw.arb` |
| Regen  | `lib/l10n/app_localizations.dart` (auto-generated — commit separately) |
| Regen  | `lib/l10n/app_localizations_en.dart` (auto-generated — commit separately) |
| Regen  | `lib/l10n/app_localizations_rw.dart` (auto-generated — commit separately) |
| Create | `lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart` |
| Create | `test/widgets/auction_ai_insights_panel_test.dart` |
| Modify | `lib/presentation/screens/client/auction_detail_screen.dart` |

---

## Task 1: Add Edge Function name constants

**Files:**
- Modify: `lib/core/constants/supabase_constants.dart`

- [ ] **Step 1: Add the two constants**

Open `lib/core/constants/supabase_constants.dart`. After the line `static const String fnAutoCloseAuctions = 'auto-close-auctions';` (currently the last Edge Function constant), add:

```dart
  static const String fnAiPredictPrice = 'ai-predict-price';
  static const String fnAiBidForecast = 'ai-bid-forecast';
```

- [ ] **Step 2: Verify no analysis errors**

```
flutter analyze lib/core/constants/supabase_constants.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit and push**

```
git add lib/core/constants/supabase_constants.dart
git commit -m "feat(constants): add fnAiPredictPrice and fnAiBidForecast Edge Function names"
git push origin main
```

Wait for push success before continuing.

---

## Task 2: Create AiRepository

**Files:**
- Create: `lib/data/repositories/ai_repository.dart`

- [ ] **Step 1: Create the file with full content**

Create `lib/data/repositories/ai_repository.dart` with the following content:

```dart
// lib/data/repositories/ai_repository.dart
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_constants.dart';
import '../../core/errors/exceptions.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiFeatures — pure static feature builder, no Supabase dependency.
// Tested independently in test/ai/ai_repository_test.dart.
// ─────────────────────────────────────────────────────────────────────────────

class AiFeatures {
  const AiFeatures._();

  static Map<String, dynamic> base(AuctionModel a) => {
        'main_category': a.resolvedMainCategory,
        'sub_category': a.subCategory,
        'brand': a.brand,
        'condition': a.condition,
        'region': a.region,
        'starting_price': a.startingPrice,
        'fuel_type': a.fuelType,
        'transmission': a.transmission,
        'mileage': a.mileage,
        'ownership_history': a.ownershipHistory,
        'accident_history': a.accidentHistory,
        'insurance_status': a.insuranceStatus,
        'asset_age': assetAge(a),
        'auction_duration_hours': durationHours(a),
        'has_description': a.description.isNotEmpty,
        'has_images': a.photoUrls.isNotEmpty,
        'is_mileage_known': a.mileage != null,
        'is_manufacturing_year_known': a.manufacturingYear != null,
        'is_accident_history_known': a.accidentHistory != null,
        'is_insurance_status_known': a.insuranceStatus != null,
      };

  static Map<String, dynamic> forecast(AuctionModel a) {
    final now = DateTime.now();
    final daysUntilClose = max(0.0, a.endDate.difference(now).inHours / 24.0);
    final timeToFirstBidHours = a.timeOfFirstBid != null
        ? a.timeOfFirstBid!.difference(a.startDate).inMinutes / 60.0
        : 0.0;
    final bidMomentum = a.totalBids > 0 && a.timeOfFirstBid != null
        ? a.totalBids / max(1, now.difference(a.timeOfFirstBid!).inHours)
        : 0.0;
    final viewToBidRatio = a.totalBids > 0
        ? a.viewsCount / a.totalBids.toDouble()
        : a.viewsCount.toDouble();
    final isFirstBidQuick = a.timeOfFirstBid != null &&
        a.timeOfFirstBid!.difference(a.startDate).inHours < 2;
    final priceTier = a.startingPrice < 2_000_000
        ? 'low'
        : a.startingPrice < 8_000_000
            ? 'medium'
            : 'high';

    return {
      ...base(a),
      'total_bids': a.totalBids,
      'unique_bidder_count': a.uniqueBidderCount,
      'views_count': a.viewsCount,
      'days_until_close': daysUntilClose,
      'time_to_first_bid_hours': timeToFirstBidHours,
      'bid_momentum': bidMomentum,
      'view_to_bid_ratio': viewToBidRatio,
      'bid_acceleration': 0.5,
      'is_first_bid_quick': isFirstBidQuick,
      'price_tier': priceTier,
    };
  }

  static int assetAge(AuctionModel a) =>
      a.manufacturingYear == null ? 5 : DateTime.now().year - a.manufacturingYear!;

  static double durationHours(AuctionModel a) =>
      a.endDate.difference(a.startDate).inMinutes / 60.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// AiRepository — abstract interface.
// Concrete: AiRepositoryImpl. Fake for tests: implement this interface.
// Returns null when shadow_mode is active (prediction stored, not surfaced).
// Throws AppFunctionException on HTTP errors.
// ─────────────────────────────────────────────────────────────────────────────

abstract class AiRepository {
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel auction);
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel auction);
}

class AiRepositoryImpl extends AiRepository {
  AiRepositoryImpl() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel auction) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnAiPredictPrice,
        body: {
          'auction_id': auction.auctionId,
          'store_prediction': true,
          'features': AiFeatures.base(auction),
        },
      );
      if (response.status != 200) {
        final error = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(error ?? 'AI price insight failed');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['shadow_mode'] == true) return null;
      return data;
    } on AppFunctionException {
      rethrow;
    } catch (e) {
      throw AppFunctionException('AI price insight failed: $e');
    }
  }

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel auction) async {
    try {
      final response = await _client.functions.invoke(
        SupabaseConstants.fnAiBidForecast,
        body: {
          'auction_id': auction.auctionId,
          'store_prediction': true,
          'features': AiFeatures.forecast(auction),
        },
      );
      if (response.status != 200) {
        final error = (response.data as Map?)?['error'] as String?;
        throw AppFunctionException(error ?? 'AI bid forecast failed');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['shadow_mode'] == true) return null;
      return data;
    } on AppFunctionException {
      rethrow;
    } catch (e) {
      throw AppFunctionException('AI bid forecast failed: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepositoryImpl(),
);
```

- [ ] **Step 2: Verify analysis**

```
flutter analyze lib/data/repositories/ai_repository.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit and push**

```
git add lib/data/repositories/ai_repository.dart
git commit -m "feat(ai): add AiRepository, AiRepositoryImpl, AiFeatures, and aiRepositoryProvider"
git push origin main
```

Wait for push success before continuing.

---

## Task 3: Write and run AiFeatures unit tests

**Files:**
- Create: `test/ai/ai_repository_test.dart`

- [ ] **Step 1: Create test directory and file**

Create the directory `test/ai/` if it does not exist. Then create `test/ai/ai_repository_test.dart`:

```dart
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
      final expected = DateTime.now().year - year;
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
  });

  group('AiFeatures.forecast — days_until_close', () {
    test('is non-negative even when auction already ended', () {
      final past = DateTime(2026, 1, 1);
      final result = AiFeatures.forecast(_makeAuction(endDate: past))['days_until_close'] as double;
      expect(result >= 0.0, true);
    });
  });

  group('AiFeatures.forecast — bid_momentum', () {
    test('is 0.0 when no bids placed', () {
      final a = _makeAuction(totalBids: 0, timeOfFirstBid: null);
      expect(AiFeatures.forecast(a)['bid_momentum'], 0.0);
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
```

- [ ] **Step 2: Run the tests and verify they all pass**

```
flutter test test/ai/ai_repository_test.dart --reporter=expanded
```

Expected: All tests pass with `+N: All tests passed!` (N = number of tests). If any fail, fix the implementation in `ai_repository.dart` before continuing.

- [ ] **Step 3: Commit and push**

```
git add test/ai/ai_repository_test.dart
git commit -m "test(ai): add AiFeatures unit tests (feature extraction, asset age, price tier, bid momentum)"
git push origin main
```

Wait for push success before continuing.

---

## Task 4: Add English localization strings

**Files:**
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: Insert AI strings before the closing `}`**

Open `lib/l10n/app_en.arb`. The last two lines currently are:

```json
  "auctionSoftDeleted": "Auction removed from listings (bid history preserved)."
}
```

Replace that closing section with:

```json
  "auctionSoftDeleted": "Auction removed from listings (bid history preserved).",

  "aiInsights": "AI Insights",
  "@aiInsights": { "description": "AI Insights panel title shown above the price/bid analysis card" },
  "aiValueSignalUnder": "Undervalued",
  "@aiValueSignalUnder": { "description": "Signal badge: auction starting price is below AI-estimated market value — good deal for buyer" },
  "aiValueSignalFair": "Fair Value",
  "@aiValueSignalFair": { "description": "Signal badge: starting price is close to AI-estimated market value" },
  "aiValueSignalOver": "Overvalued",
  "@aiValueSignalOver": { "description": "Signal badge: starting price exceeds AI-estimated market value — risky to bid high" },
  "aiEstMarketValue": "Est. market value",
  "@aiEstMarketValue": { "description": "Row label for the AI-estimated market value amount" },
  "aiPredictedWinBid": "Likely winning bid",
  "@aiPredictedWinBid": { "description": "Row label for the AI-predicted winning bid amount" },
  "aiWinProbability": "% chance to win",
  "@aiWinProbability": { "description": "Label for the win-probability row (percentage is prepended by the widget)" },
  "aiAtLeast": "at least",
  "@aiAtLeast": { "description": "Prefix shown before the predicted bid when it is clamped to the starting price floor" }
}
```

- [ ] **Step 2: Commit and push**

```
git add lib/l10n/app_en.arb
git commit -m "feat(l10n): add English AI Insights strings to app_en.arb"
git push origin main
```

Wait for push success before continuing.

---

## Task 5: Add Kinyarwanda localization strings

**Files:**
- Modify: `lib/l10n/app_rw.arb`

- [ ] **Step 1: Check the last line of app_rw.arb**

Open `lib/l10n/app_rw.arb` and find the last string entry before the closing `}`. Add the following entries (matching the same keys as in `app_en.arb`, no `@` metadata blocks needed in non-template files):

```json
  "aiInsights": "Ubushishozi bwa AI",
  "aiValueSignalUnder": "Igiciro cyoroheje",
  "aiValueSignalFair": "Igiciro gikwiriye",
  "aiValueSignalOver": "Igiciro kirenzeho",
  "aiEstMarketValue": "Igiciro ku isoko",
  "aiPredictedWinBid": "Igiciro gishoboka ko ari cyo kizatsinda",
  "aiWinProbability": "% yo gutsinda",
  "aiAtLeast": "nibura"
```

Insert these before the closing `}`, preceded by a comma on the previous last entry.

- [ ] **Step 2: Commit and push**

```
git add lib/l10n/app_rw.arb
git commit -m "feat(l10n): add Kinyarwanda AI Insights strings to app_rw.arb"
git push origin main
```

Wait for push success before continuing.

---

## Task 6: Regenerate l10n and commit generated files

**Files:**
- Regen: `lib/l10n/app_localizations.dart`
- Regen: `lib/l10n/app_localizations_en.dart`
- Regen: `lib/l10n/app_localizations_rw.dart`

- [ ] **Step 1: Run the l10n generator**

```
flutter gen-l10n
```

Expected: No errors. The command regenerates `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_en.dart`, and `lib/l10n/app_localizations_rw.dart`.

- [ ] **Step 2: Verify the new keys exist**

```
flutter analyze lib/l10n/app_localizations.dart
```

Also manually confirm `aiInsights`, `aiValueSignalUnder`, `aiEstMarketValue`, `aiPredictedWinBid`, `aiWinProbability`, `aiAtLeast` appear in `lib/l10n/app_localizations.dart`.

- [ ] **Step 3: Commit app_localizations.dart**

```
git add lib/l10n/app_localizations.dart
git commit -m "chore(l10n): regenerate app_localizations.dart with AI Insights keys"
git push origin main
```

Wait for push success.

- [ ] **Step 4: Commit app_localizations_en.dart**

```
git add lib/l10n/app_localizations_en.dart
git commit -m "chore(l10n): regenerate app_localizations_en.dart with AI Insights keys"
git push origin main
```

Wait for push success.

- [ ] **Step 5: Commit app_localizations_rw.dart**

```
git add lib/l10n/app_localizations_rw.dart
git commit -m "chore(l10n): regenerate app_localizations_rw.dart with AI Insights keys"
git push origin main
```

Wait for push success before continuing.

---

## Task 7: Create AuctionAiInsightsPanel widget

**Files:**
- Create: `lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart`

- [ ] **Step 1: Create the file**

Create directory `lib/presentation/screens/client/widgets/` if it does not exist. Then create `lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart`:

```dart
// lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_localizations_ext.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/models.dart';
import '../../../../data/repositories/ai_repository.dart';
import '../../../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget — inserted into AuctionDetailScreen after the bid stats box.
// Fires both AI calls once in initState via Future.wait.
// Any failure (network error, shadow mode, null result) → SizedBox.shrink().
// The bid flow below is NEVER blocked.
// ─────────────────────────────────────────────────────────────────────────────

class AuctionAiInsightsPanel extends ConsumerStatefulWidget {
  const AuctionAiInsightsPanel({
    super.key,
    required this.auctionId,
    required this.auction,
  });

  final String auctionId;
  final AuctionModel auction;

  @override
  ConsumerState<AuctionAiInsightsPanel> createState() =>
      _AuctionAiInsightsPanelState();
}

class _AuctionAiInsightsPanelState
    extends ConsumerState<AuctionAiInsightsPanel> {
  late final Future<List<Map<String, dynamic>?>> _combinedFuture;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(aiRepositoryProvider);
    _combinedFuture = Future.wait<Map<String, dynamic>?>([
      repo.fetchPriceInsight(widget.auction).catchError((_) => null),
      repo.fetchBidForecast(widget.auction).catchError((_) => null),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: _combinedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AiInsightsShimmer();
        }
        if (snapshot.hasError) return const SizedBox.shrink();

        final insight = snapshot.data?[0];
        final forecast = snapshot.data?[1];

        if (insight == null && forecast == null) return const SizedBox.shrink();
        if (insight?['shadow_mode'] == true) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _AiInsightsCard(
            insight: insight,
            forecast: forecast,
            startingPrice: widget.auction.startingPrice,
          ),
        );
      },
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class _AiInsightsShimmer extends StatefulWidget {
  const _AiInsightsShimmer();

  @override
  State<_AiInsightsShimmer> createState() => _AiInsightsShimmerState();
}

class _AiInsightsShimmerState extends State<_AiInsightsShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBar(120, 14),
              const SizedBox(height: 12),
              _shimmerBar(double.infinity, 12),
              const SizedBox(height: 8),
              _shimmerBar(double.infinity, 12),
              const SizedBox(height: 8),
              _shimmerBar(180, 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBar(double width, double height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      );
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _AiInsightsCard extends StatelessWidget {
  const _AiInsightsCard({
    required this.insight,
    required this.forecast,
    required this.startingPrice,
  });

  final Map<String, dynamic>? insight;
  final Map<String, dynamic>? forecast;
  final double startingPrice;

  @override
  Widget build(BuildContext context) {
    final signal = insight?['value_signal'] as String? ?? 'fair_value';
    final marketPrice =
        (insight?['expected_auction_price'] as num?)?.toDouble();
    final modelVersion = insight?['model_version'] as String? ??
        forecast?['model_b_version'] as String?;

    double? clampedBid;
    bool isAtFloor = false;
    final rawBid = (forecast?['predicted_winning_bid'] as num?)?.toDouble();
    if (rawBid != null) {
      clampedBid = max(rawBid, startingPrice);
      isAtFloor = clampedBid <= startingPrice * 1.05;
    }

    double? probability =
        (forecast?['predicted_probability'] as num?)?.toDouble();
    if (probability != null) probability = probability.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: AppColors.primaryBlue),
              const SizedBox(width: 6),
              Text(
                context.l10n.aiInsights,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryBlue,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (modelVersion != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    modelVersion,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),
          _ValueSignalBadge(signal: signal),

          if (marketPrice != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PriceRow(
              label: context.l10n.aiEstMarketValue,
              amount: marketPrice,
            ),
          ],

          if (clampedBid != null) ...[
            const Divider(height: AppSpacing.lg),
            _PriceRow(
              label: context.l10n.aiPredictedWinBid,
              amount: clampedBid,
              prefix: isAtFloor ? context.l10n.aiAtLeast : null,
            ),
          ],

          if (probability != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _ProbabilityRow(probability: probability),
          ],
        ],
      ),
    );
  }
}

// ── Value signal badge ────────────────────────────────────────────────────────

class _ValueSignalBadge extends StatelessWidget {
  const _ValueSignalBadge({required this.signal});
  final String signal;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (signal) {
      'undervalued' => (context.l10n.aiValueSignalUnder, AppColors.success),
      'overvalued' => (context.l10n.aiValueSignalOver, AppColors.warning),
      _ => (context.l10n.aiValueSignalFair, AppColors.primaryBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ── Price row ─────────────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.prefix,
  });
  final String label;
  final double amount;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final formatted = prefix != null
        ? '$prefix ${AppFormatters.rwf(amount)}'
        : AppFormatters.rwf(amount);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          formatted,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Probability row ───────────────────────────────────────────────────────────

class _ProbabilityRow extends StatelessWidget {
  const _ProbabilityRow({required this.probability});
  final double probability;

  @override
  Widget build(BuildContext context) {
    final pct = (probability * 100).round();
    final barColor = probability >= 0.6
        ? AppColors.success
        : probability >= 0.3
            ? AppColors.warning
            : AppColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.aiWinProbability,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: probability,
          backgroundColor: AppColors.border,
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          minHeight: 6,
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Verify analysis**

```
flutter analyze lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart
```

Expected: `No issues found!`

- [ ] **Step 3: Commit and push**

```
git add lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart
git commit -m "feat(ui): add AuctionAiInsightsPanel widget with shimmer, value signal badge, price rows, probability bar"
git push origin main
```

Wait for push success before continuing.

---

## Task 8: Write and run widget tests

**Files:**
- Create: `test/widgets/auction_ai_insights_panel_test.dart`

- [ ] **Step 1: Create the test file**

Create directory `test/widgets/` if it does not exist. Then create `test/widgets/auction_ai_insights_panel_test.dart`:

```dart
// test/widgets/auction_ai_insights_panel_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecyamunara/data/models/models.dart';
import 'package:ecyamunara/data/repositories/ai_repository.dart';
import 'package:ecyamunara/l10n/app_localizations.dart';
import 'package:ecyamunara/presentation/screens/client/widgets/auction_ai_insights_panel.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

// Instantly-resolving fake — returns pre-set results or throws.
class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({
    this.insight,
    this.forecast,
    this.shouldThrow = false,
  });
  final Map<String, dynamic>? insight;
  final Map<String, dynamic>? forecast;
  final bool shouldThrow;

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel _) async {
    if (shouldThrow) throw Exception('Network error');
    return insight;
  }

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel _) async {
    if (shouldThrow) throw Exception('Network error');
    return forecast;
  }
}

// Completer-backed fake — holds futures in pending state until .complete() is
// called. Used to test the shimmer (loading) state.
class _ManualFakeAiRepository implements AiRepository {
  final _insightCompleter = Completer<Map<String, dynamic>?>();
  final _forecastCompleter = Completer<Map<String, dynamic>?>();

  void complete({Map<String, dynamic>? insight, Map<String, dynamic>? forecast}) {
    if (!_insightCompleter.isCompleted) _insightCompleter.complete(insight);
    if (!_forecastCompleter.isCompleted) _forecastCompleter.complete(forecast);
  }

  @override
  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel _) =>
      _insightCompleter.future;

  @override
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel _) =>
      _forecastCompleter.future;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AuctionModel _testAuction({double startingPrice = 5_000_000}) => AuctionModel(
      auctionId: 'test-001',
      itemName: 'Toyota Hilux',
      category: 'vehicle',
      plateNumber: 'RAC 000 A',
      condition: 'good',
      description: 'Test',
      photoUrls: const ['photo.jpg'],
      startingPrice: startingPrice,
      currentHighestBid: startingPrice,
      totalBids: 5,
      region: 'Central',
      postedByAdminUid: 'admin-1',
      postedByAdminName: 'Admin',
      auctionStatus: 'active',
      startDate: DateTime(2026, 6, 14),
      endDate: DateTime(2026, 6, 17),
      createdAt: DateTime(2026, 6, 14),
      updatedAt: DateTime(2026, 6, 14),
    );

Widget _wrap(Widget child, AiRepository repo) {
  return ProviderScope(
    overrides: [aiRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final auction = _testAuction();

  group('AuctionAiInsightsPanel — loading state', () {
    testWidgets('shows AnimatedBuilder shimmer while futures are pending',
        (tester) async {
      final repo = _ManualFakeAiRepository();
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        repo,
      ));
      await tester.pump(); // one frame — futures still unresolved

      expect(find.byType(AnimatedBuilder), findsOneWidget);
      expect(find.text('AI Insights'), findsNothing);
    });
  });

  group('AuctionAiInsightsPanel — collapse cases', () {
    testWidgets('collapses when both results are null', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(insight: null, forecast: null),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });

    testWidgets('collapses when insight has shadow_mode: true', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {'shadow_mode': true},
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.7,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });

    testWidgets('collapses silently when both futures throw', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(shouldThrow: true),
      ));
      await tester.pumpAndSettle();
      expect(find.text('AI Insights'), findsNothing);
    });
  });

  group('AuctionAiInsightsPanel — value signal badges', () {
    testWidgets('shows "Undervalued" badge for undervalued signal',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 7_000_000.0,
            'value_signal': 'undervalued',
            'value_ratio': 1.4,
            'model_version': 'v1.0.4-synthetic',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('AI Insights'), findsOneWidget);
      expect(find.text('Undervalued'), findsOneWidget);
    });

    testWidgets('shows "Overvalued" badge for overvalued signal', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 3_000_000.0,
            'value_signal': 'overvalued',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overvalued'), findsOneWidget);
    });

    testWidgets('shows "Fair Value" badge for unknown signal string',
        (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: {
            'expected_auction_price': 5_000_000.0,
            'value_signal': 'some_future_unknown_signal',
            'shadow_mode': false,
          },
          forecast: null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Fair Value'), findsOneWidget);
    });
  });

  group('AuctionAiInsightsPanel — starting price floor clamping', () {
    testWidgets(
        'shows "at least" prefix when predicted bid is below starting price floor',
        (tester) async {
      // startingPrice = 5,000,000; predicted = 3,000,000 → clamped to 5,000,000
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 3_000_000.0,
            'predicted_probability': 0.4,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsOneWidget);
    });

    testWidgets(
        'shows "at least" prefix when predicted bid is within 5% above floor',
        (tester) async {
      // floor = 5,000,000; predicted = 5,100,000 (2% above) → clamped label
      final a = _testAuction(startingPrice: 5_000_000);
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: a.auctionId, auction: a),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 5_100_000.0,
            'predicted_probability': 0.5,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsOneWidget);
    });

    testWidgets('shows bare amount (no prefix) when predicted bid is above floor by > 5%',
        (tester) async {
      // floor = 5,000,000; predicted = 6,000,000 (20% above) → no prefix
      final a = _testAuction(startingPrice: 5_000_000);
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: a.auctionId, auction: a),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.6,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least'), findsNothing);
      expect(find.textContaining('RWF'), findsOneWidget);
    });
  });

  group('AuctionAiInsightsPanel — probability bar', () {
    testWidgets('renders probability percentage label', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 0.73,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('73%'), findsOneWidget);
    });

    testWidgets('clamps probability > 1.0 to 100%', (tester) async {
      await tester.pumpWidget(_wrap(
        AuctionAiInsightsPanel(auctionId: auction.auctionId, auction: auction),
        _FakeAiRepository(
          insight: null,
          forecast: {
            'predicted_winning_bid': 6_000_000.0,
            'predicted_probability': 1.3,
            'shadow_mode': false,
          },
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the widget tests**

```
flutter test test/widgets/auction_ai_insights_panel_test.dart --reporter=expanded
```

Expected: All tests pass. If any fail, fix the widget implementation in Task 7 first, then re-run.

- [ ] **Step 3: Commit and push**

```
git add test/widgets/auction_ai_insights_panel_test.dart
git commit -m "test(ui): add widget tests for AuctionAiInsightsPanel (loading, collapse, badges, clamping, probability)"
git push origin main
```

Wait for push success before continuing.

---

## Task 9: Wire panel into AuctionDetailScreen

**Files:**
- Modify: `lib/presentation/screens/client/auction_detail_screen.dart`

- [ ] **Step 1: Add the import**

In `lib/presentation/screens/client/auction_detail_screen.dart`, after the existing import on line 31:

```dart
import 'client_providers.dart';
```

Add a new import line:

```dart
import 'widgets/auction_ai_insights_panel.dart';
```

- [ ] **Step 2: Insert the panel after the bid stats box**

In the same file, find the following block (around line 432):

```dart
                      const SizedBox(height: 20),

                      // ── Bid / update button ────────────────────────────────
```

Replace it with:

```dart
                      const SizedBox(height: 20),

                      // ── AI Insights Panel ──────────────────────────────────
                      AuctionAiInsightsPanel(
                        auctionId: auction.auctionId,
                        auction: auction,
                      ),

                      // ── Bid / update button ────────────────────────────────
```

The panel carries its own `Padding(bottom: AppSpacing.md)` internally when visible, so no extra `SizedBox` is needed between it and the bid button.

- [ ] **Step 3: Verify analysis**

```
flutter analyze lib/presentation/screens/client/auction_detail_screen.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Run all tests to confirm nothing regressed**

```
flutter test --reporter=expanded
```

Expected: All tests pass.

- [ ] **Step 5: Commit and push**

```
git add lib/presentation/screens/client/auction_detail_screen.dart
git commit -m "feat(ui): insert AuctionAiInsightsPanel into AuctionDetailScreen after bid stats box"
git push origin main
```

Wait for push success before continuing.

---

## Task 10: Final verification

- [ ] **Step 1: Full analysis**

```
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

```
flutter test --reporter=expanded
```

Expected: All existing tests plus new AI tests pass.

- [ ] **Step 3: Manual smoke test (optional but recommended)**

Run the app on a connected device or emulator:

```
flutter run --dart-define-from-file=.env.json
```

1. Log in as a client.
2. Open any active auction.
3. Scroll past the bid stats box.
4. **If `ai.predictions_visible_to_clients = 'true'` in Supabase:** the AI Insights card should appear with value signal badge, market price, predicted winning bid, and probability bar.
5. **If shadow mode is on (default):** no panel is shown — this is correct behaviour.

To enable client visibility for testing, run this SQL in Supabase Dashboard → SQL Editor:

```sql
UPDATE ai_feature_flags
SET value = 'true'
WHERE key = 'ai.predictions_visible_to_clients';
```

Remember to set it back to `'false'` when done testing.

---

## Security Checklist (verify before considering Phase 8 complete)

- [ ] No `import` of FastAPI URL anywhere in Flutter code
- [ ] No service-role keys in any Flutter file
- [ ] No calls to `ai-retrain-trigger`, `ai-model-promote`, `ai-model-rollback` from Flutter
- [ ] Panel collapses silently on every error path (verified by widget tests)
- [ ] Bid button is unaffected by panel state (panel is inserted above, bid button is independent)
