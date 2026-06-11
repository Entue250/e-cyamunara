# Bidding Fix & Bid Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix bid validation so any bid ≥ starting price is accepted, and add bid-update so each client has one updatable bid per auction.

**Architecture:** Single SQL migration rewrites `accept_bid()` RPC to upsert bids and recalculate the winner from MAX across all bids. The Edge Function and Flutter layers consume two new return flags (`is_winning`, `is_update`). A `UNIQUE(auction_id, bidder_uid)` constraint enforces one row per client per auction.

**Tech Stack:** PostgreSQL (Supabase), Deno Edge Functions (TypeScript), Flutter 3 + Riverpod

---

## File Map

| File | Action |
|------|--------|
| `supabase/migrations/20260512000000_bidding_fix.sql` | CREATE — dedup + schema + RPC rewrite |
| `supabase/functions/place-bid/index.ts` | MODIFY — remove bad guard, new notification logic |
| `lib/data/models/models.dart` | MODIFY — `BidModel.updatedAt` |
| `lib/data/repositories/repositories.dart` | MODIFY — `getClientBidForAuction` |
| `lib/presentation/providers/providers.dart` | MODIFY — `BidNotifier` exposes `isUpdate`/`isWinning` |
| `lib/presentation/screens/client/client_providers.dart` | MODIFY — `clientBidForAuctionProvider` |
| `lib/presentation/screens/client/auction_detail_screen.dart` | MODIFY — bid dialog overhaul |
| `lib/presentation/screens/client/bid_confirmation_screen.dart` | MODIFY — update vs place states |
| `lib/presentation/screens/client/client_shared.dart` | MODIFY — `BidTile` update button + `bid_placed` type |

---

### Task 1: SQL Migration

**Files:**
- Create: `supabase/migrations/20260512000000_bidding_fix.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- =============================================================================
-- E-CYAMUNARA — Bidding Fix
-- File: supabase/migrations/20260512000000_bidding_fix.sql
--
-- Changes:
--   1. Add updated_at to bids
--   2. Deduplicate existing (auction_id, bidder_uid) pairs
--   3. Replace partial unique index with full UNIQUE constraint
--   4. Rewrite accept_bid() — removes BID_TOO_LOW, adds upsert + winner recalc
--
-- Safe to re-run: idempotent DDL + CREATE OR REPLACE function.
-- =============================================================================

-- 1. Add updated_at ───────────────────────────────────────────────────────────
ALTER TABLE public.bids
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 2. Deduplicate ──────────────────────────────────────────────────────────────
-- Keep the row with the highest bid_amount per (auction_id, bidder_uid).
-- On a tie, keep the most recently created row.
-- Must run BEFORE adding the unique constraint.
DELETE FROM public.bids
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY auction_id, bidder_uid
             ORDER BY bid_amount DESC, created_at DESC
           ) AS rn
    FROM public.bids
  ) ranked
  WHERE rn > 1
);

-- 3. Replace partial unique index with a full unique constraint ────────────────
DROP INDEX IF EXISTS public.idx_bids_one_winner_per_auction;

ALTER TABLE public.bids
  DROP CONSTRAINT IF EXISTS bids_auction_id_bidder_uid_key;
ALTER TABLE public.bids
  ADD CONSTRAINT bids_auction_id_bidder_uid_key
  UNIQUE (auction_id, bidder_uid);

-- 4. Rewrite accept_bid() ─────────────────────────────────────────────────────
-- Concurrency model: SELECT ... FOR UPDATE on both the auction row and the
-- existing bid row (if any). All mutations commit in one transaction.
--
-- Validation: bid_amount >= starting_price  (BID_TOO_LOW removed)
-- Upsert:     UPDATE if user already has a bid; INSERT otherwise
-- Counter:    total_bids / total_bids_placed only incremented on first bid
-- Winner:     recalculated from MAX(bid_amount) after upsert

CREATE OR REPLACE FUNCTION accept_bid(
  p_auction_id      UUID,
  p_bidder_uid      UUID,
  p_bid_amount      NUMERIC,
  p_bidder_name     TEXT,
  p_bidder_phone    TEXT,
  p_bidder_district TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auction         RECORD;
  v_existing_bid_id UUID;
  v_is_update       BOOLEAN := FALSE;
  v_new_winner_uid  UUID;
  v_new_winner_name TEXT;
  v_new_highest     NUMERIC;
  v_prev_winner     UUID;
BEGIN
  -- Acquire exclusive row lock on the auction ─────────────────────────────────
  SELECT * INTO v_auction
  FROM public.auctions
  WHERE id = p_auction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Auction not found', 'code', 'NOT_FOUND'
    );
  END IF;

  IF v_auction.auction_status <> 'active' THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Auction is not active', 'code', 'NOT_ACTIVE'
    );
  END IF;

  IF v_auction.end_date <= NOW() THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Auction has ended', 'code', 'ENDED'
    );
  END IF;

  -- Bid must be at least the starting price ────────────────────────────────────
  -- NOTE: BID_TOO_LOW (bid > current_highest) intentionally removed.
  -- Any bid >= starting_price is valid regardless of other bids.
  IF p_bid_amount < v_auction.starting_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   format('Bid must be at least %s RWF', v_auction.starting_price::text),
      'code',    'BELOW_START'
    );
  END IF;

  v_prev_winner := v_auction.current_winner_uid;

  -- Check for existing bid from this bidder and lock it ────────────────────────
  SELECT id INTO v_existing_bid_id
  FROM public.bids
  WHERE auction_id = p_auction_id
    AND bidder_uid = p_bidder_uid
  FOR UPDATE;

  IF FOUND THEN
    -- Update existing bid in place
    v_is_update := TRUE;
    UPDATE public.bids
    SET bid_amount      = p_bid_amount,
        bidder_name     = p_bidder_name,
        bidder_phone    = p_bidder_phone,
        bidder_district = p_bidder_district,
        bid_status      = 'outbid',
        updated_at      = NOW()
    WHERE id = v_existing_bid_id;
  ELSE
    -- Insert first bid from this bidder
    v_is_update := FALSE;
    INSERT INTO public.bids (
      auction_id, bidder_uid, bidder_name, bidder_phone,
      bidder_district, bid_amount, bid_status
    )
    VALUES (
      p_auction_id, p_bidder_uid, p_bidder_name, p_bidder_phone,
      p_bidder_district, p_bid_amount, 'outbid'
    );
  END IF;

  -- Recalculate winner from all bids (after upsert) ────────────────────────────
  SELECT bidder_uid, bidder_name, bid_amount
  INTO v_new_winner_uid, v_new_winner_name, v_new_highest
  FROM public.bids
  WHERE auction_id = p_auction_id
  ORDER BY bid_amount DESC, updated_at DESC
  LIMIT 1;

  -- Bulk-update all bid statuses for this auction
  UPDATE public.bids
  SET bid_status = CASE
    WHEN bidder_uid = v_new_winner_uid THEN 'winning'
    ELSE 'outbid'
  END
  WHERE auction_id = p_auction_id;

  -- Update the auction (combined with counter increment on first bid) ───────────
  IF v_is_update THEN
    UPDATE public.auctions
    SET current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        updated_at          = NOW()
    WHERE id = p_auction_id;
  ELSE
    UPDATE public.auctions
    SET total_bids          = total_bids + 1,
        current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        updated_at          = NOW()
    WHERE id = p_auction_id;

    UPDATE public.users
    SET total_bids_placed = total_bids_placed + 1
    WHERE id = p_bidder_uid;
  END IF;

  RETURN jsonb_build_object(
    'success',         true,
    'new_highest_bid', v_new_highest,
    'is_winning',      (v_new_winner_uid = p_bidder_uid),
    'is_update',       v_is_update,
    'prev_winner_uid', v_prev_winner,
    'item_name',       v_auction.item_name,
    'admin_uid',       v_auction.posted_by_admin_uid
  );

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'accept_bid error: % %', SQLERRM, SQLSTATE;
    RETURN jsonb_build_object(
      'success', false,
      'error',   'An unexpected database error occurred',
      'code',    'DB_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

-- Access control (service_role only — same as before)
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO service_role;

-- =============================================================================
-- Verification queries (run manually after applying)
-- =============================================================================
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'bids' AND column_name = 'updated_at';
-- SELECT constraint_name FROM information_schema.table_constraints
--   WHERE table_name = 'bids' AND constraint_type = 'UNIQUE';
-- SELECT routine_name, security_type FROM information_schema.routines
--   WHERE routine_name = 'accept_bid';
```

- [ ] **Step 2: Verify the file exists**

```powershell
Test-Path "supabase/migrations/20260512000000_bidding_fix.sql"
# Expected: True
```

---

### Task 2: Edge Function — place-bid

**Files:**
- Modify: `supabase/functions/place-bid/index.ts`

- [ ] **Step 1: Replace index.ts with updated version**

Full replacement — remove the `current_highest_bid` pre-check, update `result` type, update `deliverNotifications` signature and logic:

```typescript
// supabase/functions/place-bid/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // 1. Parse + validate inputs
    const body = await req.json();
    const { auction_id, bid_amount, bidder_uid } = body;

    if (!auction_id || bid_amount == null || !bidder_uid) {
      return json({ success: false, error: 'Missing required fields' }, 400);
    }
    if (typeof bid_amount !== 'number' || !isFinite(bid_amount) || bid_amount <= 0) {
      return json({ success: false, error: 'bid_amount must be a positive finite number' }, 400);
    }

    // 2. Service-role client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // 3. Verify caller JWT
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ success: false, error: 'Not authenticated' }, 401);
    }
    const {
      data: { user },
      error: authError,
    } = await createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    ).auth.getUser();

    if (authError || !user) {
      return json({ success: false, error: 'Not authenticated' }, 401);
    }
    if (user.id !== bidder_uid) {
      return json({ success: false, error: 'Bidder UID mismatch' }, 403);
    }

    // 4. Fetch bidder (suspension check + notification context)
    const { data: bidder } = await supabase
      .from('users')
      .select('id, account_status, full_names, phone_number, district, onesignal_player_id')
      .eq('id', bidder_uid)
      .single();

    if (!bidder) {
      return json({ success: false, error: 'Bidder not found' }, 404);
    }
    if (bidder.account_status !== 'active') {
      return json({ success: false, error: 'Your account is suspended' }, 403);
    }

    // 5. Fast-reject pre-check (non-locking — auction existence + status only)
    // NOTE: current_highest_bid check intentionally removed. The RPC validates
    // bid >= starting_price; any valid amount is accepted regardless of other bids.
    const { data: auction } = await supabase
      .from('auctions')
      .select('id, auction_status, end_date, item_name, posted_by_admin_uid')
      .eq('id', auction_id)
      .single();

    if (!auction) {
      return json({ success: false, error: 'Auction not found' }, 404);
    }
    if (auction.auction_status !== 'active') {
      return json({ success: false, error: 'Auction is not active' }, 400);
    }
    if (new Date(auction.end_date) <= new Date()) {
      return json({ success: false, error: 'Auction has ended' }, 400);
    }

    // 6. Atomic bid commit via RPC
    const { data: rpcResult, error: rpcError } = await supabase.rpc('accept_bid', {
      p_auction_id:      auction_id,
      p_bidder_uid:      bidder_uid,
      p_bid_amount:      bid_amount,
      p_bidder_name:     bidder.full_names,
      p_bidder_phone:    bidder.phone_number,
      p_bidder_district: bidder.district,
    });

    if (rpcError) {
      console.error(
        JSON.stringify({ event: 'rpc_error', auction_id, bidder_uid, error: rpcError.message }),
      );
      return json({ success: false, error: 'Database error during bid placement' }, 500);
    }

    const result = rpcResult as {
      success: boolean;
      error?: string;
      code?: string;
      new_highest_bid?: number;
      is_winning?: boolean;
      is_update?: boolean;
      prev_winner_uid?: string;
      item_name?: string;
      admin_uid?: string;
    };

    if (!result.success) {
      const status =
        result.code === 'NOT_FOUND' ? 404
        : result.code === 'NOT_ACTIVE' || result.code === 'ENDED' || result.code === 'BELOW_START' ? 400
        : 500;

      return json({ success: false, error: result.error, code: result.code }, status);
    }

    // 7. Deliver notifications (non-blocking — failures never roll back the bid)
    const notifCtx: NotifCtx = {
      auctionId:       auction_id,
      bidderId:        bidder_uid,
      bidderName:      bidder.full_names,
      bidderPlayerId:  bidder.onesignal_player_id ?? null,
      prevWinnerUid:   result.prev_winner_uid ?? null,
      itemName:        result.item_name ?? auction.item_name,
      adminUid:        result.admin_uid ?? auction.posted_by_admin_uid,
      isWinning:       result.is_winning ?? false,
      isUpdate:        result.is_update ?? false,
      newHighestBid:   result.new_highest_bid ?? bid_amount,
    };

    await deliverNotifications(supabase, notifCtx).catch((err) => {
      console.error(
        JSON.stringify({
          event: 'notification_failure',
          auction_id,
          bidder_uid,
          error: String(err),
        }),
      );
    });

    return json({
      success:         true,
      new_highest_bid: result.new_highest_bid,
      is_winning:      result.is_winning,
      is_update:       result.is_update,
    });
  } catch (err) {
    console.error(JSON.stringify({ event: 'place_bid_unhandled', error: String(err) }));
    return json({ success: false, error: 'An unexpected error occurred' }, 500);
  }
});

// ── Notification delivery ─────────────────────────────────────────────────────

interface NotifCtx {
  auctionId:      string;
  bidderId:       string;
  bidderName:     string;
  bidderPlayerId: string | null;
  prevWinnerUid:  string | null;
  itemName:       string;
  adminUid:       string;
  isWinning:      boolean;
  isUpdate:       boolean;
  newHighestBid:  number;
}

async function deliverNotifications(
  supabase: ReturnType<typeof createClient>,
  ctx: NotifCtx,
) {
  const {
    auctionId, bidderId, bidderName, bidderPlayerId,
    prevWinnerUid, itemName, adminUid,
    isWinning, isUpdate, newHighestBid,
  } = ctx;

  const oneSignalAppId  = Deno.env.get('ONESIGNAL_APP_ID')!;
  const oneSignalApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!;

  // In-app notification for the bidder
  const bidderNotif = isWinning
    ? {
        user_uid:   bidderId,
        title:      isUpdate ? "You're still winning! 🏆" : "You're winning! 🏆",
        body:       `You are the highest bidder on "${itemName}"`,
        type:       'winning',
        auction_id: auctionId,
      }
    : {
        user_uid:   bidderId,
        title:      isUpdate ? 'Bid updated' : 'Bid placed',
        body:       `Your bid on "${itemName}" is registered but not the highest yet`,
        type:       'bid_placed',
        auction_id: auctionId,
      };

  const notifInserts: Array<{
    user_uid: string; title: string; body: string; type: string; auction_id: string;
  }> = [bidderNotif];

  // Outbid notification for the previous winner (only when winner changed)
  const winnerChanged = isWinning && prevWinnerUid && prevWinnerUid !== bidderId;
  if (winnerChanged) {
    notifInserts.push({
      user_uid:   prevWinnerUid!,
      title:      'You have been outbid!',
      body:       `Someone placed a higher bid on "${itemName}"`,
      type:       'outbid',
      auction_id: auctionId,
    });
  }

  await supabase.from('notifications').insert(notifInserts);

  // Push: bidder
  if (bidderPlayerId) {
    await sendPush(
      oneSignalAppId, oneSignalApiKey,
      [bidderPlayerId],
      bidderNotif.title,
      bidderNotif.body,
      { type: bidderNotif.type, auction_id: auctionId },
    );
  }

  // Push: outbid notification to previous winner
  if (winnerChanged) {
    const { data: prevWinner } = await supabase
      .from('users')
      .select('onesignal_player_id')
      .eq('id', prevWinnerUid!)
      .single();
    if (prevWinner?.onesignal_player_id) {
      await sendPush(
        oneSignalAppId, oneSignalApiKey,
        [prevWinner.onesignal_player_id],
        'You have been outbid!',
        `Someone bid higher on "${itemName}"`,
        { type: 'outbid', auction_id: auctionId },
      );
    }
  }

  // Push: admin notification
  const { data: admin } = await supabase
    .from('region_admins')
    .select('onesignal_player_id')
    .eq('id', adminUid)
    .single();
  if (admin?.onesignal_player_id) {
    await sendPush(
      oneSignalAppId, oneSignalApiKey,
      [admin.onesignal_player_id],
      isUpdate ? 'Bid updated' : 'New bid placed',
      `${bidderName} ${isUpdate ? 'updated their bid' : 'placed a bid'} on "${itemName}"`,
      { type: 'system', auction_id: auctionId },
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function sendPush(
  appId: string, apiKey: string,
  playerIds: string[], title: string, body: string,
  data: Record<string, string>,
) {
  const validIds = playerIds.filter(Boolean);
  if (!validIds.length || !appId || !apiKey) return;

  await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      app_id:             appId,
      include_player_ids: validIds,
      headings:           { en: title },
      contents:           { en: body },
      data,
    }),
  });
}
```

---

### Task 3: BidModel — add updatedAt

**Files:**
- Modify: `lib/data/models/models.dart` (BidModel section, lines 373–427)

- [ ] **Step 1: Add `updatedAt` field to BidModel**

Replace the entire `BidModel` class with:

```dart
class BidModel {
  final String bidId;
  final String auctionId;
  final String bidderUid;
  final String bidderName;
  final String bidderPhone;
  final String bidderDistrict;
  final double bidAmount;
  final String bidStatus;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const BidModel({
    required this.bidId,
    required this.auctionId,
    required this.bidderUid,
    required this.bidderName,
    required this.bidderPhone,
    required this.bidderDistrict,
    required this.bidAmount,
    required this.bidStatus,
    required this.createdAt,
    this.updatedAt,
  });

  factory BidModel.fromMap(Map<String, dynamic> map) => BidModel(
    bidId:           map['id'] as String? ?? '',
    auctionId:       map['auction_id'] as String? ?? '',
    bidderUid:       map['bidder_uid'] as String? ?? '',
    bidderName:      map['bidder_name'] as String? ?? '',
    bidderPhone:     map['bidder_phone'] as String? ?? '',
    bidderDistrict:  map['bidder_district'] as String? ?? '',
    bidAmount:       (map['bid_amount'] as num?)?.toDouble() ?? 0,
    bidStatus:       map['bid_status'] as String? ?? 'outbid',
    createdAt:       DateTime.parse(
      map['created_at'] as String? ?? DateTime.now().toIso8601String(),
    ),
    updatedAt: map['updated_at'] != null
        ? DateTime.parse(map['updated_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'auction_id':       auctionId,
    'bidder_uid':       bidderUid,
    'bidder_name':      bidderName,
    'bidder_phone':     bidderPhone,
    'bidder_district':  bidderDistrict,
    'bid_amount':       bidAmount,
    'bid_status':       bidStatus,
  };

  bool get isWinning => bidStatus == 'winning';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is BidModel && other.bidId == bidId);
  @override
  int get hashCode => bidId.hashCode;
}
```

---

### Task 4: BidRepository — add getClientBidForAuction

**Files:**
- Modify: `lib/data/repositories/repositories.dart` (BidRepository, after line 130)

- [ ] **Step 1: Add method after `getClientBids`**

Insert after the `getClientBids` method (after line 130):

```dart
  // ── GET SINGLE BID BY CLIENT FOR AUCTION ─────────────────────────────────
  Future<BidModel?> getClientBidForAuction(
    String auctionId,
    String clientUid,
  ) async {
    try {
      final row = await _client
          .from(SupabaseConstants.bidsTable)
          .select()
          .eq('auction_id', auctionId)
          .eq('bidder_uid', clientUid)
          .maybeSingle();
      if (row == null) return null;
      return BidModel.fromMap(row);
    } on PostgrestException catch (e) {
      throw mapPostgrestError(e);
    }
  }
```

---

### Task 5: Providers — clientBidForAuctionProvider + BidNotifier

**Files:**
- Modify: `lib/presentation/screens/client/client_providers.dart`
- Modify: `lib/presentation/providers/providers.dart`

- [ ] **Step 1: Add `clientBidForAuctionProvider` to client_providers.dart**

Add at the end of `client_providers.dart` (after `myBidsFilterProvider`):

```dart
import '../../../data/repositories/repositories.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Existing bid for the current client on a specific auction.
// Returns null when the client has not yet placed a bid.
// ─────────────────────────────────────────────────────────────────────────────

final clientBidForAuctionProvider = FutureProvider.autoDispose
    .family<BidModel?, ({String auctionId, String clientUid})>(
  (ref, params) async {
    if (params.auctionId.isEmpty || params.clientUid.isEmpty) return null;
    final repo = ref.watch(bidRepositoryProvider);
    return repo.getClientBidForAuction(params.auctionId, params.clientUid);
  },
);
```

- [ ] **Step 2: Update `BidNotifier` in providers.dart**

Replace the `BidNotifier` class with:

```dart
class BidNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  BidNotifier(this._repo) : super(const AsyncData(null));
  final BidRepository _repo;

  bool get isUpdate => state.value?['is_update'] == true;
  bool get isWinning => state.value?['is_winning'] == true;

  /// Returns null on success, Failure on error.
  Future<Failure?> placeBid({
    required String auctionId,
    required double bidAmount,
    required String bidderUid,
  }) async {
    state = const AsyncLoading();
    try {
      final result = await _repo.placeBid(
        auctionId:  auctionId,
        bidAmount:  bidAmount,
        bidderUid:  bidderUid,
      );
      state = AsyncData(result);
      return null;
    } catch (e, st) {
      state = AsyncError(e, st);
      return UnknownFailure(e.toString());
    }
  }
}
```

---

### Task 6: auction_detail_screen.dart — bid dialog overhaul

**Files:**
- Modify: `lib/presentation/screens/client/auction_detail_screen.dart`

- [ ] **Step 1: Add import for client_providers**

Add to imports at the top of the file (after existing imports):

```dart
import 'client_providers.dart';
```

- [ ] **Step 2: Update `_showBidDialog` to fetch existing bid**

Replace the `_showBidDialog` method:

```dart
  void _showBidDialog(AuctionModel auction, double currentHighest) {
    final userState = ref.read(currentUserProvider);
    if (userState.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading your account, please wait...')),
      );
      return;
    }
    final user = userState.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to place a bid')),
      );
      return;
    }

    final existingBidAsync = ref.read(
      clientBidForAuctionProvider(
        (auctionId: auction.auctionId, clientUid: user.uid),
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BidBottomSheet(
        auction:      auction,
        bidderUid:    user.uid,
        currentHighest: currentHighest,
        existingBid:  existingBidAsync.value,
      ),
    );
  }
```

- [ ] **Step 3: Update the PLACE YOUR BID button label**

Find the button that shows `'PLACE YOUR BID'` and replace it so it shows
"UPDATE BID" when the client already has a bid:

```dart
                      if (!isExpired && auction.auctionStatus == 'active') ...[
                        Consumer(
                          builder: (context, ref, _) {
                            final user = ref.watch(currentUserProvider).value;
                            final existingBid = user == null
                                ? null
                                : ref
                                    .watch(clientBidForAuctionProvider((
                                      auctionId: auction.auctionId,
                                      clientUid: user.uid,
                                    )))
                                    .value;
                            final hasExisting = existingBid != null;
                            return SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _showBidDialog(auction, currentBid),
                                icon: Icon(hasExisting
                                    ? Icons.edit_outlined
                                    : Icons.gavel),
                                label: Text(
                                  hasExisting
                                      ? 'UPDATE YOUR BID'
                                      : 'PLACE YOUR BID',
                                  style: AppTextStyles.button,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
```

- [ ] **Step 4: Remove old static bid button**

Remove the old:
```dart
                      if (!isExpired)
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _showBidDialog(auction, currentBid),
                            icon: const Icon(Icons.gavel),
                            label: const Text('PLACE YOUR BID',
                                style: AppTextStyles.button),
                          ),
                        ),
```

- [ ] **Step 5: Rewrite `_BidBottomSheet` and `_BidBottomSheetState`**

Replace both classes with:

```dart
class _BidBottomSheet extends ConsumerStatefulWidget {
  const _BidBottomSheet({
    required this.auction,
    required this.bidderUid,
    required this.currentHighest,
    this.existingBid,
  });
  final AuctionModel auction;
  final String bidderUid;
  final double currentHighest;
  final BidModel? existingBid;

  @override
  ConsumerState<_BidBottomSheet> createState() => _BidBottomSheetState();
}

class _BidBottomSheetState extends ConsumerState<_BidBottomSheet> {
  final _bidController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.existingBid != null) {
      _bidController.text =
          widget.existingBid!.bidAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  void _validate(String text) {
    final amount = AppValidators.parseAmount(text);
    setState(() {
      if (amount == null) {
        _validationError = 'Enter a valid amount';
      } else if (amount < widget.auction.startingPrice) {
        _validationError =
            'Must be at least ${AppFormatters.rwf(widget.auction.startingPrice)}';
      } else {
        _validationError = null;
      }
    });
  }

  Future<void> _submit() async {
    final amount = AppValidators.parseAmount(_bidController.text);
    if (amount == null || amount < widget.auction.startingPrice) {
      setState(() => _validationError =
          'Must be at least ${AppFormatters.rwf(widget.auction.startingPrice)}');
      return;
    }

    final failure = await ref.read(bidNotifierProvider.notifier).placeBid(
          auctionId:  widget.auction.auctionId,
          bidAmount:  amount,
          bidderUid:  widget.bidderUid,
        );

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      // Invalidate so the button label and pre-fill refresh
      ref.invalidate(
        clientBidForAuctionProvider((
          auctionId: widget.auction.auctionId,
          clientUid: widget.bidderUid,
        )),
      );
      Navigator.pop(context);
      context.go(AppRoutes.bidConfirmation, extra: widget.auction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bidState  = ref.watch(bidNotifierProvider);
    final isUpdate  = widget.existingBid != null;
    final minPrice  = widget.auction.startingPrice;

    return Container(
      padding: EdgeInsets.only(
        left:   24,
        right:  24,
        top:    24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft:  Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              isUpdate ? 'Update Your Bid' : 'Place Your Bid',
              style: AppTextStyles.h1,
            ),
          ),
          const SizedBox(height: 16),

          // ── Info rows ──────────────────────────────────────────────────────
          _InfoRow(
            label: 'Minimum Price',
            value: AppFormatters.rwf(minPrice),
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 6),
          _InfoRow(
            label: 'Current Highest Bid',
            value: AppFormatters.rwf(widget.currentHighest),
            color: AppColors.darkGold,
          ),
          if (isUpdate) ...[
            const SizedBox(height: 6),
            _InfoRow(
              label: 'Your Current Bid',
              value: AppFormatters.rwf(widget.existingBid!.bidAmount),
              color: AppColors.primaryBlue,
            ),
          ],

          const SizedBox(height: 16),

          TextField(
            controller: _bidController,
            keyboardType: TextInputType.number,
            onChanged: _validate,
            decoration: InputDecoration(
              labelText: 'Your Bid Amount (RWF)',
              prefixIcon: const Icon(Icons.monetization_on_outlined),
              errorText: _validationError,
              helperText:
                  'Min: ${AppFormatters.rwf(minPrice)}',
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: bidState.isLoading ? null : _submit,
              child: bidState.isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                  : Text(
                      isUpdate ? 'UPDATE BID' : 'PLACE BID',
                      style: AppTextStyles.button,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row helper ─────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      );
}
```

---

### Task 7: bid_confirmation_screen.dart — update flow

**Files:**
- Modify: `lib/presentation/screens/client/bid_confirmation_screen.dart`

- [ ] **Step 1: Replace full file**

```dart
// lib/presentation/screens/client/bid_confirmation_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../app_router.dart';

class BidConfirmationScreen extends ConsumerWidget {
  const BidConfirmationScreen({super.key, this.auction});
  final AuctionModel? auction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bidData   = ref.watch(bidNotifierProvider).value;
    final newBid    = (bidData?['new_highest_bid'] as num?)?.toDouble() ?? 0;
    final bidId     = bidData?['bid_id'] as String?;
    final isUpdate  = bidData?['is_update'] == true;
    final isWinning = bidData?['is_winning'] == true;

    final itemName  = auction?.itemName ?? 'Auction Item';
    final region    = auction?.region ?? '—';
    final category  = auction?.category.toUpperCase() ?? 'VEHICLE';
    final refLabel  = bidId != null && bidId.length >= 8
        ? 'RNP-${bidId.substring(0, 8).toUpperCase()}'
        : 'RNP-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch % 100000}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isUpdate ? 'Bid Updated' : 'Bid Placed'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go(AppRoutes.home),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // ── Success icon ─────────────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isWinning ? AppColors.success : AppColors.primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWinning ? Icons.emoji_events : Icons.check,
                color: Colors.white,
                size: 44,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              isUpdate ? 'Bid Updated!' : 'Bid Successfully Placed!',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryBlue,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            Text(
              isWinning
                  ? 'You are currently the highest bidder on this auction.'
                  : 'Your bid is registered. Keep watching — you can update it anytime.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),
            Container(height: 3, color: AppColors.gold),
            const SizedBox(height: 20),

            // ── Details card ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BID REFERENCE', style: AppTextStyles.label),
                          const SizedBox(height: 4),
                          Text(
                            refLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius:
                              BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 24, color: AppColors.border),

                  const Text('ITEM DETAILS', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Text(itemName, style: AppTextStyles.h2),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.map_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(region, style: AppTextStyles.bodySmall),
                    ],
                  ),

                  const Divider(height: 24, color: AppColors.border),

                  const Text('YOUR BID AMOUNT', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Text(
                    newBid > 0 ? AppFormatters.rwf(newBid) : 'RWF 0',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkGold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submitted On ${DateTime.now().toString().substring(0, 16)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Status badge ─────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: (isWinning ? AppColors.success : AppColors.primaryBlue)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: (isWinning
                                ? AppColors.success
                                : AppColors.primaryBlue)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text('CURRENT STATUS',
                            style: AppTextStyles.label),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isWinning
                                    ? AppColors.success
                                    : AppColors.primaryBlue,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isWinning
                                          ? Icons.stars
                                          : Icons.gavel_outlined,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isWinning
                                          ? 'CURRENTLY WINNING'
                                          : 'BID REGISTERED',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.go(AppRoutes.myBids),
                child: const Text('VIEW MY BIDS', style: AppTextStyles.button),
              ),
            ),

            const SizedBox(height: 12),

            GestureDetector(
              onTap: () => context.go(AppRoutes.home),
              child: const Text(
                'Back to Home',
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
```

---

### Task 8: client_shared.dart — BidTile update button + bid_placed notification

**Files:**
- Modify: `lib/presentation/screens/client/client_shared.dart`

- [ ] **Step 1: Add `bid_placed` entry to `_typeConfig` in `NotificationTile`**

Add after the `'system'` entry in `_typeConfig`:

```dart
    'bid_placed': (
      icon: Icons.gavel_outlined,
      color: AppColors.primaryBlue,
      bg: Color(0xFFE3F2FD),
    ),
```

- [ ] **Step 2: Add "Update Bid" button to `BidTile`**

In `BidTile.build`, in the bottom row of the tile (the Row with "View Details"), add an "Update Bid" button before "View Details" when the auction is active:

Replace the bottom `Row` (which currently has time-ago and "View Details") with:

```dart
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.access_time_outlined,
                                size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              DateHelper.timeAgo(bid.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (auction != null &&
                                auction!.auctionStatus == 'active' &&
                                !auction!.isExpired)
                              TextButton(
                                onPressed: () =>
                                    context.go('/auction/${bid.auctionId}'),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                ),
                                child: const Text(
                                  'Update Bid',
                                  style: TextStyle(
                                    color: AppColors.darkGold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (auction != null &&
                                auction!.auctionStatus == 'active' &&
                                !auction!.isExpired)
                              const SizedBox(width: 8),
                            TextButton(
                              onPressed: () =>
                                  context.go('/auction/${bid.auctionId}'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                              ),
                              child: const Text(
                                'View Details',
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
```

---

### Task 9: flutter analyze + fix

**Files:** All modified files

- [ ] **Step 1: Run flutter analyze**

```powershell
cd "D:\LEVEL 3\Semester II\MOBILE APPLICATION\ecyamunara"
flutter analyze
```

- [ ] **Step 2: Fix any issues reported**

Common issues to watch for:
- Missing `const` on constructors
- Unused imports
- Dead code after refactor
- `withOpacity` → `withValues(alpha:)` if flagged

- [ ] **Step 3: Confirm zero errors**

```powershell
flutter analyze
# Expected: No issues found!
```

---

## Self-Review Checklist

- [x] Task 1 covers: dedup, `updated_at`, UNIQUE constraint, `accept_bid` rewrite — all spec requirements
- [x] Task 2 covers: remove bad pre-check, `is_winning`/`is_update` notifications, `bid_placed` type
- [x] Task 3 covers: `BidModel.updatedAt` field
- [x] Task 4 covers: `getClientBidForAuction` method
- [x] Task 5 covers: `clientBidForAuctionProvider`, `BidNotifier.isUpdate`/`isWinning`
- [x] Task 6 covers: updated dialog — min price, pre-fill, validation fix, "Update" label, invalidate on success
- [x] Task 7 covers: confirmation screen — update vs place heading, winning vs registered badge
- [x] Task 8 covers: `bid_placed` notification type, "Update Bid" button in BidTile
- [x] Task 9 covers: `flutter analyze` + fix cycle
- [x] Test cases: Case 1 (A=9M, B=7M, both accepted) handled by RPC validation change; Case 2 (update to highest) handled by upsert + recalc; Case 3 (bid reduction + winner recalc) handled by MAX recalculation; Case 4 (below min) handled by BELOW_START guard; Case 5 (expired) handled by ENDED guard
- [x] No TBD, TODO, or placeholder steps found
- [x] Type names consistent: `BidModel.updatedAt`, `clientBidForAuctionProvider`, `BidNotifier.isUpdate`, `BidNotifier.isWinning` — all match across tasks
