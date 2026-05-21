# REALTIME STABILITY REPORT — E-CYAMUNARA
Last updated: 2026-04-23

---

## REALTIME USAGE IN THE APP

| Screen | Subscription | Method |
|--------|-------------|--------|
| HomeScreen (auction list) | Active auctions by region | `.stream().eq('region')` |
| AuctionDetailScreen | Single auction bid updates | `.stream().eq('id')` |
| None (admin dashboard) | Admin's auctions | FutureProvider (one-shot) |

---

## FINDING 1 — SUPABASE REALTIME CONNECTION LIMITS

**Risk level:** HIGH  
**Symptom:** Auction list and detail screens stop updating for users who cannot establish a Realtime WebSocket.

Supabase's `postgres_changes` Realtime uses a WebSocket connection per subscription. The Flutter SDK's `.stream()` API creates one subscription per call.

If a user has both the home screen (auction list) and an auction detail screen open simultaneously via deep navigation, they hold 2 Realtime connections. At 300 concurrent active users on Pro plan (500-connection limit), this means only 250 users can have both screens active simultaneously.

**Connection math:**
- Free plan (200 max): breaks at ~100 dual-screen users
- Pro plan (500 max): breaks at ~250 dual-screen users
- Team plan (unlimited + quotas): sufficient for launch

**Current behavior when limit is reached:** Supabase silently drops new connection requests. The `.stream()` subscription returns the initial data once, then never updates. The user sees a stale auction list with no error message. No retry logic is implemented.

**Recommendation:**
1. Upgrade to Pro before launch.
2. Add a `StreamBuilder` error handler that shows a "Live updates paused — pull to refresh" banner when the Realtime connection is lost.
3. For the home screen, replace `.stream()` with a `FutureProvider` that auto-refreshes every 30 seconds using `ref.invalidateSelf()`. Reserve Realtime for the auction detail screen only where real-time bid updates are critical.

---

## FINDING 2 — NO RECONNECTION LOGIC ON NETWORK INTERRUPTION

**Risk level:** MEDIUM  
**Symptom:** User loses mobile data momentarily. Realtime stream silently stops. User has no indication their auction view is stale.

Supabase's Flutter SDK does implement WebSocket reconnection internally, but:
1. During reconnection, there is a gap where `postgres_changes` events are missed.
2. The `.stream()` API does not buffer missed events and replays them after reconnection.
3. If an auction's price changed during the disconnection, the user sees the old price.

**How it fails in production:** User is viewing an auction at RWF 500,000. Network drops for 30 seconds. Another user bids RWF 550,000. User's screen still shows 500,000. User submits a bid of 510,000. `place-bid` correctly rejects it with "Bid must be higher than current highest bid of 550,000". User is confused — their screen showed 500,000 as the current price.

**Recommendation:**
1. On the `AuctionDetailScreen`, when the Realtime stream emits an error, fall back to a periodic `getAuctionById()` one-shot fetch every 10 seconds with a visible warning:
   ```dart
   final auctionAsync = ref.watch(auctionWatcherProvider(auctionId));
   // On error, display stale-data banner + periodic refresh
   ```
2. Always show a "Last updated: X seconds ago" timestamp near the bid price so users know if their data is fresh.

---

## FINDING 3 — REALTIME EVENTS ARE NOT REGION-FILTERED SERVER-SIDE ON FREE PLAN

**Risk level:** MEDIUM  
**Detail:** On the Supabase free plan, `postgres_changes` broadcasts all table change events to all subscribers, and filtering (`eq('region', ...)`) is done client-side by the Flutter SDK. This means:
- A user subscribed to "Eastern" auctions receives change events for Western, Northern, Southern, and Central auctions.
- The SDK discards non-matching events, but they are still transmitted over the WebSocket.
- At scale (many concurrent auctions across all regions), this increases bandwidth usage on the client's mobile data.

On the Pro plan, Supabase supports server-side filtering for `postgres_changes`, which eliminates this unnecessary traffic.

**Recommendation:** After upgrading to Pro, verify that `.stream().eq('region', region)` is server-side filtered by checking Supabase Dashboard → Realtime → Inspect → confirm the subscription filter.

---

## FINDING 4 — ONESIGNAL PUSH: STALE PLAYER IDs

**Risk level:** MEDIUM  
**Source:** `lib/core/services/notification_service.dart`, `place-bid/index.ts`

OneSignal `player_id` (also called `external_id` in newer SDK versions) can become stale when:
1. User reinstalls the app — new player ID generated.
2. User switches devices.
3. OS revokes the push registration (common on iOS after app update).

When the player ID is stale, `sendPush()` in the Edge Functions sends to a non-existent device. OneSignal returns a 200 OK regardless (it silently discards invalid player IDs), so the Edge Function does not detect the failure.

**How it fails:** Admin posts a new auction. `on-new-auction` fires. 30% of player IDs in the region are stale (conservative estimate after 6 months of users reinstalling). 3,000 out of 10,000 clients never receive the push notification. They miss the auction.

**Recommendation:**
1. Ensure `refreshPlayerId()` is called on every login and app foreground (already done in `loginClient()` and `loginAdmin()`).
2. Handle OneSignal's `onOSPermissionChanged` callback to update the player ID when iOS permission status changes.
3. Consider migrating to OneSignal's External User ID pattern: tag each device with the Supabase `uid`, then target by external ID instead of player ID. This survives reinstalls.

---

## FINDING 5 — PENDING ROUTE IN NOTIFICATION SERVICE IS NEVER CONSUMED

**Risk level:** LOW  
**Source:** `lib/core/services/notification_service.dart`

`NotificationService` stores a `_pendingRoute` string when a notification is tapped (the `type` + `auction_id` from the notification data). However, there is no code in `app_router.dart` or any screen that reads `_pendingRoute` and navigates to the appropriate screen.

**How it fails:** User receives "You've been outbid" push notification. They tap it. The app opens. They land on the home screen instead of the auction detail. If the auction is time-sensitive, they may miss bidding before it closes.

**Recommendation:**
Add a listener in `main.dart` or the router that calls `NotificationService.instance.pendingRoute` on app startup and after routing is initialized:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final route = NotificationService.instance.consumePendingRoute();
  if (route != null) {
    context.go(route); // e.g., '/auction/abc123'
  }
});
```

---

## FINDING 6 — NO ERROR HANDLING ON ONESIGNAL TAG SUBSCRIPTION

**Risk level:** LOW  
**Source:** `lib/core/services/notification_service.dart`

`subscribeToRegion()` and `setUserRole()` call `OneSignal.User.addTag(...)`. If OneSignal is unavailable (network offline, SDK not initialized), these calls fail silently.

**How it fails:** User registers. Their device is in a tunnel with no signal. `subscribeToRegion()` fails silently. The user's device is never tagged with their region in OneSignal. They never receive region-based push notifications.

**Recommendation:** Wrap tag operations in a try/catch and retry on next app launch:
```dart
try {
  OneSignal.User.addTag('region', region);
} catch (e) {
  debugPrint('[NOTIF] subscribeToRegion failed: $e — will retry on next login');
}
```
Also: re-call `subscribeToRegion(user.region)` on every successful login to self-heal stale tag state.

---

## SUMMARY TABLE

| Finding | Risk | Impact |
|---------|------|--------|
| Realtime connection limit | HIGH | Stale data for users over limit |
| No reconnection fallback | MEDIUM | User bids on wrong price |
| Client-side filter on free plan | MEDIUM | Unnecessary bandwidth usage |
| Stale OneSignal player IDs | MEDIUM | Silent push notification failure |
| Pending route never consumed | LOW | Push tap doesn't deep-link |
| No tag subscription error handling | LOW | Users miss push notifications |
