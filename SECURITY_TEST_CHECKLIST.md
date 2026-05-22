# SECURITY TEST CHECKLIST — E-CYAMUNARA
Phase 4: Flutter Authentication Hardening
Last updated: 2026-04-23

---

## HOW TO USE
Each scenario describes the setup, the action, and the expected result.
PASS = behaviour matches expected. FAIL = log the deviation.
Run against a real Supabase instance. Do not use mocks for security tests.

---

## 1. SUSPENDED USER LOGIN TESTS

### 1.1 Suspended client — login attempt
- Setup: Set `account_status = 'suspended'` for a client in `users` table
- Action: Open login screen, enter correct phone + password, tap LOGIN
- Expected:
  - Error snackbar: "Your account has been suspended. Please contact support."
  - App stays on login screen
  - `Supabase.instance.client.auth.currentUser` is `null` after the attempt
  - No navigation occurs
- Debug log expected: `[AUTH] loginClient: rejected — account_status=suspended`

### 1.2 Suspended region_admin — login attempt
- Setup: Set `account_status = 'suspended'` for a region_admin
- Action: Admin login screen, correct credentials, tap LOGIN AS ADMIN
- Expected:
  - Error snackbar: "Your admin account has been suspended. Contact the system administrator."
  - App stays on admin login screen
  - `currentUser` is `null`
  - No navigation occurs
- Debug log expected: `[AUTH] loginAdmin: region_admin suspended`

### 1.3 Suspended super_admin — login attempt
- Setup: Set `account_status = 'suspended'` for a super_admin
- Action: Admin login screen, correct credentials
- Expected: Same rejection as 1.2, no navigation
- Debug log expected: `[AUTH] loginAdmin: super_admin suspended`

### 1.4 Client suspended WHILE already logged in
- Setup: Log in as an active client, then set `account_status = 'suspended'` via Supabase dashboard
- Action: Navigate to any protected route (e.g. tap My Bids)
- Expected:
  - Router calls `_getUserRole()` → detects suspended → calls `signOut()`
  - App navigates to `/login`
  - Any further navigation is blocked
- Debug log expected: `[ROUTER] client suspended`

### 1.5 Region admin suspended WHILE already logged in
- Setup: Log in as active region_admin, then set `account_status = 'suspended'`
- Action: Navigate to any admin route
- Expected: Signed out, redirected to `/login`
- Debug log expected: `[ROUTER] region_admin suspended`

### 1.6 Super admin suspended WHILE already logged in
- Setup: Log in as super_admin, then set `account_status = 'suspended'`
- Action: Navigate to any super route
- Expected: Signed out, redirected to `/login`
- Debug log expected: `[ROUTER] super_admin suspended`

---

## 2. VALID LOGIN TESTS

### 2.1 Active client — successful login
- Setup: Active client account
- Action: Login screen, correct credentials
- Expected:
  - Returns role = 'client'
  - `last_login` updated in `users` table
  - Navigates to `/region-select`
  - `currentUser` is non-null
- Debug log expected: `[AUTH] loginClient: success`

### 2.2 Active region_admin — successful login
- Setup: Active region_admin account
- Action: Admin login screen, correct credentials
- Expected:
  - Returns role = 'region_admin'
  - `last_login` updated in `region_admins` table
  - Navigates to `/admin/dashboard`
- Debug log expected: `[AUTH] loginAdmin: success role=region_admin`

### 2.3 Active super_admin — successful login
- Setup: Active super_admin account
- Action: Admin login screen, correct credentials
- Expected:
  - Returns role = 'super_admin'
  - `last_login` updated in `super_admins` table
  - Navigates to `/super/dashboard`

---

## 3. ROLE ESCALATION ATTEMPT TESTS

### 3.1 Client tries to navigate to admin dashboard
- Setup: Logged in as active client
- Action: Call `context.go('/admin/dashboard')` directly (or via deep link)
- Expected: Router redirects to `/home`, not `/admin/dashboard`

### 3.2 Client tries to navigate to super admin dashboard
- Action: `context.go('/super/dashboard')`
- Expected: Router redirects to `/home`

### 3.3 Region admin tries to navigate to super admin routes
- Setup: Logged in as active region_admin
- Action: `context.go('/super/dashboard')` or `context.go('/super/admins')`
- Expected: Router redirects to `/admin/dashboard`

### 3.4 Client uses admin login screen
- Setup: Active client account
- Action: Enter client credentials in the ADMIN login screen
- Expected:
  - `loginAdmin()` checks super_admins + region_admins tables → both null
  - Throws: "This account is not an admin account"
  - Session cleared, stays on admin login screen

### 3.5 Admin uses client login screen
- Setup: Active region_admin account
- Action: Enter admin credentials in the CLIENT login screen
- Expected:
  - `loginClient()` checks `users` table → null (no row for admin UID)
  - Throws: "Account record not found"
  - Session cleared, stays on login screen

---

## 4. DEEP LINK / DIRECT NAVIGATION BYPASS TESTS

### 4.1 Unauthenticated deep link to protected route
- Setup: No active session
- Action: Launch app with initial route `/home` or `/admin/dashboard`
- Expected: Router detects no session, redirects to `/login`

### 4.2 Unauthenticated deep link to public route
- Action: Launch app with initial route `/login` or `/register`
- Expected: Route allowed, no redirect loop

### 4.3 Authenticated client deep links to auction detail
- Setup: Active client session
- Action: Navigate to `/auction/some-uuid`
- Expected: Route allowed (isClientRoute matches `/auction*`)

### 4.4 Auth state changes mid-navigation
- Setup: Active session, app on home screen
- Action: Manually invalidate session in Supabase dashboard, then tap a nav item
- Expected: Router detects no session on next redirect, redirects to `/login`

---

## 5. SESSION PERSISTENCE TESTS

### 5.1 Hot restart with active session
- Setup: Logged in as client
- Action: Hot restart the app
- Expected: Splash screen → `_getUserRole()` → 'client' → navigates to `/home`

### 5.2 Hot restart after suspension (suspended between restarts)
- Setup: Log in as client, suspend the account, hot restart
- Action: App resumes, splash runs
- Expected: Splash calls `_getUserRole()` → 'suspended' → signs out → `/login`

### 5.3 App killed and reopened with suspended session
- Setup: Log in as client, kill app, suspend account, reopen app
- Expected: Splash calls `_getUserRole()` → 'suspended' → signs out → `/login`

### 5.4 Session restoration after app backgrounded for > 1 hour
- Setup: Log in, background app for > 1 hour (JWT refresh window)
- Action: Foreground the app, navigate
- Expected: Supabase auto-refreshes JWT; if account is still active, navigation proceeds normally

### 5.5 Token refresh after suspension
- Setup: Active session, suspend the account, wait for Supabase to auto-refresh the token
- Action: Navigate in the app
- Expected: Router's `_getUserRole()` checks DB status → 'suspended' → signs out

---

## 6. NETWORK FAILURE DURING AUTH TESTS

### 6.1 Network failure after signInWithPassword succeeds
- Setup: Simulate network drop after sign-in but before DB status check (e.g. airplane mode after entering credentials)
- Action: Tap LOGIN
- Expected:
  - `catch (e)` fires with `signedIn = true`
  - `_safeSignOut()` called, session cleared
  - Error snackbar shown: "Login failed: ..."
  - `currentUser` is null after

### 6.2 Network failure during `getUserRole()` from router
- Setup: Active session, then disconnect network
- Action: Navigate to a new route
- Expected:
  - `_getUserRole()` catches the exception → returns 'unauthenticated'
  - Router sees `role == 'unauthenticated'` → but session is non-null
  - Currently: falls through to route checks without sign-out (acceptable — transient failure)
  - User can retry navigation when network recovers

### 6.3 Partial network recovery (Supabase reachable, DB not)
- Same as 6.2 — router catches exception, returns 'unauthenticated', no forced sign-out
- Acceptable: signed-in user is not punished for transient network issues

---

## 7. LOGOUT FLOW TESTS

### 7.1 Normal client logout
- Setup: Logged in as client, navigate to profile
- Action: Tap logout button
- Expected:
  - `LogoutUseCase` → `AuthRepository.logout()` → `signOut()`
  - `currentUser` becomes null
  - Auth state stream emits `signedOut` event
  - `currentUserProvider` invalidates (now watches authStateProvider)
  - App navigates to `/login`

### 7.2 Admin logout
- Setup: Logged in as region_admin
- Action: Tap logout from AdminProfileScreen
- Expected:
  - `signOut()` called
  - `currentAdminProvider` invalidates (now watches authStateProvider)
  - App navigates to `/admin/login`

### 7.3 Stale provider data after logout
- Setup: Logged in as client, `currentUserProvider` loaded with user data
- Action: Logout
- Expected:
  - `currentUserProvider` rebuilds (watches authStateProvider)
  - `getCurrentUser()` returns null (no session)
  - No stale UserModel remains accessible

---

## 8. CONCURRENT / RACE CONDITION TESTS

### 8.1 Double-tap LOGIN button
- Setup: Active client
- Action: Tap LOGIN twice in rapid succession
- Expected:
  - Button disabled via `onPressed: _isLoading ? null : _handleLogin`
  - Only one login attempt fires
  - No double session created

### 8.2 Multiple simultaneous navigation attempts during auth check
- Setup: Slow network, router redirect in progress
- Action: Tap two different nav items quickly
- Expected: GoRouter serialises redirects; the latter navigation is evaluated after the first resolves

---

## SIGN-OFF

| Category                          | Status  |
|-----------------------------------|---------|
| Suspended client login rejected   | [ ] PASS / [ ] FAIL |
| Suspended admin login rejected    | [ ] PASS / [ ] FAIL |
| Super admin suspension at runtime | [ ] PASS / [ ] FAIL |
| Client→admin escalation blocked   | [ ] PASS / [ ] FAIL |
| region_admin→super escalation blocked | [ ] PASS / [ ] FAIL |
| Deep link bypass blocked          | [ ] PASS / [ ] FAIL |
| Network failure session cleanup   | [ ] PASS / [ ] FAIL |
| Stale provider cleared on logout  | [ ] PASS / [ ] FAIL |
| Hot restart suspended session     | [ ] PASS / [ ] FAIL |
