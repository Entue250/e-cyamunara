// supabase/functions/on-new-auction/index.ts
//
// Triggered automatically when a new auction row is inserted.
// Set this up as a Database Webhook:
//   Supabase Dashboard → Database → Webhooks → Create new webhook
//   Table: auctions  |  Events: INSERT  |  URL: .../functions/v1/on-new-auction
//
// What it does:
//   1. Checks if auction_status == 'active'
//   2. Sends push notification to all clients in the auction's region
//   3. Saves a notification record for each client

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // Supabase Database Webhooks send the new row in req.body as { record, old_record, type }
    const payload = await req.json();
    const auction = payload.record;

    if (!auction || auction.auction_status !== 'active') {
      return new Response('Skipped — not active', { status: 200 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const appId = Deno.env.get('ONESIGNAL_APP_ID')!;
    const apiKey = Deno.env.get('ONESIGNAL_REST_API_KEY')!;

    // Get all active clients in the same region
    const { data: clients } = await supabase
      .from('users')
      .select('id, onesignal_player_id')
      .eq('region', auction.region)
      .eq('account_status', 'active');

    if (!clients?.length) return new Response('No clients in region', { status: 200 });

    const playerIds = clients.map((c: any) => c.onesignal_player_id).filter(Boolean);

    const title = `New Auction: ${auction.item_name}`;
    const body = `A new ${auction.category} is available in ${auction.region} region`;

    // Send push notification
    if (playerIds.length > 0 && appId && apiKey) {
      const BATCH = 2000;
      for (let i = 0; i < playerIds.length; i += BATCH) {
        await fetch('https://onesignal.com/api/v1/notifications', {
          method: 'POST',
          headers: {
            Authorization: `Basic ${apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            app_id: appId,
            include_player_ids: playerIds.slice(i, i + BATCH),
            headings: { en: title },
            contents: { en: body },
            data: { type: 'new_auction', auction_id: auction.id },
          }),
        });
      }
    }

    // Save notification records
    const notifRows = clients.map((c: any) => ({
      user_uid: c.id,
      title,
      body,
      type: 'new_auction',
      auction_id: auction.id,
    }));

    for (let i = 0; i < notifRows.length; i += 500) {
      await supabase.from('notifications').insert(notifRows.slice(i, i + 500));
    }

    return new Response(JSON.stringify({ sent: playerIds.length }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('on-new-auction error:', e);
    return new Response(String(e), { status: 500 });
  }
});
