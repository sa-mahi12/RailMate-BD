import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../core/supabase/supabase_client.dart';
import '../features/ai/key/byok_vault.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/supabase_auth_client.dart';
import '../features/auth/username/username_availability.dart';
import '../features/board/comments/comment.dart';
import '../features/board/post/post.dart';
import '../features/board/post/post_feed_state.dart';
import '../features/booking/seat_ui/seat_selection_state.dart' show SeatFetcher;
import '../features/bookings/booking_history.dart';
import '../features/graphql/graphql_client.dart';
import '../features/search/search_repository.dart';
import '../features/search/seat_inventory.dart';

/// F02 — application dependency composition (RailMate BD).
///
/// Single place where the running app binds feature slices to the hosted
/// backend. Constructed ONCE in `main.dart` after real
/// `Supabase.initialize` succeeds; every tab/screen receives closures or
/// state built from here — no screen constructs its own backend client.
///
/// Rules:
/// * Publishable (anon) key only; the service-role key never enters this
///   file, the app, or any test.
/// * Only the coordinator edits this file (workers request new closures via
///   their handoffs with exact code). This prevents shared-file contention.
/// * Failures from these closures are genuine backend errors surfaced by the
///   screens' normal error paths — never silent fallbacks, never fake rows.
class AppDependencies {
  /// Authenticated Supabase client from `Supabase.initialize`.
  ///
  /// Null only in [AppDependencies.test] (a real client starts background
  /// timers that break widget tests); backend closures throw [StateError]
  /// instead of touching the network when null.
  final SupabaseClient? client;

  /// Session state (restored once in `main.dart`).
  final AuthState auth;

  /// Hosted trip search (REST; GraphQL-first arrives with F04).
  final SearchApi searchApi;

  /// Read-only pg_graphql station client.
  final StationGraphqlClient graphql;

  AppDependencies({
    this.client,
    required this.auth,
    required this.searchApi,
    required this.graphql,
  });

  /// Production composition. Call only after
  /// `SupabaseBootstrap.instance.initialize(connect: supabaseConnect)`
  /// reports ready.
  factory AppDependencies.create() {
    final SupabaseClient client = Supabase.instance.client;
    final AppConfigParts parts = AppConfigParts.current();
    return AppDependencies(
      client: client,
      auth: AuthState(repository: AuthRepository(client: SupabaseAuthClient())),
      searchApi: SupabaseSearchApi(client),
      graphql: StationGraphqlClient(
        supabaseUrl: parts.url,
        anonKey: parts.anonKey,
      ),
    );
  }

  /// Test composition: no `Supabase.initialize` needed. [client] defaults
  /// to an unconnected instance (queries fail fast — tests assert error
  /// paths or inject slice-level fakes, never real rows).
  factory AppDependencies.test({
    required AuthState auth,
    required SearchApi searchApi,
    SupabaseClient? client,
    StationGraphqlClient? graphql,
  }) {
    return AppDependencies(
      client: client,
      auth: auth,
      searchApi: searchApi,
      graphql:
          graphql ??
          const StationGraphqlClient(
            supabaseUrl: 'http://localhost:54321',
            anonKey: 'test-anon-key',
          ),
    );
  }

  // ------------------------------------------------------------------
  // Seats (F02; availability rule extended by F06).
  // ------------------------------------------------------------------

  /// Backend client or a [StateError] when this is a client-less test
  /// composition.
  SupabaseClient get _backend {
    final SupabaseClient? backend = client;
    if (backend == null) {
      throw StateError('No backend client in this composition.');
    }
    return backend;
  }

  /// Live seat inventory for one trip (read-only).
  SeatFetcher get seatFetcher =>
      (String tripId) => fetchTripSeats(_backend, tripId);

  // ------------------------------------------------------------------
  // Journey Board: feed / posts / storage (F02; reactions/ratings in F13).
  // ------------------------------------------------------------------

  /// Newest-first board window.
  Future<List<Post>> fetchBoardPosts({
    int limit = PostFeedState.defaultLimit,
  }) async {
    final rows = await _backend
        .from('posts')
        .select()
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit)
        .timeout(const Duration(seconds: 15));
    return (rows as List)
        .map((row) => Post.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Authenticated post insert (RLS: own `user_id` only).
  Future<Post> createBoardPost({
    required String userId,
    required String body,
  }) async {
    final Post draft = Post.draft(userId: userId, body: body);
    final row = await _backend
        .from('posts')
        .insert(draft.toInsertMap())
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
    return Post.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Uploads board image bytes to the owned `post-media` path.
  Future<void> uploadBoardImage(String path, List<int> bytes) {
    return _backend.storage
        .from('post-media')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: false),
        )
        .timeout(const Duration(seconds: 30));
  }

  /// Best-effort orphan object delete.
  Future<void> deleteBoardObject(String path) {
    return _backend.storage
        .from('post-media')
        .remove(<String>[path])
        .timeout(const Duration(seconds: 30));
  }

  /// Orphan post-row delete (RLS: own rows only).
  Future<void> deleteBoardPost(String postId) {
    return _backend
        .from('posts')
        .delete()
        .eq('id', postId)
        .timeout(const Duration(seconds: 15));
  }

  /// Persists the uploaded image object path onto a board post row
  /// (F11 link step; RLS: own rows only).
  Future<Post> updateBoardPostImage({
    required String postId,
    required String imagePath,
  }) async {
    final row = await _backend
        .from('posts')
        .update(<String, String>{'image_path': imagePath})
        .eq('id', postId)
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
    return Post.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Public display URL for a board image (`post-media` is world-readable
  /// per migration 20260927000004 — no signed URL needed).
  String? boardImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    final String base = AppConfigParts.current().url.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    return '$base/storage/v1/object/public/post-media/$imagePath';
  }

  /// Live username availability against `public.usernames` (RLS: public
  /// read). Feeds the register screen's availability field (F03 follow-up).
  Future<UsernameAvailability> checkUsername(String raw) {
    return UsernameAvailabilityChecker(
      existsQuery: (String normalized) async {
        final rows = await _backend
            .from('usernames')
            .select('username')
            .eq('username', normalized)
            .limit(1)
            .timeout(const Duration(seconds: 15));
        return (rows as List).isNotEmpty;
      },
    ).check(raw);
  }

  /// Newest-first comments for one post.
  Future<List<Comment>> fetchComments({required String postId}) async {
    final rows = await _backend
        .from('post_comments')
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .timeout(const Duration(seconds: 15));
    return (rows as List)
        .map((row) => Comment.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// Authenticated comment insert (RLS: own `user_id` only).
  Future<Comment> addCommentRow({
    required String postId,
    required String userId,
    required String body,
  }) async {
    final Comment draft = Comment.draft(
      postId: postId,
      userId: userId,
      body: body,
    );
    final row = await _backend
        .from('post_comments')
        .insert(draft.toInsertMap())
        .select()
        .single()
        .timeout(const Duration(seconds: 15));
    return Comment.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Comment delete (RLS: own rows only).
  Future<void> deleteCommentRow(String commentId) {
    return _backend
        .from('post_comments')
        .delete()
        .eq('id', commentId)
        .timeout(const Duration(seconds: 15));
  }

  // ------------------------------------------------------------------
  // Booking history + cancel (F02 wiring; Edge deploy lands in F07).
  // ------------------------------------------------------------------

  /// History repository for one owner. Row reads are direct REST (RLS
  /// owner-only); cancel goes through the `cancel-booking` Edge Function,
  /// which fails with a genuine error until F07 deploys it.
  BookingHistoryRepository historyFor(String ownerId) {
    return BookingHistoryRepository(
      fetchRows: (String owner) async {
        final rows = await _backend
            .from('bookings')
            .select()
            .eq('user_id', owner)
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 15));
        return (rows as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      },
      cancelRpc: ({required String ownerId, required String bookingId}) async {
        final FunctionResponse response = await _backend.functions
            .invoke(
              'cancel-booking',
              body: <String, String>{'booking_id': bookingId},
            )
            .timeout(const Duration(seconds: 30));
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          response.data as Map,
        );
        return data['status'] == 'CANCELLED';
      },
    );
  }

  // ------------------------------------------------------------------
  // Booking submit (F07): payment-to-booking through the `book-trip` Edge
  // Function. The app never touches booking tables or the service-role key;
  // the Edge verifies the user JWT and calls the service-role-only
  // `book_trip_service` RPC with the VERIFIED uid. Returns the server-issued
  // booking id (uuid) on CONFIRMED; throws [BookingSubmitException] with the
  // genuine server code otherwise. Never fabricates a booking or ticket.
  // ------------------------------------------------------------------

  /// Submits one atomic booking after a simulated-success payment.
  ///
  /// [requestId] MUST be a UUID (Edge-enforced; the pre-F07 legacy
  /// pay-plus-microseconds simulation keys are rejected as INVALID_REQUEST).
  /// Callers pass `PaymentState.requestId`, constructed with a real UUID at
  /// the payment step so retries reuse the same idempotency key.
  Future<String> submitBooking({
    required String tripId,
    required String requestId,
    required List<String> passengerNames,
    required List<String> seatCodes,
    required bool simulateSuccess,
  }) {
    final body = buildBookTripBody(
      tripId: tripId,
      requestId: requestId,
      passengerNames: passengerNames,
      seatCodes: seatCodes,
      simulateSuccess: simulateSuccess,
    );
    return _backend.functions
        .invoke('book-trip', body: body)
        .timeout(const Duration(seconds: 30))
        .then((FunctionResponse response) {
          final data = Map<String, dynamic>.from(response.data as Map);
          return parseBookTripResponse(data);
        });
  }

  // ------------------------------------------------------------------
  // BYOK vault (account-scoped in F03; null scope until then).
  // ------------------------------------------------------------------

  /// Vault scoped to one account so two accounts never share key material.
  ByokVault vaultFor(String? accountId) =>
      ByokVault(backend: SecureStorageBackend(), accountId: accountId);
}

/// Genuine booking-submit failure from the `book-trip` Edge Function.
///
/// [code] is the server's public code (`SEAT_UNAVAILABLE`,
/// `TRIP_UNAVAILABLE`, `IDEMPOTENCY_CONFLICT`, `INVALID_REQUEST`,
/// `UNAUTHORIZED`, `BOOKING_FAILED`, ...). Screens map codes to honest
/// user-facing messages; `SEAT_UNAVAILABLE` must also trigger a seat
/// revalidation so the user reselects from live inventory.
class BookingSubmitException implements Exception {
  final String code;

  const BookingSubmitException(this.code);

  /// Human-readable message naming the genuine failure (no fake booking).
  String get message {
    switch (code) {
      case 'SEAT_UNAVAILABLE':
        return 'Those seats were just taken. No booking was created — '
            'please go back and pick from the live seat map.';
      case 'TRIP_UNAVAILABLE':
        return 'This trip is no longer available for booking. '
            'No booking was created.';
      case 'IDEMPOTENCY_CONFLICT':
        return 'This payment was already used for a different booking. '
            'No duplicate booking was created.';
      case 'PAYMENT_SIMULATION_FAILED':
        return 'DEMONSTRATION ONLY — payment simulation failed, '
            'no booking created, no charge.';
      case 'UNAUTHORIZED':
        return 'Please sign in again to complete the booking.';
      default:
        return 'Booking failed ($code). No booking was created.';
    }
  }

  @override
  String toString() => 'BookingSubmitException($code)';
}

/// Pure payload builder for the `book-trip` Edge Function body.
///
/// Mirrors the Edge's contract (`trip_id`, `request_id` UUIDs; 1–4
/// passengers; `seat_codes` aligned 1:1 with passengers;
/// `simulateSuccess` boolean). The Edge is the enforcer — this builder
/// only shapes the map so it is hermetically unit-testable.
Map<String, Object?> buildBookTripBody({
  required String tripId,
  required String requestId,
  required List<String> passengerNames,
  required List<String> seatCodes,
  required bool simulateSuccess,
}) {
  return <String, Object?>{
    'trip_id': tripId,
    'request_id': requestId,
    'passengers': <Map<String, String>>[
      for (final name in passengerNames) {'name': name.trim()},
    ],
    'seat_codes': List<String>.of(seatCodes),
    'simulateSuccess': simulateSuccess,
  };
}

/// Pure response parser for the `book-trip` Edge Function.
///
/// Returns the server-issued booking id on a CONFIRMED status payload;
/// throws [BookingSubmitException] with the genuine server code otherwise.
/// Never synthesises an id.
String parseBookTripResponse(Map<String, dynamic> data) {
  final status = data['status'];
  final bookingId = data['booking_id'];
  if (status == 'CONFIRMED' && bookingId is String && bookingId.isNotEmpty) {
    return bookingId;
  }
  final code = data['code'];
  if (code is String && code.isNotEmpty) {
    throw BookingSubmitException(code);
  }
  if (status == 'PAYMENT_SIMULATION_FAILED') {
    throw const BookingSubmitException('PAYMENT_SIMULATION_FAILED');
  }
  throw const BookingSubmitException('BOOKING_FAILED');
}

/// Display reference derived from a server-issued booking uuid.
///
/// Strips dashes and takes the first 8 hex chars uppercased (e.g.
/// `A1B2C3D4`) — a deterministic display transform of the real id, valid
/// per `TicketData.isValidReference` (bookings have no short human
/// reference column; the full uuid remains the cancel/history key).
/// Throws [ArgumentError] when no 8 hex chars can be derived.
String displayReferenceForBookingId(String bookingId) {
  final hex = bookingId.replaceAll('-', '');
  if (hex.length < 8 ||
      !RegExp(r'^[0-9a-fA-F]{8}').hasMatch(hex.substring(0, 8))) {
    throw ArgumentError.value(
      bookingId,
      'bookingId',
      'Cannot derive a display reference',
    );
  }
  return hex.substring(0, 8).toUpperCase();
}

/// Validated bootstrap config parts for composing URL-bound clients.
///
/// Reads the config that reached `ready` during startup; never key
/// material beyond the publishable key already held by the app.
class AppConfigParts {
  final String url;
  final String anonKey;

  const AppConfigParts({required this.url, required this.anonKey});

  factory AppConfigParts.current() {
    final config = SupabaseBootstrap.instance.config;
    if (config == null) {
      throw StateError(
        'SupabaseBootstrap has no ready config; '
        'AppDependencies.create() requires a successful initialize.',
      );
    }
    return AppConfigParts(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
  }
}
