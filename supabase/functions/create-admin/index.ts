// supabase/functions/create-admin/index.ts
// Called by super admin to create a new region admin account.
//
// Fixes applied:
//   • Email now uses the rw-prefix format to match Flutter's _phoneToEmail()
//   • Permissions from request body are respected (not hardcoded)
//   • Caller suspension is checked before proceeding
//   • Region is validated against the allowed list
//   • Duplicate region assignment is detected and rejected with 409

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const ALLOWED_REGIONS = ['Eastern', 'Western', 'Northern', 'Southern', 'Central'];

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Verify caller is an active super_admin
    const callerRole = await getCallerRole(req, supabase);
    if (callerRole !== 'super_admin') {
      return json({ success: false, error: 'Super admin only' }, 403);
    }

    const { full_names, national_id, phone_number, region, created_by, permissions } =
      await req.json();

    // Validate required fields
    if (!full_names || !national_id || !phone_number || !region) {
      return json({ success: false, error: 'Missing required fields' }, 400);
    }

    // Validate region
    if (!ALLOWED_REGIONS.includes(region)) {
      return json({ success: false, error: `Invalid region. Must be one of: ${ALLOWED_REGIONS.join(', ')}` }, 400);
    }

    // Check region uniqueness (region_admins.region is UNIQUE but give a clear error)
    const { data: existing } = await supabase
      .from('region_admins')
      .select('id')
      .eq('region', region)
      .maybeSingle();
    if (existing) {
      return json({ success: false, error: `Region ${region} already has an assigned admin` }, 409);
    }

    // Build email matching Flutter's _phoneToEmail() exactly:
    //   0789000001 → rw0789000001@ecyamunara.rw
    const normalizedPhone = normalizePhone(phone_number);
    const email = `rw${normalizedPhone}@ecyamunara.rw`;

    // Generate a secure temp password (returned to caller — Flutter must display it)
    const tempPassword = generatePassword();

    // Create Supabase Auth account
    const { data: authUser, error: authError } = await supabase.auth.admin.createUser({
      email,
      password: tempPassword,
      email_confirm: true,
    });
    if (authError) throw authError;

    const uid = authUser.user!.id;
    const now = new Date().toISOString();

    // Honour the permissions the super admin configured in the UI.
    // Fall back to true for any key that was omitted.
    const adminPermissions = {
      post_auctions:  permissions?.post_auctions  ?? true,
      manage_clients: permissions?.manage_clients ?? true,
      view_reports:   permissions?.view_reports   ?? true,
      close_auctions: permissions?.close_auctions ?? true,
    };

    await supabase.from('region_admins').insert({
      id: uid,
      full_names,
      national_id,
      phone_number: normalizedPhone,
      region,
      role: 'region_admin',
      account_status: 'active',
      permissions: adminPermissions,
      total_auctions_posted: 0,
      total_auctions_closed: 0,
      created_at: now,
      updated_at: now,
      created_by,
    });

    // Return temp_password so the caller can display it to the super admin.
    // Flutter's AddAdminScreen MUST read and show this value.
    return json({ success: true, uid, temp_password: tempPassword });
  } catch (e) {
    return json({ success: false, error: String(e) }, 500);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function normalizePhone(phone: string): string {
  let digits = phone.replace(/\D/g, '');
  if (digits.startsWith('250') && digits.length > 9) digits = digits.slice(3);
  if (!digits.startsWith('0')) digits = '0' + digits;
  return digits;
}

function generatePassword(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#';
  return Array.from({ length: 12 }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

async function getCallerRole(req: Request, supabase: ReturnType<typeof createClient>): Promise<string> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return 'unknown';

  const { data: { user } } = await createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  ).auth.getUser();

  if (!user) return 'unknown';

  const { data: sa } = await supabase
    .from('super_admins')
    .select('role, account_status')
    .eq('id', user.id)
    .maybeSingle();
  if (sa) return sa.account_status === 'active' ? 'super_admin' : 'suspended';

  const { data: ra } = await supabase
    .from('region_admins')
    .select('role, account_status')
    .eq('id', user.id)
    .maybeSingle();
  if (ra) return ra.account_status === 'active' ? 'region_admin' : 'suspended';

  return 'client';
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
