// ignore_for_file: avoid_dynamic_calls

import 'dart:io' show File, Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_client.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';

/// Seeker-facing REST API surface.
///
/// Every method either returns a decoded value from the PHP success envelope
/// `{ "ok": true, "data": ... }` or throws a clean [Exception] with the
/// server's error message (extracted from `error` or `message` field).
///
/// The [ApiClient.unwrap] helper is used throughout to validate the envelope
/// and extract `data`. All [DioException]s are caught and rethrown as plain
/// [Exception]s with a user-readable message.
class SeekerApi {
  const SeekerApi(this._dio);

  final Dio _dio;

  /// Converts a [DioException] into a clean [Exception] whose message is the
  /// PHP `error` or `message` field when available, otherwise a generic
  /// network-error string.
  static Exception _handleDio(DioException e) {
    final dynamic body = e.response?.data;
    String msg = 'Network error. Please check your connection.';
    if (body is Map<String, dynamic>) {
      final dynamic err = body['error'] ?? body['message'];
      if (err is String && err.isNotEmpty) msg = err;
    }
    return Exception(msg);
  }

  /// Converts a [StateError] thrown by [ApiClient.unwrap] (e.g. when the
  /// server returns `{"ok": false, "error": "..."}` with HTTP 200) into a
  /// clean [Exception] whose message is the server's error text without the
  /// `Bad state: ` prefix that [StateError.toString()] prepends.
  static Exception _handleStateError(StateError e) {
    final String raw = e.message;
    return Exception(raw.isNotEmpty ? raw : 'An unexpected error occurred.');
  }

  // ── Browse ──────────────────────────────────────────────────────────────────

  /// Returns a paginated list of service listings.
  ///
  /// [search] is a free-text query. [categoryId] filters by category.
  /// [page] is 1-indexed.
  ///
  /// Returns the raw `data` value from the PHP envelope — typically a map
  /// with `items` (list) and pagination metadata.
  Future<Map<String, dynamic>> getListings({
    String? search,
    int? categoryId,
    int page = 1,
  }) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.listings,
        queryParameters: <String, dynamic>{
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null) 'category_id': categoryId,
          'page': page,
        },
      );
      // Return full body so callers can access both data[] and meta{}.
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      final String msg = (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns a paginated list of providers.
  ///
  /// [search] matches business name or description.
  /// [category] is a category slug or name string.
  /// [city] filters by city.
  /// [page] is 1-indexed.
  Future<Map<String, dynamic>> getProviders({
    String? search,
    String? category,
    String? city,
    int page = 1,
  }) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providers,
        queryParameters: <String, dynamic>{
          if (search != null && search.isNotEmpty) 'search': search,
          if (category != null && category.isNotEmpty) 'category': category,
          if (city != null && city.isNotEmpty) 'city': city,
          'page': page,
        },
      );
      // Return full body so callers can access both data[] and meta{}.
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      final String msg = (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the full profile of a single provider by [id].
  Future<Map<String, dynamic>> getProviderDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerDetail,
        queryParameters: <String, dynamic>{'id': id},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the full detail of a single service listing by [id].
  ///
  /// show.php returns `{ ok: true, data: {...listing...}, reviews: [...] }`.
  /// The reviews array is merged into the returned map under the 'reviews' key
  /// so callers can access both listing fields and reviews from a single map.
  Future<Map<String, dynamic>> getListingDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.listingDetail,
        queryParameters: <String, dynamic>{'id': id},
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        final Map<String, dynamic> listing = Map<String, dynamic>.from(
            (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{});
        final dynamic reviews = body['reviews'];
        if (reviews != null) listing['reviews'] = reviews;
        return listing;
      }
      final String msg = (body is Map
              ? (body['error'] ?? body['message'] ?? 'Server error')
              : 'Server error')
          .toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Bookings ────────────────────────────────────────────────────────────────

  /// Creates a new booking for the authenticated seeker.
  ///
  /// [listingId] — the `service_listings.id` being booked.
  /// [address] — service address supplied by the seeker.
  /// [preferredDate] — ISO-8601 date string (`YYYY-MM-DD`).
  /// [preferredTime] — time string (`HH:MM` or `HH:MM:SS`).
  /// [paymentMethod] — one of `'cash'`, `'gcash'`, `'paymongo'`, etc.
  /// [fullName] — contact name for the booking (pre-filled from profile).
  /// [contactNumber] — phone number for the booking (pre-filled from profile).
  ///
  /// Returns the created booking envelope from the server, typically
  /// containing the new `availed_service_id` and any payment URL.
  Future<Map<String, dynamic>> createBooking({
    required int listingId,
    required String address,
    required String preferredDate,
    required String preferredTime,
    required String paymentMethod,
    String? fullName,
    String? contactNumber,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.createBooking,
        data: <String, dynamic>{
          'listing_id': listingId,
          'address': address,
          'preferred_date': preferredDate,
          'preferred_time': preferredTime,
          'payment_method': paymentMethod,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
          if (contactNumber != null && contactNumber.isNotEmpty)
            'contact_number': contactNumber,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Confirms payment for a pending booking (e.g. after PayMongo redirect).
  ///
  /// [bookingId] is the `availed_services.id`.
  Future<Map<String, dynamic>> confirmPayment(int bookingId) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.confirmPayment,
        data: <String, dynamic>{'booking_id': bookingId},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns a paginated list of the seeker's bookings.
  ///
  /// [status] is an optional ENUM filter matching `availed_services.status`
  /// values (e.g. `'pending'`, `'on_going'`, `'completed'`).
  /// [page] is 1-indexed.
  Future<Map<String, dynamic>> getBookings({
    String? status,
    int page = 1,
  }) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.bookings,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'page': page,
        },
      );
      // Return full body so callers can access both data[] and meta{}.
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      final String msg = (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the full detail of a single booking by [id].
  ///
  /// show.php returns `{ ok: true, data: {...booking...}, review: {...} }`.
  /// The review is merged into the returned map under 'review'.
  Future<Map<String, dynamic>> getBookingDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.bookingDetail,
        queryParameters: <String, dynamic>{'id': id},
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        final Map<String, dynamic> booking = Map<String, dynamic>.from(
            (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{});
        final dynamic review = body['review'];
        if (review != null) booking['review'] = review;
        return booking;
      }
      final String msg = (body is Map
              ? (body['error'] ?? body['message'] ?? 'Server error')
              : 'Server error')
          .toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Requests cancellation of a booking.
  ///
  /// Throws [DioException] or [StateError] on failure. Returns void on
  /// success — callers should refresh the booking list after this resolves.
  Future<void> cancelBooking(int bookingId) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.cancelBooking,
        data: <String, dynamic>{'booking_id': bookingId},
      );
      ApiClient.unwrap(res); // validate ok=true; discard data
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Service day ─────────────────────────────────────────────────────────────

  /// Submits the seeker-side control number to complete dual verification.
  ///
  /// [availId] — `availed_services.id`.
  /// [controlNumber] — the 10-char code the seeker received.
  ///
  /// Returns the updated booking snapshot on success.
  Future<Map<String, dynamic>> verifyCn({
    required int availId,
    required String controlNumber,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.verifySeeker,
        data: <String, dynamic>{
          'avail_id': availId,
          'control_number': controlNumber,
        },
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the remaining balance due for a partially-paid booking.
  ///
  /// Useful for cash/on-site payment flows where a deposit was taken upfront.
  Future<Map<String, dynamic>> getRemainingPayment(int bookingId) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.remainingPayment,
        queryParameters: <String, dynamic>{'booking_id': bookingId},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Submits a review for a completed booking.
  ///
  /// [availId] — `availed_services.id`.
  /// [rating] — integer 1–5.
  /// [comment] — free-text review body.
  /// [image] — optional photo attachment. When provided, the request is sent
  ///   as `multipart/form-data`; otherwise as JSON.
  ///
  /// Returns the created review record on success.
  Future<Map<String, dynamic>> submitReview({
    required int availId,
    required int rating,
    required String comment,
    File? image,
  }) async {
    try {
      final Response<dynamic> res;

      if (image != null) {
        // Multipart — PHP reads $_FILES['image']
        final FormData formData = FormData.fromMap(<String, dynamic>{
          'avail_id': availId,
          'rating': rating,
          'comment': comment,
          'image': await MultipartFile.fromFile(
            image.path,
            filename: image.path.split(Platform.pathSeparator).last,
          ),
        });
        res = await _dio.post(ApiEndpoints.submitReview, data: formData);
      } else {
        // JSON — no file payload
        res = await _dio.post(
          ApiEndpoints.submitReview,
          data: <String, dynamic>{
            'avail_id': availId,
            'rating': rating,
            'comment': comment,
          },
        );
      }

      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Notifications ────────────────────────────────────────────────────────────

  /// Returns the notification list and unread count for the authenticated seeker.
  ///
  /// PHP response shape: `{ ok: true, data: [...], unread_count: N }`.
  /// Returns `{ 'items': List, 'unread_count': int }`.
  /// Callers cast individual items rather than the whole list to avoid
  /// unchecked cast warnings.
  Future<Map<String, dynamic>> getNotifications() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.notifications);
      final dynamic body = res.data;
      if (body is Map<String, dynamic>) {
        return <String, dynamic>{
          'items': body['data'] ?? <dynamic>[],
          'unread_count': body['unread_count'] ?? 0,
        };
      }
      return <String, dynamic>{'items': <dynamic>[], 'unread_count': 0};
    } on DioException catch (e) {
      throw _handleDio(e);
    }
  }

  /// Returns the count of unread notifications as a plain integer.
  ///
  /// PHP `notifications/count.php` returns `{ "ok": true, "count": N }` where
  /// `count` is at the top level of the envelope (not nested in `data`).
  Future<int> getNotificationCount() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.notifCount);
      final dynamic body = res.data;
      if (body is Map<String, dynamic>) {
        // Primary shape: { ok: true, count: N }
        final dynamic top = body['count'];
        if (top is int) return top;
        if (top != null) return int.tryParse(top.toString()) ?? 0;
        // Fallback: { ok: true, data: { count: N } }
        final dynamic data = body['data'];
        if (data is Map<String, dynamic>) {
          final dynamic nested = data['count'];
          if (nested is int) return nested;
          if (nested != null) return int.tryParse(nested.toString()) ?? 0;
        }
        // Fallback: { ok: true, data: N }
        if (data is int) return data;
      }
      return 0;
    } on DioException catch (e) {
      throw _handleDio(e);
    }
  }

  /// Marks all notifications as read for the authenticated seeker.
  Future<void> markNotificationsRead() async {
    try {
      final Response<dynamic> res =
          await _dio.post(ApiEndpoints.notifMarkRead);
      ApiClient.unwrap(res); // validate ok=true; discard data
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────────

  /// Returns the list of message conversations (one entry per provider).
  Future<List<dynamic>> getMessages() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.messages);
      final dynamic data = ApiClient.unwrap(res);
      return data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the ordered message thread between the seeker and [providerId].
  Future<List<dynamic>> getMessageThread(int providerId) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.messageThread,
        // thread.php reads $_GET['with'] — the user ID of the other party.
        queryParameters: <String, dynamic>{'with': providerId},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Sends a message to [receiverId] (a provider's user ID).
  ///
  /// Returns void on success — callers should reload the thread after this
  /// resolves to reflect the newly sent message.
  Future<void> sendMessage({
    required int receiverId,
    required String message,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.sendMessage,
        data: <String, dynamic>{
          'to': receiverId,
          'message': message,
        },
      );
      ApiClient.unwrap(res); // validate ok=true; discard data
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Profile ──────────────────────────────────────────────────────────────────

  /// Returns the authenticated seeker's profile data.
  ///
  /// Profile endpoint returns `{ "ok": true, "user": {...} }` — uses the
  /// `user` key rather than the standard `data` key, so ApiClient.unwrap()
  /// cannot be used here.
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.profile);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        final dynamic user = body['user'] ?? body['data'];
        if (user is Map<String, dynamic>) return user;
      }
      final String msg = (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Updates the authenticated seeker's profile.
  ///
  /// All parameters are optional — only provided fields are changed.
  /// [avatar] is an optional new profile photo. When provided the request is
  /// sent as `multipart/form-data`; otherwise as JSON.
  ///
  /// Returns the updated profile snapshot.
  Future<Map<String, dynamic>> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    File? avatar,
  }) async {
    try {
      final bool hasFile = avatar != null;

      final Response<dynamic> res;

      if (hasFile) {
        final Map<String, dynamic> fields = <String, dynamic>{
          if (firstName != null) 'first_name': firstName,
          if (lastName != null) 'last_name': lastName,
          if (phone != null) 'phone': phone,
          'avatar': await MultipartFile.fromFile(
            avatar.path,
            filename: avatar.path.split(Platform.pathSeparator).last,
          ),
        };
        res = await _dio.post(
          ApiEndpoints.profile,
          data: FormData.fromMap(fields),
        );
      } else {
        res = await _dio.post(
          ApiEndpoints.profile,
          data: <String, dynamic>{
            if (firstName != null) 'first_name': firstName,
            if (lastName != null) 'last_name': lastName,
            if (phone != null) 'phone': phone,
          },
        );
      }

      // Profile POST also returns {"ok": true, "user": {...}}, not "data"
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        final dynamic user = body['user'] ?? body['data'];
        if (user is Map<String, dynamic>) return user;
      }
      final String msg = (body is Map ? (body['error'] ?? body['message'] ?? 'Server error') : 'Server error').toString();
      throw StateError(msg);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Riverpod [Provider] for [SeekerApi].
///
/// Inject [dioProvider] so the singleton Dio instance (with its JWT and
/// error interceptors) is shared across all API classes.
///
/// Usage:
/// ```dart
/// final api = ref.read(seekerApiProvider);
/// final result = await api.getListings(page: 1);
/// ```
final Provider<SeekerApi> seekerApiProvider = Provider<SeekerApi>(
  (Ref ref) => SeekerApi(ref.watch(dioProvider)),
);
