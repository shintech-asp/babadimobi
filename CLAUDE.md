q# CLAUDE.md — pestify_flutter

This file provides guidance to Claude Code when working inside `/Users/sheenrusselcastillo/Documents/babadimobi/` (this machine is macOS; older notes in this file referencing `C:/...` paths are stale — the PHP backend actually lives at `/Applications/XAMPP/xamppfiles/htdocs/pestify/` via XAMPP for macOS).

## What this project is

Flutter front-end for **Pestify** — a pest control service marketplace. This app is the mobile/web client for the PHP backend at `/Applications/XAMPP/xamppfiles/htdocs/pestify/`.

**Current scope:** Phase 1 (Seeker) is functionally complete but had numerous latent bugs fixed in an earlier session (see "Recent work log" and "Known backend gotchas" below — read those before touching booking/payment/review code). **Phase 2 (Provider) core flow is now built** — dashboard, listings CRUD, service requests, dual-code verify, QR scan (see "Phase 2 — Provider" section for what's done vs. still open). Phase 3 (Admin + Portal Staff) still has placeholder routes only.

**Run command:** `flutter run -d web-server --web-port 3000` — opens at `http://localhost:3000`.

**Before starting work, verify XAMPP is actually running** — see "Local dev environment (macOS)" below. A cold machine will have MySQL stopped, and every API call will fail in a way that looks like an app bug but isn't.

---

## How to use the PHP backend as reference

**Always read the PHP file before writing or debugging any API call.** The PHP source is the single source of truth for:
- Exact field names (`req_inp('to', ...)` not `receiver_id`, etc.)
- Which fields are required vs optional (`req_inp` vs `inp`)
- Response envelope shape — especially endpoints that return extra top-level keys alongside `data`
- Validation rules (Cavite-only address, date format, allowed `status` values, etc.)

**PHP API files live at:** `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/<path matching ApiEndpoints constant>`

Examples:
- `ApiEndpoints.sendMessage` → `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/messages/send.php`
- `ApiEndpoints.createBooking` → `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/seeker/bookings/store.php`
- `ApiEndpoints.listingDetail` → `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/listings/show.php`

**For broader web architecture** (booking workflow, session/auth guards, DB schema, `.htaccess` routing): read `/Applications/XAMPP/xamppfiles/htdocs/pestify/CLAUDE.md` if present, but treat it cautiously — this session's audit found the web app itself has significant internal inconsistencies (see "Known backend gotchas").

**Don't trust the web app's PHP as an automatically-correct spec.** It's the source of truth for *field names and envelope shape*, but this session found real bugs in it too (status-string drift across files, dead/unreachable code, an empty required include, a PHP syntax error in `seeker/payment-success.php`). When a web PHP file and the mobile API layer (`api/v1/`) disagree, prefer whichever one `includes/booking_workflow_helper.php` (the canonical FSM) agrees with — that file uses `on_going`, `waiting_for_remaining_payment`, `waiting_for_seeker_confirmation`, `waiting_for_provider_confirmation` as the canonical spellings.

**When a new endpoint needs to be created** on the PHP side: follow the patterns in existing files in `api/v1/`. The `_bootstrap.php` file at the root of `api/v1/` sets up `db()`, `ok()`, `fail()`, `req_inp()`, `inp()`, `allow()`, `require_seeker()`, `current_provider()` helpers — read it first.

---

## Backend relationship

All data comes from the PHP API layer at `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/`. XAMPP must be running with Apache and MySQL before launching the Flutter app.

**API base URL** (set in `lib/core/api/api_endpoints.dart`):
- Flutter web: `http://localhost/pestify/api/v1`
- Android emulator: `http://10.0.2.2/pestify/api/v1`
- Real device: swap to LAN IP (e.g. `192.168.x.x/pestify/api/v1`)

**Auth:** JWT Bearer tokens. The PHP backend signs HS256 tokens with a 30-day expiry. Flutter stores the token in `flutter_secure_storage` via `lib/core/auth/auth_storage.dart`.

**Envelope contract:** Every PHP endpoint returns `{"ok": true, "data": ...}` on success or `{"ok": false, "error": "..."}` on failure. `ApiClient.unwrap(response)` validates the envelope and returns `body['data']`. Some endpoints (e.g. `show.php`) return extra top-level keys alongside `data` (e.g. `reviews`) — those must be read from `response.data` directly before calling `unwrap`, or extracted by reading `body['reviews']` after checking `body['ok'] == true`.

**When making PHP-side changes:** The corresponding endpoint file lives in `/Applications/XAMPP/xamppfiles/htdocs/pestify/api/v1/<path>`. Reference `FLUTTER_PLAN.md` in the PHP project root for the full endpoint map, if present.

---

## Local dev environment (macOS)

- **XAMPP root:** `/Applications/XAMPP/xamppfiles/`
- **MySQL CLI:** `/Applications/XAMPP/xamppfiles/bin/mysql -u root pestify`
- **Database:** `pestify` (imported from `pestify.sql` in this Flutter project's root — that dump is the current known-good schema + seed data)
- **PHP error log:** `/Applications/XAMPP/xamppfiles/logs/php_error_log` — check here first for any 500 error or unexpected empty response
- **Apache access log:** `/Applications/XAMPP/xamppfiles/logs/access_log` — useful for confirming what HTTP method/status an actual request hit (e.g. diagnosing a GET-vs-POST mismatch)

**Starting MySQL when it's stopped:** plain `sudo /Applications/XAMPP/xamppfiles/ctlscript.sh start mysql` fails in a non-interactive shell (no TTY for the password prompt). Use the macOS admin-password dialog instead, which works from any shell:
```bash
osascript -e 'do shell script "/Applications/XAMPP/xamppfiles/ctlscript.sh start mysql" with administrator privileges'
```
Same pattern works for `start apache` / `start all`.

**Crafting a test JWT for curl-testing an endpoint directly** (bypasses needing to log in through the app — useful for isolating whether a bug is server-side or client-side):
```bash
cd /Applications/XAMPP/xamppfiles/htdocs/pestify && php -r '
define("JWT_SECRET", "pestify_jwt_s3cr3t_CHANGE_IN_PRODUCTION");
function _b64u($s){ return rtrim(strtr(base64_encode($s), "+/", "-_"), "="); }
$claims = ["sub"=>USER_ID, "user_type"=>"seeker", "iat"=>time(), "exp"=>time()+3600];
$h = _b64u(json_encode(["typ"=>"JWT","alg"=>"HS256"]));
$p = _b64u(json_encode($claims));
echo "$h.$p." . _b64u(hash_hmac("sha256", "$h.$p", JWT_SECRET, true));
'
```
(Replace `USER_ID` with a real `users.id`; swap `user_type` for `provider`/`admin`/`portal_staff` as needed.) `JWT_SECRET` is read from `api/v1/_bootstrap.php` — re-check it hasn't changed if this stops working.

---

## Stack

| Tool | Version / Notes |
|------|----------------|
| Flutter | Stable channel |
| Dart | null-safe |
| State management | `flutter_riverpod` — `StateNotifierProvider`, `Provider` |
| Routing | `go_router` with `StatefulShellRoute` for the 4-tab seeker shell |
| HTTP | `dio` with JWT interceptor + error interceptor |
| Images | `cached_network_image` |
| Auth storage | `flutter_secure_storage` (via `AuthStorage` helper) |
| Payments | `webview_flutter` — opens PayMongo Checkout URL in-app |
| QR code display | `qr_flutter` |
| QR code scanning | `mobile_scanner` |
| Star ratings | `flutter_rating_bar` |
| File/image picker | `image_picker` |
| Deep links / maps | `url_launcher` |
| Date formatting | `intl` |
| JWT decoding | `jwt_decoder` |

---

## Folder layout

```
lib/
  main.dart                        App entry point — ProviderScope, theme, router
  core/
    api/
      api_client.dart              Dio provider, _JwtInterceptor, _ErrorInterceptor, ApiClient.unwrap()
      api_endpoints.dart           All endpoint path constants (see table below)
    auth/
      auth_state.dart              AuthState model, AuthNotifier (StateNotifier), authProvider
      auth_storage.dart            flutter_secure_storage wrapper (getToken / saveToken / deleteToken)
    router/
      app_router.dart              GoRouter config, _SeekerShell (bottom nav), all route definitions
    theme/
      app_theme.dart               AppTheme tokens + ThemeData
  features/
    auth/
      auth_api.dart                login(), register(), verifyOtp(), resendOtp(), forgotPassword()
      screens/
        splash_screen.dart         Calls AuthNotifier.init(), redirects by role
        login_screen.dart          Clerk/Linear style — labels above fields, radial green circles
        register_screen.dart       Registration form
        otp_screen.dart            OTP verification after register
        forgot_password_screen.dart
    seeker/
      seeker_api.dart              All seeker API methods (see SeekerApi table below)
      screens/
        home_screen.dart           Full-width service row cards with ratings + "View Details"
        providers_screen.dart      Provider listing/search
        provider_detail_screen.dart Provider profile — 3-tab layout
        listing_detail_screen.dart  Service detail — FB mobile style, gallery + reviews + provider bio
        book_service_screen.dart   Booking form — name/contact pre-fill, map picker, payment cards
        my_bookings_screen.dart    Seeker's booking list
        booking_detail_screen.dart Single booking detail + QR token display
        qr_display_screen.dart     Full-screen QR code to show to technician
        enter_cn_screen.dart       Enter provider's control number (seeker verification step)
        payment_webview_screen.dart PayMongo checkout WebView
        payment_confirm_screen.dart Post-payment confirmation
        remaining_payment_screen.dart Downpayment → remaining balance payment
        submit_review_screen.dart  Star rating + written review submission
        messages_screen.dart       Telegram-style inbox with gradient avatars + inline search
        message_thread_screen.dart Individual conversation thread
        notifications_screen.dart  Booking status + system notifications
        profile_screen.dart        Spotify/Airbnb style — navy hero, straddling avatar, settings fields
  shared/
    widgets/
      booking_status_chip.dart     Colored status badge chip — takes `hasStarted` to disambiguate legacy statuses (see "Booking status literal drift")
      error_banner.dart            Dismissable red error chip
      loading_button.dart          ElevatedButton with loading spinner
    utils/
      booking_status_utils.dart    normalizeBookingStatus() — canonicalizes legacy/web-app status spellings; read this before writing ANY code that branches on `booking['status']`
```

---

## API endpoints

All constants live in `lib/core/api/api_endpoints.dart`.

| Constant | Path | PHP file |
|----------|------|----------|
| `login` | `/auth/login.php` | `api/v1/auth/login.php` |
| `register` | `/auth/register.php` | `api/v1/auth/register.php` |
| `verifyOtp` | `/auth/verify-otp.php` | `api/v1/auth/verify-otp.php` |
| `resendOtp` | `/auth/resend-otp.php` | `api/v1/auth/resend-otp.php` |
| `forgotPassword` | `/auth/forgot-password.php` | `api/v1/auth/forgot-password.php` |
| `categories` | `/categories/index.php` | `api/v1/categories/index.php` |
| `listings` | `/listings/index.php` | `api/v1/listings/index.php` |
| `listingDetail` | `/listings/show.php` | `api/v1/listings/show.php` |
| `providers` | `/providers/index.php` | `api/v1/providers/index.php` |
| `providerDetail` | `/providers/show.php` | `api/v1/providers/show.php` |
| `bookings` | `/seeker/bookings/index.php` | `api/v1/seeker/bookings/index.php` |
| `bookingDetail` | `/seeker/bookings/show.php` | `api/v1/seeker/bookings/show.php` |
| `createBooking` | `/seeker/bookings/store.php` | `api/v1/seeker/bookings/store.php` |
| `cancelBooking` | `/seeker/bookings/cancel.php` | `api/v1/seeker/bookings/cancel.php` |
| `confirmPayment` | `/seeker/bookings/confirm-payment.php` | `api/v1/seeker/bookings/confirm-payment.php` |
| `remainingPayment` | `/seeker/bookings/remaining-payment.php` | `api/v1/seeker/bookings/remaining-payment.php` — **POST only**, despite the Dart method being named `getRemainingPayment()` |
| `verifySeeker` | `/seeker/bookings/verify.php` | `api/v1/seeker/bookings/verify.php` |
| `submitReview` | `/seeker/bookings/feedback.php` | `api/v1/seeker/bookings/feedback.php` |
| `confirmComplete` | `/seeker/bookings/confirm-complete.php` | `api/v1/seeker/bookings/confirm-complete.php` — seeker confirms a completed service |
| `rescheduleRespond` | `/seeker/bookings/reschedule-respond.php` | `api/v1/seeker/bookings/reschedule-respond.php` — accept/reject a provider's reschedule proposal |
| `emergencyNow` | `/seeker/bookings/emergency-now.php` | `api/v1/seeker/bookings/emergency-now.php` — request immediate service |
| `retryPayment` | `/seeker/bookings/retry-payment.php` | `api/v1/seeker/bookings/retry-payment.php` — re-opens checkout for a booking stuck `pending`/`accepted` + `unpaid` |
| `notifications` | `/notifications/index.php` | `api/v1/notifications/index.php` |
| `notifCount` | `/notifications/count.php` | `api/v1/notifications/count.php` |
| `notifMarkRead` | `/notifications/mark-read.php` | `api/v1/notifications/mark-read.php` |
| `messages` | `/messages/index.php` | `api/v1/messages/index.php` |
| `messageThread` | `/messages/thread.php` | `api/v1/messages/thread.php` |
| `sendMessage` | `/messages/send.php` | `api/v1/messages/send.php` |
| `profile` | `/user/profile.php` | `api/v1/user/profile.php` |

---

## SeekerApi methods (`lib/features/seeker/seeker_api.dart`)

Accessed via `ref.read(seekerApiProvider)`.

| Method | Returns | Notes |
|--------|---------|-------|
| `getListings({search, categoryId, page})` | `Map` (full body with `data` list + pagination) | Returns raw body, not just `data`, so callers can access `meta` |
| `getListingDetail(id)` | `Map` (listing fields + `reviews` key merged in) | `show.php` puts reviews at root level; this method merges them under `listing['reviews']` |
| `createBooking({listingId, address, preferredDate, preferredTime, paymentMethod, fullName?, contactNumber?})` | `Map` with `id`, `checkout_url` | Returns PayMongo checkout URL; push to `/seeker/payment` with it |
| `getBookings()` | `List` | All seeker bookings |
| `getBookingDetail(id)` | `Map` | Single booking; includes `qr_token` when status is `starting` |
| `cancelBooking(id)` | `void` | `pending`/`accepted`/`waiting_for_provider_confirmation` only |
| `verifySeeker({availId, code})` | `Map` | Seeker enters provider's control number |
| `submitReview({availId, rating, comment, image?})` | `Map` | Field sent as `feedback` (not `comment`) to match PHP. Rejects with 409 if already reviewed — check for that before retrying |
| `getRemainingPayment(bookingId)` | `Map` with `checkout_url` | **POST despite the name** — creates a fresh PayMongo session every call (voids prior pending ones server-side). Downpayment flow's second payment |
| `confirmServiceComplete(availId)` | `void` | Seeker confirms a completed service. Only valid once status is (normalized) `waiting_for_seeker_confirmation` — see "Booking status literal drift" |
| `respondToReschedule({availId, accept})` | `void` | Accept/reject a provider's proposed new date/time |
| `requestEmergencyNow(availId)` | `Map` | Only valid for `accepted`/`preparing` + `paid`/`partial` payment |
| `retryPayment(bookingId)` | `Map` with `checkout_url` | Recovers a booking stuck `pending`/`accepted` + `unpaid` (e.g. the initial PayMongo session failed to create) |
| `getProviders({search, categoryId, page})` | `Map` | |
| `getProviderDetail(id)` | `Map` | Provider profile + listings |
| `getMessages()` | `List` | Thread list |
| `getMessageThread(providerId)` | `Map` with `other` (provider info) + `data` (messages list) | |
| `sendMessage({to, message})` | `void` | Field name is `to`, not `receiver_id` |
| `getNotifications()` | `List` | |
| `getNotifCount()` | `int` | Unread count |
| `markNotifsRead()` | `void` | |
| `getProfile()` | `Map` | Fields: `first_name`, `last_name`, `email`, `phone`, `address`, `profile_image`, etc. |
| `updateProfile({firstName, lastName, phone, address})` | `Map` | |
| `uploadAvatar(file)` | `String` (new image URL) | Multipart POST |

---

## Routes

Defined in `lib/core/router/app_router.dart`.

| Path | Screen | Extra / params |
|------|--------|----------------|
| `/splash` | `SplashScreen` | — |
| `/login` | `LoginScreen` | — |
| `/register` | `RegisterScreen` | — |
| `/otp?email=...` | `OtpScreen` | `email` query param |
| `/forgot-password` | `ForgotPasswordScreen` | — |
| `/seeker/home` | `HomeScreen` | tab 0 |
| `/seeker/bookings` | `MyBookingsScreen` | tab 1 |
| `/seeker/messages` | `MessagesScreen` | tab 2 |
| `/seeker/profile` | `ProfileScreen` | tab 3 |
| `/seeker/providers` | `ProvidersScreen` | — |
| `/seeker/provider/:id` | `ProviderDetailScreen` | `id` path param |
| `/seeker/listing/:id` | `ListingDetailScreen` | `id` path param |
| `/seeker/book` | `BookServiceScreen` | extra: `{'listingId': int}` (also accepts `listing_id`) |
| `/seeker/payment` | `PaymentWebViewScreen` | extra: `{'checkoutUrl': String, 'bookingId': int}` |
| `/seeker/payment-confirm` | `PaymentConfirmScreen` | extra: `int` (bookingId) |
| `/seeker/booking/:id` | `BookingDetailScreen` | `id` path param |
| `/seeker/qr` | `QrDisplayScreen` | extra: `{'qrToken': String}` |
| `/seeker/verify` | `EnterCnScreen` | extra: `{'availId': int}` |
| `/seeker/remaining-payment` | `RemainingPaymentScreen` | extra: `{'bookingId': int}` |
| `/seeker/review` | `SubmitReviewScreen` | extra: `{'availId': int}` |
| `/seeker/notifications` | `NotificationsScreen` | — |
| `/seeker/message-thread` | `MessageThreadScreen` | extra: `{'providerId': int, 'providerName': String}` |
| `/provider/home` | placeholder | Phase 2 |
| `/admin/dashboard` | placeholder | Phase 3 |
| `/portal/dashboard` | placeholder | Phase 3 |

**Auth redirect rules:**
- Any `/seeker/*` route → redirect to `/login` if not logged in.
- Auth screens (`/login`, `/register`, `/otp`, `/forgot-password`) → redirect to role home if already logged in.
- Splash is exempt — it runs `AuthNotifier.init()` then redirects imperatively.

---

## Auth state

`AuthState` (in `lib/core/auth/auth_state.dart`) is a Riverpod `StateNotifier`. Fields decoded from the JWT:

| Field | Source | Values |
|-------|--------|--------|
| `token` | raw JWT string | `null` when logged out |
| `userType` | JWT claim `user_type` | `'seeker'`, `'provider'`, `'admin'`, `'portal_staff'` |
| `userId` | JWT claim `sub` | numeric id |
| `role` | JWT claim `role` | `'hr'`, `'finance'`, etc. — only for admin/portal_staff |

`authState.isLoggedIn` is the canonical logged-in check. Never test `token` directly.

---

## AppTheme tokens (`lib/core/theme/app_theme.dart`)

| Token | Value | Use |
|-------|-------|-----|
| `AppTheme.primary` | `#2E8B57` | Brand green — buttons, highlights, stars |
| `AppTheme.primaryLight` | `#48BB78` | Lighter green accents |
| `AppTheme.navy` | `#1A1F3A` | Headings, nav icons, body text |
| `AppTheme.indigo` | `#4C51BF` | Secondary CTA, category chips |
| `AppTheme.surface` | `#F8FAFC` | Scaffold background |
| `AppTheme.cardColor` | `#FFFFFF` | Card backgrounds |
| `AppTheme.border` | `#E2E8F0` | Dividers, input borders |
| `AppTheme.textMuted` | `#718096` | Secondary labels, hints |
| `AppTheme.starColor` | `#F59E0B` | `RatingBarIndicator` fill color |

**Dart const rules:**
- `AppTheme.primary` is a `static const Color` — it IS a compile-time constant. Use it directly: `color: AppTheme.primary`. Do NOT write `const AppTheme.primary` (that's a constructor call, not a field reference).
- `AppBar(...)` cannot be `const` even with a `const Text` title — write `AppBar(title: const Text(...))`.
- `withValues(alpha: x)` not `withOpacity(x)` — `withOpacity` is deprecated in recent Flutter.

---

## Booking status literal drift — READ THIS before touching any booking-status code

The PHP backend does **not** use one consistent spelling per booking state. Three different parts of the codebase (the legacy web app, the mobile API layer, and the Phase-3 provider-portal CRM) independently invented spellings for the same states, and — worse — one spelling is reused for two genuinely different meanings. This was discovered and worked around this session; do not "clean it up" by picking one spelling without re-reading `lib/shared/utils/booking_status_utils.dart`'s doc comment first, since the workaround is load-bearing.

**Known spelling variants for the same states:**
| Canonical (mobile FSM, `includes/booking_workflow_helper.php`) | Legacy variant(s) | Written by |
|---|---|---|
| `on_going` | `ongoing` | legacy web pages |
| `waiting_for_remaining_payment` | `waiting_remaining_payment` | `seeker/my-requests.php` |
| `waiting_for_seeker_confirmation` | `waiting_provider_confirmation` (no "for"!), `waiting_seeker_information`, `waiting_seeker_confirmation` | `seeker/my-requests.php`'s normalization layer |
| `starting` | `on_the_way` | provider-portal CRM (Phase 3) |
| `on_going` | `in_progress` | historical only — see below |

**`in_progress` is now legacy, not a status new code should ever produce.** Until a 2026-09-01 session, `includes/ControlNumberService.php`'s dual control-number verification (`unlockService()`, called by both `api/v1/seeker/bookings/verify.php` and `api/v1/provider/requests/verify.php`) wrote `status = 'in_progress'` directly the moment both sides' codes matched — completely skipping `starting` and never generating a `qr_token`. That meant the QR flow (`qr_display_screen.dart`, `enter_cn_screen.dart`'s counterpart on the provider side) was **unreachable in practice**: nothing in any code path a real user could hit ever populated `qr_token`, because the one function that does (`generateQrToken()` inside `transitionBookingStatus()`'s `BK_STARTING` case) was never called by anything wired up to a working app. `provider/service-requests.php`'s own separate inline dual-verification handler had the *same* gap — it hand-rolled its own `UPDATE ... SET status='starting'` without ever generating a token either.

Both were fixed in the same session to advance to `starting` (with a freshly generated `qr_token`) instead — the intended design is: dual code verification ("Start Early") confirms both sides agreed to start, often *before* the technician is on-site, and a **QR scan on arrival** (`scanQrAndStartService()`) is the actual proof-of-arrival step that advances `starting → on_going`. This makes the outcome symmetric regardless of which side (seeker via mobile, or provider via the web dashboard) submits the completing code second — previously, whichever side finished last determined whether you got `starting` (web finishing) or `in_progress` (mobile finishing), which is exactly the kind of order-dependent bug this drift-tracking section exists to catch. `normalizeBookingStatus()` still maps `in_progress → on_going` for any pre-existing bookings that already have that value, and `BookingStatusChip`/`_StatusTimeline` render it correctly — but no verification flow will ever write it again going forward.

**The dangerous one:** `waiting_provider_confirmation` (no "for") has **three unrelated meanings** depending on which part of the system wrote it:
1. On the seeker web app, it means "the seeker must confirm the service is done" (despite the string literally saying "provider").
2. On the mobile API, the canonical `waiting_for_provider_confirmation` (WITH "for") is a *different string* meaning "the provider must confirm" (e.g. after a downpayment's remaining balance is paid).
3. On the provider-portal CRM (Phase 3), the *same no-"for" string* means "a portal staffer just accepted a pending request" — an early, pre-service state.

If you write code that trusts `status == 'waiting_provider_confirmation'` to mean "ready to finalize," a booking that a portal staffer just accepted could be completed by the seeker with zero service having happened. **`api/v1/seeker/bookings/confirm-complete.php` disambiguates this using `dual_verified_at`** (only stamped once a booking reaches `starting` via the seeker+provider control-number handshake — a freshly-accepted booking can never have it set) — mirror that guard (`dual_verified_at` non-empty AND not the MySQL zero-date sentinel `'0000-00-00 00:00:00'`) anywhere else you accept this status family.

**The fix:** `lib/shared/utils/booking_status_utils.dart` exports `normalizeBookingStatus(String status, {bool hasStarted = true})`. Always run a raw `booking['status']` through this before comparing it to a canonical value, switching on it for UI, or deciding what actions to offer. Pass `hasStarted` (derived from `dual_verified_at`) whenever you have it — omitting it defaults to `true`, which is safe for the *unambiguous* canonical spellings but will mislabel the ambiguous legacy family if a booking is actually in the portal's early-accepted state.

`BookingStatusChip` and `_StatusTimeline` (in `booking_detail_screen.dart`) both already thread `hasStarted` through correctly — use them as the reference implementation. `my_bookings_screen.dart`'s card list computes its own local `hasStarted` from the row's `dual_verified_at` (returned by `bookings/index.php` via `av.*`).

**Also check `api/v1/seeker/bookings/index.php`'s `status=active` filter** if you add a new legacy spelling anywhere — that `IN (...)` list must include every spelling the normalizer recognizes, or bookings in that state become invisible in My Bookings (this exact gap was found and fixed this session).

---

## Key patterns

### Reading API data safely
PHP columns come back as `String` or `null` even for numeric values. Always parse defensively:
```dart
final double price = double.tryParse(data['price']?.toString() ?? '') ?? 0;
final int count = int.tryParse(data['review_count']?.toString() ?? '') ?? 0;
final bool isEco = data['is_eco_friendly'] == true || data['is_eco_friendly'] == 1;
```

### Navigating with extra
```dart
// Push with extra
context.push('/seeker/book', extra: {'listingId': listing['id'] as int});

// Read extra in router
final Map<String, dynamic>? extra = state.extra as Map<String, dynamic>?;
final int listingId = extra?['listingId'] as int? ?? 0;
```

### SeekerApi in a widget
```dart
final SeekerApi api = ref.read(seekerApiProvider);
final Map<String, dynamic> listing = await api.getListingDetail(id);
```

### show.php response shape
`listings/show.php` returns:
```json
{ "ok": true, "data": { ...listing fields... }, "reviews": [ ...review objects... ] }
```
`getListingDetail()` merges `body['reviews']` into the returned map under the key `reviews`. Access them as `listing['reviews']`.

### sendMessage field name
The PHP `messages/send.php` reads `$to = req_inp('to', ...)`. Always send `'to': receiverId`, never `'receiver_id'`.

### Booking payment_method values
`store.php` accepts `'full_payment'` or `'downpayment'`. Flutter should send these exact strings (or `'full'` which the PHP normalises to `'full_payment'`).

---

## Known backend gotchas (recurring bug classes — check for these before assuming a bug is Flutter-side)

This session found the same handful of PHP bug patterns repeatedly across different endpoints. When something fails mysteriously, check these first — they've each bitten multiple endpoints already:

1. **Missing `AUTO_INCREMENT` on a table's `id` column.** Found on both `messages.id` (earlier session) and `service_reviews.id` (this session) — both let the *first-ever* insert silently succeed with `id=0`, then crashed on the second insert with "Duplicate entry '0' for key 'PRIMARY'". If a new table's INSERT ever fails with a duplicate-PK error despite auto-increment being intended, run `DESCRIBE <table>` and check the `Extra` column — `ALTER TABLE <table> MODIFY id INT(11) NOT NULL AUTO_INCREMENT;` fixes it without disturbing existing rows.
2. **Response envelope not nested under `data`.** `ok()` in `_bootstrap.php` does `array_merge(['ok' => true], $data)` — if an endpoint calls `ok(['foo' => 'bar'])` instead of `ok(['data' => ['foo' => 'bar']])`, the result is a **flat** body (`{"ok":true,"foo":"bar"}`), and `ApiClient.unwrap()` (which does `body['data']`) silently returns `null`. The Flutter-side symptom is a generic exception ("Payment check failed, retrying...", a `TypeError`, etc.) that looks unrelated to the real cause. Found and fixed in `confirm-payment.php` this session — **always wrap an endpoint's payload in `'data' => [...]`** unless deliberately adding a sibling key like `review`/`receipts` (which is fine — see `show.php`, and remember to merge those in on the Dart side same as `getBookingDetail()` does).
3. **HTTP method mismatch between Flutter and `allow()`.** Two confirmed instances: `confirm-payment.php` was `allow('GET')` while Flutter POSTed (fixed by widening to `allow('GET','POST')`); `remaining-payment.php` is `allow('POST')` while `getRemainingPayment()` used `_dio.get()` (fixed by switching Flutter to POST — see "Recent work log"). A 405 response from a real endpoint is the tell; check the PHP's `allow(...)` call against the actual Dio verb.
4. **Wrong column name copied from a different schema version.** `store.php` inserted into `availed_services.listing_id`, but the live table only has `service_id` — same bug also existed in `provider/requests/index.php` and `show.php`'s `JOIN`. If an INSERT/UPDATE/JOIN references a column, verify it exists with `DESCRIBE <table>` rather than trusting the PHP looks right — table schemas have drifted from what some PHP files assume.
5. **Field name mismatch between Flutter's JSON keys and PHP's `req_inp()`/`inp()` calls.** `submitReview()` sent `'comment'`; PHP read `inp('feedback')` — silently dropped the seeker's written review with no error. Always grep the actual PHP file for the exact `inp('...')` / `req_inp('...')` key names rather than assuming REST-y naming.
6. **PDO exception handling that reaches `ok()` even after a failed write.** A bare `catch (Exception $e) { /* non-fatal */ }` around a DB write, followed by unconditional `ok([...])`, tells the client "success" even when the write rolled back. `retry-payment.php` / `remaining-payment.php` now `catch (Throwable $e)`, `error_log(...)`, then `fail(..., 500)` — copy that pattern for any new endpoint that writes then reports a checkout URL or similar.
7. **DB connection charset is `utf8` (3-byte), not `utf8mb4`, even though every table/column already is.** `config/database.php` ran `$this->conn->exec("set names utf8")` — any INSERT/UPDATE containing a 4-byte character (most emoji) fails with `SQLSTATE[22007]: Invalid datetime format: 1366 Incorrect string value: '\xF0\x9F\x9A\x80...'`. That SQLSTATE is misleading — MySQL/PDO reuses the same generic code for both real datetime errors *and* string/charset truncation, so this reads like a date bug when it's actually an emoji-in-a-3-byte-connection bug. Found via `includes/ControlNumberService.php`'s dual-verification notification message containing 🚀. Fixed by changing `database.php` to `set names utf8mb4`. If you ever see "Invalid datetime format" from a query that has no dates in it, suspect this class of bug first.
8. **PHP and MySQL run on different timezones.** `php.ini`'s `date.timezone` was left at XAMPP's default `Europe/Berlin`, while MySQL's server clock follows the OS's actual timezone (`Asia/Manila` — this app is Philippines/Cavite-only). Any PHP-side `date('Y-m-d')` comparison against a MySQL-stored date (e.g. "is today the service day yet?" checks) could be off by several hours, worst right around midnight Philippine time. Fixed with `date_default_timezone_set('Asia/Manila')` at the top of `config/config.php`. If a date-gate check rejects something that should clearly be allowed "today," check this before assuming the gate logic itself is wrong.
9. **Missing `AUTO_INCREMENT` is not limited to `messages.id`/`service_reviews.id`.** Also found on `control_number_audit.id` — every dual-verification attempt silently failed to write its audit-log row (caught internally, so it never surfaced as a user-facing error, just a missing audit trail). Same fix: `ALTER TABLE control_number_audit MODIFY id INT(11) NOT NULL AUTO_INCREMENT;`. Worth a quick `DESCRIBE` sweep of any table that logs/audits something whenever a "why is nothing showing up in this log table" question comes up.
10. **`service_listings.pricing_type` real ENUM is `('fixed','per_sqft','hourly','custom')` — not `per_sqm`.** `api/v1/provider/listings/store.php`'s validation list had `per_sqm` (copied from a different schema version, matching a stale value CLAUDE.md itself used to document). Under `STRICT_TRANS_TABLES` (this DB's `sql_mode`), inserting an out-of-enum value throws an uncaught `PDOException` → a raw 500, not a clean JSON error. Fixed `store.php` and added the same validation to `update.php` (which previously accepted any string). **The Flutter provider listing form's pricing-type options must stay `fixed` / `per_sqft` / `hourly` / `custom`.**
11. **The `uploads/` tree's Unix permissions block the Apache worker from writing new files.** On this macOS/XAMPP setup Apache runs as `daemon:daemon` (see `httpd.conf`'s `User`/`Group`), but `uploads/*` subdirectories are owned by the dev user with mode `0755` — `daemon` falls under "other" and has no write bit, so `move_uploaded_file()` silently fails with "Failed to save uploaded image." (or the equivalent in whichever endpoint). This had never been hit before because no listing/provider logo image had ever actually been uploaded through a running Apache process (all `images`/`logo_url` columns were `NULL` in the seed data). Fixed for this session with `chmod -R o+w uploads/`; if a fresh clone of this repo starts throwing the same "Failed to save uploaded image" error, re-run that chmod.
12. **`api/v1/providers/show.php` 500'd for every single caller, always.** Its SELECT referenced `p.phone` — but `providers` has no `phone` column; the phone number lives on the linked `users` row (`p.user_id → users.id`), already joined into the query as `u`. Every other file that needs a provider's phone gets this right (`seeker/bookings/show.php`, `admin/bookings/show.php` both correctly select `u_p.phone` from their own provider-side `users` join) — only `show.php` had the wrong alias. Found while testing the new guest-accessible `/seeker/provider/:id` route (see "Landing page" below), but this bug predates that work and has nothing to do with guest access specifically — it broke `provider_detail_screen.dart`'s "View Provider" for every seeker, logged in or not, the whole time that screen has existed. Fixed by selecting `u.phone` instead of `p.phone`.
13. **Beyond the 500 above, `provider_detail_screen.dart` and `providers/show.php` had never actually agreed on a response shape.** Once #12 was fixed, the page loaded but showed empty Services and Reviews tabs (reported directly by a user testing "View Provider & Book" from the new DSS results screen). Root cause was a stack of independent mismatches, none related to guest access — this screen has apparently never worked correctly for anyone:
    - `getProviderDetail()` in `seeker_api.dart` didn't merge `show.php`'s sibling `listings`/`reviews` keys into the returned map at all (unlike the already-correct `getListingDetail()`/`getBookingDetail()`) — so both were always empty regardless of what the PHP returned.
    - The screen read `d['rating']`; PHP returns `avg_rating`.
    - `_ServiceListingCard` read `data['image_url']` (PHP returns `images`, a list — needs `images.first` + `ApiEndpoints.resolveImageUrl()`), `data['is_emergency']` (PHP returns `is_emergency_available`), and cast `data['id'] as int?` directly on a value that comes back as a numeric *string* from PDO (would have thrown the moment someone tapped a service card, even after the empty-list issue was fixed).
    - `_ReviewCard` read `data['comment']` (PHP returns `feedback`), `data['reviewer_name']` (PHP returns separate `first_name`/`last_name` — never combined), and `data['image_url']` (PHP's reviews query didn't even select `feedback_image` at all).
    - `is_eco_friendly` and `feedback_image` weren't in `show.php`'s SELECTs to begin with — added both.
    - `logoUrl` was passed straight to `CachedNetworkImage` without `ApiEndpoints.resolveImageUrl()` — same class of bug as the seeker-side image gap noted in the Phase 2 log below, now fixed for this one screen.

    **If you touch this screen again**, re-verify every field name against a fresh `curl` of `providers/show.php` rather than trusting the Dart side — the drift here was total, not a one-off typo.

---

## Packages not available

These packages are **not** in `pubspec.yaml`. Do not generate code that imports them:
- `google_maps_flutter` — use `webview_flutter` + Leaflet HTML for maps
- `geolocator` — no GPS. Use Nominatim reverse-geocoding after the user picks a point on the Leaflet map
- `google_fonts` — no CDN fonts; use system fonts or inline `@font-face` in WebView HTML
- `provider` (the non-Riverpod package) — use `flutter_riverpod` only

---

## Running & testing

```bash
# Start the dev server
flutter run -d web-server --web-port 3000

# Analyze for errors
flutter analyze --no-fatal-infos

# Build web
flutter build web
```

XAMPP must be running (Apache + MySQL) before starting the Flutter app. The PHP backend is at `http://localhost/pestify/api/v1`.

---

## Phase 2 — Provider

**Status: built.** All screens below exist (`lib/features/provider/`), wired into a `/provider/*` `StatefulShellRoute` (Dashboard / Listings / Requests / Messages tabs) in `app_router.dart`, gated by a role guard in the router's global `redirect` (must be logged in AND `userType == 'provider'`, else bounced to `/login` or the caller's own home). `lib/features/provider/provider_api.dart` (`ProviderApi`, `providerApiProvider`) mirrors `SeekerApi`'s conventions. Verified end-to-end against the real PHP/MySQL backend (dashboard stats, listing create/edit/deactivate with real image upload, full request-status state machine walk, dual-code verify, QR scan, messaging round-trip, notifications, profile read/write) plus a live browser pass of the first batch (login → dashboard → listings → edit form → requests → request detail all render real data correctly).

**Not yet built:** push notifications, and anything from "Provider portal (Phase 3)" below (staff management, HR/Finance/CRM, subscriptions) — that's a separate, larger phase, explicitly deferred.

Provider role (`user_type: 'provider'`) logs in via the shared `auth/login.php` endpoint. After login the JWT payload is identical in shape; only `user_type` differs. Route them to `/provider/home`.

**Before building this phase, re-read "Booking status literal drift" above.** An audit this session found the web app's provider-facing pages (`provider/service-requests.php`) are internally inconsistent with the mobile API layer documented below: they use different literal spellings for the same statuses in places, and the web app's control-number verification uses a `PCV` prefix in one code path vs. `PCF`/`PCP` in `includes/ControlNumberService.php` (which the mobile API's `provider/requests/verify.php` actually uses). **Build against the `api/v1/provider/*` endpoints and `includes/ControlNumberService.php`/`includes/booking_workflow_helper.php` as the source of truth, not the legacy web pages** — the web pages have their own bugs (including a `provider/verify-service.php` that calls an undefined function in an empty required file, and a disabled dead-code block) that predate this Flutter work and shouldn't be replicated.

### Provider screens to build

| Route | Screen | API | Notes |
|-------|--------|-----|-------|
| `/provider/home` | Dashboard | `GET provider/dashboard.php` | Stat cards: pending requests, active bookings, completed jobs, active listings, avg rating, recent 5 requests |
| `/provider/listings` | My Listings | `GET provider/listings/index.php` | Active/inactive toggle, "Add" FAB |
| `/provider/listings/create` | Create Listing | `POST provider/listings/store.php` | Title, description, price, pricing type (`fixed`/`per_sqft`/`hourly`/`custom` — see "Known backend gotchas" #10, NOT `per_sqm`), category, multi-image upload, emergency flag |
| `/provider/listings/edit` (extra: `listingId`) | Edit Listing | `POST provider/listings/update.php` | Same form as create, pre-filled |
| `/provider/requests` | Service Requests | `GET provider/requests/index.php` | Status filter tabs, newest first |
| `/provider/requests/:id` | Request Detail | `GET provider/requests/show.php`, `POST provider/requests/update-status.php` | Seeker info, action buttons, PCF-… code displayed |
| `/provider/verify` (extra: `availId`) | Enter Seeker Code | `POST provider/requests/verify.php` | Provider enters seeker's PCF-… code verbally read aloud on service day |
| `/provider/scan-qr` (extra: `availId`) | QR Scanner | `POST provider/requests/scan-qr.php` | `starting` bookings only; camera scanner + manual 6-char entry; strip dashes before POST |
| `/provider/messages` | Messages (tab) | `GET messages/index.php` | Inbox of clients who have messaged this provider |
| `/provider/message-thread` (extra: `userId`, `userName`) | Message Thread | `GET messages/thread.php`, `POST messages/send.php` | Opening the thread marks it read server-side |
| `/provider/notifications` | Notifications | `GET notifications/index.php`, `POST notifications/mark-read.php` | Booking + message items merged server-side; taps deep-link to the request or thread |
| `/provider/profile` | Profile & Settings | `GET/POST user/profile.php` | Company fields + personal fields + avatar; holds the logout action |

**Shared (not provider-specific) endpoints the provider app reuses:** `messages/*`, `notifications/*` and `user/profile.php` are guarded by `current_user()` — **not** `require_seeker()` — and each branches on `user_type` internally, so a provider JWT gets provider-shaped data (e.g. `notifications/index.php` describes the *seeker* who booked, and `profile.php` merges in the `providers` row's `company_name` / `logo_url` / `description` / `service_radius` and writes those back on POST). These were fully implemented server-side but had never been called by any client before Phase 2. `ProviderApi` has its own copies of these methods rather than reusing `SeekerApi`'s, so each role's API surface stays self-contained — `ProviderApi.updateProfile()` additionally takes the company fields, which `SeekerApi.updateProfile()` has no use for.

### Provider API endpoints

All require `Authorization: Bearer <provider_jwt>`. The PHP auth guard is `current_provider()` in `api/v1/_bootstrap.php`.

| Method | Path | Notes |
|--------|------|-------|
| GET | `provider/dashboard.php` | Summary stats |
| GET | `provider/listings/index.php` | Provider's own listings |
| POST | `provider/listings/store.php` | Create listing; images via multipart `FormData` |
| POST | `provider/listings/update.php` | Body: `id` + updated fields |
| POST | `provider/listings/delete.php` | Body: `id` |
| GET | `provider/requests/index.php` | All booking requests for this provider |
| GET | `provider/requests/show.php?id=X` | Single request detail incl. `control_number` (PCF-… seeker code) |
| POST | `provider/requests/update-status.php` | Body: `avail_id`, `status`, `notes`?. Allowed transitions: `pending→accepted`, `accepted→preparing`, `preparing→starting`, `ongoing→waiting_for_seeker_confirmation` (full) or `ongoing→waiting_for_remaining_payment` (downpayment). **`starting→on_going` is NOT allowed here — use `scan-qr.php`** |
| POST | `provider/requests/verify.php` | Body: `avail_id`, `control_number` (PCF-… code from seeker). Stamps `provider_verified_at` |
| POST | `provider/requests/scan-qr.php` | Body: `token` (raw 6-char, no dashes). Advances `starting → on_going`, stamps `qr_scanned_at` |

### Critical provider rules

- **`starting → on_going` is QR-gated.** Calling `update-status.php` with `status=on_going` returns 422. Always go through `scan-qr.php`.
- **Strip dashes before sending the QR token.** The seeker app displays `XXX-XXX`; the provider's manual-entry field should strip the dash before POSTing.
- **Listing images use multipart/form-data.** Use `dio`'s `FormData` + `MultipartFile.fromFile()` — never base64. Image paths come back relative (e.g. `uploads/services/x.jpg`); resolve them for display with `ApiEndpoints.resolveImageUrl()` (added this session) — don't pass the raw relative path straight to `CachedNetworkImage`.
- **`providers.status` enum is `('pending','active','inactive','suspended')` — there is no literal `'approved'` value.** "Approved" in product terms means `status == 'active'`. New provider accounts start `pending`; `provider_home_screen.dart` shows a banner (fed by `dashboard.php`'s `provider_status` field, added this session) whenever it isn't `active`.

---

## Phase 3 — Admin Panel & Provider Portal Staff

Two separate role families share the `/admin/*` and `/portal/*` routes. They use **separate JWT signing flows** and **different login endpoints**.

**Status: Admin panel's Dashboard + Provider approval slice is built** (`lib/features/admin/`) — a `/admin/*` `StatefulShellRoute` (Dashboard/Providers tabs) and `/admin/providers/:id`. There is **no separate `/admin/login`** — see "Login is centralized" immediately below, a deliberate change from this section's original design. Users, Bookings, Logs, Subscriptions, HR, and Finance admin screens are **not built** — still no UI, though (per the PHP survey below) every one of their backing endpoints already exists. Provider Portal Staff (`/portal/*`) is **entirely unbuilt** — still the literal placeholder — deliberately deferred.

### Login is centralized — not per-role-family

The Flutter app's login is a single form (`/login`, `AuthApi.login()`) for **every** role — seeker, provider, admin, and (once built) portal staff — mirroring the web app's shared `auth/login.php` login page rather than giving each role family its own login screen. `api/v1/auth/login.php` checks `admin_users` → `provider_staff` (portal staff) → `users` (seeker/provider) in that order, using whichever table's password matches first; a row matching the identifier but failing the password check falls through to the next tier rather than failing outright, exactly like the web. `AuthState.userType`/`role` are decoded from the JWT the same way regardless of which tier issued it, so the rest of the app (routing, guards) doesn't need to know or care which tier a session came from.

This superseded an earlier version of this file (and an earlier version of the Flutter app) that had Admin/Portal each on entirely separate login screens, endpoints, and — per the original table below — separate `flutter_secure_storage` keys. That table is kept for reference since `admin/auth/login.php` and `portal/auth/login.php` still exist as valid standalone PHP endpoints (e.g. for non-Flutter clients) and the JWT shape they issue is identical to what the centralized cascade issues — the Flutter app just no longer calls them directly:

| Role family | Standalone PHP login endpoint (not called by Flutter) | `user_type` | `role` claim |
|-------------|---------------------------------------------------------|-------------|-------------|
| Admin panel | `admin/auth/login.php` | `admin` | `super_admin` \| `admin` \| `hr` \| `finance` |
| Portal staff | `portal/auth/login.php` | `portal_staff` | `owner` \| `hr` \| `finance` \| `crm` |

Still true regardless of login path: do **not** mix JWTs — an admin JWT sent to a portal endpoint returns 403, and vice versa. The app uses one shared `AuthStorage`/`authProvider` session for all roles (same as Provider does relative to Seeker in Phase 2) — logging in as one role's account simply overwrites whatever session was active, which is an accepted, already-established constraint, not a gap introduced here.

The centralized response carries `must_change_password: true` when the account has a temp password (only ever true for admin/portal-staff — seeker/provider never sends this field). No dedicated Change Password screen is built yet, so `login_screen.dart` just shows a snackbar heads-up and proceeds to the normal role home rather than forcing a redirect — a known, deliberate gap until that screen exists.

---

### Admin panel screens to build

Routes live under `/admin/*`. The admin JWT is required for all. Sign-in happens at the shared `/login` (see "Login is centralized" above) — there's no `/admin/login`.

| Route | Screen | API | Roles | Status |
|-------|--------|-----|-------|--------|
| `/admin/dashboard` | Dashboard | `GET admin/dashboard.php` | super_admin, admin, hr, finance *(PHP is more permissive than this table implied — `require_admin_role('super_admin','admin','hr','finance')`)* | **Built** |
| `/admin/users` | Users list | `GET admin/users/index.php` | super_admin, admin | Not built |
| `/admin/users/:id` | User detail | `GET admin/users/show.php` | super_admin, admin | Not built |
| `/admin/providers` | Providers list | `GET admin/providers/index.php` | super_admin, admin | **Built** |
| `/admin/providers/:id` | Provider detail + approve/reject | `GET admin/providers/show.php`, `POST admin/providers/approve.php`, `POST admin/providers/reject.php` | super_admin, admin | **Built** |
| `/admin/bookings` | Bookings list | `GET admin/bookings/index.php` | super_admin, admin | Not built |
| `/admin/bookings/:id` | Booking detail | `GET admin/bookings/show.php` | super_admin, admin | Not built |
| `/admin/subscriptions` | Subscription plans | `GET admin/subscription-plans/index.php`, `POST admin/subscription-plans/store.php`, `POST admin/subscription-plans/update.php`, `POST admin/subscription-plans/activate.php`, `POST admin/subscription-plans/expire.php` | super_admin only | Not built |
| `/admin/logs` | Activity logs | `GET admin/logs/index.php` | super_admin, admin | Not built |
| `/admin/hr/employees` | HR — Employees | `GET admin/hr/employees/index.php` | super_admin, admin, hr | Not built |
| `/admin/hr/attendance` | HR — Attendance | `GET admin/hr/attendance/index.php` | super_admin, admin, hr | Not built |
| `/admin/hr/payroll` | HR — Payroll | `GET admin/hr/payroll/index.php` | super_admin, admin, hr | Not built |
| `/admin/hr/recruitment` | HR — Recruitment | `GET admin/hr/recruitment/index.php` | super_admin, admin, hr | Not built |
| `/admin/finance/income` | Finance — Income | `GET admin/finance/income/index.php` | super_admin, admin, finance | Not built |
| `/admin/finance/expenses` | Finance — Expenses | `GET admin/finance/expenses/index.php` | super_admin, admin, finance | Not built |
| `/admin/finance/requests` | Finance — Requests | `GET admin/finance/requests/index.php` | super_admin, admin, finance | Not built |

**Admin RBAC:** Gate each screen by the `role` claim in the JWT. `super_admin` can access everything. `admin` can access all non-HR/Finance. `hr` sees only HR module. `finance` sees only Finance module. Show a "Not authorized" screen for routes outside the current role's scope.

---

### Provider Portal Staff screens to build

Routes live under `/portal/*`. The portal JWT is required for all. The JWT payload includes `provider_id` — all queries are automatically scoped server-side.

**Tier system:** The portal has a Free / Pro / Grace subscription gate. Most features (HR, Finance, CRM, services) require an active Pro or Grace subscription. Free accounts can only access: auth, dashboard, staff management, and subscriptions.

| Tier | Condition | Access |
|------|-----------|--------|
| Free | Default | Dashboard, staff management, subscriptions |
| Pro | Active paid subscription | HR, Finance, CRM, services |
| Grace | Within 3 days after subscription expires | Same as Pro |

| Route | Screen | API | Roles | Tier |
|-------|--------|-----|-------|------|
| `/portal/dashboard` | Dashboard | `GET portal/dashboard.php` | all | free |
| `/portal/change-password` | Change Password | `POST portal/auth/change-password.php` | all | free |
| `/portal/staff` | Staff list | `GET portal/staff/index.php` | owner | free |
| `/portal/staff/create` | Add staff | `POST portal/staff/store.php` | owner | free |
| `/portal/staff/edit` (extra: `staffId`) | Edit staff | `POST portal/staff/update.php` | owner | free |
| `/portal/subscriptions` | Subscription purchase | `GET portal/subscriptions/index.php`, `POST portal/subscriptions/store.php` | owner | free |
| `/portal/hr/attendance` | Attendance | `GET portal/hr/attendance/index.php`, `POST portal/hr/attendance/clock-in.php`, `POST portal/hr/attendance/clock-out.php` | owner, hr | pro |
| `/portal/hr/payroll` | Payroll | `GET portal/hr/payroll/index.php`, `POST portal/hr/payroll/store.php` | owner, hr | pro |
| `/portal/hr/recruitment` | Recruitment | `GET portal/hr/recruitment/index.php`, `POST portal/hr/recruitment/store.php` | owner, hr | pro |
| `/portal/finance/income` | Income | `GET portal/finance/income/index.php`, `POST portal/finance/income/store.php` | owner, finance | pro |
| `/portal/finance/expenses` | Expenses | `GET portal/finance/expenses/index.php`, `POST portal/finance/expenses/store.php` | owner, finance | pro |
| `/portal/finance/requests` | Finance requests | `GET portal/finance/requests/index.php`, `POST portal/finance/requests/store.php` | owner, finance | pro |
| `/portal/crm/bookings` | CRM — Bookings | `GET portal/crm/bookings/index.php` | owner, crm | pro |
| `/portal/crm/bookings/:id` | CRM — Booking detail | `GET portal/crm/bookings/show.php`, `POST portal/crm/bookings/update-status.php` | owner, crm | pro |
| `/portal/crm/scan-qr` (extra: `bookingId`) | CRM — QR Scanner | `POST portal/crm/bookings/scan-qr.php` | owner, crm | pro |
| `/portal/crm/services` | CRM — Services | `GET portal/crm/services/index.php`, `POST portal/crm/services/store.php`, `POST portal/crm/services/update.php` | owner, crm | pro |

**Portal RBAC:** Gate screens by `role` claim. `owner` sees all portal screens. `hr` sees only HR. `finance` sees only Finance. `crm` sees only CRM + services. Show a "Not authorized" screen for out-of-role routes. Additionally, show a "Upgrade to Pro" paywall for Pro-tier screens when the provider is on the Free tier — the subscription purchase screen is always accessible.

**`must_change_password` gate:** If the JWT response from `portal/auth/login.php` includes `must_change_password: true`, navigate immediately to `/portal/change-password` and hide all nav items except Change Password and Logout.

**Portal subscription purchase flow:** Same PayMongo WebView flow as seeker bookings. `POST portal/subscriptions/store.php` returns `checkout_url`. Open in WebView, detect `/subscription-success.php` redirect, then call `GET portal/subscriptions/index.php` to confirm the new tier.

---

## Recent work log

### Login Screen — Clerk/Linear Style
**File:** `lib/features/auth/screens/login_screen.dart`

Complete rewrite: white scaffold, radial green `Positioned` decoration circles, 56×56px green rounded-square brand icon, left-aligned 34px "Sign in to\nPestify" heading, labels rendered above inputs via `_fieldLabel()` helper (not floating), filled `Color(0xFFF7F8FA)` inputs with `borderRadius: 12`, "Forgot password?" link right-aligned in the same `Row` as the Password label.

### Messages Screen — Telegram 2024 Style
**File:** `lib/features/seeker/screens/messages_screen.dart`

Complete rewrite: no `AppBar`, custom `Container` header with 30px bold title + edit icon, inline search `TextField` with live client-side filtering, `_kAvatarGradients` palette (8 gradient pairs cycled by provider id), 56px gradient `CircleAvatar` with white initials, no list separators, smart timestamp (time / weekday / date).

### Profile Screen — Spotify/Airbnb Style
**File:** `lib/features/seeker/screens/profile_screen.dart`

Complete rewrite using a 3-layer `Stack`: navy gradient hero (navy → `#2C3E7A`), white rounded card starting at `heroHeight - 32`, `CircleAvatar` (radius 48) straddling the seam at `heroHeight - 48`. Settings-style field rows with bottom-border-only separators. Danger zone logout button in a red-tinted box.

### Messaging & Booking Bug Fixes
**Files:** `lib/features/seeker/seeker_api.dart`, `api/v1/messages/send.php` (PHP), `api/v1/seeker/bookings/store.php` (PHP)

- `sendMessage()` was sending `receiver_id`; PHP reads `to` — fixed field name in `seeker_api.dart`.
- `messages.id` had no `AUTO_INCREMENT` — second message hit a duplicate primary key error — fixed with `ALTER TABLE`.
- `createBooking()` sent no `full_name` field but PHP had `req_inp('full_name')` — changed to `inp()` with server-side profile fallback.
- Flutter sent `payment_method: 'full'` but PHP only accepted `'full_payment'` — PHP now normalises both.

### Home Screen — Full-Width Service Row Cards
**File:** `lib/features/seeker/screens/home_screen.dart`

Replaced 2-column `SliverGrid` with `SliverList` of full-width horizontal row cards (`_ListingCard`). Each card: 100×100 left image, title + company name, `RatingBarIndicator` with count, price in green, ECO/URGENT badge chips, "View Details →" `TextButton`.

### Listing Detail Screen — FB Mobile Profile Style
**File:** `lib/features/seeker/screens/listing_detail_screen.dart`

Complete rewrite. `SliverAppBar` (expandedHeight 280) with `PageView` image gallery, page-dot indicator, gradient fade, frosted back button. Content: title + badges, price + rating, provider row with "View Profile" shortcut, "About this Service", "About the Provider" (description + address/city chips), "Customer Reviews" (up to 5 cards with initials avatar, stars, date, feedback text). Sticky bottom bar with price + "Book Now" button. `seeker_api.dart` `getListingDetail()` updated to merge `body['reviews']` into the returned map.

### Book Service Screen — Map Picker + Pre-fill + Payment Cards
**File:** `lib/features/seeker/screens/book_service_screen.dart`

Added Name field (pre-filled from `getProfile()` on `initState`), Contact Number field (pre-filled from `phone`). Map picker: `ModalBottomSheet` with `WebView` rendering OpenStreetMap + Leaflet CDN HTML; user taps to pin, HTML calls `window.FlutterMapChannel.postMessage(JSON)` via `JavascriptChannel`; Flutter reverse-geocodes via Nominatim. Payment section redesigned: two selectable `_PaymentCard` widgets (Full Payment / Down Payment) with icon, label, and amount breakdown note. `seeker_api.dart` `createBooking()` updated to accept optional `fullName` and `contactNumber`.

### Session-expired mislabeling fix
**File:** `lib/core/api/api_client.dart`

`_ErrorInterceptor` was rewriting **every** 401 response to "Session expired. Please log in again." — including `login.php` rejecting bad credentials on a fresh, unauthenticated login attempt. Fixed to only apply that message when the failing request actually carried an `Authorization` header (i.e. was an authenticated call); unauthenticated 401s (wrong login credentials) now fall through to the real PHP-provided message.

### Unsafe int casts crashing "View Details" and chat
**Files:** `lib/features/seeker/screens/home_screen.dart`, `lib/features/seeker/screens/messages_screen.dart`

Both did a direct `as int?` cast on an id field that PHP returns as a string (`type 'String' is not a subtype of type 'int?'`). Fixed with `int.tryParse(x?.toString() ?? '')` in both places — this is the general pattern; see "Reading API data safely" above and never direct-cast a PHP-sourced numeric field.

### Booking creation crash — wrong column name
**Files (PHP):** `api/v1/seeker/bookings/store.php`, `api/v1/provider/requests/index.php`, `api/v1/provider/requests/show.php`

All three referenced `availed_services.listing_id`, but the live table only has `service_id` (confirmed via `DESCRIBE`). Booking creation 500'd with "Unknown column 'listing_id'"; the two provider files had the same bug in a `JOIN`. Fixed all three to use `service_id`.

### Payment confirmation stuck on "Payment Pending" despite success
**File (PHP):** `api/v1/seeker/bookings/confirm-payment.php`

Two independent bugs, found in sequence:
1. `allow('GET')` while Flutter's `confirmPayment()` POSTs — every poll 405'd, caught as a generic "network hiccup" and retried until timeout. Fixed: `allow('GET', 'POST')`.
2. After fixing #1, the endpoint still failed client-side — it returned `ok(['verified' => true, 'booking' => [...]])`, a **flat** body, not nested under `data`. `ApiClient.unwrap()` returned `null`, and the subsequent `as Map<String, dynamic>` cast threw, which the seeker-facing screen displayed as "Payment check failed, retrying...". Fixed by wrapping all three of the endpoint's `ok()` calls in `'data' => [...]`. See "Known backend gotchas" #2 and #3.

### Review submission crash + silent data loss + duplicate-rating gap
**Files (PHP):** `api/v1/seeker/bookings/feedback.php`; **DB:** `service_reviews` table; **Flutter:** `lib/features/seeker/seeker_api.dart`, `lib/features/seeker/screens/booking_detail_screen.dart`

- `service_reviews.id` had no `AUTO_INCREMENT` (same bug class as the earlier `messages.id` fix) — the second-ever review (for a different booking) crashed with a duplicate-PK error. Fixed with `ALTER TABLE ... MODIFY id INT NOT NULL AUTO_INCREMENT`.
- Flutter sent the review text as `'comment'`; PHP read `inp('feedback')` — silently discarded. Fixed the Flutter key.
- `feedback.php` never processed the uploaded photo despite a `feedback_image` column existing and the web app's `includes/feedback_media_helper.php` helper being ready to use — wired it up (`uploadFeedbackImage('image', ...)`).
- Added an explicit 409 rejection for a second review on the same booking (was previously a silent `ON DUPLICATE KEY UPDATE` overwrite).
- Flutter: `booking_detail_screen.dart` now shows a non-clickable "You rated this X/5" badge instead of the "Leave a Review" button once a review exists (`_hasNoReview`/`_existingRating`), so the action can't be triggered twice from the UI either.

### `getRemainingPayment()` used the wrong HTTP verb
**File:** `lib/features/seeker/seeker_api.dart`

Used `_dio.get()`, but `remaining-payment.php` is `allow('POST')` — the entire "Pay Remaining Balance" screen 405'd on load, silently, for as long as this method has existed. Found while wiring up the new seeker-side endpoints below (their PHP counterparts made the mismatch obvious via `access_log`). Fixed to `_dio.post()`.

### Seeker-side gap-filling: 5 new/extended endpoints + booking-status normalization
**Files (PHP, new):** `api/v1/seeker/bookings/confirm-complete.php`, `reschedule-respond.php`, `emergency-now.php`, `retry-payment.php`
**Files (PHP, extended):** `remaining-payment.php`, `show.php` (added `receipts` sibling key), `index.php` (widened `status=active` filter)
**Files (Flutter, new):** `lib/shared/utils/booking_status_utils.dart`
**Files (Flutter, extended):** `seeker_api.dart`, `api_endpoints.dart`, `booking_detail_screen.dart` (substantially — new action buttons, reschedule banner, receipts section, reworked `_StatusTimeline`), `booking_status_chip.dart`, `my_bookings_screen.dart`

An audit comparing the web app's seeker-facing booking lifecycle against the mobile app found several functions with **no mobile API endpoint at all** — not just a missing screen. Built and hardened over 4 rounds of adversarial review (Opus review → Sonnet fix → re-verify), which surfaced 18 real bugs total, the most serious being the three-way `waiting_provider_confirmation` status collision documented in "Booking status literal drift" above. Key correctness invariants now enforced (verify these still hold before modifying any of these files):
- A seeker can only "Confirm Service Complete" when genuinely past the service-day handshake for the ambiguous legacy status family (`dual_verified_at` check, zero-date-sentinel-aware).
- Every payment-transaction-creating endpoint voids prior `pending` rows for the same booking before inserting a new one, and does so inside a DB transaction with `catch (Throwable)` → `error_log` → `fail(500)` (never silently falls through to `ok()` after a failed write).
- Every status-changing UPDATE re-asserts the expected prior status in its `WHERE` clause and checks `rowCount()` before proceeding (no TOCTOU).
- The "Pay Remaining Balance" / "Confirm Service Complete" action buttons in `_ActionArea` (`booking_detail_screen.dart`) are kept in exact sync with their corresponding endpoint's accept/reject conditions — if you change one side, change the other.

### Dual control-number verification was unreachable early, and skipped the QR step entirely
**Files (PHP):** `includes/ControlNumberService.php`, `provider/service-requests.php`, `api/v1/seeker/bookings/verify.php`, `api/v1/provider/requests/verify.php`, `config/database.php`, `config/config.php`
**Files (Flutter):** `lib/features/seeker/screens/booking_detail_screen.dart`, `lib/features/seeker/screens/my_bookings_screen.dart`

A user testing the "seeker/provider exchange control numbers to start the service" flow on mobile hit a chain of bugs, found and fixed in sequence:

1. **The seeker had no way to see or submit their code early.** `booking_detail_screen.dart`'s "Enter Provider Code" and "Show My QR Code" actions were both gated to `status == 'starting'` — but `starting` is only ever *reached* via this exact code exchange, so neither action was ever actually reachable. Fixed by adding a "Show My Verification Code" action (new bottom sheet, reads the already-returned-but-unused `booking['control_number']`) and loosening "Enter Provider Code" to a `_verificationWindowOpen` window (`!hasStarted` and not `pending`/`cancelled`/`completed`) — matching what the backend (`ControlNumberService`) actually allows, which has no status or ordering requirement at all. Both actions now also refresh the booking on return (`context.push` awaited, then `_refresh()`), and `my_bookings_screen.dart`'s tab lists do the same — previously they fetched once in `initState()` and went stale for the rest of the session (`AutomaticKeepAliveClientMixin` + `StatefulShellRoute` keep them mounted indefinitely).
2. **`api/v1/seeker/bookings/verify.php` had the flat-envelope bug** (see "Known backend gotchas" #2) — `ok(['message'=>...])` not nested under `'data'`, so `ApiClient.unwrap()` returned `null` and `seeker_api.dart`'s `verifyCn()` crashed on `data as Map<String, dynamic>` — even when the submitted code was correct and the server-side write succeeded. Fixed the envelope; also fixed the identical bug in the provider-side counterpart `api/v1/provider/requests/verify.php` (unused by any app yet — Phase 2 Provider is 0% built — but will hit the same crash the moment it's consumed).
3. **Dual verification skipped `starting` and the QR step entirely**, landing on a status called `in_progress` that no code path ever generates a QR token for — see "Booking status literal drift" above for the full fix (now advances to `starting` + generates `qr_token`, symmetric regardless of which side finishes the code exchange last).
4. **Two more backend bugs surfaced while chasing this**, both now in "Known backend gotchas": the `utf8` vs `utf8mb4` DB connection charset (an emoji in the unlock notification crashed the whole transaction with a misleading "Invalid datetime format" error), and PHP (`Europe/Berlin`) vs MySQL (`Asia/Manila`) timezone mismatch (made the web dashboard's "is it service day yet?" date-gate reject a same-day verification).

### Phase 2 (Provider) core flow built from scratch
**Files (Flutter, new):** `lib/features/provider/provider_api.dart`, `lib/features/provider/screens/{provider_home_screen,provider_listings_screen,provider_listing_form_screen,provider_requests_screen,provider_request_detail_screen,provider_verify_screen,provider_scan_qr_screen}.dart`
**Files (Flutter, extended):** `app_router.dart` (new `/provider/*` `StatefulShellRoute` + full-screen pushes, replacing `_ProviderHomePlaceholder`; role guard added to the global `redirect`), `api_endpoints.dart` (provider endpoint constants + `resolveImageUrl()`)
**Files (PHP, fixed):** `api/v1/provider/dashboard.php` (`'ongoing'` → `'on_going'` typo in the active-bookings count, plus both spellings kept for legacy rows; added `provider_status`/`company_name` to the response), `api/v1/provider/listings/store.php` + `update.php` (pricing-type validation fixed from the nonexistent `per_sqm` to the real ENUM — see "Known backend gotchas" #10; `update.php`/`delete.php` also had the flat-envelope bug, #2), `api/v1/provider/requests/update-status.php` (same flat-envelope bug)

Existing PHP (`provider/requests/{index,show,update-status,verify,scan-qr}.php`) was already built correctly against `includes/booking_workflow_helper.php`'s canonical FSM from an earlier session — no changes needed there beyond the envelope fix above. Verified against the real DB: full state-machine walk (`pending → accepted → preparing → starting → on_going → waiting_for_seeker_confirmation → completed`), the downpayment branch (`on_going → waiting_for_remaining_payment → waiting_for_provider_confirmation → completed`), `verify.php` with both a wrong and a correct control number, and a real multipart image upload through `listings/store.php` — the last of which surfaced "Known backend gotchas" #11 (uploads directory permissions), fixed and documented there. All synthetic test rows/files created during verification were deleted afterward.

**Not done this session (deferred to a follow-up):** Provider Portal Staff (Phase 3) — dashboard, staff management, subscriptions, HR/Finance/CRM. The image-URL-resolution gap this session's `resolveImageUrl()` fixes was only applied to the new provider screens, not retrofitted onto the seeker-side screens that render `images`/`logo_url` (`home_screen.dart`, `listing_detail_screen.dart`, `providers_screen.dart`, `provider_detail_screen.dart`) — those still pass PHP's raw relative path straight to `CachedNetworkImage`, which will break the moment any of those rows actually gets a real (non-`NULL`) image, same as the provider-listing images did before this session.

### Provider messaging, notifications and profile
**Files (Flutter, new):** `lib/features/provider/screens/{provider_messages_screen,provider_message_thread_screen,provider_notifications_screen,provider_profile_screen}.dart`
**Files (Flutter, extended):** `provider_api.dart` (messages/notifications/profile methods), `app_router.dart` (Messages shell branch + three pushed routes), `provider_home_screen.dart` (logout moved out of the app bar into Profile; replaced by a notification bell with an unread `Badge.count` and a profile button)

Closed the last functional gaps on the provider side. The most consequential was messaging: seekers could already message a provider from the seeker app, but the provider had no way to see or answer it — the conversation was one-way in practice. No PHP changes were needed; all three surfaces use shared `current_user()`-guarded endpoints that already branched on `user_type` (see the note under "Provider screens to build" above).

Verified against real data with a provider JWT: `profile.php` GET returns the merged company fields, `notifications/index.php` returns provider-shaped booking + message items (`unread_count` matching `count.php`), `messages/index.php` lists the real seeker conversation, `thread.php` returns both participants' messages, and `send.php` round-trips a provider→seeker reply (test row deleted afterward). **Not browser-verified** — the Chrome extension wasn't connected that day, so these four screens have only been checked by static analysis (0 errors/warnings) and API-level testing, unlike the first Phase 2 batch which did get a live click-through.

### Pull-to-refresh looked like it did nothing — `RefreshIndicator.onRefresh` wasn't actually awaiting the fetch
**Files:** all 6 provider screens with a `RefreshIndicator` (`provider_home_screen.dart`, `provider_listings_screen.dart`, `provider_requests_screen.dart`, `provider_request_detail_screen.dart`, `provider_messages_screen.dart`, `provider_notifications_screen.dart`)

A user reported that creating a listing took "many refreshes" before it showed up in My Listings. Checking `access_log` around the actual test showed the server had the correct, updated `listings/index.php` response starting from the **very first** GET after the create POST — the user then pulled to refresh 5 more times and got byte-identical responses every time. So this was never a data-freshness problem; it was `RefreshIndicator`'s spinner lying about when the fetch was actually done.

Every one of these screens had `_refresh()` reassign `_future = _fetch()` inside `setState()` but never `await` the new future — so the function (or its `() async => _refresh()` wrapper, used on 3 of the 6) returned essentially immediately, before the network round-trip completed. `RefreshIndicator` dismisses its spinner the instant `onRefresh`'s returned future resolves, so the pull gesture looked like it "did nothing" almost instantly, training the user to pull again (and again) even though a `FutureBuilder` watching the same future would have shown the new data correctly on its own a moment later. **Fixed pattern** — `_refresh()` now captures the new future, assigns it to `_future` inside `setState`, then `await`s that same future in a `try/catch` (swallowed — `FutureBuilder`'s `snapshot.hasError` already renders it) so `RefreshIndicator`'s spinner stays up for the real round-trip:
```dart
Future<void> _refresh() async {
  final Future<List<dynamic>> next = _fetch();
  setState(() => _future = next);
  try {
    await next;
  } catch (_) {
    // FutureBuilder surfaces the error via snapshot.hasError.
  }
}
```

**Follow-up: also fixed on the seeker side.** Audited every seeker screen with a `RefreshIndicator` (`booking_detail_screen.dart`, `my_bookings_screen.dart`, `messages_screen.dart`, `home_screen.dart`, `notifications_screen.dart`, `providers_screen.dart`). Only two actually had the bug — `booking_detail_screen.dart`'s `_refresh()` and `my_bookings_screen.dart`'s `_refresh()`, both the same `setState(() => _future = _load())`-without-`await` shape — fixed with the same pattern as above. The other four were already structured correctly (they `await` the network call *inside* the async function body and `setState` the result directly, rather than reassigning a `FutureBuilder`'s future and hoping the caller awaits it), so their `onRefresh` genuinely waits and needed no change.

`my_bookings_screen.dart` had a second, related instance: its `_EmptyState` widget took `onRefresh` typed as `VoidCallback` (`void Function()`) and called it inside `RefreshIndicator(onRefresh: () async => onRefresh())`. Dart allows passing a `Future<void> Function()` (like `_refresh`) wherever `VoidCallback` is expected — the return value is just silently discarded — so calling it through that `VoidCallback`-typed parameter threw away the very Future that needed awaiting, defeating the fix even after `_refresh()` itself was correct. Changed `_EmptyState.onRefresh` to `Future<void> Function()` and wired `RefreshIndicator(onRefresh: onRefresh)` directly. **Any other widget in this codebase that takes a `VoidCallback` and hands it straight to a `RefreshIndicator.onRefresh` has this same trap** — check the parameter type, not just whether `_refresh()` itself awaits.

### Landing page + Decision Support System ("Find My Match")
**Files (Flutter, new):** `lib/features/landing/screens/{landing_screen,find_my_match_screen,recommend_results_screen}.dart`
**Files (Flutter, extended):** `app_router.dart` (new `/landing`, `/recommend`, `/recommend/results` routes; `/landing` added to the auth-screen exclusion list; a guest-safe exception carved into the `/seeker/*` guard — see below), `splash_screen.dart` (the not-logged-in branch now goes to `/landing` instead of `/login` — the session-expired and error-recovery branches deliberately still go to `/login`, unchanged), `seeker_api.dart` (`getCategories()`, `getRecommendOptions()`, `getRecommendations()`), `api_endpoints.dart` (`recommend`, `recommendOptions` constants)
**Files (PHP, new):** `api/v1/seeker/recommend.php`, `api/v1/seeker/recommend-options.php`
**Files (PHP, fixed):** `api/v1/providers/show.php` (see "Known backend gotchas" #12)

Previously the app dropped every not-logged-in user straight onto the login screen — no way to explore anything first. Added a guest landing page (hero, stats, popular categories, featured services, "how it works", Login/Sign Up CTAs) plus a full port of the web's DSS "Find My Match" feature (`seeker/recommend.php` + `includes/dss_helper.php`, which explicitly named `api/v1/seeker/recommend.php` in its own top-of-file comment as the intended-but-not-yet-built mobile endpoint — this session built exactly that).

**The DSS pipeline itself needed zero changes** — `dss_helper.php`'s scoring engine (`dssRank()`, Simple Additive Weighting across category/rating/price/reliability/recency/urgency, Bayesian-shrunk ratings, a rules-then-Groq cascade for free-text English/Tagalog/Taglish parsing, batched LLM-generated explanations with a deterministic template fallback) was already complete and correct — `api/v1/seeker/recommend.php` just calls it and returns JSON instead of rendering a page, mirroring `seeker/recommend.php`'s logic line-for-line (same filter defaults, same rules→Groq cascade, same per-item explanation fallback). Verified against the real DB: plain query (7 candidates ranked), Tagalog free text ("may anay sa kusina namin" → correctly parsed to Termite Control by the *rule* parser alone, no Groq needed), and `urgency=emergency`+`eco=1` correctly re-weighting results. **Groq is actually enabled in this environment** via a gitignored `config/secrets.php` (not `config/config.php`, which defines an empty placeholder key) — explanations returned are real LLM prose, not just the template fallback; don't assume Groq is off just because `config.php` shows an empty `GROQ_API_KEY` default.

**Guest access to two read-only `/seeker/*` routes.** Landing's category tiles and featured-service cards, and DSS results' "View Provider & Book" button, all need to push into `/seeker/listing/:id` and `/seeker/provider/:id` — both already backed by guest-accessible PHP (`listings/show.php`, `providers/show.php` require no auth) but previously unreachable in the app because the router's global redirect gated the *entire* `/seeker/*` prefix behind login. Carved out a narrow exception for just those two path prefixes; every other `/seeker/*` route (the shell tabs, booking, messages, profile, ...) is still fully gated, unchanged. Confirmed `listing_detail_screen.dart`/`provider_detail_screen.dart` have no hidden dependency on `authProvider` or a logged-in session (they only call `SeekerApi`, which already degrades gracefully with no token) — the only thing that changed is which routes the *router* allows a guest to reach.

**If you touch DSS again:** the Flutter form (`find_my_match_screen.dart`) and results screen (`recommend_results_screen.dart`) mirror the web form/result-card fields exactly (need_text, category chips, budget_max, urgency chips, priority chips, city, eco toggle → rank badge, score %, explanation, up to 2 review snippets, expandable per-criterion breakdown bars, "View Provider & Book") — keep them in sync if `dss_helper.php`'s filter or breakdown shape ever changes, same as the "Pay Remaining Balance" / booking action-button sync rule noted elsewhere in this file.

**If you touch any part of this flow again:** `ControlNumberService::unlockService()` and `provider/service-requests.php`'s own inline dual-verification completion block must stay in sync — they're two independent implementations of the same "both codes matched" outcome (one for the JWT API, one for the session-based web dashboard), and this session's bug was exactly that they'd drifted apart (one wrote `starting`, the other wrote `in_progress`). Verified fixed by testing all four call-order combinations live (seeker-then-provider and provider-then-seeker, through both the JWT API and a real web dashboard session) — all four now land on `starting` with a real `qr_token`.

### Phase 3 — Admin panel, Dashboard + Provider approval slice built
**Files (Flutter, new):** `lib/features/admin/admin_api.dart`, `lib/features/admin/screens/{admin_dashboard_screen,admin_providers_screen,admin_provider_detail_screen,not_authorized_screen}.dart`
**Files (Flutter, extended):** `app_router.dart` (an `/admin/*` `StatefulShellRoute` (Dashboard/Providers tabs) + `/admin/providers/:id`, replacing `_AdminDashboardPlaceholder`; new `/admin/*` auth guard mirroring the `/provider/*` one), `api_endpoints.dart` (`adminDashboard`, `adminProviders`, `adminProviderDetail`, `adminProviderApprove`, `adminProviderReject`)
**Files (PHP, fixed):** `api/v1/admin/providers/reject.php`, `api/v1/admin/providers/approve.php`, `api/v1/auth/login.php` (see below)

Scoped deliberately to just Dashboard + the provider-approval flow, per explicit agreement — Users, Bookings, Logs, Subscriptions, HR, and Finance admin screens are **not built**, though every one of their backing PHP endpoints already exists (confirmed by listing `api/v1/admin/`). Reuses the single shared `AuthStorage`/`authProvider` session (same pattern as Provider in Phase 2), not a separate storage key.

**First pass built a separate `/admin/login` screen and `AuthApi.adminLogin()` calling `admin/auth/login.php` directly — reverted one message later.** The user pointed out login should be centralized, matching how the *web app* already works: a single `auth/login.php` shared login page that checks `admin_users` → `provider_staff` → `users` in one cascade, not a separate login page per role family. The mobile API's `auth/login.php` only ever checked `users`, so it didn't yet have web parity here. Fixed by rewriting `api/v1/auth/login.php` to implement the same three-tier cascade the web uses (see "Login is centralized" above for the full design), then deleting `admin_login_screen.dart`, the `/admin/login` route, `AuthApi.adminLogin()`, and the `ApiEndpoints.adminLogin` constant — `login_screen.dart` now handles every role transparently, with no "admin sign in" link needed. Verified all three tiers end-to-end with real accounts (temp-password round-trips, restored after): admin login by email, portal-staff login *by username* (confirming the username-or-email matching works, not just email), and a positive seeker login (not just the existing negative/401 case) to confirm zero regression on the most-used path.

**Found and fixed a real bug before it ever shipped:** `admin/providers/reject.php` set `providers.status = 'rejected'` — but `providers.status` is `ENUM('pending','active','inactive','suspended')` (confirmed via `DESCRIBE`) with no `rejected` value, so every single call 500'd (`SQLSTATE[01000]: ... Data truncated for column 'status'` under this DB's strict mode). Reproduced live with a disposable test provider row before touching the Flutter side at all, so the admin Reject button was never built against a broken endpoint. Fixed by only setting `verification_status = 'rejected'` (the free-text column that `index.php`/`show.php` actually key their pending/approved/rejected filtering and display off of) and leaving `status` untouched. `approve.php` and `reject.php` also had the familiar flat-envelope bug (`ok(['message' => ...])` not nested under `'data'`) — fixed both. See the PHP project's own `CLAUDE.md` for the mirrored write-up.

Verified against real data with a real admin JWT (temp-password round-trip on the seeded `superadmin` account, restored after): dashboard stats including the `super_admin`-only `active_subscriptions`/`monthly_revenue` extras, providers list with status-tab filtering, provider detail, and a live approve → reject → approve cycle on a disposable test provider (deleted afterward). **Not browser-verified** — same Chrome-extension-not-connecting situation as the rest of this session's UI work; verified via `flutter analyze` (0 errors/warnings) and direct API calls, not a click-through.

**RBAC note:** `admin/dashboard.php` is actually more permissive than the route table above states — it allows all four admin roles (`super_admin`, `admin`, `hr`, `finance`), not just the first two, with `super_admin` getting two extra response fields. `admin/providers/*` really is `super_admin`/`admin`-only though; `AdminProvidersScreen` checks the JWT's `role` claim itself and shows [NotAuthorizedScreen] for `hr`/`finance`, since an `hr`/`finance` admin has no HR/Finance screens to actually use yet either — landing on Providers with nothing to do would be worse than a clear "not authorized" message.

**Correction to the "verified" claim two paragraphs up:** "providers list with status-tab filtering" was only verified at the API level (`AdminApi.getProviders(status: ...)` called directly, matching a manual `curl`) — the actual Flutter tab-tap interaction was never exercised, and it turned out to be broken. See the two fixes immediately below, both reported directly by a user testing the real UI, which is exactly the category of bug that API-level testing without a browser will never catch.

### Admin dashboard blank for super_admin + Providers status tabs didn't filter
**File:** `admin_dashboard_screen.dart`, `admin_providers_screen.dart`

Two bugs, reported together, fixed together:

1. **Dashboard rendered blank, but only when logged in as `super_admin`.** That role-specific detail was the key clue — `super_admin` is the only role for which `admin/dashboard.php` returns the extra `active_subscriptions`/`monthly_revenue` fields, and `AdminDashboardScreen` renders those two inside a plain `Row` (not the `GridView.count` the other six stat tiles live in). `_StatCard`'s internal layout used `Spacer()` between its icon and its value text — fine inside the `GridView`, which bounds each cell's height via `childAspectRatio`, but `Spacer()` (a flex widget) throws `RenderFlex children have non-zero flex but incoming height constraints are unbounded` when its ancestor doesn't provide a bounded height, which the bare `Row` doesn't. Fixed by replacing `Spacer()` with a fixed `SizedBox(height: 12)`, making `_StatCard` safe to drop into any layout, not just its original `GridView` cell.
2. **Providers screen's status tabs (Pending/Approved/Rejected) never actually refiltered** — tapping a tab left whatever the previous tab's results were on screen. The status-filter query itself was verified correct server-side first (`admin/providers/index.php?status=pending` and `?status=rejected` both correctly return empty — there are simply no pending/rejected providers in the current seed data, all three existing ones are `approved`), which narrowed this to a pure Flutter bug.

**This one took two attempts.** First fix: swap `TabController.addListener` + `indexIsChanging` (the textbook pattern for reacting to tab changes, but one that doesn't reliably fire for a bare `TabBar` with no `TabBarView` behind it) for `TabBar(onTap: ...)`, which per the Flutter SDK source (`_TabBarState._handleTap`, `packages/flutter/lib/src/material/tabs.dart`) fires deterministically once per tap, after `TabController.animateTo()` has already synchronously updated `.index` (confirmed by reading `TabController._changeIndex` in `tab_controller.dart` directly rather than trusting memory). This didn't actually fix it — a follow-up report showed the exact same 3 providers appearing in all 4 tabs even after a genuine hard-refresh. The Apache access log told the real story: each tap correctly sent a *different* `status=` query param and got back a correctly *different*-sized response (843 bytes for all/approved's 3 results, 59 bytes for pending/rejected's empty array) — but fired **twice** per tap, identically, for a reason never fully root-caused. The request/response layer was proven correct the whole time; only the on-screen result was wrong, which the duplicate-firing was the closest available clue to.

Rather than keep chasing `TabBar`/`TabController` timing further, replaced the entire mechanism with the exact `SegmentedButton<String>` pattern already proven working elsewhere in this codebase (`provider_listings_screen.dart`'s Active/Inactive toggle) — no controller, no animation, no listener-timing surface to get wrong, just a direct `onSelectionChanged` callback with the definitively-selected value. **If a future screen needs tab-like filtering with a manually-managed body (no `TabBarView`), prefer `SegmentedButton` over `TabBar`/`TabController` entirely** — this class of bug (silent stale-data-on-tab-switch, with a correct backend and correct network layer) cost two debugging rounds to fully resolve.

### `services`/`service_listings` catalog merge on the PHP side — no Flutter code changes needed, but read this before touching any listing/booking endpoint
**Files (PHP only — see the pestify project's own `CLAUDE.md` for the full write-up):** `api/v1/listings/{index,show}.php`, `api/v1/providers/{index,show}.php`, `api/v1/provider/listings/{store,update,delete,index}.php`, `api/v1/provider/{dashboard,requests/index,requests/show}.php`, `api/v1/seeker/{recommend-options,bookings/store,bookings/show}.php`, `api/v1/admin/{providers/show,bookings/index,bookings/show}.php`, `api/v1/portal/crm/{bookings/index,bookings/show,services/index,services/store,services/update}.php`

The PHP backend had two independent, unsynced tables for the same thing — `services` (the web app's provider-management/booking flow) and `service_listings` (the table every one of the files above actually queried). A service a provider created through this Flutter app was invisible to, and unbookable from, the web app and vice versa. Backend-side, `service_listings` was migrated into `services` and renamed to `service_listings_archived`. **No Dart code needed to change** — every mobile-facing SQL `SELECT` was updated to alias `service_name AS title` so this app's existing `listing['title']`/`data['title']` reads keep working exactly as before; verified by grepping this app's own source for every literal key read off a listing-shaped API response before touching each PHP file, not by assumption. If you're debugging a listing/booking endpoint and see `services` instead of `service_listings` in a PHP file, that's expected post-migration, not a regression.

**Practical upshot for this app:** a listing created via `provider/listings/store.php` (this app's own create-listing screen) is now visible and bookable through the website too, and — the direction that matters more for future Flutter work — a service the *website* knows about that this app didn't create can still be booked from here via `createBooking()`, since `api/v1/seeker/bookings/store.php` now resolves `service_id` against the same unified table regardless of which side originated the listing. Verified live end-to-end: created a listing via this app's API, confirmed it appeared on the web's browse pages, then booked it through the *web's* own request flow and confirmed the resulting `availed_services` row correctly resolved back through this app's `bookings/show.php`.

### Inspection-required bookings showed a payment step (and, worse, a false error on submit)
**File:** `lib/features/seeker/screens/book_service_screen.dart`

A non-fixed-price listing (`pricing_type` Hourly/Custom on the PHP side always forces `requires_inspection=1` — see the pestify project's own `CLAUDE.md`, "Pricing Model" entry) has no final price yet: a technician has to inspect on-site first, and `api/v1/seeker/bookings/store.php` deliberately skips creating a PayMongo checkout for these, returning `{"data": {"checkout_url": null, "requires_inspection": true, ...}}` instead. This screen had never been told `requires_inspection` existed at all — it only ever received `listingId` (via GoRouter `extra`) and always rendered the Full Payment / Down Payment cards regardless.

**That was a UX problem. The actual functional bug was in `_submit()`:** it treated `result['checkout_url'] == null` as an unconditional error ("Unexpected server response. Please try again.") and stopped there — so submitting an inspection-required booking **always showed a false failure message**, even though the booking had genuinely saved server-side (confirmable in `availed_services`), with no indication to the seeker that anything had actually worked and no navigation anywhere.

**Fix:** `initState()` now also calls `SeekerApi.getListingDetail(widget.listingId)` to read the listing's real `requires_inspection` flag — note the PHP returns it as the *string* `"1"`, not a bool (`curl` confirmed this live), so the check is `== true || == 1 || == '1'`, matching this codebase's established "Reading API data safely" pattern above. When true: the Payment Method section is replaced with a blue "No payment needed yet — a technician will inspect on-site..." notice (mirrors the equivalent fix on the web side), the submit button reads "Submit Request" instead of "Proceed to Payment", and `_submit()` branches on `result['requires_inspection'] == true` to show a success snackbar and `context.go('/seeker/bookings')` instead of erroring. The *other* legitimate reason `checkout_url` can be null — a genuine PayMongo failure, distinguishable by the response's `paymongo_error` key / absent `requires_inspection` — still correctly shows an error (booking saved, retry payment from My Bookings), so that failure mode isn't accidentally swallowed by this fix.

Verified: `flutter analyze` clean on the file (0 errors; only pre-existing, unrelated `info`-level style lints elsewhere in it remain). **If you add a new booking-creation entry point** (e.g. a "Book Again" shortcut from booking history), route it through the same `requires_inspection` check rather than assuming `checkout_url` is always present on a successful `createBooking()` call.

### "Pick on Map" stuck on an infinite loading spinner
**Files:** `lib/features/seeker/screens/book_service_screen.dart` (`_MapPickerSheetState`), new `assets/leaflet/{map.html,leaflet.js,leaflet.css}`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`

User reported the map picker in Book Service just spins forever. Root cause: `_buildMapHtml()` built an inline HTML string loaded via `WebViewController.loadHtmlString()`, with `<link href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">` and a render-blocking `<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js">` in `<head>`. `_webReady` (which controls the spinner overlay) only flips to `true` inside `NavigationDelegate.onPageFinished`, and a WebView typically doesn't fire that callback until blocking `<script>` tags finish loading — so on any device/emulator where `unpkg.com` is slow, blocked, or simply unreachable (e.g. an emulator/device with only LAN access to the XAMPP backend but no real public-internet route), the page visually never "finishes loading" and the spinner never goes away, with zero indication of why.

Two fixes, both applied:
1. **Removed the CDN dependency for the page itself.** Leaflet's JS/CSS are now bundled as local assets (`assets/leaflet/leaflet.js`, `leaflet.css`, downloaded from the same pinned `1.9.4` version) and the picker HTML (`assets/leaflet/map.html`, hardcoding the same Cavite default center/zoom the old inline builder used) is loaded via `WebViewController.loadFlutterAsset('assets/leaflet/map.html')` instead of `loadHtmlString()`. `_buildMapHtml()` was deleted. Note this doesn't make the picker fully offline-capable — the actual map tiles (`tile.openstreetmap.org`) and reverse-geocoding (`nominatim.openstreetmap.org`) still need real internet — it only removes the *page shell itself* as a point of failure, so `onPageFinished` now fires immediately regardless of the device's broader network situation.
2. **Added a 15-second load timeout with a Retry button**, so a genuinely stalled load (e.g. tiles/geocoding still unreachable) shows "Map is taking too long to load. Check your internet connection." instead of spinning forever with no feedback. `_startLoad()` is now re-callable (changed `_webCtrl` from `late final` to `late`) so Retry can rebuild the controller from scratch.

**Also fixed while investigating:** `android/app/src/main/AndroidManifest.xml` (the release manifest, not `debug`/`profile`) was missing `<uses-permission android:name="android.permission.INTERNET"/>` entirely — Flutter's tooling auto-injects it for debug/profile builds (which is why `flutter run` never surfaced this), but a real `flutter build apk --release` would have had **no network access at all**, not just for the map. Added explicitly. Separately, `webview_flutter_web` was never added as a dependency even though this project's own documented primary run command is `flutter run -d web-server` — `pubspec.lock` only had `webview_flutter_android`/`webview_flutter_wkwebview` resolved, meaning `WebViewWidget` had zero platform implementation on the web target (confirmed via `.flutter-plugins-dependencies`). Added `webview_flutter_web: ^0.2.3+4`; `flutter pub get` resolved it cleanly.

First verification pass: `flutter analyze` clean, but not yet run on a real device/emulator. The user then reported the timeout message ("Map is taking too long to load") still appeared after this fix — investigated live on a connected Android emulator (`adb`-driven UI automation + `flutter run --verbose` + `onPageStarted`/`onWebResourceError` logging added to the `NavigationDelegate`) rather than guessing further.

**The real, complete root cause, found via logcat:** `onPageStarted` fired instantly (bundled assets do load fast, confirming fix #1 above was necessary and correct), but `onPageFinished` didn't fire until **24 seconds later** — well past the 15s timeout. In between, logcat showed 9 `onWebResourceError` entries, one per tile URL (`a/b/c.tile.openstreetmap.org`), all `WebResourceErrorType.hostLookup` / `ERR_NAME_NOT_RESOLVED` (confirmed separately: this emulator's own Android `NetworkMonitor` can't resolve `www.google.com` either — it has LAN access to the XAMPP backend only, no real public internet). The Android WebView implementation does **not** fire `onPageFinished` until every network request the page issued — including each async tile image fetch triggered by `L.tileLayer(...).addTo(map)`, not just synchronous `<script>`/`<link>` tags — has finished or failed. With no DNS at all, each tile lookup has to individually time out, and 9 of them compounding pushed the "finished" signal to 24s. The map was actually interactive almost immediately; `_webReady` was just wired to the wrong signal.

**Fix:** `assets/leaflet/map.html` now calls `map.whenReady(function() { FlutterMapChannel.postMessage('ready'); })` right after creating the Leaflet map — this fires as soon as Leaflet has laid itself out, independent of tile-loading success. `_handleMapMessage()` in `book_service_screen.dart` now treats a `'ready'` message as the primary "usable" signal (`_webReady = true`), with `onPageFinished` kept as a harmless secondary path (whichever fires first wins) and the 15s timeout retained as a last-resort safety net for a genuinely broken load.

Verified live end-to-end on the connected emulator after this fix: the picker sheet now opens with the Leaflet UI (zoom controls, "Leaflet | © OpenStreetMap contributors" attribution) rendered within ~2 seconds — no spinner at all — and tapping the map correctly drops the custom pin and round-trips coordinates back through `FlutterMapChannel` (`_lat`/`_lng` populate, "Use This Location" enables). The map tiles themselves still render as blank grey and the address field sticks on "Fetching address…" on this specific emulator, because it genuinely has no path to the public internet (confirmed via the DNS failures above) — that's expected, not a bug, and resolves itself on any device/emulator with real internet access. **If this regresses again, check `onWebResourceError` logs before assuming `loadFlutterAsset` broke** — the pattern here (fast `onPageStarted`, slow `onPageFinished`, a cluster of `hostLookup` errors in between) is the signature to look for.

### Map picker: bigger drag target + real Cavite-only geofence
**File:** `assets/leaflet/map.html`

Two follow-up requests from the user once the picker itself was working: (1) the pin was "hard to drag" for fine-tuning, and (2) nothing stopped a seeker from dropping a pin outside Cavite even though every other part of the booking flow enforces Cavite-only (see the address-field validators referenced throughout this file and the PHP `stripos($address,'cavite')` check).

- **Bigger drag target:** the custom Leaflet `divIcon` grew from 30px to 44px (`iconAnchor` adjusted from `[15,30]` to `[22,44]` to keep the teardrop's point anchored to the actual coordinate) — a small icon made it easy to miss when trying to grab it to drag.
- **Geofence, attempt 1 (rejected after live testing):** a simple lat/lng bounding-box rectangle (`L.latLngBounds`). Looked reasonable in isolation, but testing it live on the emulator immediately surfaced the problem: tapping on **Pasay** (a Metro Manila city, not Cavite) was accepted and placed a pin, because Pasay's coordinates (14.5378, 121.0014) happen to fall inside a straight-line box loose enough to cover Cavite's own irregular northern/eastern edge. A rectangle fundamentally can't match a real province's shape.
- **Geofence, attempt 2 (shipped):** fetched Cavite province's actual OSM administrative boundary via Nominatim (`relation 1503544`, ~3500-point polygon), simplified to ~230 points with Douglas-Peucker (epsilon=0.001°) to keep it embeddable, and implemented a standard ray-casting point-in-polygon test in plain JS (`pointInCavite(lat, lng)` — no library needed for a single simple polygon). Verified the simplified polygon against 13 known points (every major Cavite town plus Pasay/Manila/Las Piñas/Santa Rosa/Nasugbu as known-negative neighbors) in Python before embedding, then re-verified live on-device that the exact Pasay tap that leaked through attempt 1 is now correctly rejected.
- Tap outside the polygon: no pin is placed, and the JS posts `'outside_cavite'` through `FlutterMapChannel`; `_handleMapMessage()` in `book_service_screen.dart` shows a SnackBar ("Please pick a location within Cavite.") for it.
- Dragging outside the polygon: unlike a rectangle, there's no cheap way to "clamp to the nearest edge point" of an irregular polygon mid-drag, so instead the marker's `drag` handler tracks the last position that was still inside Cavite and snaps straight back to it the instant a drag step lands outside — verified correct by construction (reuses the same `pointInCavite()` already proven against the 13-point test set) but **not exercised through an actual Leaflet drag gesture in this session** — `adb shell input swipe` did not reliably trigger Leaflet's own marker-drag handling (the marker didn't move even for a swipe fully inside Cavite, suggesting the synthetic touch sequence doesn't satisfy Leaflet's drag-start detection, not a boundary-logic problem) — worth a real on-device finger-drag check next time this file is touched.
- `map.setMaxBounds(...)` also now derives its rectangle from the polygon's own min/max lat/lng (padded 0.1°) rather than a hand-picked box, so panning restriction and the placement geofence can't drift out of sync with each other.

### Book Service screen's "Preferred Schedule" section never adapted its copy for inspection-required listings
**File:** `lib/features/seeker/screens/book_service_screen.dart`

User caught this directly ("the info in book service is wrong"): the Schedule section always read "Preferred Schedule" / "Select when you need the service." / field label "DATE" — even for a `requires_inspection` listing, where the date actually being picked is stored as `inspection_date` (see `api/v1/seeker/bookings/store.php`) and just schedules a technician's on-site assessment, not the service itself. The Payment Method section had already been correctly made conditional on `_requiresInspection` earlier in this session; the Schedule section right above it was missed in that pass.

Fixed to mirror the web app's equivalent (`seeker/provider-details.php`'s `openModal()`, which relabels its own date field to "Preferred Inspection Date" the same way): when `_requiresInspection` is true, the section header becomes "Preferred Inspection Schedule" with subtitle "Select when a technician can inspect on-site. The service date is set after you agree to the final price.", and the date field's `_FieldLabel` becomes "INSPECTION DATE" instead of "DATE". The TIME field label is left unchanged (matches the web version, which also only relabels the date side).

Verified live on the connected emulator against the real `requires_inspection=1` "Rat Exterminator" listing (id 35): the screen now correctly shows "Preferred Inspection Schedule" / the inspection-specific subtitle / "INSPECTION DATE", alongside the already-working "No payment needed yet" notice and "Submit Request" button from the earlier fix — all three inspection-mode adaptations rendering together correctly on the same screen.

### A freshly-created booking didn't show up in My Bookings until a manual pull-to-refresh
**Files (new):** `lib/core/state/bookings_refresh.dart`
**Files (extended):** `lib/features/seeker/screens/my_bookings_screen.dart`, `lib/features/seeker/screens/book_service_screen.dart`

User booked a second service (same service, same provider as an existing booking) and it didn't appear on the mobile My Bookings screen, even though the exact same account correctly showed it on the web app. Confirmed via a direct `curl` against `api/v1/seeker/bookings/index.php` with a real JWT that the backend was never the problem — both the unfiltered list and the `status=active` group correctly included the new booking from the very first request after creation.

**Root cause was purely client-side caching**, not a dedup/filter bug in the list-rendering code itself (there is none — `ListView.separated` renders every item the fetch returns). `_BookingTabViewState` (one instance per tab: Active/Completed/Cancelled) uses `AutomaticKeepAliveClientMixin` and only ever (re)fetches in `initState()` (once) or `_refresh()` — called only from pull-to-refresh, or from `_openBooking()` after *pushing into and returning from* a booking's detail screen. Creating a new booking happens on `book_service_screen.dart`, a completely separate screen reached via the listing/provider detail flow, not by pushing out of My Bookings — so there was no "return" event to hook a refresh off of, and the Active tab's already-fetched, kept-alive list just never got told anything had changed. The web app has no equivalent problem simply because every page load there is a fresh PHP request with no client-side cache to go stale.

**Fix:** a small shared `StateProvider<int> bookingsRefreshTick` (`bookings_refresh.dart`) that any booking-mutating action bumps. `book_service_screen.dart`'s `_submit()` now does `ref.read(bookingsRefreshTick.notifier).state++;` the moment the booking row is confirmed to exist server-side (right after the `bookingId == null` guard — covers all three of its outcome branches: inspection-pending, checkout-creation-failed, and the normal payment-redirect path, since the booking exists in all three cases). `my_bookings_screen.dart`'s `_BookingTabViewState.build()` registers `ref.listen<int>(bookingsRefreshTick, ...)`, calling its existing `_refresh()` whenever the tick changes — Riverpod listener subscriptions set up during `build()` stay live for the widget's lifetime regardless of whether that specific tab is the currently-visible one, which is exactly what's needed here since `AutomaticKeepAliveClientMixin` keeps all three tabs' states alive simultaneously.

Checked for other booking-creation entry points that would need the same wiring — `createBooking()` has exactly one caller (`book_service_screen.dart`), so no other screen needs touching. `flutter analyze` clean on all three files (only pre-existing, unrelated style `info` lints remain).

### Booking detail screen offered "Complete Payment" for a requires_inspection booking whose price wasn't final yet
**File:** `lib/features/seeker/screens/booking_detail_screen.dart`

Direct follow-up to the two `book_service_screen.dart` inspection-mode fixes earlier in this log — same underlying issue, different screen. `_ActionArea`'s "Complete Payment" button (comment: "Retry Payment — initial checkout never completed") showed whenever `status` was `pending`/`accepted` and `payment_status` was `unpaid`, with **no check at all for `requires_inspection`**. For a `pricing_type: custom` (or `hourly`) listing — which per the "Pricing Model" entry always forces `requires_inspection=1` — the booking sits at exactly `pending`/`unpaid` right after creation, so this button showed unconditionally. Tapping it would call `retryPayment()`, which creates a real PayMongo checkout for the booking's current `total_amount` — except for these bookings that amount is explicitly just an *estimate* (`api/v1/seeker/bookings/store.php` never creates a checkout for them in the first place, precisely because there's nothing final to charge yet), so this button was offering to let the seeker pay against a number that hasn't been agreed to.

**Fix:** added a `requiresPendingPayment` bool to `_ActionArea`, computed in the parent from `booking['requires_inspection']` and `booking['inspection_agreed_at']` — `true` (payment action allowed) whenever the service never required inspection *or* the seeker has already agreed to the technician's final price (`inspection_agreed_at` set, at which point the booking is a normal, already-finalized booking again per the two-date design). The "Complete Payment" condition now additionally requires this flag. Also extracted a small `_isRealTimestamp()` top-level helper (this file had two near-identical inline zero-date-sentinel checks already — `dual_verified_at` here, now `inspection_agreed_at` too — consolidated into one instead of writing a third copy).

Verified against the exact real booking that prompted this report (`id=75`, `status=pending`, `payment_status=unpaid`, `requires_inspection='1'`, `inspection_agreed_at=null` — confirmed via a live `curl` against `api/v1/seeker/bookings/show.php` with a real JWT, matching the field types/values the fix's condition expects) that `requiresPendingPayment` correctly evaluates to `false` for it. `flutter analyze` clean (no issues at all on this file, not even pre-existing style infos).
