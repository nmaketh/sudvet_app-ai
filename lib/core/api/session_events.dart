import 'dart:async';

/// Broadcasts when any API call receives an unrecoverable 401 response.
/// [AppBootstrap] subscribes and dispatches [AuthLogoutRequested].
final _sessionExpiredController = StreamController<void>.broadcast();

Stream<void> get onSessionExpired => _sessionExpiredController.stream;

void signalSessionExpired() => _sessionExpiredController.add(null);
