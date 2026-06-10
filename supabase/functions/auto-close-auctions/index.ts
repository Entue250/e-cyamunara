// supabase/functions/auto-close-auctions/index.ts
// Triggered by Supabase pg_cron (every 5 minutes)
// Set up in: Dashboard → Database → Extensions → enable pg_cron
// Then run: select cron.schedule('close-auctions', '*/5 * * * *',
//   $$select net.http_post(url:='https://YOUR_REF.supabase.co/functions/v1/auto-close-auctions',
//   headers:='{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
//   body:='{}'::jsonb)$$);
//
// SECURITY: This function is protected by the service role key.
// Only pg_cron (or an operator with the key) can trigger it.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  // ── AUTH GUARD: only accept calls from pg_cron via service role key ─────────
  // The cron sends:  Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
  // Any other caller (missing header, wrong key) receives 401 immediately.
  const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const incomingAuth = req.headers.get('Authorization') ?? '';
  if (!expectedKey || incomingAuth !== `Bearer ${expectedKey}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const now = new Date().toISOString();

  // Find all expired active auctions
  const { data: expired } = await supabase
    .from('auctions')
    .select('*')
    .eq('auction_status', 'active')
    .lte('end_date', now);

  if (!expired?.length) {
    return new Response(JSON.stringify({ closed: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const appId = Deno.env.get('ONESIGNAL_APP_ID')!;
  const apiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!;

  for (const auction of expired) {
    const closedAt = new Date().toISOString();
    const winnerUid = auction.current_winner_uid;
    const winnerName = auction.current_winner_name;
    const winningAmt = auction.current_highest_bid;

    // Update auction to closed
    await supabase
      .from('auctions')
      .update({
        auction_status: 'closed',
        winner_uid: winnerUid,
        winner_name: winnerName,
        winning_amount: winningAmt,
        closed_at: closedAt,
        updated_at: closedAt,
      })
      .eq('id', auction.id);

    // Increment winner's total
    if (winnerUid) {
      const { data: winner } = await supabase
        .from('users')
        .select('total_auctions_won, onesignal_player_id')
        .eq('id', winnerUid)
        .single();
      if (winner) {
        await supabase
          .from('users')
          .update({ total_auctions_won: winner.total_auctions_won + 1 })
          .eq('id', winnerUid);

        // Notify winner
        await supabase.from('notifications').insert({
          user_uid: winnerUid,
          auction_id: auction.id,
          title: '🎉 Congratulations! You won!',
          body: `You won the auction for "${auction.item_name}"`,
          type: 'won',
        });
        await sendPush(
          appId,
          apiKey,
          [winner.onesignal_player_id],
          '🎉 Congratulations! You won!',
          `You won the auction for "${auction.item_name}"`,
          { type: 'won', auction_id: auction.id },
        );
      }
    }

    // Notify all other bidders
    const { data: otherBids } = await supabase
      .from('bids')
      .select('bidder_uid')
      .eq('auction_id', auction.id)
      .eq('bid_status', 'outbid');
    const otherUids = [
      ...new Set(
        (otherBids || []).map((b: any) => b.bidder_uid).filter((uid: string) => uid !== winnerUid),
      ),
    ];

    for (const uid of otherUids) {
      const { data: u } = await supabase
        .from('users')
        .select('onesignal_player_id')
        .eq('id', uid)
        .single();
      await supabase.from('notifications').insert({
        user_uid: uid,
        auction_id: auction.id,
        title: 'Auction ended',
        body: `The auction for "${auction.item_name}" has ended`,
        type: 'system',
      });
      if (u?.onesignal_player_id) {
        await sendPush(
          appId,
          apiKey,
          [u.onesignal_player_id],
          'Auction ended',
          `"${auction.item_name}" has closed`,
          { type: 'system', auction_id: auction.id },
        );
      }
    }

    // Notify region admin
    const { data: admin } = await supabase
      .from('region_admins')
      .select('onesignal_player_id')
      .eq('id', auction.posted_by_admin_uid)
      .single();
    if (admin?.onesignal_player_id) {
      await sendPush(
        appId,
        apiKey,
        [admin.onesignal_player_id],
        'Auction auto-closed',
        `"${auction.item_name}" closed — Winner: ${winnerName || 'None'}`,
        { type: 'system', auction_id: auction.id },
      );
    }

    // Audit log
    await supabase.from('auction_auto_close_logs').insert({
      auction_id:  auction.id,
      closed_at:   closedAt,
      winner_uid:  winnerUid ?? null,
      final_price: winningAmt ?? null,
      status:      winnerUid ? 'winner_found' : 'no_bids',
    });
  }

  return new Response(JSON.stringify({ closed: expired.length }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});

async function sendPush(
  appId: string,
  apiKey: string,
  playerIds: string[],
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const valid = playerIds.filter(Boolean);
  if (!valid.length || !appId || !apiKey) return;
  await fetch('https://onesignal.com/api/v1/notifications', {
    method: 'POST',
    headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      app_id: appId,
      include_player_ids: valid,
      headings: { en: title },
      contents: { en: body },
      data,
    }),
  });
}
