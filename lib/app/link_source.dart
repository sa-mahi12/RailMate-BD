/// Incoming app-link source (RailMate BD).
///
/// Thin seam over `app_links` so [AppGate] can be driven in tests without
/// platform channels. Production uses [AppLinksSource]; tests inject a fake.
///
/// Single-owner rule: exactly one component — [AppGate] via this source —
/// consumes auth-callback links. `Supabase.initialize` is called WITHOUT
/// `authCallbackUrlHostname`, so the Supabase client performs no automatic
/// URI detection/exchange of its own; the PKCE `code` is exchanged exactly
/// once by the gate (see the consumed-code guard there).
library;

import 'dart:async';

import 'package:app_links/app_links.dart';

/// Cold-start link (the URI that launched the app, if any) plus the warm
/// stream (taps received while the app runs).
abstract class LinkSource {
  /// The link that launched the app, or null for a normal launch.
  Future<Uri?> getInitialLink();

  /// Links delivered while the app is already running.
  Stream<Uri> get uriLinkStream;
}

/// Production [LinkSource] backed by the `app_links` plugin.
class AppLinksSource implements LinkSource {
  final AppLinks _links = AppLinks();

  @override
  Future<Uri?> getInitialLink() => _links.getInitialLink();

  @override
  Stream<Uri> get uriLinkStream => _links.uriLinkStream;
}
