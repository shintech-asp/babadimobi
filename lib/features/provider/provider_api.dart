// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pestify_flutter/core/api/api_client.dart';
import 'package:pestify_flutter/core/api/api_endpoints.dart';

/// Provider-facing REST API surface (Phase 2).
///
/// Mirrors [SeekerApi]'s conventions: every method either returns a decoded
/// value from the PHP success envelope `{ "ok": true, "data": ... }` or
/// throws a clean [Exception] with the server's error message.
class ProviderApi {
  const ProviderApi(this._dio);

  final Dio _dio;

  static Exception _handleDio(DioException e) {
    final dynamic body = e.response?.data;
    String msg = 'Network error. Please check your connection.';
    if (body is Map<String, dynamic>) {
      final dynamic err = body['error'] ?? body['message'];
      if (err is String && err.isNotEmpty) msg = err;
    }
    return Exception(msg);
  }

  static Exception _handleStateError(StateError e) {
    final String raw = e.message;
    return Exception(raw.isNotEmpty ? raw : 'An unexpected error occurred.');
  }

  static Future<List<MultipartFile>> _toMultipart(List<io.File> files) {
    return Future.wait(
      files.map(
        (io.File f) => MultipartFile.fromFile(
          f.path,
          filename: f.path.split(io.Platform.pathSeparator).last,
        ),
      ),
    );
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  /// Returns provider dashboard summary: stat counts, avg rating, the 5 most
  /// recent requests, plus `provider_status` and `company_name` (used to gate
  /// the "pending admin approval" banner).
  Future<Map<String, dynamic>> getDashboard() async {
    try {
      final Response<dynamic> res =
          await _dio.get(ApiEndpoints.providerDashboard);
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Listings ───────────────────────────────────────────────────────────────

  /// Returns this provider's own listings. [status] is `'active'` or
  /// `'inactive'`; omit for all.
  Future<Map<String, dynamic>> getListings({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerListings,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': 50,
        },
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Creates a new listing. [pricingType] must be one of `fixed`, `per_sqft`,
  /// `hourly`, `custom` (matches `service_listings.pricing_type`'s ENUM —
  /// NOT `per_sqm`, which the PHP validation used to (wrongly) accept).
  /// Returns the new listing's id.
  Future<int> createListing({
    required String title,
    required String description,
    required double price,
    required String pricingType,
    required int categoryId,
    required bool isEmergencyAvailable,
    required bool requiresInspection,
    required int duration,
    String durationUnit = 'hour',
    String? equipmentNotes,
    List<io.File> images = const <io.File>[],
    io.File? video,
  }) async {
    try {
      final FormData formData = FormData.fromMap(<String, dynamic>{
        'title': title,
        'description': description,
        'price': price.toString(),
        'pricing_type': pricingType,
        'category_id': categoryId.toString(),
        'is_emergency_available': isEmergencyAvailable ? '1' : '0',
        // Server forces this true regardless when pricing_type != 'fixed'
        // (store.php) — sent as-is either way, same as the web form.
        'requires_inspection': requiresInspection ? '1' : '0',
        'duration': duration.toString(),
        'duration_unit': durationUnit,
        if (equipmentNotes != null && equipmentNotes.isNotEmpty)
          'equipment_notes': equipmentNotes,
        // The key MUST include the literal "[]" suffix — Dio's
        // FormData.fromMap sends every item in a List<MultipartFile> under
        // the exact same bare field name with no brackets (verified against
        // dio 5.11.0's encodeMap/urlEncode: a MultipartFile list item isn't
        // a Map/List, so no index gets appended). PHP's multipart parser
        // only accumulates repeated-name file parts into $_FILES[...] as an
        // array when the name itself ends in "[]" (confirmed empirically);
        // without it, PHP silently keeps only the LAST file and drops the
        // rest. This was a real bug: picking 3 photos previously uploaded
        // only 1. PHP strips the trailing "[]" itself, so the backend still
        // sees a plain $_FILES['images'] key — no server-side change needed.
        if (images.isNotEmpty) 'images[]': await _toMultipart(images),
        if (video != null)
          'videos': await MultipartFile.fromFile(
            video.path,
            filename: video.path.split(io.Platform.pathSeparator).last,
          ),
      });
      final Response<dynamic> res =
          await _dio.post(ApiEndpoints.providerListingStore, data: formData);
      final dynamic data = ApiClient.unwrap(res);
      final dynamic id = (data as Map<String, dynamic>)['id'];
      return id is int ? id : int.tryParse(id.toString()) ?? 0;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Updates an existing listing. Only non-null fields are changed.
  ///
  /// [newImages] are uploaded and, by default, appended to the listing's
  /// existing images; pass [replaceImages] `true` to replace the entire set
  /// with just [newImages] instead (mirrors `update.php`'s `replace_images`
  /// flag — there is no per-image delete on the backend).
  Future<void> updateListing({
    required int id,
    String? title,
    String? description,
    double? price,
    String? pricingType,
    int? categoryId,
    bool? isEmergencyAvailable,
    bool? requiresInspection,
    String? status,
    int? duration,
    String? durationUnit,
    String? equipmentNotes,
    List<io.File> newImages = const <io.File>[],
    bool replaceImages = false,
    io.File? video,
  }) async {
    try {
      final FormData formData = FormData.fromMap(<String, dynamic>{
        'id': id.toString(),
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (price != null) 'price': price.toString(),
        if (pricingType != null) 'pricing_type': pricingType,
        if (categoryId != null) 'category_id': categoryId.toString(),
        if (isEmergencyAvailable != null)
          'is_emergency_available': isEmergencyAvailable ? '1' : '0',
        // Server forces this true regardless when the EFFECTIVE pricing_type
        // (new value if provided, else the listing's existing one) isn't
        // 'fixed' (update.php) — sent as-is either way, same as the web form.
        if (requiresInspection != null)
          'requires_inspection': requiresInspection ? '1' : '0',
        if (status != null) 'status': status,
        if (duration != null) 'duration': duration.toString(),
        if (durationUnit != null) 'duration_unit': durationUnit,
        if (equipmentNotes != null) 'equipment_notes': equipmentNotes,
        if (newImages.isNotEmpty) ...<String, dynamic>{
          // See the identical "[]" note in createListing() above.
          'images[]': await _toMultipart(newImages),
          if (replaceImages) 'replace_images': '1',
        },
        if (video != null)
          'videos': await MultipartFile.fromFile(
            video.path,
            filename: video.path.split(io.Platform.pathSeparator).last,
          ),
      });
      final Response<dynamic> res =
          await _dio.post(ApiEndpoints.providerListingUpdate, data: formData);
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Deactivates a listing (soft-delete — sets `status = 'inactive'`).
  Future<void> deactivateListing(int id) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerListingDelete,
        data: <String, dynamic>{'id': id},
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the full category list (`id`, `name`, ...) for the listing
  /// form's category picker. Not provider-scoped — same endpoint the seeker
  /// app would use, but there's no shared `getCategories()` on [SeekerApi]
  /// today, so this is its own call here.
  Future<List<dynamic>> getCategories() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.categories);
      final dynamic data = ApiClient.unwrap(res);
      return data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Service requests ─────────────────────────────────────────────────────────

  /// Returns this provider's booking requests. [status] is an exact
  /// `availed_services.status` match (the PHP endpoint has no grouping like
  /// the seeker side's `status=active`) — pass `null` for all statuses and
  /// bucket client-side.
  Future<Map<String, dynamic>> getRequests({String? status}) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerRequests,
        queryParameters: <String, dynamic>{
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': 100,
        },
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) return body;
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns the full detail of a single request, including the seeker's
  /// contact info and the `control_number` (PCF-…) the provider must enter.
  Future<Map<String, dynamic>> getRequestDetail(int id) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerRequestDetail,
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

  /// Transitions a booking's status. [status] must be one of the DB-canonical
  /// spellings `update-status.php` allows — `starting → on_going` is
  /// deliberately NOT among them; use [scanQr] for that step instead.
  Future<void> updateRequestStatus({
    required int id,
    required String status,
    String? notes,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerUpdateStatus,
        data: <String, dynamic>{
          'id': id,
          'status': status,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Submits the SEEKER's control number (PCF-…), which the provider
  /// received via notification, to complete the provider's side of the
  /// dual-verification handshake. Returns `{dual_verified, status, message}`.
  Future<Map<String, dynamic>> verifyCode({
    required int availId,
    required String controlNumber,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerVerify,
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

  /// Scans (or manually enters) the seeker's 6-char QR token to advance a
  /// `starting` booking to `on_going`. [token] may contain dashes — they are
  /// stripped server-side, but callers should strip them too for clean UX.
  Future<Map<String, dynamic>> scanQr(String token) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerScanQr,
        data: <String, dynamic>{'token': token},
      );
      final dynamic data = ApiClient.unwrap(res);
      return data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Equipment / staff assignment ────────────────────────────────────────────

  /// Assigns a field technician, an optional companion (co-staff), and
  /// equipment/consumables to a booking, checking out inventory server-side.
  /// Works both as the one-shot `accepted` -> `preparing` trigger AND,
  /// called again later, as the edit path for a booking that's already
  /// `preparing` (server diffs against what was assigned last time — see
  /// `prepareAvailedBooking()`/`deductInventoryForBooking()` in
  /// `includes/booking_workflow_helper.php`). Mirrors the web's "Prepare
  /// Booking" / "Edit Equipment & Staff" modal exactly.
  Future<void> prepareBooking({
    required int id,
    required int staffId,
    int? companionId,
    required List<Map<String, int>> equipment,
    required List<Map<String, int>> consumables,
    String? notes,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerPrepareBooking,
        data: <String, dynamic>{
          'id': id,
          'staff_id': staffId,
          if (companionId != null) 'companion_id': companionId,
          'equipment': jsonEncode(equipment),
          'consumables': jsonEncode(consumables),
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Inspection / reschedule / emergency ─────────────────────────────────────

  /// Submits (or resubmits, if the seeker requested changes) an inspection
  /// report for a `requires_inspection` booking sitting at 'accepted' or
  /// 'revising' — moves it to 'awaiting_agreement'. Always multipart since
  /// the photo is required server-side. [staffId] is optional — which field
  /// technician performed the inspection (from the same `field_staff` list
  /// `getRequestDetail()` already returns).
  Future<void> submitInspectionReport({
    required int availId,
    int? staffId,
    required String notes,
    required double proposedPrice,
    required String proposedWorkingDate,
    required io.File image,
  }) async {
    try {
      final FormData formData = FormData.fromMap(<String, dynamic>{
        'avail_id': availId,
        if (staffId != null) 'staff_id': staffId,
        'notes': notes,
        'proposed_price': proposedPrice,
        'proposed_working_date': proposedWorkingDate,
        'image': await MultipartFile.fromFile(
          image.path,
          filename: image.path.split(io.Platform.pathSeparator).last,
        ),
      });
      final Response<dynamic> res = await _dio.post(ApiEndpoints.providerSubmitInspection, data: formData);
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Accepts a booking's "Emergency Service Now" request — the same
  /// accepted->preparing bypass the web's `accept_emergency_now` handler
  /// does (see `api/v1/provider/requests/emergency-accept.php`).
  Future<void> acceptEmergency({required int availId}) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerEmergencyAccept,
        data: <String, dynamic>{'avail_id': availId},
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Proposes a new date/time for an accepted/preparing booking — the
  /// seeker then accepts or rejects it (already built on the seeker side of
  /// this app). Server re-validates working hours/slot fit and booking
  /// conflicts the same way `provider/service-requests.php` does.
  Future<void> requestReschedule({
    required int availId,
    required String rescheduleDate,
    required String rescheduleTime,
    required String rescheduleReason,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerReschedule,
        data: <String, dynamic>{
          'avail_id': availId,
          'reschedule_date': rescheduleDate,
          'reschedule_time': rescheduleTime,
          'reschedule_reason': rescheduleReason,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Messages (transaction-scoped: one thread per booking) ──────────────────
  //
  // Mirrors SeekerApi's identical methods exactly, pointed at the provider-
  // scoped endpoints (api/v1/provider/messages/*) — replaces the old
  // provider_id-scoped, lifetime-thread model this app used to have here,
  // which had fallen behind the web's already-shipped transaction-scoped
  // redesign (see CLAUDE.md's "Chat became transaction-scoped" entry).

  /// Returns one row per booking this provider has ever had, each a chat
  /// thread (even with zero messages yet).
  Future<List<dynamic>> getBookingThreads() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.providerBookingThreads);
      final dynamic data = ApiClient.unwrap(res);
      return data as List<dynamic>;
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Returns `{'messages': List, 'booking': Map}` for one booking's thread.
  /// Fetching also marks the provider's unread messages on it as read.
  Future<Map<String, dynamic>> getBookingThread(int bookingId) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerBookingThread,
        queryParameters: <String, dynamic>{'booking': bookingId},
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        return <String, dynamic>{
          'messages': body['data'] ?? <dynamic>[],
          'booking': body['booking'] ?? <String, dynamic>{},
        };
      }
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Polls for messages newer than [sinceId] on [bookingId], plus the
  /// booking's current status/chat_open.
  Future<Map<String, dynamic>> pollBookingMessages({
    required int bookingId,
    required int sinceId,
  }) async {
    try {
      final Response<dynamic> res = await _dio.get(
        ApiEndpoints.providerPollBookingMessages,
        queryParameters: <String, dynamic>{
          'booking': bookingId,
          'since': sinceId,
        },
      );
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        return <String, dynamic>{
          'messages': body['data'] ?? <dynamic>[],
          'status': body['status'],
          'chat_open': body['chat_open'] == true,
        };
      }
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Sends a message on [bookingId]'s thread. Rejected server-side if that
  /// booking's transaction is already closed (completed/cancelled).
  Future<void> sendBookingMessage({
    required int bookingId,
    required String message,
  }) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.providerSendBookingMessage,
        data: <String, dynamic>{
          'booking_id': bookingId,
          'message': message,
        },
      );
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Notifications ────────────────────────────────────────────────────────────

  /// Returns `{'items': List, 'unread_count': int}`. For a provider, booking
  /// items describe the seeker who booked; message items describe the sender.
  Future<Map<String, dynamic>> getNotifications() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.notifications);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        return <String, dynamic>{
          'items': body['data'] ?? <dynamic>[],
          'unread_count':
              int.tryParse(body['unread_count']?.toString() ?? '') ?? 0,
        };
      }
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Unread badge count. `count.php` returns `count` at the top level of the
  /// envelope, not nested under `data`.
  Future<int> getNotificationCount() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.notifCount);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        return int.tryParse(body['count']?.toString() ?? '') ?? 0;
      }
      return 0;
    } on DioException catch (e) {
      throw _handleDio(e);
    }
  }

  /// Marks booking + message notifications read for this provider.
  Future<void> markNotificationsRead() async {
    try {
      final Response<dynamic> res = await _dio.post(ApiEndpoints.notifMarkRead);
      ApiClient.unwrap(res);
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  // ── Profile ──────────────────────────────────────────────────────────────────

  /// Returns the provider's own profile. `profile.php` returns it under a
  /// `user` key (not `data`), and for providers merges in the `providers` row's
  /// `company_name`, `logo_url`, `description` and `service_radius`.
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final Response<dynamic> res = await _dio.get(ApiEndpoints.profile);
      final dynamic body = res.data;
      if (body is Map<String, dynamic> && body['ok'] == true) {
        final dynamic user = body['user'] ?? body['data'];
        if (user is Map<String, dynamic>) return user;
      }
      throw StateError(_bodyError(body));
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Updates the provider's profile. Personal fields land on `users`; the
  /// company fields ([companyName], [description], [serviceRadius]) land on
  /// `providers` — `profile.php` splits them itself. Only non-null fields
  /// are sent, and an [avatar] switches the request to multipart.
  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
    String? city,
    String? companyName,
    String? description,
    int? serviceRadius,
    io.File? avatar,
    List<io.File> portfolioImages = const <io.File>[],
    io.File? portfolioVideo,
  }) async {
    try {
      final Map<String, dynamic> fields = <String, dynamic>{
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (companyName != null) 'company_name': companyName,
        if (description != null) 'description': description,
        if (serviceRadius != null) 'service_radius': serviceRadius.toString(),
      };

      final Response<dynamic> res;
      if (avatar != null || portfolioImages.isNotEmpty || portfolioVideo != null) {
        res = await _dio.post(
          ApiEndpoints.profile,
          data: FormData.fromMap(<String, dynamic>{
            ...fields,
            if (avatar != null)
              'avatar': await MultipartFile.fromFile(
                avatar.path,
                filename: avatar.path.split(io.Platform.pathSeparator).last,
              ),
            // "[]" required — see the identical note on createListing()'s
            // images field; Dio sends every List<MultipartFile> item under
            // the bare key otherwise, and PHP keeps only the last one.
            if (portfolioImages.isNotEmpty)
              'portfolio_images[]': await _toMultipart(portfolioImages),
            if (portfolioVideo != null)
              'portfolio_video': await MultipartFile.fromFile(
                portfolioVideo.path,
                filename: portfolioVideo.path.split(io.Platform.pathSeparator).last,
              ),
          }),
        );
      } else {
        res = await _dio.post(ApiEndpoints.profile, data: fields);
      }

      final dynamic body = res.data;
      if (!(body is Map<String, dynamic> && body['ok'] == true)) {
        throw StateError(_bodyError(body));
      }
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  /// Removes one portfolio photo by its index in the gallery array.
  Future<void> removePortfolioImage(int index) async {
    try {
      final Response<dynamic> res = await _dio.post(
        ApiEndpoints.profile,
        data: <String, dynamic>{
          'remove_portfolio_image_index': index.toString(),
        },
      );
      final dynamic body = res.data;
      if (!(body is Map<String, dynamic> && body['ok'] == true)) {
        throw StateError(_bodyError(body));
      }
    } on DioException catch (e) {
      throw _handleDio(e);
    } on StateError catch (e) {
      throw _handleStateError(e);
    }
  }

  static String _bodyError(dynamic body) {
    return (body is Map
            ? (body['error'] ?? body['message'] ?? 'Server error')
            : 'Server error')
        .toString();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final Provider<ProviderApi> providerApiProvider = Provider<ProviderApi>(
  (Ref ref) => ProviderApi(ref.watch(dioProvider)),
);
