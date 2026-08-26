# CLAUDE.md — pestify_flutter

This file provides guidance to Claude Code when working inside `C:/Users/Isystem/pestify_flutter/`.

## What this project is

Flutter front-end for **Pestify** — a pest control service marketplace. This app is the mobile/web client for the PHP backend at `C:/xampp/htdocs/Pestify/`.

**Current scope:** Phase 1 (Seeker) is complete. Phase 2 (Provider) and Phase 3 (Admin + Portal Staff) have placeholder routes and are the next build targets.

**Run command:** `flutter run -d web-server --web-port 3000` — opens at `http://localhost:3000`.

---

## How to use the PHP backend as reference

**Always read the PHP file before writing or debugging any API call.** The PHP source is the single source of truth for:
- Exact field names (`req_inp('to', ...)` not `receiver_id`, etc.)
- Which fields are required vs optional (`req_inp` vs `inp`)
- Response envelope shape — especially endpoints that return extra top-level keys alongside `data`
- Validation rules (Cavite-only address, date format, allowed `status` values, etc.)

**PHP API files live at:** `C:/xampp/htdocs/Pestify/api/v1/<path matching ApiEndpoints constant>`

Examples:
- `ApiEndpoints.sendMessage` → `C:/xampp/htdocs/Pestify/api/v1/messages/send.php`
- `ApiEndpoints.createBooking` → `C:/xampp/htdocs/Pestify/api/v1/seeker/bookings/store.php`
- `ApiEndpoints.listingDetail` → `C:/xampp/htdocs/Pestify/api/v1/listings/show.php`

**For broader web architecture** (booking workflow, session/auth guards, DB schema, `.htaccess` routing): read `C:/xampp/htdocs/Pestify/CLAUDE.md`.

**When a new endpoint needs to be created** on the PHP side: follow the patterns in existing files in `api/v1/`. The `_bootstrap.php` file at the root of `api/v1/` sets up `db()`, `ok()`, `fail()`, `req_inp()`, `inp()`, `allow()`, `require_seeker()`, `current_provider()` helpers — read it first.

---

## Backend relationship

All data comes from the PHP API layer at `C:/xampp/htdocs/Pestify/api/v1/`. XAMPP must be running with Apache and MySQL before launching the Flutter app.

**API base URL** (set in `lib/core/api/api_endpoints.dart`):
- Flutter web: `http://localhost/pestify/api/v1`
- Android emulator: `http://10.0.2.2/pestify/api/v1`
- Real device: swap to LAN IP (e.g. `192.168.x.x/pestify/api/v1`)

**Auth:** JWT Bearer tokens. The PHP backend signs HS256 tokens with a 30-day expiry. Flutter stores the token in `flutter_secure_storage` via `lib/core/auth/auth_storage.dart`.

**Envelope contract:** Every PHP endpoint returns `{"ok": true, "data": ...}` on success or `{"ok": false, "error": "..."}` on failure. `ApiClient.unwrap(response)` validates the envelope and returns `body['data']`. Some endpoints (e.g. `show.php`) return extra top-level keys alongside `data` (e.g. `reviews`) — those must be read from `response.data` directly before calling `unwrap`, or extracted by reading `body['reviews']` after checking `body['ok'] == true`.

**When making PHP-side changes:** The corresponding endpoint file lives in `C:/xampp/htdocs/Pestify/api/v1/<path>`. Reference `FLUTTER_PLAN.md` in the PHP project root for the full endpoint map.

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
      booking_status_chip.dart     Colored status badge chip for booking cards
      error_banner.dart            Dismissable red error chip
      loading_button.dart          ElevatedButton with loading spinner
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
| `remainingPayment` | `/seeker/bookings/remaining-payment.php` | `api/v1/seeker/bookings/remaining-payment.php` |
| `verifySeeker` | `/seeker/bookings/verify.php` | `api/v1/seeker/bookings/verify.php` |
| `submitReview` | `/seeker/bookings/feedback.php` | `api/v1/seeker/bookings/feedback.php` |
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
| `cancelBooking(id)` | `void` | Pending/accepted only |
| `verifySeeker({availId, code})` | `Map` | Seeker enters provider's control number |
| `submitReview({availId, rating, feedback})` | `void` | |
| `confirmRemainingPayment(bookingId)` | `Map` with `checkout_url` | Downpayment flow second payment |
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

Provider role (`user_type: 'provider'`) logs in via the shared `auth/login.php` endpoint. After login the JWT payload is identical in shape; only `user_type` differs. Route them to `/provider/home`.

### Provider screens to build

| Route | Screen | API | Notes |
|-------|--------|-----|-------|
| `/provider/home` | Dashboard | `GET provider/dashboard.php` | Stat cards: pending requests, active bookings, completed jobs, active listings, avg rating, recent 5 requests |
| `/provider/listings` | My Listings | `GET provider/listings/index.php` | Active/inactive toggle, "Add" FAB |
| `/provider/listings/create` | Create Listing | `POST provider/listings/store.php` | Title, description, price, pricing type (`fixed`/`hourly`/`per_sqm`), category, multi-image upload, emergency flag |
| `/provider/listings/edit` (extra: `listingId`) | Edit Listing | `POST provider/listings/update.php` | Same form as create, pre-filled |
| `/provider/requests` | Service Requests | `GET provider/requests/index.php` | Status filter tabs, newest first |
| `/provider/requests/:id` | Request Detail | `GET provider/requests/show.php`, `POST provider/requests/update-status.php` | Seeker info, action buttons, PCF-… code displayed |
| `/provider/verify` (extra: `availId`) | Enter Seeker Code | `POST provider/requests/verify.php` | Provider enters seeker's PCF-… code verbally read aloud on service day |
| `/provider/scan-qr` (extra: `availId`) | QR Scanner | `POST provider/requests/scan-qr.php` | `starting` bookings only; camera scanner + manual 6-char entry; strip dashes before POST |

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
- **Listing images use multipart/form-data.** Use `dio`'s `FormData` + `MultipartFile.fromFile()` — never base64.
- **Provider status must be `approved` before listings are visible.** New provider accounts start as `pending` — admin must approve via the admin panel. Show an appropriate "pending approval" banner in the provider home screen until approved.

---

## Phase 3 — Admin Panel & Provider Portal Staff

Two separate role families share the `/admin/dashboard` and `/portal/dashboard` placeholder routes. They use **separate JWT signing flows** and **different login endpoints**.

### Auth separation

| Role family | Login endpoint | `user_type` | `role` claim |
|-------------|---------------|-------------|-------------|
| Admin panel | `admin/auth/login.php` | `admin` | `super_admin` \| `admin` \| `hr` \| `finance` |
| Portal staff | `portal/auth/login.php` | `portal_staff` | `owner` \| `hr` \| `finance` \| `crm` |

Do **not** mix JWTs — an admin JWT sent to a portal endpoint returns 403, and vice versa. Use separate `flutter_secure_storage` keys for each family (or split into separate Flutter apps).

Both login endpoints return `must_change_password: true` when the account has a temp password. If true: navigate to the Change Password screen and show **only** Change Password + Logout in the nav until the password is changed.

---

### Admin panel screens to build

Routes live under `/admin/*`. The admin JWT is required for all.

| Route | Screen | API | Roles |
|-------|--------|-----|-------|
| `/admin/dashboard` | Dashboard | `GET admin/dashboard.php` | super_admin, admin |
| `/admin/users` | Users list | `GET admin/users/index.php` | super_admin, admin |
| `/admin/users/:id` | User detail | `GET admin/users/show.php` | super_admin, admin |
| `/admin/providers` | Providers list | `GET admin/providers/index.php` | super_admin, admin |
| `/admin/providers/:id` | Provider detail + approve/reject | `GET admin/providers/show.php`, `POST admin/providers/approve.php`, `POST admin/providers/reject.php` | super_admin, admin |
| `/admin/bookings` | Bookings list | `GET admin/bookings/index.php` | super_admin, admin |
| `/admin/bookings/:id` | Booking detail | `GET admin/bookings/show.php` | super_admin, admin |
| `/admin/subscriptions` | Subscription plans | `GET admin/subscription-plans/index.php`, `POST admin/subscription-plans/store.php`, `POST admin/subscription-plans/update.php`, `POST admin/subscription-plans/activate.php`, `POST admin/subscription-plans/expire.php` | super_admin only |
| `/admin/logs` | Activity logs | `GET admin/logs/index.php` | super_admin, admin |
| `/admin/hr/employees` | HR — Employees | `GET admin/hr/employees/index.php` | super_admin, admin, hr |
| `/admin/hr/attendance` | HR — Attendance | `GET admin/hr/attendance/index.php` | super_admin, admin, hr |
| `/admin/hr/payroll` | HR — Payroll | `GET admin/hr/payroll/index.php` | super_admin, admin, hr |
| `/admin/hr/recruitment` | HR — Recruitment | `GET admin/hr/recruitment/index.php` | super_admin, admin, hr |
| `/admin/finance/income` | Finance — Income | `GET admin/finance/income/index.php` | super_admin, admin, finance |
| `/admin/finance/expenses` | Finance — Expenses | `GET admin/finance/expenses/index.php` | super_admin, admin, finance |
| `/admin/finance/requests` | Finance — Requests | `GET admin/finance/requests/index.php` | super_admin, admin, finance |

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
