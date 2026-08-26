import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:pestify_flutter/core/auth/auth_storage.dart';

// ── Model ────────────────────────────────────────────────────────────────────

/// Immutable snapshot of the current authentication state.
///
/// All fields are nullable; [isLoggedIn] is the canonical "is the user
/// authenticated?" check — do not test [token] directly.
class AuthState {
  const AuthState({
    this.token,
    this.userType,
    this.userId,
    this.role,
  });

  /// Raw JWT string, or `null` when logged out.
  final String? token;

  /// One of: `'seeker'`, `'provider'`, `'admin'`, `'portal_staff'`.
  final String? userType;

  /// Numeric primary-key decoded from the JWT `sub` claim.
  final int? userId;

  /// Admin sub-role or portal department, e.g. `'hr'`, `'finance'`.
  /// Only populated when [userType] is `'admin'` or `'portal_staff'`.
  final String? role;

  /// True when the user holds a non-empty token.
  bool get isLoggedIn => token != null && token!.isNotEmpty;

  /// Returns a copy of this state with the supplied fields replaced.
  AuthState copyWith({
    String? token,
    String? userType,
    int? userId,
    String? role,
  }) {
    return AuthState(
      token: token ?? this.token,
      userType: userType ?? this.userType,
      userId: userId ?? this.userId,
      role: role ?? this.role,
    );
  }

  /// The logged-out sentinel.
  static const AuthState unauthenticated = AuthState();
}

// ── Notifier ─────────────────────────────────────────────────────────────────

/// Manages [AuthState] transitions and keeps [AuthStorage] in sync.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.unauthenticated);

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Decodes [token] and builds an [AuthState] from its claims.
  ///
  /// Expected JWT payload shape (set by the PHP backend):
  /// ```json
  /// {
  ///   "sub": 42,
  ///   "user_type": "seeker",
  ///   "role": "hr"          // optional
  /// }
  /// ```
  static AuthState _stateFromToken(String token) {
    if (token.isEmpty) return AuthState.unauthenticated;

    try {
      final Map<String, dynamic> claims = JwtDecoder.decode(token);
      final dynamic rawSub = claims['sub'];
      final int? userId = rawSub is int
          ? rawSub
          : rawSub != null
              ? int.tryParse(rawSub.toString())
              : null;

      return AuthState(
        token: token,
        userType: claims['user_type'] as String?,
        userId: userId,
        role: claims['role'] as String?,
      );
    } catch (_) {
      // Malformed token — treat as logged out.
      return AuthState.unauthenticated;
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Reads any persisted token from [AuthStorage] and restores state.
  /// Call once at app startup (e.g. in a ProviderScope override or SplashScreen).
  Future<void> init() async {
    final String? stored = await AuthStorage.getToken();
    if (stored == null || stored.isEmpty) return;

    // Reject tokens that have already expired so we don't enter an
    // inconsistent authenticated state without a valid token.
    if (JwtDecoder.isExpired(stored)) {
      await AuthStorage.deleteToken();
      return;
    }

    state = _stateFromToken(stored);
  }

  /// Persists [token], decodes it, and updates state.
  Future<void> login(String token) async {
    await AuthStorage.saveToken(token);
    state = _stateFromToken(token);
  }

  /// Deletes the stored token and resets state to [AuthState.unauthenticated].
  Future<void> logout() async {
    await AuthStorage.deleteToken();
    state = AuthState.unauthenticated;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Global [AuthState] provider. Read this anywhere in the widget tree.
///
/// ```dart
/// final authState = ref.watch(authProvider);
/// if (authState.isLoggedIn) { ... }
/// ```
final StateNotifierProvider<AuthNotifier, AuthState> authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
