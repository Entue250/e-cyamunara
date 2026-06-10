-- supabase/migrations/20260610000001_task4_workflow_fixes.sql
--
-- Task 4 — Three workflow fixes:
--   A. Soft-delete columns on auctions (hard delete if no bids, soft if bids exist)
--   B. Fix FK constraints (notifications CASCADE, feedback SET NULL)
--   C. Region admin DELETE RLS policy
--   D. auction_auto_close_logs table for auto-close audit trail
--
-- Apply: supabase db push

-- ── A. Soft-delete columns ────────────────────────────────────────────────────
ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS is_deleted  BOOLEAN     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_by  UUID;

-- Partial index — queries that exclude soft-deleted rows scan only live rows
CREATE INDEX IF NOT EXISTS idx_auctions_active
  ON public.auctions (posted_by_admin_uid, is_deleted, created_at DESC)
  WHERE is_deleted = false;

-- ── B. Fix FK constraints ─────────────────────────────────────────────────────

-- notifications: deleting an auction should cascade-delete its notifications
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_auction_id_fkey;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_auction_id_fkey
  FOREIGN KEY (auction_id) REFERENCES public.auctions(id) ON DELETE CASCADE;

-- feedback: preserve feedback but unlink the deleted auction
ALTER TABLE public.feedback
  DROP CONSTRAINT IF EXISTS feedback_auction_id_fkey;
ALTER TABLE public.feedback
  ADD CONSTRAINT feedback_auction_id_fkey
  FOREIGN KEY (auction_id) REFERENCES public.auctions(id) ON DELETE SET NULL;

-- ── C. Region admin DELETE RLS ────────────────────────────────────────────────
-- Previously region_admins had no DELETE policy, causing silent no-ops.
-- They may only delete auctions they posted in their own region.
DROP POLICY IF EXISTS "auctions_region_admin_delete" ON public.auctions;
CREATE POLICY "auctions_region_admin_delete" ON public.auctions
  FOR DELETE
  USING (
    get_my_role() = 'region_admin'
    AND posted_by_admin_uid = auth.uid()
  );

-- ── D. auction_auto_close_logs ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.auction_auto_close_logs (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id  UUID         NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
  closed_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  winner_uid  UUID,
  final_price NUMERIC(15,2),
  status      TEXT         NOT NULL DEFAULT 'closed'
              CHECK (status IN ('winner_found', 'no_bids', 'closed')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

ALTER TABLE public.auction_auto_close_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auto_close_logs_admin_read" ON public.auction_auto_close_logs;
CREATE POLICY "auto_close_logs_admin_read" ON public.auction_auto_close_logs
  FOR SELECT
  USING (get_my_role() IN ('region_admin', 'super_admin'));

-- ── pg_cron setup (run once manually in Supabase SQL Editor) ──────────────────
-- 1. Enable extension: Dashboard → Database → Extensions → pg_cron
-- 2. Run:
--    SELECT cron.schedule(
--      'auto-close-auctions',
--      '*/5 * * * *',
--      $$SELECT net.http_post(
--        url  := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/auto-close-auctions',
--        headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
--        body := '{}'::jsonb
--      )$$
--    );
