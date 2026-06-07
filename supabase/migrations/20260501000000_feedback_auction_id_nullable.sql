-- Allow general (non-auction) feedback by making auction_id optional.
-- Previously NOT NULL, which prevented submitting feedback without an auction reference.
ALTER TABLE public.feedback ALTER COLUMN auction_id DROP NOT NULL;
