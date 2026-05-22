import "dart:async";

import "package:flutter/foundation.dart";

/// A small helper to trigger `go_router` refreshes from a `Stream`.
///
/// Some `go_router` versions ship a similar helper, but we include this locally
/// so the app builds consistently in CI.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  StreamSubscription<dynamic>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

