// supabase/functions/activate-user/index.ts
//
// Fixes applied:
//   • Added authorization check (was completely missing)
//   • Supports both users and region_admins tables
//   • Region admins can only activate clients within their own region
//   • Super admins can activate clients and region admins
//   • Reads onesignal_player_id from the correct table

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

    // Verify and identify the caller
    const caller = await getCallerInfo(req, supabase);
    if (!caller || !['super_admin', 'region_admin'].includes(caller.role)) {
      return json({ success: false, error: 'Admin access required' }, 403);
    }

    const { uid } = await req.json();
    if (!uid) return json({ success: false, error: 'uid required' }, 400);

    // Determine which table the target belongs to
    const { data: superTarget } = await supabase
      .from('super_admins').select('id').eq('id', uid).maybeSingle();
    if (superTarget) {
      return json({ success: false, error: 'Super admin accounts cannot be managed through this function' }, 403);
    }

    const { data: adminTarget } = await supabase
      .from('region_admins').select('id, region, onesignal_player_id').eq('id', uid).maybeSingle();

    const { data: clientTarget } = await supabase
      .from('users').select('id, region, onesignal_player_id').eq('id', uid).maybeSingle();

    if (!adminTarget && !clientTarget) {
      return json({ success: false, error: 'User not found' }, 404);
    }

    // Region admins can only activate clients in their own region
    if (caller.role === 'region_admin') {
      if (adminTarget) {
        return json({ success: false, error: 'Region admins cannot activate other admins' }, 403);
      }
      if (clientTarget && clientTarget.region !== caller.region) {
        return json({ success: false, error: 'Cannot activate a client from a different region' }, 403);
      }
    }

    // Lift the Supabase Auth ban
    await supabase.auth.admin.updateUserById(uid, { ban_duration: 'none' });

    // Update the correct role table
    const table = adminTarget ? 'region_admins' : 'users';
    await supabase
      .from(table)
      .update({ account_status: 'active', updated_at: new Date().toISOString() })
      .eq('id', uid);

    // In-app notification
    await supabase.from('notifications').insert({
      user_uid: uid,
      title: 'Account Reactivated',
      body: 'Your E-CYAMUNARA account is now active again. Welcome back!',
      type: 'system',
    });

    // Push notification — read player ID from whichever table the user is in
    const playerIdSource = adminTarget ?? clientTarget;
    const playerId = playerIdSource?.onesignal_player_id;
    const appId = Deno.env.get('ONESIGNAL_APP_ID');
    const apiKey = Deno.env.get('ONESIGNAL_REST_API_KEY');

    if (playerId && appId && apiKey) {
      await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          app_id: appId,
          include_player_ids: [playerId],
          headings: { en: 'Account Reactivated' },
          contents: { en: 'Your account is now active. You can use the app again!' },
          data: { type: 'system' },
        }),
      });
    }

    return json({ success: true });
  } catch (e) {
    return json({ success: false, error: String(e) }, 500);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

interface CallerInfo {
  uid: string;
  role: string;
  region: string | null;
}

async function getCallerInfo(
  req: Request,
  supabase: ReturnType<typeof createClient>,
): Promise<CallerInfo | null> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return null;

  const { data: { user } } = await createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  ).auth.getUser();

  if (!user) return null;

  const { data: sa } = await supabase
    .from('super_admins').select('account_status').eq('id', user.id).maybeSingle();
  if (sa) {
    return { uid: user.id, role: sa.account_status === 'active' ? 'super_admin' : 'suspended', region: null };
  }

  const { data: ra } = await supabase
    .from('region_admins').select('account_status, region').eq('id', user.id).maybeSingle();
  if (ra) {
    return { uid: user.id, role: ra.account_status === 'active' ? 'region_admin' : 'suspended', region: ra.region };
  }

  return { uid: user.id, role: 'client', region: null };
}
