// supabase/functions/send-auction-notification/index.ts
// Sends a bulk push notification to all clients in a region.
// Called by region admin or super admin.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const json = (d: unknown, s = 200) =>
    new Response(JSON.stringify(d), {
      status: s,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Verify caller is admin or super admin
    const authHeader = req.headers.get('Authorization')!;
    const {
      data: { user },
    } = await createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    }).auth.getUser();

    if (!user) return json({ success: false, error: 'Not authenticated' }, 401);

    const { data: isAdmin } = await supabase
      .from('region_admins')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();
    const { data: isSuper } = await supabase
      .from('super_admins')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();

    if (!isAdmin && !isSuper) {
      return json({ success: false, error: 'Admin only' }, 403);
    }

    const { title, body, target_region, auction_id } = await req.json();
    if (!title || !body || !target_region) {
      return json({ success: false, error: 'title, body, and target_region required' }, 400);
    }

    // Get all active clients in the region with a player ID
    const { data: clients } = await supabase
      .from('users')
      .select('id, onesignal_player_id')
      .eq('region', target_region)
      .eq('account_status', 'active')
      .not('onesignal_player_id', 'is', null);

    if (!clients?.length) return json({ success: true, recipients: 0 });

    const playerIds = clients.map((c: any) => c.onesignal_player_id).filter(Boolean);

    // OneSignal allows max 2000 player IDs per request — batch if needed
    const BATCH = 2000;
    for (let i = 0; i < playerIds.length; i += BATCH) {
      const chunk = playerIds.slice(i, i + BATCH);
      await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: {
          Authorization: `Basic ${Deno.env.get('ONESIGNAL_REST_API_KEY')}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          app_id: Deno.env.get('ONESIGNAL_APP_ID'),
          include_player_ids: chunk,
          headings: { en: title },
          contents: { en: body },
          data: { type: 'new_auction', auction_id: auction_id ?? '' },
        }),
      });
    }

    // Save notification to each client's notifications table
    const notifRows = clients.map((c: any) => ({
      user_uid: c.id,
      title,
      body,
      type: 'new_auction',
      auction_id: auction_id ?? null,
    }));

    // Insert in batches of 500
    for (let i = 0; i < notifRows.length; i += 500) {
      await supabase.from('notifications').insert(notifRows.slice(i, i + 500));
    }

    return json({ success: true, recipients: playerIds.length });
  } catch (e) {
    return json({ success: false, error: String(e) }, 500);
  }
});
