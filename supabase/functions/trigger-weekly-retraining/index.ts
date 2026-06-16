// supabase/functions/trigger-weekly-retraining/index.ts
// Phase 9D — Triggers a weekly model retraining job on the training worker.
//
// Called by pg_cron every Sunday at 03:00 UTC (05:00 Kigali, UTC+2).
// Also callable manually by super_admins for on-demand retraining.
//
// Required secrets (set via: supabase secrets set --env-file supabase/.env):
//   TRAINING_WORKER_URL   — Base URL of the training worker service
//                           e.g. https://ecyamunara-training-worker.up.railway.app
//   TRAINING_WORKER_TOKEN — Bearer token for the training worker (optional
//                           if the service has no auth; set to "" to skip)
//
// pg_cron setup (add to supabase/pg_cron_setup.sql after deploying):
//   SELECT cron.schedule(
//     'weekly-retraining',
//     '0 3 * * 0',   -- Every Sunday at 03:00 UTC
//     $$
//       SELECT net.http_post(
//         url     := 'https://YOUR_PROJECT.supabase.co/functions/v1/trigger-weekly-retraining',
//         headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
//         body    := '{}'::jsonb
//       )
//     $$
//   );

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TRAINING_WORKER_URL = Deno.env.get("TRAINING_WORKER_URL");
const TRAINING_WORKER_TOKEN = Deno.env.get("TRAINING_WORKER_TOKEN") ?? "";

serve(async (req: Request) => {
  // ── Auth guard — only service_role or super_admin may trigger ──────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "missing Authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // pg_cron calls with the service role key — verify it matches.
  const token = authHeader.replace("Bearer ", "");
  const isPgCron = token === serviceKey;

  if (!isPgCron) {
    // Validate as a super_admin JWT.
    const supabase = createClient(supabaseUrl, serviceKey);
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const { data: sa } = await supabase
      .from("super_admins")
      .select("id")
      .eq("id", user.id)
      .eq("account_status", "active")
      .maybeSingle();
    if (!sa) {
      return new Response(JSON.stringify({ error: "forbidden" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  // ── Check training worker URL is configured ────────────────────────────────
  if (!TRAINING_WORKER_URL) {
    console.error("TRAINING_WORKER_URL secret is not set");
    return new Response(
      JSON.stringify({ error: "TRAINING_WORKER_URL not configured" }),
      { status: 503, headers: { "Content-Type": "application/json" } },
    );
  }

  // ── Parse optional body overrides ─────────────────────────────────────────
  let model = "all";
  let datasource = "real";
  try {
    const body = await req.json().catch(() => ({}));
    if (body.model) model = body.model;
    if (body.datasource) datasource = body.datasource;
  } catch {
    // No body or invalid JSON — use defaults.
  }

  // ── Call POST /train on the training worker ───────────────────────────────
  const workerHeaders: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (TRAINING_WORKER_TOKEN) {
    workerHeaders["Authorization"] = `Bearer ${TRAINING_WORKER_TOKEN}`;
  }

  let workerRes: Response;
  try {
    workerRes = await fetch(`${TRAINING_WORKER_URL}/train`, {
      method: "POST",
      headers: workerHeaders,
      body: JSON.stringify({ model, datasource }),
    });
  } catch (err) {
    console.error("Failed to reach training worker:", err);
    return new Response(
      JSON.stringify({ error: "training worker unreachable", detail: String(err) }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  const workerBody = await workerRes.json().catch(() => null);

  if (!workerRes.ok) {
    console.error("Training worker returned error:", workerRes.status, workerBody);
    return new Response(
      JSON.stringify({ error: "training worker error", status: workerRes.status, body: workerBody }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  console.log("Weekly retraining triggered:", workerBody);
  return new Response(
    JSON.stringify({ triggered: true, job: workerBody }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
