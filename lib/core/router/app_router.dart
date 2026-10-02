import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:pestify_flutter/core/auth/auth_state.dart';
import 'package:pestify_flutter/features/auth/screens/splash_screen.dart';
import 'package:pestify_flutter/features/auth/screens/login_screen.dart';
import 'package:pestify_flutter/features/auth/screens/register_screen.dart';
import 'package:pestify_flutter/features/auth/screens/otp_screen.dart';
import 'package:pestify_flutter/features/auth/screens/forgot_password_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/home_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/my_bookings_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/messages_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/profile_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/providers_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/provider_detail_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/listing_detail_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/book_service_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/payment_webview_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/payment_confirm_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/booking_detail_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/qr_display_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/enter_cn_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/remaining_payment_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/submit_review_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/notifications_screen.dart';
import 'package:pestify_flutter/features/seeker/screens/message_thread_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_home_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_listings_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_listing_form_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_requests_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_request_detail_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_prepare_booking_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_submit_inspection_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_reschedule_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_verify_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_scan_qr_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_messages_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_message_thread_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_notifications_screen.dart';
import 'package:pestify_flutter/features/provider/screens/provider_profile_screen.dart';
import 'package:pestify_flutter/features/landing/screens/landing_screen.dart';
import 'package:pestify_flutter/features/landing/screens/find_my_match_screen.dart';
import 'package:pestify_flutter/features/landing/screens/recommend_results_screen.dart';
import 'package:pestify_flutter/features/admin/screens/admin_dashboard_screen.dart';
import 'package:pestify_flutter/features/admin/screens/admin_providers_screen.dart';
import 'package:pestify_flutter/features/admin/screens/admin_provider_detail_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_home_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_attendance_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_leave_requests_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_payslips_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_my_bookings_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_change_password_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_subscription_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_subscription_webview_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_subscription_confirm_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_employees_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_staff_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_hr_leave_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_payroll_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_income_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_expenses_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_inventory_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_budget_requests_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_crm_bookings_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_crm_scan_qr_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_crm_services_screen.dart';
import 'package:pestify_flutter/features/portal/screens/portal_crm_outreach_screen.dart';

// ── Auth ChangeNotifier (refreshListenable bridge) ────────────────────────────

/// Wraps [AuthState] as a [ChangeNotifier] so [GoRouter.refreshListenable]
/// triggers a redirect re-evaluation whenever auth state changes.
class AuthChangeNotifier extends ChangeNotifier {
  AuthChangeNotifier();

  AuthState _state = AuthState.unauthenticated;

  AuthState get current => _state;

  /// Called by [appRouterProvider] via [Ref.listen] on every new
  /// [AuthState] emission.
  void update(AuthState next) {
    _state = next;
    notifyListeners();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Provides the single [GoRouter] instance for the app.
///
/// [authProvider] is wired as the router's [refreshListenable] through an
/// [AuthChangeNotifier] bridge, so the redirect callback re-runs on every
/// auth state change — including automatic logout when a 401 clears the token.
final Provider<GoRouter> appRouterProvider =
    Provider<GoRouter>((Ref<GoRouter> ref) {
  final AuthChangeNotifier notifier = AuthChangeNotifier();

  // Keep the notifier in sync with Riverpod auth state for the lifetime of
  // this provider.
  ref.listen<AuthState>(
    authProvider,
    (AuthState? previous, AuthState next) => notifier.update(next),
    fireImmediately: true,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    refreshListenable: notifier,

    // ── Global redirect ─────────────────────────────────────────────────────
    redirect: (BuildContext context, GoRouterState state) {
      final bool loggedIn = notifier.current.isLoggedIn;
      final String location = state.uri.toString();

      final bool goingToAuthScreen =
          location.startsWith('/login') ||
          location.startsWith('/register') ||
          location.startsWith('/otp') ||
          location.startsWith('/forgot-password') ||
          location.startsWith('/landing');

      // A handful of /seeker/* routes are read-only detail views backed by
      // guest-accessible PHP endpoints (listings/show.php, providers/show.php
      // require no auth, same as the web app) — letting guests open them from
      // the landing page / DSS results is what makes "explore before you sign
      // up" actually work. Everything else under /seeker/* (the shell tabs,
      // booking, messages, profile, ...) still requires login.
      final bool isGuestSafeSeekerRoute =
          location.startsWith('/seeker/listing/') ||
          location.startsWith('/seeker/provider/');

      // Protect every other /seeker/* route.
      if (location.startsWith('/seeker') && !loggedIn && !isGuestSafeSeekerRoute) {
        return '/login';
      }

      // Protect every /provider/* route — must be logged in AND a provider.
      if (location.startsWith('/provider')) {
        if (!loggedIn) return '/login';
        if (notifier.current.userType != 'provider') {
          return _homeForUserType(notifier.current.userType);
        }
      }

      // Protect every /admin/* route — must be logged in AND an admin. Login
      // is fully centralized through the single /login screen and
      // auth/login.php (which checks admin_users → provider_staff → users in
      // one cascade) — there is no separate /admin/login.
      if (location.startsWith('/admin')) {
        if (!loggedIn) return '/login';
        if (notifier.current.userType != 'admin') {
          return _homeForUserType(notifier.current.userType);
        }
      }

      // Protect every /portal/* route — must be logged in AND either a
      // promoted portal_staff (owner/hr/finance/crm) or a plain
      // portal_employee self-service account (see auth/login.php's
      // provider_staff/employees tiers).
      if (location.startsWith('/portal')) {
        if (!loggedIn) return '/login';
        final String? ut = notifier.current.userType;
        if (ut != 'portal_staff' && ut != 'portal_employee') {
          return _homeForUserType(ut);
        }
      }

      // Logged-in users who land on auth screens are sent home. Splash is
      // excluded — it performs its own imperative redirect after calling
      // AuthNotifier.init().
      if (loggedIn && goingToAuthScreen) {
        return _homeForUserType(notifier.current.userType);
      }

      return null; // no redirect needed
    },

    routes: <RouteBase>[
      // ── Splash ─────────────────────────────────────────────────────────────
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),

      // ── Landing (guests) ────────────────────────────────────────────────────
      GoRoute(
        path: '/landing',
        name: 'landing',
        builder: (BuildContext context, GoRouterState state) =>
            const LandingScreen(),
      ),

      // ── Decision Support System ("Find My Match") — guest-accessible ──────
      GoRoute(
        path: '/recommend',
        name: 'recommend',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra as Map<String, dynamic>?;
          final dynamic rawId = extra?['categoryId'];
          final int? categoryId =
              rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
          return FindMyMatchScreen(initialCategoryId: categoryId);
        },
      ),
      GoRoute(
        path: '/recommend/results',
        name: 'recommend-results',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return RecommendResultsScreen(
            result: extra['result'] as Map<String, dynamic>,
            budgetMax: extra['budgetMax'] as double?,
            urgency: extra['urgency']?.toString() ?? 'flexible',
            city: extra['city'] as String?,
          );
        },
      ),

      // ── Auth ────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: '/otp',
        name: 'otp',
        builder: (BuildContext context, GoRouterState state) {
          final String rawEmail =
              state.uri.queryParameters['email'] ?? '';
          return OtpScreen(email: Uri.decodeComponent(rawEmail));
        },
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (BuildContext context, GoRouterState state) =>
            const ForgotPasswordScreen(),
      ),

      // ── Seeker shell (StatefulShellRoute) ───────────────────────────────────
      //
      // The four persistent tabs (Home, Bookings, Messages, Profile) each live
      // in their own [StatefulShellBranch] so navigation stacks are independent
      // and scroll positions are preserved when switching tabs.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            _SeekerShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          // Branch 0 — Home
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/seeker/home',
                name: 'seeker-home',
                builder: (BuildContext context, GoRouterState state) =>
                    const HomeScreen(),
              ),
            ],
          ),
          // Branch 1 — Bookings
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/seeker/bookings',
                name: 'seeker-bookings',
                builder: (BuildContext context, GoRouterState state) =>
                    const MyBookingsScreen(),
              ),
            ],
          ),
          // Branch 2 — Messages
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/seeker/messages',
                name: 'seeker-messages',
                builder: (BuildContext context, GoRouterState state) =>
                    const MessagesScreen(),
              ),
            ],
          ),
          // Branch 3 — Profile
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/seeker/profile',
                name: 'seeker-profile',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Seeker — browse (full-screen push, outside shell) ─────────────────
      GoRoute(
        path: '/seeker/providers',
        name: 'seeker-providers',
        builder: (BuildContext context, GoRouterState state) =>
            const ProvidersScreen(),
      ),
      GoRoute(
        path: '/seeker/provider/:id',
        name: 'seeker-provider-detail',
        builder: (BuildContext context, GoRouterState state) {
          final int id =
              int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return ProviderDetailScreen(providerId: id);
        },
      ),
      GoRoute(
        path: '/seeker/listing/:id',
        name: 'seeker-listing-detail',
        builder: (BuildContext context, GoRouterState state) {
          final int id =
              int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return ListingDetailScreen(listingId: id);
        },
      ),

      // ── Seeker — booking flow ──────────────────────────────────────────────
      GoRoute(
        path: '/seeker/book',
        name: 'seeker-book',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra as Map<String, dynamic>?;
          // Accept 'listingId' (canonical) or legacy 'listing_id'.
          final dynamic rawId =
              extra?['listingId'] ?? extra?['listing_id'];
          final int listingId = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '') ?? 0;
          return BookServiceScreen(listingId: listingId);
        },
      ),
      GoRoute(
        path: '/seeker/payment',
        name: 'seeker-payment',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          final String checkoutUrl = extra['checkoutUrl'] as String;
          final dynamic rawId = extra['bookingId'];
          final int bookingId = rawId is int
              ? rawId
              : int.tryParse(rawId?.toString() ?? '') ?? 0;
          return PaymentWebViewScreen(
            checkoutUrl: checkoutUrl,
            bookingId: bookingId,
          );
        },
      ),
      GoRoute(
        path: '/seeker/payment-confirm',
        name: 'seeker-payment-confirm',
        builder: (BuildContext context, GoRouterState state) {
          final dynamic extra = state.extra;
          final int bookingId = extra is int
              ? extra
              : int.tryParse(extra?.toString() ?? '') ?? 0;
          return PaymentConfirmScreen(bookingId: bookingId);
        },
      ),
      GoRoute(
        path: '/seeker/booking/:id',
        name: 'seeker-booking-detail',
        builder: (BuildContext context, GoRouterState state) {
          final int id =
              int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return BookingDetailScreen(bookingId: id);
        },
      ),

      // ── Seeker — service-day & comms ──────────────────────────────────────
      GoRoute(
        path: '/seeker/qr',
        name: 'seeker-qr',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return QrDisplayScreen(qrToken: extra['qrToken'] as String);
        },
      ),
      GoRoute(
        path: '/seeker/verify',
        name: 'seeker-verify',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return EnterCnScreen(availId: extra['availId'] as int);
        },
      ),
      GoRoute(
        path: '/seeker/remaining-payment',
        name: 'seeker-remaining-payment',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return RemainingPaymentScreen(bookingId: extra['bookingId'] as int);
        },
      ),
      GoRoute(
        path: '/seeker/review',
        name: 'seeker-review',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return SubmitReviewScreen(availId: extra['availId'] as int);
        },
      ),
      GoRoute(
        path: '/seeker/notifications',
        name: 'seeker-notifications',
        builder: (BuildContext context, GoRouterState state) =>
            const NotificationsScreen(),
      ),
      GoRoute(
        path: '/seeker/message-thread',
        name: 'seeker-message-thread',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return MessageThreadScreen(
            bookingId: extra['bookingId'] as int,
            initialCompanyName: extra['companyName'] as String? ?? 'Provider',
            initialServiceName: extra['serviceName'] as String? ?? '',
            initialStatus: extra['status'] as String? ?? '',
          );
        },
      ),

      // ── Provider shell (Phase 2) ────────────────────────────────────────────
      //
      // Three persistent tabs (Dashboard, Listings, Requests), same
      // StatefulShellRoute pattern as the seeker shell above.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            _ProviderShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/provider/home',
                name: 'provider-home',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProviderHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/provider/listings',
                name: 'provider-listings',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProviderListingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/provider/requests',
                name: 'provider-requests',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProviderRequestsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/provider/messages',
                name: 'provider-messages',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProviderMessagesScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Provider — listings CRUD & requests (full-screen pushes) ───────────
      GoRoute(
        path: '/provider/listings/create',
        name: 'provider-listing-create',
        builder: (BuildContext context, GoRouterState state) =>
            const ProviderListingFormScreen(),
      ),
      GoRoute(
        path: '/provider/listings/edit',
        name: 'provider-listing-edit',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          final dynamic rawId = extra['listingId'];
          final int listingId =
              rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
          return ProviderListingFormScreen(
            listingId: listingId,
            initialListing: extra['listing'] as Map<String, dynamic>?,
          );
        },
      ),
      GoRoute(
        path: '/provider/requests/:id',
        name: 'provider-request-detail',
        builder: (BuildContext context, GoRouterState state) {
          final int id =
              int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return ProviderRequestDetailScreen(requestId: id);
        },
      ),
      GoRoute(
        path: '/provider/prepare-booking',
        name: 'provider-prepare-booking',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return ProviderPrepareBookingScreen(
            requestId: extra['requestId'] as int,
            isEdit: extra['isEdit'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/provider/submit-inspection',
        name: 'provider-submit-inspection',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return ProviderSubmitInspectionScreen(
            requestId: extra['requestId'] as int,
            isRevising: extra['isRevising'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/provider/reschedule',
        name: 'provider-reschedule',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return ProviderRescheduleScreen(requestId: extra['requestId'] as int);
        },
      ),
      GoRoute(
        path: '/provider/verify',
        name: 'provider-verify',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return ProviderVerifyScreen(availId: extra['availId'] as int);
        },
      ),
      GoRoute(
        path: '/provider/scan-qr',
        name: 'provider-scan-qr',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra =
              state.extra as Map<String, dynamic>?;
          return ProviderScanQrScreen(availId: extra?['availId'] as int?);
        },
      ),

      // ── Provider — comms & profile (full-screen pushes) ────────────────────
      GoRoute(
        path: '/provider/message-thread',
        name: 'provider-message-thread',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          final dynamic rawId = extra['bookingId'];
          final int bookingId =
              rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
          return ProviderMessageThreadScreen(
            bookingId: bookingId,
            initialSeekerName: extra['seekerName']?.toString() ?? 'Client',
            initialServiceName: extra['serviceName']?.toString() ?? '',
            initialStatus: extra['status']?.toString() ?? '',
          );
        },
      ),
      GoRoute(
        path: '/provider/notifications',
        name: 'provider-notifications',
        builder: (BuildContext context, GoRouterState state) =>
            const ProviderNotificationsScreen(),
      ),
      GoRoute(
        path: '/provider/profile',
        name: 'provider-profile',
        builder: (BuildContext context, GoRouterState state) =>
            const ProviderProfileScreen(),
      ),

      // ── Admin (Phase 3 — Dashboard + Provider approval slice) ──────────────
      // Login is centralized through /login (see the redirect guard above) —
      // there is no separate admin login route.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) =>
            _AdminShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/admin/dashboard',
                name: 'admin-dashboard',
                builder: (BuildContext context, GoRouterState state) =>
                    const AdminDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/admin/providers',
                name: 'admin-providers',
                builder: (BuildContext context, GoRouterState state) {
                  final Map<String, dynamic>? extra =
                      state.extra as Map<String, dynamic>?;
                  return AdminProvidersScreen(
                    initialStatus: extra?['status'] as String?,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/admin/providers/:id',
        name: 'admin-provider-detail',
        builder: (BuildContext context, GoRouterState state) {
          final int id =
              int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return AdminProviderDetailScreen(providerId: id);
        },
      ),

      // ── Provider portal (Phase 3: foundation shell) ───────────────────────
      GoRoute(
        path: '/portal/dashboard',
        name: 'portal-dashboard',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalHomeScreen(),
      ),

      // ── Provider portal (Phase 4: employee self-service) ──────────────────
      GoRoute(
        path: '/portal/attendance',
        name: 'portal-attendance',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalAttendanceScreen(),
      ),
      GoRoute(
        path: '/portal/leave-requests',
        name: 'portal-leave-requests',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalLeaveRequestsScreen(),
      ),
      GoRoute(
        path: '/portal/payslips',
        name: 'portal-payslips',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalPayslipsScreen(),
      ),
      GoRoute(
        path: '/portal/my-bookings',
        name: 'portal-my-bookings',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalMyBookingsScreen(),
      ),
      GoRoute(
        path: '/portal/change-password',
        name: 'portal-change-password',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalChangePasswordScreen(),
      ),

      // ── Provider portal (Phase 5: subscription tier + purchase) ───────────
      GoRoute(
        path: '/portal/subscription',
        name: 'portal-subscription',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalSubscriptionScreen(),
      ),
      GoRoute(
        path: '/portal/subscription-checkout',
        name: 'portal-subscription-checkout',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic> extra =
              state.extra as Map<String, dynamic>;
          return PortalSubscriptionWebViewScreen(
            checkoutUrl: extra['checkoutUrl'] as String,
          );
        },
      ),
      GoRoute(
        path: '/portal/subscription-confirm',
        name: 'portal-subscription-confirm',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalSubscriptionConfirmScreen(),
      ),

      // ── Provider portal (Phase 6: HR management) ───────────────────────────
      GoRoute(
        path: '/portal/staff',
        name: 'portal-staff',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalStaffScreen(),
      ),
      GoRoute(
        path: '/portal/employees',
        name: 'portal-employees',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalEmployeesScreen(),
      ),
      GoRoute(
        path: '/portal/hr/leave-requests',
        name: 'portal-hr-leave-requests',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalHrLeaveScreen(),
      ),
      GoRoute(
        path: '/portal/payroll',
        name: 'portal-payroll',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalPayrollScreen(),
      ),

      // ── Provider portal (Phase 7: Finance management) ──────────────────────
      GoRoute(
        path: '/portal/income',
        name: 'portal-income',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalIncomeScreen(),
      ),
      GoRoute(
        path: '/portal/expenses',
        name: 'portal-expenses',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalExpensesScreen(),
      ),
      GoRoute(
        path: '/portal/inventory',
        name: 'portal-inventory',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalInventoryScreen(),
      ),
      GoRoute(
        path: '/portal/budget-requests',
        name: 'portal-budget-requests',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalBudgetRequestsScreen(),
      ),

      // ── Provider portal (Phase 8: CRM) ──────────────────────────────────────
      GoRoute(
        path: '/portal/crm/bookings',
        name: 'portal-crm-bookings',
        builder: (BuildContext context, GoRouterState state) {
          final Map<String, dynamic>? extra = state.extra as Map<String, dynamic>?;
          return PortalCrmBookingsScreen(
            initialStatus: extra?['status'] as String?,
            title: extra?['title'] as String? ?? 'Bookings',
          );
        },
      ),
      GoRoute(
        path: '/portal/crm/scan-qr',
        name: 'portal-crm-scan-qr',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalCrmScanQrScreen(),
      ),
      GoRoute(
        path: '/portal/crm/services',
        name: 'portal-crm-services',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalCrmServicesScreen(),
      ),
      GoRoute(
        path: '/portal/crm/outreach',
        name: 'portal-crm-outreach',
        builder: (BuildContext context, GoRouterState state) =>
            const PortalCrmOutreachScreen(),
      ),
    ],
  );

  // Dispose the notifier when the provider is disposed.
  ref.onDispose(notifier.dispose);

  return router;
});

// ── Seeker bottom-nav shell ───────────────────────────────────────────────────

/// Persistent scaffold that holds the four seeker tabs in a [NavigationBar].
class _SeekerShell extends StatelessWidget {
  const _SeekerShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_TabItem> _tabs = <_TabItem>[
    _TabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    _TabItem(
      label: 'Bookings',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    _TabItem(
      label: 'Messages',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
    _TabItem(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            // Re-tapping the active tab pops to the branch root.
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: _tabs
            .map(
              (_TabItem t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

// ── Provider bottom-nav shell (Phase 2) ───────────────────────────────────────

/// Persistent scaffold that holds the three provider tabs in a [NavigationBar].
/// Same [StatefulShellRoute] pattern as [_SeekerShell].
class _ProviderShell extends StatelessWidget {
  const _ProviderShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_TabItem> _tabs = <_TabItem>[
    _TabItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
    ),
    _TabItem(
      label: 'Listings',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
    ),
    _TabItem(
      label: 'Requests',
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
    ),
    _TabItem(
      label: 'Messages',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: _tabs
            .map(
              (_TabItem t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Admin bottom-nav shell (Phase 3 — Dashboard + Providers slice) ──────────

/// Persistent scaffold holding the two built admin tabs in a [NavigationBar].
/// Same [StatefulShellRoute] pattern as [_SeekerShell]/[_ProviderShell].
class _AdminShell extends StatelessWidget {
  const _AdminShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_TabItem> _tabs = <_TabItem>[
    _TabItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
    ),
    _TabItem(
      label: 'Providers',
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: _tabs
            .map(
              (_TabItem t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: t.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Maps a [userType] string to the appropriate home route path.
String _homeForUserType(String? userType) {
  switch (userType) {
    case 'provider':
      return '/provider/home';
    case 'admin':
      return '/admin/dashboard';
    case 'portal_staff':
    case 'portal_employee':
      return '/portal/dashboard';
    case 'seeker':
    default:
      return '/seeker/home';
  }
}
