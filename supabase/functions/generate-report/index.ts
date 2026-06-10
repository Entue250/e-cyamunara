// supabase/functions/generate-report/index.ts
// Generates JSON or PDF auction reports for admins.
// PDF is uploaded to Supabase Storage and a signed URL is returned.

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

    // Verify admin
    const authHeader = req.headers.get('Authorization')!;
    const {
      data: { user },
    } = await createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    }).auth.getUser();
    if (!user) return json({ error: 'Not authenticated' }, 401);

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
    if (!isAdmin && !isSuper) return json({ error: 'Admin only' }, 403);

    const { region, start_date, end_date, format } = await req.json();
    if (!start_date || !end_date) return json({ error: 'start_date and end_date required' }, 400);

    const isAll = region === 'ALL';

    // Query auctions
    let query = supabase
      .from('auctions')
      .select('*')
      .gte('created_at', start_date)
      .lte('created_at', end_date);

    if (!isAll) query = query.eq('region', region);

    const { data: auctions } = await query;
    const all = auctions ?? [];

    const closed = all.filter((a: any) => a.auction_status === 'closed');
    const totalRevenue = closed.reduce((s: number, a: any) => s + (a.winning_amount ?? 0), 0);
    const avgWinning = closed.length ? Math.round(totalRevenue / closed.length) : 0;

    // Category breakdown
    const byCat: Record<string, number> = {};
    all.forEach((a: any) => {
      byCat[a.category] = (byCat[a.category] ?? 0) + 1;
    });

    const stats = {
      region: isAll ? 'All Regions' : region,
      period: { start: start_date, end: end_date },
      total_auctions: all.length,
      closed_auctions: closed.length,
      active_auctions: all.filter((a: any) => a.auction_status === 'active').length,
      total_revenue: totalRevenue,
      avg_winning_price: avgWinning,
      top_categories: byCat,
      generated_at: new Date().toISOString(),
    };

    if (format === 'json') return json(stats);

    // ── PDF generation ────────────────────────────────────────────────────────
    // We generate a simple HTML report and upload it as PDF-like text.
    // For a true PDF, integrate a service like gotenberg.dev (free self-hosted).
    // Here we generate a well-structured HTML that browsers can print to PDF.
    const html = buildHtmlReport(stats, all);
    const htmlBytes = new TextEncoder().encode(html);
    const fileName = `reports/${region}_${Date.now()}.html`;

    const { error: uploadError } = await supabase.storage
      .from('reports')
      .upload(fileName, htmlBytes, { contentType: 'text/html' });

    if (uploadError) throw uploadError;

    const { data: signed } = await supabase.storage
      .from('reports')
      .createSignedUrl(fileName, 60 * 60 * 24 * 7); // 7 days

    return json({ ...stats, download_url: signed?.signedUrl });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function buildHtmlReport(stats: any, auctions: any[]): string {
  const rows = auctions
    .slice(0, 100)
    .map(
      (a: any, i: number) => `
    <tr style="background:${i % 2 === 0 ? '#fff' : '#f5f7fa'}">
      <td>${i + 1}</td>
      <td>${a.item_name}</td>
      <td>${a.category}</td>
      <td>${a.region}</td>
      <td>${a.auction_status.toUpperCase()}</td>
      <td>RWF ${Number(a.starting_price).toLocaleString()}</td>
      <td>${a.winning_amount ? 'RWF ' + Number(a.winning_amount).toLocaleString() : '—'}</td>
    </tr>`,
    )
    .join('');

  return `<!DOCTYPE html>
<html><head><meta charset="UTF-8">
<title>E-CYAMUNARA Report — ${stats.region}</title>
<style>
  body { font-family: Arial, sans-serif; color: #333; margin: 40px; }
  h1   { color: #003087; } h2 { color: #003087; border-bottom: 2px solid #FFD700; }
  .stat-grid { display: grid; grid-template-columns: repeat(3,1fr); gap: 16px; margin: 24px 0; }
  .stat { background: #f5f7fa; border-radius: 8px; padding: 16px; text-align: center; }
  .stat .value { font-size: 28px; font-weight: bold; color: #003087; }
  .stat .label { font-size: 13px; color: #666; margin-top: 4px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th    { background: #003087; color: #fff; padding: 8px 12px; text-align: left; }
  td    { padding: 7px 12px; border-bottom: 1px solid #eee; }
  .footer { margin-top: 40px; font-size: 12px; color: #999; text-align: center; }
</style></head><body>
<h1>🏛️ E-CYAMUNARA — Auction Report</h1>
<p><strong>Region:</strong> ${stats.region} &nbsp;|&nbsp;
   <strong>Period:</strong> ${stats.period.start.substring(0, 10)} → ${stats.period.end.substring(0, 10)} &nbsp;|&nbsp;
   <strong>Generated:</strong> ${new Date(stats.generated_at).toLocaleString()}</p>

<h2>Summary</h2>
<div class="stat-grid">
  <div class="stat"><div class="value">${stats.total_auctions}</div><div class="label">Total Auctions</div></div>
  <div class="stat"><div class="value">${stats.closed_auctions}</div><div class="label">Closed Auctions</div></div>
  <div class="stat"><div class="value">${stats.active_auctions}</div><div class="label">Active Auctions</div></div>
  <div class="stat"><div class="value">RWF ${stats.total_revenue.toLocaleString()}</div><div class="label">Total Revenue</div></div>
  <div class="stat"><div class="value">RWF ${stats.avg_winning_price.toLocaleString()}</div><div class="label">Avg Winning Bid</div></div>
  <div class="stat"><div class="value">${Object.entries(stats.top_categories)
    .map(([k, v]) => `${k}: ${v}`)
    .join(', ')}</div><div class="label">By Category</div></div>
</div>

<h2>Auction Details</h2>
<table>
  <thead><tr><th>#</th><th>Item</th><th>Category</th><th>Region</th><th>Status</th><th>Starting Price</th><th>Winning Bid</th></tr></thead>
  <tbody>${rows}</tbody>
</table>
<div class="footer">Rwanda National Police — E-CYAMUNARA Auction Platform — Confidential</div>
</body></html>`;
}
