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
          location.startsWith('/forgot-password');

      // Protect every /seeker/* route.
      if (location.startsWith('/seeker') && !loggedIn) {
        return '/login';
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
            providerId: extra['providerId'] as int,
            providerName: extra['providerName'] as String,
          );
        },
      ),

      // ── Provider (Phase 2) ────────────────────────────────────────────────
      GoRoute(
        path: '/provider/home',
        name: 'provider-home',
        builder: (BuildContext context, GoRouterState state) =>
            const _ProviderHomePlaceholder(),
      ),

      // ── Admin (Phase 3) ───────────────────────────────────────────────────
      GoRoute(
        path: '/admin/dashboard',
        name: 'admin-dashboard',
        builder: (BuildContext context, GoRouterState state) =>
            const _AdminDashboardPlaceholder(),
      ),

      // ── Provider portal (Phase 3) ─────────────────────────────────────────
      GoRoute(
        path: '/portal/dashboard',
        name: 'portal-dashboard',
        builder: (BuildContext context, GoRouterState state) =>
            const _PortalDashboardPlaceholder(),
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

// ── Phase-2+ placeholder screens ─────────────────────────────────────────────

class _ProviderHomePlaceholder extends StatelessWidget {
  const _ProviderHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provider Home')),
      body: const Center(child: Text('Provider home — coming soon')),
    );
  }
}

class _AdminDashboardPlaceholder extends StatelessWidget {
  const _AdminDashboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: const Center(child: Text('Admin dashboard — coming soon')),
    );
  }
}

class _PortalDashboardPlaceholder extends StatelessWidget {
  const _PortalDashboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portal')),
      body: const Center(child: Text('Provider portal — coming soon')),
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
    case 'portal_staff':
      return '/admin/dashboard';
    case 'seeker':
    default:
      return '/seeker/home';
  }
}
