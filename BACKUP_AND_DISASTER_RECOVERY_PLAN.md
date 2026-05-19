# BACKUP AND DISASTER RECOVERY PLAN — E-CYAMUNARA
Last updated: 2026-04-23

---

## DATA CLASSIFICATION

| Data | Location | Sensitivity | Recovery priority |
|------|----------|-------------|------------------|
| Auction records (item, price, status, winner) | `auctions` table | HIGH — legal record | P1 |
| Bid records | `bids` table | HIGH — payment evidence | P1 |
| User profiles (name, phone, district, region) | `users` table | HIGH — PII | P1 |
| Encrypted National IDs | `users.national_id` column | CRITICAL — protected by law | P1 |
| Region admin profiles | `region_admins` table | HIGH | P1 |
| Auction photos | `auction-photos` storage bucket | MEDIUM | P2 |
| Notifications (history) | `notifications` table | LOW | P3 |
| Reports | `reports` storage bucket | MEDIUM | P3 |
| App settings, districts | `app_settings`, `districts` | LOW — static config | P3 |

---

## BACKUP STRATEGY

### Automated Backups (Supabase Managed)

**Free plan:** Daily backups, 7-day retention. No point-in-time recovery (PITR).  
**Pro plan:** Daily backups, 7-day retention, + PITR down to 1-second granularity (last 7 days).  
**Action required:** Upgrade to Pro before launch to enable PITR.

Backups are managed by Supabase and stored in their infrastructure. You cannot export them directly but can restore via the Dashboard.

### Manual Backup (Critical Operations)

Run before every deployment and before any schema change:

```
Supabase Dashboard → Database → Backups → Create backup
```

Document the backup timestamp in the deployment log.

### Storage Backup

Supabase Storage (photos, reports, national IDs) is NOT included in database backups. The buckets contain binary blobs stored in S3-compatible storage. Supabase Pro plan includes storage replication within their infrastructure, but there is no built-in export to an external destination.

**Recommendation:** For `national-ids` bucket specifically, implement a weekly export of encrypted National ID blobs to a separate secure S3 bucket (or similar) under RNP control, independent of Supabase.

---

## RECOVERY TIME OBJECTIVES (RTO)

| Incident type | Target RTO |
|--------------|-----------|
| Supabase Auth outage (they manage) | 0 — no action needed; existing sessions work |
| RLS policy break | < 15 min (revoke + restore from migration file) |
| Data corruption (partial) | < 30 min (run repair SQL from Incident Guide) |
| Full DB restore from backup | < 2 hours (Supabase dashboard restore) |
| Edge Function bad deploy | < 5 min (disable function + redeploy previous) |
| App build crash (Flutter) | < 30 min (publish previous APK) |

---

## RECOVERY POINT OBJECTIVES (RPO)

| Scenario | RPO with Free plan | RPO with Pro plan |
|----------|-------------------|------------------|
| DB hardware failure | Up to 24 hours of data loss | Up to 1 second |
| Accidental data delete | Up to 24 hours (last daily backup) | Up to 1 second (PITR) |
| RLS break (data exposure) | Immediate — no data loss, only exposure | Same |

---

## DISASTER RECOVERY PROCEDURES

### DR-1: Complete Database Restore

Use when: Widespread data corruption, accidental table truncation, catastrophic migration failure.

1. **Stop new writes immediately:**
   - Supabase Dashboard → Edge Functions → Pause `place-bid`, `close-auction-manually`, `create-admin`
   - Supabase Dashboard → Authentication → Disable new sign-ups
   - Post OneSignal broadcast: "System maintenance in progress. Bidding is temporarily paused."

2. **Determine restore point:**
   - For Pro plan with PITR: identify the last known-good timestamp before corruption
   - For daily backups: use the most recent backup before the incident

3. **Execute restore:**
   - Supabase Dashboard → Database → Backups → select backup → Restore
   - Restore time: 15–60 minutes depending on database size

4. **Verify restore:**
   ```sql
   SELECT COUNT(*) FROM auctions WHERE auction_status = 'active';
   SELECT COUNT(*) FROM bids;
   SELECT COUNT(*) FROM users;
   SELECT MAX(created_at) FROM bids; -- confirm most recent bid timestamp
   ```

5. **Re-enable services:**
   - Re-enable Edge Functions
   - Re-enable sign-ups
   - Test bid placement with a known account
   - Post: "System maintenance complete. Normal service resumed."

---

### DR-2: Partial Data Repair (Without Full Restore)

Use when: Specific auctions have wrong `current_highest_bid` or `total_bids` counters.

```sql
-- Identify affected auctions
SELECT a.id, a.current_highest_bid, MAX(b.bid_amount) as actual_highest,
       a.total_bids, COUNT(b.id) as actual_bids
FROM auctions a
LEFT JOIN bids b ON b.auction_id = a.id
GROUP BY a.id, a.current_highest_bid, a.total_bids
HAVING a.current_highest_bid != COALESCE(MAX(b.bid_amount), a.starting_price)
   OR a.total_bids != COUNT(b.id);

-- Repair all active auctions
UPDATE auctions a
SET current_highest_bid = COALESCE(
    (SELECT MAX(bid_amount) FROM bids WHERE auction_id = a.id), a.starting_price),
    total_bids = (SELECT COUNT(*) FROM bids WHERE auction_id = a.id),
    updated_at = NOW()
WHERE auction_status = 'active';
```

Refer to `INCIDENT_RESPONSE_GUIDE.md` INCIDENT 4 for full procedure.

---

### DR-3: National ID Encryption Key Loss

Use when: A user reports their National ID cannot be decrypted (device reinstall, storage corruption).

This is currently an unrecoverable situation without a backend key store. The user must re-submit their National ID.

**Immediate action:**
1. Identify the affected user UID from admin complaint.
2. Null out their encrypted National ID: `UPDATE users SET national_id = NULL WHERE id = 'uid';`
3. Send in-app notification: "We were unable to access your identity document. Please re-submit your National ID for verification."
4. The user re-registers their National ID through the app's profile edit flow.

**Long-term fix:** Move encryption key to Supabase Vault (server-side key management). Key becomes tied to the authenticated user's UID, not the device, and survives reinstalls.

---

### DR-4: Storage Bucket Corruption / Photo Loss

Use when: Auction photos return 404 or storage bucket is unavailable.

Supabase Storage is backed by S3-compatible distributed storage with redundancy. Single-object loss is unlikely. Bucket-level loss is a Supabase infrastructure incident.

**Mitigation already in place:** All photo URLs are stored as absolute public URLs in `auctions.photo_urls` (array column). Even if Supabase storage has an outage, the URLs are preserved. Once storage recovers, photos are accessible again with no app changes needed.

**Permanent photo loss:** If photos are permanently deleted (e.g., via `deleteAuction()` followed by a recovery-from-backup that restored the DB row but not the storage), the auction record shows broken image links. No recovery possible without the original files.

**Recommendation:** Store photo metadata (original filename, size, upload date) in the DB. This helps distinguish "photo was deleted intentionally" from "storage corruption".

---

## BACKUP VERIFICATION SCHEDULE

| Task | Frequency | How to verify |
|------|-----------|--------------|
| Confirm automated backup exists | Weekly | Dashboard → Database → Backups → check latest timestamp |
| Test restore to staging | Monthly | Create a Supabase staging project, restore backup, run smoke tests |
| Verify PITR is enabled | After every billing cycle | Dashboard → Database → Backups → confirm PITR is listed |
| Test partial data repair SQL | Quarterly | Run the SELECT version of DR-2 on a staging DB with synthetic corruption |

---

## KNOWN LIMITATIONS FOR V1.0

1. **No staging environment** — Backup restore tests cannot be run without creating a temporary Supabase project (requires a second account or project). Document this as a known gap.
2. **No off-site storage backup** — `national-ids` and `reports` buckets are not backed up outside Supabase infrastructure.
3. **Encryption key not recoverable** — National ID data is permanently lost if the encryption key is destroyed. Backend key store needed for v1.1.
4. **pg_cron not monitored** — If `auto-close-auctions` fails silently, auctions expire without closing. No alert is configured for cron job failure.
