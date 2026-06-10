// supabase/functions/register-client/index.ts
//
// Public client registration endpoint.
//
// Uses the service role so admin.createUser() is called with
// email_confirm:true — this skips the confirmation-email flow entirely,
// which means GoTrue never performs the MX-record validation that rejects
// the synthetic @ecyamunara.rw domain when using client-side signUp().
//
// Mirrors the pattern already used by create-admin for region admins.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const body = await req.json();
    const {
      phone_number,
      password,
      full_names,
      national_id,
      district,
      province,
      region,
      onesignal_player_id,
    } = body;

    if (!phone_number || !password || !full_names || !national_id || !district) {
      return json({ success: false, error: 'Missing required fields' }, 400);
    }

    const normalizedPhone = normalizePhone(String(phone_number));

    if (!isValidRwandaPhone(normalizedPhone)) {
      return json({ success: false, error: 'Invalid Rwanda phone number format' }, 400);
    }

    // Build email exactly matching Flutter _phoneToEmail()
    const email = `rw${normalizedPhone}@ecyamunara.rw`;

    // Reject duplicates before attempting auth creation
    const { data: existingUser } = await supabase
      .from('users')
      .select('id')
      .eq('phone_number', normalizedPhone)
      .maybeSingle();

    if (existingUser) {
      return json(
        { success: false, error: 'An account with this phone number already exists' },
        409,
      );
    }

    // Create auth user via admin API.
    // email_confirm:true marks the user confirmed without sending any email,
    // so GoTrue skips MX-record validation on the @ecyamunara.rw domain.
    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });

    if (authError) {
      const msg = authError.message.toLowerCase();
      if (msg.includes('already registered') || msg.includes('already been registered')) {
        return json(
          { success: false, error: 'An account with this phone number already exists' },
          409,
        );
      }
      throw authError;
    }

    const uid = authData.user!.id;
    const now = new Date().toISOString();

    const { error: dbError } = await supabase.from('users').insert({
      id: uid,
      full_names: String(full_names),
      national_id: String(national_id),
      phone_number: normalizedPhone,
      district: String(district),
      province: province ? String(province) : '',
      region: region ? String(region) : '',
      role: 'client',
      account_status: 'active',
      onesignal_player_id: onesignal_player_id ?? null,
      total_bids_placed: 0,
      total_auctions_won: 0,
      created_at: now,
      updated_at: now,
    });

    if (dbError) {
      // Roll back: remove the orphan auth user so the phone can be re-used
      await supabase.auth.admin.deleteUser(uid).catch(() => {});
      throw dbError;
    }

    return json({ success: true, uid });
  } catch (e) {
    console.error('[register-client]', e);
    return json({ success: false, error: String(e) }, 500);
  }
});

function normalizePhone(phone: string): string {
  let digits = phone.replace(/\D/g, '');
  if (digits.startsWith('250') && digits.length > 9) digits = digits.slice(3);
  if (!digits.startsWith('0')) digits = '0' + digits;
  return digits;
}

function isValidRwandaPhone(phone: string): boolean {
  return /^07[2389]\d{7}$/.test(phone);
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
