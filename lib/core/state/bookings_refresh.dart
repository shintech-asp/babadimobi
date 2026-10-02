import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped whenever a booking is created or otherwise mutated somewhere in
/// the app (currently: [BookServiceScreen]'s successful submit). My Bookings
/// (`my_bookings_screen.dart`) keeps each tab's fetched list alive for the
/// whole session via `AutomaticKeepAliveClientMixin` — it only ever refetches
/// on manual pull-to-refresh or when returning from a *pushed* booking-detail
/// screen. Creating a new booking happens on a completely separate screen
/// with no "return to My Bookings" navigation event to hook a refresh off
/// of, so without this signal a freshly-created booking would stay invisible
/// on the Active tab until the user thought to pull-to-refresh themselves —
/// even though the backend and the web app both show it immediately.
///
/// Usage: after a mutation, `ref.read(bookingsRefreshTick.notifier).state++;`
/// My Bookings' tabs `ref.listen` this and refetch whenever it changes.
final StateProvider<int> bookingsRefreshTick = StateProvider<int>((Ref ref) => 0);
