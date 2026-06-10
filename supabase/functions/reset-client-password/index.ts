// supabase/functions/reset-client-password/index.ts
//
// Resets a client's password using phone number as identity.
//
// admin.updateUserById() sets the new password directly without sending
// any password-reset email, so the MX-record issue with @ecyamunara.rw
// never applies.  resetPasswordForEmail() would fail for the same reason
// client-side signUp() does — it tries to deliver an email.

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
    const { phone_number, new_password } = body;

    if (!phone_number || !new_password) {
      return json({ success: false, error: 'Phone number and new password are required' }, 400);
    }

    const pw = String(new_password);
    if (pw.length < 8) {
      return json({ success: false, error: 'Password must be at least 8 characters' }, 400);
    }

    const normalizedPhone = normalizePhone(String(phone_number));

    // Resolve the user by phone number
    const { data: userRow } = await supabase
      .from('users')
      .select('id, account_status')
      .eq('phone_number', normalizedPhone)
      .maybeSingle();

    if (!userRow) {
      return json({ success: false, error: 'No account found with this phone number' }, 404);
    }

    if ((userRow.account_status as string) !== 'active') {
      return json(
        { success: false, error: 'Account is suspended. Please contact support.' },
        403,
      );
    }

    // Update password via admin API — no email sent, no MX validation
    const { error: updateError } = await supabase.auth.admin.updateUserById(
      userRow.id as string,
      { password: pw },
    );

    if (updateError) throw updateError;

    return json({ success: true });
  } catch (e) {
    console.error('[reset-client-password]', e);
    return json({ success: false, error: String(e) }, 500);
  }
});

function normalizePhone(phone: string): string {
  let digits = phone.replace(/\D/g, '');
  if (digits.startsWith('250') && digits.length > 9) digits = digits.slice(3);
  if (!digits.startsWith('0')) digits = '0' + digits;
  return digits;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
