// supabase/functions/get-user-stats/index.ts
// Returns aggregated stats based on the caller's role.
// Client → own bid/win stats
// Region Admin → region auction stats
// Super Admin → national stats across all regions

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

    // Verify caller
    const authHeader = req.headers.get('Authorization')!;
    const {
      data: { user },
    } = await createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    }).auth.getUser();

    if (!user) return json({ error: 'Not authenticated' }, 401);

    // Determine role
    const { data: clientRow } = await supabase
      .from('users')
      .select('*')
      .eq('id', user.id)
      .maybeSingle();
    const { data: adminRow } = await supabase
      .from('region_admins')
      .select('*')
      .eq('id', user.id)
      .maybeSingle();
    const { data: superRow } = await supabase
      .from('super_admins')
      .select('id')
      .eq('id', user.id)
      .maybeSingle();

    // ── CLIENT STATS ─────────────────────────────────────────────────────────
    if (clientRow) {
      const { data: activeBids } = await supabase
        .from('bids')
        .select('id')
        .eq('bidder_uid', user.id)
        .eq('bid_status', 'winning');

      return json({
        role: 'client',
        total_bids: clientRow.total_bids_placed ?? 0,
        total_wins: clientRow.total_auctions_won ?? 0,
        active_bids: activeBids?.length ?? 0,
        region: clientRow.region,
      });
    }

    // ── REGION ADMIN STATS ────────────────────────────────────────────────────
    if (adminRow) {
      const { data: auctions } = await supabase
        .from('auctions')
        .select('auction_status, winning_amount')
        .eq('region', adminRow.region);

      const total = auctions?.length ?? 0;
      const active = auctions?.filter((a: any) => a.auction_status === 'active').length ?? 0;
      const closed = auctions?.filter((a: any) => a.auction_status === 'closed').length ?? 0;
      const revenue =
        auctions
          ?.filter((a: any) => a.auction_status === 'closed')
          .reduce((sum: number, a: any) => sum + (a.winning_amount ?? 0), 0) ?? 0;

      const { data: clientCount } = await supabase
        .from('users')
        .select('id', { count: 'exact', head: true })
        .eq('region', adminRow.region);

      return json({
        role: 'region_admin',
        region: adminRow.region,
        total_auctions: total,
        active_auctions: active,
        closed_auctions: closed,
        total_revenue: revenue,
        total_clients: clientCount ?? 0,
      });
    }

    // ── SUPER ADMIN STATS ─────────────────────────────────────────────────────
    if (superRow) {
      const { data: auctions } = await supabase
        .from('auctions')
        .select('region, auction_status, winning_amount');

      const { data: users } = await supabase
        .from('users')
        .select('id', { count: 'exact', head: true });

      const { data: admins } = await supabase
        .from('region_admins')
        .select('id', { count: 'exact', head: true });

      // Build by-region breakdown
      const byRegion: Record<string, any> = {};
      for (const a of auctions ?? []) {
        if (!byRegion[a.region]) {
          byRegion[a.region] = { total: 0, active: 0, closed: 0, revenue: 0 };
        }
        byRegion[a.region].total++;
        if (a.auction_status === 'active') byRegion[a.region].active++;
        if (a.auction_status === 'closed') {
          byRegion[a.region].closed++;
          byRegion[a.region].revenue += a.winning_amount ?? 0;
        }
      }

      return json({
        role: 'super_admin',
        total_auctions: auctions?.length ?? 0,
        total_clients: users ?? 0,
        total_admins: admins ?? 0,
        total_revenue:
          auctions
            ?.filter((a: any) => a.auction_status === 'closed')
            .reduce((s: number, a: any) => s + (a.winning_amount ?? 0), 0) ?? 0,
        by_region: byRegion,
      });
    }

    return json({ error: 'Unknown role' }, 403);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
