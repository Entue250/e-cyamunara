// supabase/functions/cleanup-notifications/index.ts
// Deletes notifications older than 30 days.
//
// Schedule with pg_cron (run in SQL Editor):
//   select cron.schedule(
//     'cleanup-notifications',
//     '0 22 * * 0',   -- every Sunday at 22:00 UTC (midnight Kigali UTC+2)
//     $$
//       select net.http_post(
//         url := 'https://YOUR_REF.supabase.co/functions/v1/cleanup-notifications',
//         headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
//         body := '{}'::jsonb
//       )
//     $$
//   );

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (_req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const { count, error } = await supabase
      .from('notifications')
      .delete({ count: 'exact' })
      .lt('created_at', cutoff);

    if (error) throw error;

    console.log(`Deleted ${count} old notifications`);
    return new Response(JSON.stringify({ success: true, deleted: count }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ success: false, error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
