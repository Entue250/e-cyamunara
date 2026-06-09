// supabase/functions/close-auction-manually/index.ts
//
// Fixes applied:
//   • total_auctions_closed now reads from region_admins (was reading
//     auction.total_auctions_closed which does not exist — was writing undefined)
//   • Added account_status suspension check for the calling admin
//   • region_admins select now also fetches total_auctions_closed and account_status

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

    // Authenticate caller
    const authHeader = req.headers.get('Authorization')!;
    const { data: { user } } = await createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    ).auth.getUser();

    if (!user) return json({ success: false, error: 'Not authenticated' }, 401);

    // Fetch admin record (includes suspension status and stats counter)
    const { data: admin } = await supabase
      .from('region_admins')
      .select('region, account_status, total_auctions_closed')
      .eq('id', user.id)
      .maybeSingle();

    const { data: superAdmin } = await supabase
      .from('super_admins')
      .select('id, account_status')
      .eq('id', user.id)
      .maybeSingle();

    if (!admin && !superAdmin) {
      return json({ success: false, error: 'Admin access required' }, 403);
    }

    // Reject suspended callers
    if (admin && admin.account_status !== 'active') {
      return json({ success: false, error: 'Your account is suspended' }, 403);
    }
    if (superAdmin && superAdmin.account_status !== 'active') {
      return json({ success: false, error: 'Your account is suspended' }, 403);
    }

    const { auction_id } = await req.json();

    const { data: auction } = await supabase
      .from('auctions')
      .select('*')
      .eq('id', auction_id)
      .single();

    if (!auction) return json({ success: false, error: 'Auction not found' }, 404);

    // Region admins may only close auctions in their own region
    if (admin && auction.region !== admin.region) {
      return json({ success: false, error: 'Auction is in a different region' }, 403);
    }

    if (auction.auction_status !== 'active') {
      return json({ success: false, error: 'Auction is not active' }, 400);
    }

    const now = new Date().toISOString();

    // Close the auction and record the winner
    await supabase
      .from('auctions')
      .update({
        auction_status: 'closed',
        winner_uid: auction.current_winner_uid,
        winner_name: auction.current_winner_name,
        winning_amount: auction.current_highest_bid,
        closed_at: now,
        updated_at: now,
      })
      .eq('id', auction_id);

    // Increment the region admin's closed counter using the value fetched above
    if (admin) {
      await supabase
        .from('region_admins')
        .update({ total_auctions_closed: (admin.total_auctions_closed ?? 0) + 1 })
        .eq('id', user.id);
    }

    // Notify the winner
    if (auction.current_winner_uid) {
      await supabase.from('notifications').insert({
        user_uid: auction.current_winner_uid,
        auction_id,
        title: '🎉 You won!',
        body: `You won the auction for "${auction.item_name}" with a bid of ${auction.current_highest_bid} RWF`,
        type: 'won',
      });

      // Update winner's total_auctions_won stat
      const { data: winner } = await supabase
        .from('users')
        .select('total_auctions_won')
        .eq('id', auction.current_winner_uid)
        .single();

      if (winner) {
        await supabase
          .from('users')
          .update({ total_auctions_won: (winner.total_auctions_won ?? 0) + 1 })
          .eq('id', auction.current_winner_uid);
      }
    }

    return json({
      success: true,
      winner: {
        name: auction.current_winner_name,
        amount: auction.current_highest_bid,
      },
    });
  } catch (e) {
    return json({ success: false, error: String(e) }, 500);
  }
});
