# Phase 8 — AI Buyer-Assistance Integration Design

**Date:** 2026-06-15  
**Status:** Approved  
**Scope:** Flutter client UI only — no changes to Edge Functions, FastAPI, model registry, training pipelines, or promotion/rollback logic.

---

## 1. Goal

Surface AI-generated price insights and bid forecasts to authenticated buyers inside `AuctionDetailScreen`. All AI data flows exclusively through the two buyer-facing Edge Functions (`ai-predict-price`, `ai-bid-forecast`). The AI panel is strictly additive — every failure mode collapses it silently; the bid flow is never blocked.

---

## 2. Security Constraints (non-negotiable)

- Flutter **never** calls FastAPI directly. Only `_client.functions.invoke(...)` is used.
- Only `ai-predict-price` and `ai-bid-forecast` are called from Flutter. The three admin-only functions (`ai-retrain-trigger`, `ai-model-promote`, `ai-model-rollback`) are never referenced in client code.
- No API keys, service-role keys, or admin credentials appear anywhere in Flutter code.
- AI features never block: viewing auctions, placing bids, registration, or authentication.

---

## 3. Domain Constraint — Starting Price Floor

Region admins set a minimum starting price when posting an auction. No bid below that floor is accepted by the system. This has two implications for the AI panel:

1. `predicted_winning_bid` from Model B is clamped: `max(predicted_winning_bid, auction.startingPrice)`. If the clamped value equals `startingPrice` or is within 5% above it, display "at least RWF X" instead of a bare number to communicate honest uncertainty.
2. The value signal ratio `expected_auction_price / startingPrice` — values > 1.0 indicate the starting price is below market (good deal for buyer); values < 1.0 indicate the starting price already exceeds estimated market value (risky).

---

## 4. Architecture

```
AuctionDetailScreen
  └─ AuctionAiInsightsPanel(auctionId, auction)    ConsumerStatefulWidget
       │  initState fires both futures once, in parallel
       ├─ AiRepository.fetchPriceInsight(auction)
       │    └─ functions.invoke('ai-predict-price', body: {auction_id, features})
       │
       └─ AiRepository.fetchBidForecast(auction)
            └─ functions.invoke('ai-bid-forecast', body: {auction_id, features})
```

Futures are stored in `initState` and combined via `Future.wait([...])`. They fire exactly once per screen visit — not on each bid stream update. The Edge Functions have a 30-minute server-side cache, so repeat visits to the same auction return instantly. Memory is released when the widget is disposed.

---

## 5. Files Changed / Created

| File | Change |
|------|--------|
| `lib/core/constants/supabase_constants.dart` | Add `fnAiPredictPrice`, `fnAiBidForecast` constants |
| `lib/data/repositories/ai_repository.dart` | **NEW** — `AiRepository` class + `aiRepositoryProvider` |
| `lib/presentation/screens/client/widgets/auction_ai_insights_panel.dart` | **NEW** — `ConsumerStatefulWidget` panel + shimmer + card sub-widgets |
| `lib/presentation/screens/client/auction_detail_screen.dart` | Insert `AuctionAiInsightsPanel` after bid stats box (~line 432) |
| `lib/core/localization/language_service.dart` | Add EN + RW localization strings for all AI-facing text |
| `test/ai/ai_repository_test.dart` | **NEW** — unit tests for feature extraction and clamping |
| `test/widgets/auction_ai_insights_panel_test.dart` | **NEW** — widget tests for all panel states |

No new screens. No new routes. No service-role usage.

---

## 6. AiRepository

### Class skeleton

```dart
class AiRepository {
  AiRepository() : _client = Supabase.instance.client;
  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetchPriceInsight(AuctionModel auction) async { ... }
  Future<Map<String, dynamic>?> fetchBidForecast(AuctionModel auction) async { ... }

  Map<String, dynamic> _buildBaseFeatures(AuctionModel a) { ... }
  int _assetAge(AuctionModel a) { ... }
  double _durationHours(AuctionModel a) { ... }
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository());
```

Returns `null` when the Edge Function responds with `shadow_mode: true` (prediction stored but not surfaced to client). Throws `AppFunctionException` on HTTP errors so providers emit `AsyncError`.

### Base features sent to both Edge Functions

| Feature key | Source |
|---|---|
| `main_category` | `auction.mainCategory ?? auction.category` |
| `sub_category` | `auction.subCategory` |
| `brand` | `auction.brand` |
| `condition` | `auction.condition` |
| `region` | `auction.region` |
| `starting_price` | `auction.startingPrice` |
| `fuel_type` | `auction.fuelType` |
| `transmission` | `auction.transmission` |
| `mileage` | `auction.mileage` |
| `ownership_history` | `auction.ownershipHistory` |
| `accident_history` | `auction.accidentHistory` |
| `insurance_status` | `auction.insuranceStatus` |
| `asset_age` | `now.year − manufacturingYear` (default 5 if null) |
| `auction_duration_hours` | `endDate.difference(startDate).inMinutes / 60` |
| `has_description` | `auction.description.isNotEmpty` |
| `has_images` | `auction.photoUrls.isNotEmpty` |
| `is_mileage_known` | `auction.mileage != null` |
| `is_manufacturing_year_known` | `auction.manufacturingYear != null` |
| `is_accident_history_known` | `auction.accidentHistory != null` |
| `is_insurance_status_known` | `auction.insuranceStatus != null` |

### Additional features for `ai-bid-forecast` only

| Feature key | Computation |
|---|---|
| `total_bids` | `auction.totalBids` |
| `unique_bidder_count` | `auction.uniqueBidderCount` |
| `views_count` | `auction.viewsCount` |
| `days_until_close` | `endDate.difference(now).inHours / 24` (min 0.0) |
| `time_to_first_bid_hours` | `timeOfFirstBid != null ? timeOfFirstBid!.difference(startDate).inMinutes / 60 : 0.0` |
| `bid_momentum` | `totalBids > 0 && timeOfFirstBid != null ? totalBids / max(1, now.difference(timeOfFirstBid!).inHours) : 0.0` |
| `view_to_bid_ratio` | `totalBids > 0 ? viewsCount / totalBids : viewsCount.toDouble()` |
| `bid_acceleration` | `0.5` (static default — no per-interval bid data available client-side) |
| `is_first_bid_quick` | `timeOfFirstBid != null && timeOfFirstBid!.difference(startDate).inHours < 2` |
| `price_tier` | `startingPrice < 2_000_000 ? 'low' : startingPrice < 8_000_000 ? 'medium' : 'high'` |

---

## 7. Provider / State Pattern

`AuctionAiInsightsPanel` is a `ConsumerStatefulWidget`. Both AI futures are fired exactly once in `initState` by reading `aiRepositoryProvider` directly. This avoids re-firing on every bid stream update (the auction stream emits on every bid; using `ref.watch` inside a `FutureProvider` would cause unnecessary refetches).

```dart
class _AuctionAiInsightsPanelState extends ConsumerState<AuctionAiInsightsPanel> {
  late final Future<Map<String, dynamic>?> _insightFuture;
  late final Future<Map<String, dynamic>?> _forecastFuture;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(aiRepositoryProvider);
    _insightFuture = repo.fetchPriceInsight(widget.auction);
    _forecastFuture = repo.fetchBidForecast(widget.auction);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([_insightFuture, _forecastFuture]),
      builder: (context, snapshot) { ... },
    );
  }
}
```

`FutureBuilder` with `Future.wait([...])` gives a single combined snapshot. Both futures run in parallel. The widget is disposed when the user leaves the screen — no memory leak.

---

## 8. Widget Structure — `AuctionAiInsightsPanel`

```
AuctionAiInsightsPanel(auctionId, auction)   ConsumerStatefulWidget
  │  initState → _insightFuture, _forecastFuture (both via ref.read(aiRepositoryProvider))
  │
  └─ FutureBuilder(future: Future.wait([_insightFuture, _forecastFuture]))
       ├─ ConnectionState.waiting              → _AiInsightsShimmer()
       ├─ snapshot.hasError                   → SizedBox.shrink()
       ├─ data[0] == null && data[1] == null  → SizedBox.shrink()
       ├─ data[0]?['shadow_mode'] == true     → SizedBox.shrink()
       │
       └─ _AiInsightsCard(insight, forecast, startingPrice: auction.startingPrice)
            ├─ Header: Icon(Icons.auto_awesome) + "AI Insights" + version chip
            ├─ _ValueSignalBadge(signal)          colored chip
            ├─ _PriceRow(label, amount)           Est. market value
            ├─ Divider
            ├─ _PriceRow(label, amount, isFloor)  Likely winning bid (clamped)
            └─ _ProbabilityRow(probability)       linear bar + percentage label
```

### Clamping logic (inside `_AiInsightsCard`)

```dart
final rawBid = (forecast['predicted_winning_bid'] as num).toDouble();
final floor = startingPrice;
final clampedBid = max(rawBid, floor);
final isAtFloor = clampedBid <= floor * 1.05;
```

If `isAtFloor` is true, the label reads "at least RWF X" instead of "RWF X".

### Colors

| Signal | Color |
|---|---|
| `undervalued` | `AppColors.success` |
| `fair_value` | `AppColors.primaryBlue` |
| `overvalued` | `AppColors.warning` |
| Unknown signal | `AppColors.primaryBlue` (safe default) |

### Shimmer

`_AiInsightsShimmer` — same card height as the real panel, three grey rounded rectangles, `AnimatedOpacity` pulsing between 0.3 and 0.7. No external animation package.

### Insertion point

`auction_detail_screen.dart` ~line 432, inside the content `Column`, after the bid stats box and before the bid button section:

```dart
AuctionAiInsightsPanel(
  auctionId: widget.auctionId,
  auction: auction,
),
```

Wrapped in `Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.md))` to match surrounding content padding.

---

## 9. Localization Strings

Added to `language_service.dart` under both `_en` and `_rw` maps:

| Key | English | Kinyarwanda |
|---|---|---|
| `aiInsights` | `AI Insights` | `Ubushishozi bwa AI` |
| `aiValueSignalUnder` | `Undervalued` | `Igiciro cyoroheje` |
| `aiValueSignalFair` | `Fair Value` | `Igiciro gikwiriye` |
| `aiValueSignalOver` | `Overvalued` | `Igiciro kirenzeho` |
| `aiEstMarketValue` | `Est. market value` | `Igiciro ku isoko` |
| `aiPredictedWinBid` | `Likely winning bid` | `Igiciro gishoboka ko ari cyo kizatsinda` |
| `aiWinProbability` | `% chance to win` | `% yo gutsinda` |
| `aiAtLeast` | `at least` | `nibura` |

---

## 10. Error Handling — Full Decision Table

| Scenario | Behaviour |
|---|---|
| `shadow_mode: true` in response | `null` returned by repository → panel collapses |
| HTTP 4xx / 5xx from Edge Function | `AppFunctionException` thrown → `AsyncError` → panel collapses |
| Network timeout (provider never resolves) | Flutter default future timeout → `AsyncError` → panel collapses |
| `predicted_winning_bid < startingPrice` | Clamped to `startingPrice`; "at least" prefix added |
| `predicted_winning_bid` within 5% above floor | "at least" prefix added |
| `predicted_probability` outside [0.0, 1.0] | Clamped to `[0.0, 1.0]` |
| Unknown `value_signal` string | Rendered as `fair_value` (blue chip) |
| Auction already closed | Panel renders normally (read-only insight) |
| `expected_auction_price` null in response | Price row omitted; bid forecast rows still shown |
| `auctionWatcherProvider` not yet emitted | Both providers return `null` → panel collapses |

---

## 11. Tests

### `test/ai/ai_repository_test.dart`

- Full auction → all feature keys present and correctly mapped
- Sparse auction (all nullable fields null) → `is_xxx_known: false` flags set; `asset_age` defaults to 5
- `asset_age` computed correctly from `manufacturingYear`
- `auction_duration_hours` computed correctly
- `predicted_winning_bid` below `startingPrice` → clamped to `startingPrice`
- `predicted_probability` = 1.3 → clamped to 1.0
- HTTP 500 response → `AppFunctionException` thrown
- `shadow_mode: true` response → returns `null`

### `test/widgets/auction_ai_insights_panel_test.dart`

- `AsyncLoading` on either provider → shimmer rendered
- `AsyncError` on either provider → `SizedBox.shrink()` rendered (finder finds no `_AiInsightsCard`)
- `shadow_mode: true` → `SizedBox.shrink()` rendered
- `value_signal: 'undervalued'` → green chip rendered
- `value_signal: 'overvalued'` → warning-color chip rendered
- Unknown `value_signal` → blue chip rendered
- `predicted_winning_bid` below floor → "at least" text present
- Probability bar renders with correct percentage label

---

## 12. What Is Explicitly Out of Scope

- Admin-facing AI panels (retrain, promote, rollback) — Phase 9
- My Bids screen AI overlay — Phase 9
- Home screen auction badges ("Worth Watching" etc.) — Phase 9
- Any changes to FastAPI, model registry, training pipelines, or Edge Function logic
- Push notifications for AI insights
