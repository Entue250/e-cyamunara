# E-CYAMUNARA — Bidding Logic Fix & Bid Update Feature
**Date:** 2026-05-12  
**Status:** Approved  
**Scope:** Fix broken bid validation, add bid-update functionality, update UI/UX

---

## Problem

The `accept_bid` PostgreSQL RPC rejects any bid that does not exceed the current highest bid:

```sql
IF p_bid_amount <= v_auction.current_highest_bid THEN
  RETURN ... 'BID_TOO_LOW' ...
```

This is wrong. An auction allows any bid ≥ the starting (minimum) price. Only the highest bid at close time wins — other lower bids are valid participants.

The same incorrect guard is also duplicated in the Flutter `_BidBottomSheet` widget.

---

## Requirements Summary

### Validation rules (ALLOW)
- `bid_amount >= starting_price`
- auction `status == 'active'`
- auction `end_date > NOW()`
- authenticated, non-suspended client

### Validation rules (DISALLOW)
- `bid_amount < starting_price`
- closed / expired auction
- suspended account
- non-numeric / invalid amount

### Bid update
- One active bid per `(auction_id, bidder_uid)` — stored in a single DB row, updated in place
- Updating replaces the previous amount atomically
- `updated_at` refreshed on every update
- `total_bids` on the auction and `total_bids_placed` on the user are incremented only on the first bid (not on updates)

### Winner logic (unchanged)
- `current_highest_bid = MAX(bid_amount)` across all bids for the auction
- `current_winner_uid` = bidder with that max amount
- All other bids remain as `bid_status = 'outbid'`
- On auction close: `winner_uid = current_winner_uid`

---

## Architecture

### Approach: Replace `accept_bid` RPC (Approach A)

Single SQL migration rewrites the server-side function. All bid placement and update logic is handled in one atomic transaction. No separate Edge Function branch needed — the function transparently handles both "new bid" and "update bid" cases.

---

## Layer-by-layer Changes

### 1. Database Migration (`supabase/migrations/20260512000000_bidding_fix.sql`)

```
bids table:
  + updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  - DROP INDEX IF EXISTS idx_bids_one_winner_per_auction   (partial unique index)
  + ADD UNIQUE (auction_id, bidder_uid)                    (replaces the partial index)

Pre-constraint deduplication:
  DELETE rows where (auction_id, bidder_uid) duplicate, keeping the row
  with the highest bid_amount (or latest created_at if tie).

accept_bid() rewrite:
  REMOVES: BID_TOO_LOW check (p_bid_amount <= current_highest_bid)
  KEEPS:   BELOW_START check (p_bid_amount < starting_price)
  KEEPS:   NOT_ACTIVE, ENDED, NOT_FOUND guards
  NEW logic:
    1. Lock auction row (FOR UPDATE)
    2. All existing validation guards (no BID_TOO_LOW)
    3. Lock existing bid row if present (FOR UPDATE)
    4. If existing bid → UPDATE amount + updated_at (no stat increments)
    5. If no existing bid → INSERT; increment total_bids + total_bids_placed
    6. Recalculate winner: SELECT ... ORDER BY bid_amount DESC LIMIT 1
    7. Bulk UPDATE bids SET bid_status = 'winning'/'outbid' for this auction
    8. UPDATE auctions SET current_highest_bid, current_winner_uid, current_winner_name
    9. Return: success, new_highest_bid, is_winning, is_update, prev_winner_uid,
               item_name, admin_uid

GRANT/REVOKE: same as before (service_role only)
```

### 2. Edge Function `place-bid`

- Remove fast-reject `current_highest_bid` comparison (step 5 in current code)
- After RPC success, use `result.is_winning` and `result.is_update` to choose notification:

| is_update | is_winning | Bidder notification |
|-----------|-----------|---------------------|
| false     | true      | "You're winning! 🏆" |
| false     | false     | "Bid placed — not the highest yet" (`bid_placed` type) |
| true      | true      | "You're now leading! 🏆" |
| true      | false     | "Bid updated — not the highest yet" |

- Outbid notification to `prev_winner_uid` when a NEW winner takes over (same as now)
- Response to client: `{ success, new_highest_bid, is_winning, is_update }`

### 3. Flutter — Data Layer

**`BidModel`** (`lib/data/models/models.dart`):
- Add `final DateTime? updatedAt`
- `fromMap`: parse `updated_at`
- `toMap`: emit `updated_at`

**`BidRepository`** (`lib/data/repositories/repositories.dart`):
- `placeBid` method: signature unchanged — Edge Function transparently handles place vs update
- Add: `Future<BidModel?> getClientBidForAuction(String auctionId, String clientUid)`
  - Queries `bids WHERE auction_id = ? AND bidder_uid = ?`, returns `maybeSingle()`

**`client_providers.dart`**:
- Add: `clientBidForAuctionProvider`
  ```dart
  FutureProvider.family<BidModel?, ({String auctionId, String clientUid})>
  ```
  Calls `BidRepository.getClientBidForAuction`. Invalidated after a successful bid.

### 4. Flutter — Presentation Layer

**`auction_detail_screen.dart`**:
- `_showBidDialog` fetches `clientBidForAuctionProvider` and passes `existingBid` to the bottom sheet
- `_BidBottomSheet` gains:
  - `final BidModel? existingBid`
  - Title: "Update Your Bid" / "Place Your Bid"
  - Info rows: Minimum Price | Current Highest Bid | Your Current Bid (if exists)
  - Pre-fill `_bidController` with existing bid amount
  - Validation: `amount >= auction.startingPrice` (replaces `> currentHighest`)
  - Submit button label: "UPDATE BID" / "PLACE BID"
  - After success: invalidate `clientBidForAuctionProvider`

**`bid_confirmation_screen.dart`**:
- Read `is_update` from `bidNotifierProvider` state value
- Heading: "Bid Updated!" / "Bid Successfully Placed!"
- Status pill: "CURRENTLY WINNING" (green, `AppColors.success`) or "BID REGISTERED" (blue, `AppColors.primaryBlue`)

**`client_shared.dart` — `BidTile`**:
- Add "Update Bid" `TextButton` when `auction?.isActive == true && auction?.isExpired == false`
- Navigates to `/auction/{bid.auctionId}` (detail screen handles the rest)

**`my_bids_screen.dart`**:
- No structural changes required; existing filter logic already handles one bid per auction

**`providers.dart` — `BidNotifier`**:
- Expose `isUpdate` getter derived from `state.value?['is_update']`

---

## Notification Types (new type: `bid_placed`)

Add `bid_placed` to the `_typeConfig` map in `client_shared.dart`:
```dart
'bid_placed': (
  icon: Icons.gavel_outlined,
  color: AppColors.primaryBlue,
  bg: Color(0xFFE3F2FD),
),
```

---

## Test Cases

| # | Setup | Expected |
|---|-------|----------|
| 1 | Min=5M, A bids 9M, B bids 7M | Both accepted; A remains winner |
| 2 | B updates 7M → 10M | Accepted; B becomes winner; A gets outbid notification |
| 3 | B updates 10M → 6M | Accepted; A recalculated as winner; B gets outbid |
| 4 | Anyone bids 4M (min=5M) | Rejected: BELOW_START |
| 5 | Auction expired | New bids and updates rejected: ENDED |

---

## Files Changed

| File | Change |
|------|--------|
| `supabase/migrations/20260512000000_bidding_fix.sql` | New migration |
| `supabase/functions/place-bid/index.ts` | Remove bad guard, update notifications |
| `lib/data/models/models.dart` | Add `updatedAt` to `BidModel` |
| `lib/data/repositories/repositories.dart` | Add `getClientBidForAuction` |
| `lib/presentation/providers/providers.dart` | `BidNotifier` exposes `is_update` |
| `lib/presentation/screens/client/client_providers.dart` | Add `clientBidForAuctionProvider` |
| `lib/presentation/screens/client/auction_detail_screen.dart` | Update bid dialog |
| `lib/presentation/screens/client/bid_confirmation_screen.dart` | Handle update flow |
| `lib/presentation/screens/client/client_shared.dart` | BidTile "Update Bid" button + `bid_placed` type |

---

## Constraints

- Android 7 / small screens: no new RenderFlex overflow — all new rows use `Flexible`/`FittedBox`
- Currency formatting: existing `AppFormatters.rwf()` — no changes
- Expired auction guard: checked both in RPC (`end_date <= NOW()`) and UI (`isExpired`)
- Closed auction guard: UI hides bid button when `auction.isClosed`
- Suspended user: checked in Edge Function before RPC call (unchanged)
