import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around [FlutterSecureStorage] for JWT persistence.
///
/// All methods are static so callers don't need to instantiate anything.
/// The storage options request hardware-backed keystore on Android and
/// the iOS Keychain with accessibility after first unlock.
class AuthStorage {
  AuthStorage._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _tokenKey = 'jwt_main';

  /// Persist [token] to secure storage. Overwrites any existing value.
  static Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  /// Returns the stored JWT, or `null` if none exists yet.
  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  /// Removes the stored JWT. Safe to call even when no token is stored.
  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
