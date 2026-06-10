// supabase/functions/place-bid/index.ts
//
// Changes from previous version:
//   • Removed fast-reject current_highest_bid comparison (any bid >= starting_price is valid)
//   • Updated RPC result type: is_winning, is_update fields
//   • Updated deliverNotifications: tailored messages for place vs update, winning vs outbid
//   • New notification type 'bid_placed' for non-winning bids
//   • Response includes is_winning and is_update for the Flutter client

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
    // ── 1. Parse + validate inputs ──────────────────────────────────────────
    const body = await req.json();
    const { auction_id, bid_amount, bidder_uid } = body;

    if (!auction_id || bid_amount == null || !bidder_uid) {
      return json({ success: false, error: 'Missing required fields' }, 400);
    }
    if (typeof bid_amount !== 'number' || !isFinite(bid_amount) || bid_amount <= 0) {
      return json({ success: false, error: 'bid_amount must be a positive finite number' }, 400);
    }

    // ── 2. Service-role client ──────────────────────────────────────────────
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // ── 3. Verify caller JWT ────────────────────────────────────────────────
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

    // ── 4. Fetch bidder (suspension check + notification context) ────────────
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

    // ── 5. Fast-reject pre-check (non-locking — auction existence + status) ──
    // NOTE: current_highest_bid comparison intentionally removed.
    // The RPC validates bid >= starting_price; any valid amount is accepted
    // regardless of other bids. accept_bid() re-validates everything under lock.
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

    // ── 6. Atomic bid commit via RPC ────────────────────────────────────────
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
      success:          boolean;
      error?:           string;
      code?:            string;
      new_highest_bid?: number;
      is_winning?:      boolean;
      is_update?:       boolean;
      prev_winner_uid?: string;
      new_winner_uid?:  string;
      item_name?:       string;
      admin_uid?:       string;
    };

    if (!result.success) {
      const status =
        result.code === 'NOT_FOUND'  ? 404
        : result.code === 'NOT_ACTIVE' || result.code === 'ENDED' || result.code === 'BELOW_START'
          ? 400
          : 500;

      return json({ success: false, error: result.error, code: result.code }, status);
    }

    // ── 7. Deliver notifications (non-blocking — failures never roll back bid)
    const notifCtx: NotifCtx = {
      auctionId:      auction_id,
      bidderId:       bidder_uid,
      bidderName:     bidder.full_names,
      bidderPlayerId: bidder.onesignal_player_id ?? null,
      prevWinnerUid:  result.prev_winner_uid ?? null,
      newWinnerUid:   result.new_winner_uid ?? null,
      itemName:       result.item_name ?? auction.item_name,
      adminUid:       result.admin_uid ?? auction.posted_by_admin_uid,
      isWinning:      result.is_winning ?? false,
      isUpdate:       result.is_update ?? false,
      newHighestBid:  result.new_highest_bid ?? bid_amount,
    };

    await deliverNotifications(supabase, notifCtx).catch((err) => {
      console.error(
        JSON.stringify({
          event:      'notification_failure',
          auction_id,
          bidder_uid,
          error:      String(err),
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
// Runs after the bid transaction commits. Any throw is caught by .catch() in
// the main handler — bid response has already been sent.

interface NotifCtx {
  auctionId:      string;
  bidderId:       string;
  bidderName:     string;
  bidderPlayerId: string | null;
  prevWinnerUid:  string | null;
  newWinnerUid:   string | null;
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
    prevWinnerUid, newWinnerUid, itemName, adminUid,
    isWinning, isUpdate, newHighestBid,
  } = ctx;

  const oneSignalAppId  = Deno.env.get('ONESIGNAL_APP_ID')!;
  const oneSignalApiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!;

  // ── In-app notification for the bidder ─────────────────────────────────────
  const bidderNotif = isWinning
    ? {
        user_uid:   bidderId,
        title:      isUpdate ? "Still winning! 🏆" : "You're winning! 🏆",
        body:       `You are the highest bidder on "${itemName}"`,
        type:       'winning',
        auction_id: auctionId,
      }
    : {
        user_uid:   bidderId,
        title:      isUpdate ? 'Bid updated' : 'Bid placed',
        body:       `Your bid on "${itemName}" is registered. Keep an eye on it!`,
        type:       'bid_placed',
        auction_id: auctionId,
      };

  const notifInserts: Array<{
    user_uid: string; title: string; body: string; type: string; auction_id: string;
  }> = [bidderNotif];

  // ── Outbid notification — only when bidder's new bid overtook the previous winner ─
  // Case A: bidder placed/raised bid above prev winner → prev winner is now outbid
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

  // ── Winning notification — when bidder LOWERED their bid, a different user is now winning ─
  // Case B: bid reduction caused winner to change to a third party
  const reductionWinnerChanged =
    !isWinning &&
    newWinnerUid &&
    newWinnerUid !== bidderId &&
    newWinnerUid !== prevWinnerUid;
  if (reductionWinnerChanged) {
    notifInserts.push({
      user_uid:   newWinnerUid!,
      title:      "You're now winning! 🏆",
      body:       `You became the highest bidder on "${itemName}"`,
      type:       'winning',
      auction_id: auctionId,
    });
  }

  await supabase.from('notifications').insert(notifInserts);

  // ── Push: bidder ────────────────────────────────────────────────────────────
  if (bidderPlayerId) {
    await sendPush(
      oneSignalAppId, oneSignalApiKey,
      [bidderPlayerId],
      bidderNotif.title,
      bidderNotif.body,
      { type: bidderNotif.type, auction_id: auctionId },
    );
  }

  // ── Push: outbid notification to the previous winner (Case A) ──────────────
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

  // ── Push: winning notification to new winner after bid reduction (Case B) ──
  if (reductionWinnerChanged) {
    const { data: newWinner } = await supabase
      .from('users')
      .select('onesignal_player_id')
      .eq('id', newWinnerUid!)
      .single();
    if (newWinner?.onesignal_player_id) {
      await sendPush(
        oneSignalAppId, oneSignalApiKey,
        [newWinner.onesignal_player_id],
        "You're now winning! 🏆",
        `You became the highest bidder on "${itemName}"`,
        { type: 'winning', auction_id: auctionId },
      );
    }
  }

  // ── Push: region admin notification ────────────────────────────────────────
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
  appId:     string,
  apiKey:    string,
  playerIds: string[],
  title:     string,
  body:      string,
  data:      Record<string, string>,
) {
  const validIds = playerIds.filter(Boolean);
  if (!validIds.length || !appId || !apiKey) return;

  await fetch('https://onesignal.com/api/v1/notifications', {
    method:  'POST',
    headers: {
      Authorization:  `Basic ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      app_id:             appId,
      include_player_ids: validIds,
      headings:           { en: title },
      contents:           { en: body },
      data,
    }),
  });
}
