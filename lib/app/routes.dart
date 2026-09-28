import 'package:flutter/material.dart';

import '../features/ai/key/byok_vault.dart';
import '../features/ai/key/key_setup_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/booking/passenger_ui/booking_review_screen.dart';
import '../features/booking/passenger_ui/passenger.dart';
import '../features/booking/passenger_ui/passenger_details_screen.dart';
import '../features/booking/passenger_ui/passenger_form_state.dart';
import '../features/booking/payment_ui/payment_screen.dart';
import '../features/booking/payment_ui/payment_state.dart';
import '../features/booking/seat_ui/seat_selection_screen.dart';
import '../features/booking/seat_ui/seat_selection_state.dart';
import '../features/bookings/booking_history_screen.dart';
import '../features/search/models/trip.dart';
import '../features/search/search_results_screen.dart';
import '../features/search/search_state.dart';
import '../features/station_guide/guide_detail_screen.dart';
import '../features/station_guide/guide_list_screen.dart';
import '../features/station_guide/station_guide.dart';
import '../features/ticket/ticket_data.dart';
import '../features/ticket/ticket_screen.dart';
import 'board_compose_host.dart';
import 'dependencies.dart';
import 'home_shell.dart' show SignInRequiredScreen;

/// Central route-name constants + [RouteFactory] for RailMate BD (I01, R-21).
///
/// No cycles by construction: every named push below lands on a screen whose
/// AppBar/close control calls `maybePop` (see each feature screen), so every
/// push has a pop path back to its tab root. Unknown names fall through to
/// [RouteErrorScreen] — they never crash and never strand the user.
abstract final class AppRoutes {
  static const String home = '/';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String searchResults = '/search-results';
  static const String seatSelection = '/seat-selection';
  static const String passengerDetails = '/passenger-details';
  static const String review = '/review';
  static const String payment = '/payment';
  static const String ticket = '/ticket';
  static const String history = '/history';
  static const String boardCompose = '/board/compose';
  static const String guide = '/guide';
  static const String guideDetail = '/guide/detail';
  static const String keySetup = '/ai/key-setup';

  /// Central [RouteFactory] used by the app and by every per-tab Navigator.
  ///
  /// [dependencies] supplies session state for account-gated routes; it is
  /// passed from [RailMateApp] so every tab shares one composition.
  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    AppDependencies? dependencies,
  }) {
    switch (settings.name) {
      case welcome:
        if (dependencies == null) {
          return _error(settings, 'App dependencies missing.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => WelcomeScreen(auth: dependencies.auth),
        );
      case login:
        if (dependencies == null) {
          return _error(settings, 'App dependencies missing.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => LoginScreen(auth: dependencies.auth),
        );
      case searchResults:
        final args = settings.arguments;
        if (args is! SearchResultsArgs) {
          return _error(settings, 'Search results need a search state.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => SearchResultsScreen(
            state: args.state,
            onSelectTrip: args.onSelectTrip,
          ),
        );
      case seatSelection:
        final args = settings.arguments;
        if (args is! SeatRouteArgs) {
          return _error(settings, 'Seat selection needs a trip.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => SeatSelectionScreen(
            trip: args.trip,
            state: args.state,
            onContinue: args.onContinue,
          ),
        );
      case passengerDetails:
        final args = settings.arguments;
        if (args is! PassengerRouteArgs) {
          return _error(settings, 'Passenger details need a form state.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => PassengerDetailsScreen(
            formState: args.formState,
            onContinue: args.onContinue,
          ),
        );
      case review:
        final args = settings.arguments;
        if (args is! ReviewRouteArgs) {
          return _error(settings, 'Review needs a form state.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => BookingReviewScreen(
            formState: args.formState,
            onEditJourney: args.onEditJourney,
            onEditPassengers: args.onEditPassengers,
            onConfirm: args.onConfirm,
          ),
        );
      case payment:
        final args = settings.arguments;
        if (args is! PaymentRouteArgs) {
          return _error(settings, 'Payment needs a form state.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => PaymentScreen(
            formState: args.formState,
            paymentState: args.paymentState,
            onSucceeded: args.onSucceeded,
          ),
        );
      case ticket:
        final args = settings.arguments;
        if (args is! TicketRouteArgs) {
          return _error(settings, 'Ticket needs a ticket snapshot.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => TicketScreen(ticket: args.ticket),
        );
      case history:
        if (dependencies == null) {
          return _error(settings, 'App dependencies missing.');
        }
        final String? uid = dependencies.auth.user?.id;
        if (uid == null) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Builder(
              builder: (context) => SignInRequiredScreen(
                title: 'My Trips',
                onSignIn: () =>
                    Navigator.of(context).pushReplacementNamed(login),
              ),
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => BookingHistoryScreen(
            repository: dependencies.historyFor(uid),
            ownerId: uid,
          ),
        );
      case boardCompose:
        final args = settings.arguments;
        final userId = args is BoardComposeRouteArgs ? args.userId : null;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              BoardComposeHost(userId: userId, dependencies: dependencies),
        );
      case guideDetail:
        final args = settings.arguments;
        if (args is! GuideDetailRouteArgs) {
          return _error(settings, 'Station guide needs a guide entry.');
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => GuideDetailScreen(guide: args.guide),
        );
      case keySetup:
        // Vault scoped to the signed-in account (null when logged out) so
        // two accounts on one device never share key material.
        final String? accountId = dependencies?.auth.user?.id;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => KeySetupScreen(
            vault: ByokVault(
              backend: SecureStorageBackend(),
              accountId: accountId,
            ),
          ),
        );
      case guide:
        // GuideListScreen is offline-first with zero required args, so the
        // named route can build it directly (see also the Guide tab root).
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const GuideListScreen(),
        );
      default:
        return _error(settings, 'Unknown route: ${settings.name}.');
    }
  }

  static MaterialPageRoute<void> _error(
    RouteSettings settings,
    String message,
  ) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => RouteErrorScreen(message: message),
    );
  }
}

/// Arguments for [AppRoutes.searchResults]: the tab-owned search state plus
/// the host callback that continues the booking journey.
class SearchResultsArgs {
  final SearchState state;
  final ValueChanged<Trip> onSelectTrip;

  const SearchResultsArgs({required this.state, required this.onSelectTrip});
}

/// Arguments for [AppRoutes.seatSelection].
class SeatRouteArgs {
  final Trip trip;
  final SeatSelectionState state;
  final ValueChanged<List<String>> onContinue;

  const SeatRouteArgs({
    required this.trip,
    required this.state,
    required this.onContinue,
  });
}

/// Arguments for [AppRoutes.passengerDetails].
class PassengerRouteArgs {
  final PassengerFormState formState;
  final ValueChanged<List<Passenger>> onContinue;

  const PassengerRouteArgs({required this.formState, required this.onContinue});
}

/// Arguments for [AppRoutes.review].
class ReviewRouteArgs {
  final PassengerFormState formState;
  final VoidCallback onEditJourney;
  final VoidCallback onEditPassengers;
  final VoidCallback onConfirm;

  const ReviewRouteArgs({
    required this.formState,
    required this.onEditJourney,
    required this.onEditPassengers,
    required this.onConfirm,
  });
}

/// Arguments for [AppRoutes.payment].
class PaymentRouteArgs {
  final PassengerFormState formState;
  final PaymentState paymentState;
  final VoidCallback onSucceeded;

  const PaymentRouteArgs({
    required this.formState,
    required this.paymentState,
    required this.onSucceeded,
  });
}

/// Arguments for [AppRoutes.ticket]: the confirmed ticket snapshot.
class TicketRouteArgs {
  final TicketData ticket;

  const TicketRouteArgs({required this.ticket});
}

/// Arguments for [AppRoutes.boardCompose]: nullable uid — null shows the
/// setup note while draft + AI Improve Wording stay usable.
class BoardComposeRouteArgs {
  final String? userId;

  const BoardComposeRouteArgs({this.userId});
}

/// Arguments for [AppRoutes.guideDetail].
class GuideDetailRouteArgs {
  final StationGuide guide;

  const GuideDetailRouteArgs({required this.guide});
}

/// Graceful placeholder for routes whose runtime dependency (Supabase client,
/// auth uid) is not wired at shell level yet. Never fakes data.
class SetupRequiredScreen extends StatelessWidget {
  final String title;
  final String missing;

  const SetupRequiredScreen({
    super.key,
    required this.title,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.construction_outlined,
                size: 48,
                color: Color(0xFF0E5A66),
              ),
              const SizedBox(height: 12),
              const Text(
                'Setup required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(missing, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error screen for unknown routes and invalid route arguments. Always has a
/// pop path (back chevron) so no route cycle can strand the user.
class RouteErrorScreen extends StatelessWidget {
  final String message;

  const RouteErrorScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Something went wrong'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
