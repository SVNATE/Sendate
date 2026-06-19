import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity changes and triggers appropriate actions.
/// Fixes the common KDE Connect / LocalSend issue of devices disappearing
/// after network changes (WiFi switch, hotspot toggle, etc).
class ConnectivityMonitor {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  final _changeController = StreamController<NetworkChangeEvent>.broadcast();

  List<ConnectivityResult> _lastResults = [];

  Stream<NetworkChangeEvent> get networkChanges => _changeController.stream;

  /// Start monitoring
  void start() {
    _subscription = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    // Get initial state
    _connectivity.checkConnectivity().then((results) => _lastResults = results);
  }

  /// Stop monitoring
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasConnected = _lastResults.any((r) => r != ConnectivityResult.none);
    final isConnected = results.any((r) => r != ConnectivityResult.none);
    final hadWifi = _lastResults.contains(ConnectivityResult.wifi);
    final hasWifi = results.contains(ConnectivityResult.wifi);

    NetworkChangeEvent? event;

    if (!wasConnected && isConnected) {
      // Went from offline to online
      event = NetworkChangeEvent(
        type: NetworkChangeType.connected,
        hasWifi: hasWifi,
        message: 'Network connected',
      );
    } else if (wasConnected && !isConnected) {
      // Went from online to offline
      event = NetworkChangeEvent(
        type: NetworkChangeType.disconnected,
        hasWifi: false,
        message: 'Network disconnected',
      );
    } else if (!hadWifi && hasWifi) {
      // Switched to WiFi (from mobile or other)
      event = NetworkChangeEvent(
        type: NetworkChangeType.wifiConnected,
        hasWifi: true,
        message: 'WiFi connected — restarting discovery',
      );
    } else if (hadWifi && !hasWifi && isConnected) {
      // Lost WiFi but still connected (mobile data)
      event = NetworkChangeEvent(
        type: NetworkChangeType.wifiLost,
        hasWifi: false,
        message: 'WiFi lost — discovery paused',
      );
    }

    _lastResults = results;

    if (event != null) {
      _changeController.add(event);
    }
  }

  /// Check if client isolation might be active (no response after broadcasts)
  Future<ConnectionDiagnostic> diagnoseConnection({
    required bool discoveryHasDevices,
    required Duration timeSinceStart,
  }) async {
    final results = await _connectivity.checkConnectivity();
    final hasWifi = results.contains(ConnectivityResult.wifi);

    if (!hasWifi) {
      return ConnectionDiagnostic(
        issue: ConnectionIssue.noWifi,
        suggestion: 'Connect to a WiFi network, or create a hotspot on one device and connect the other.',
        alternatives: ['Hotspot', 'WiFi Direct', 'QR Code', 'Manual IP'],
      );
    }

    if (!discoveryHasDevices && timeSinceStart > const Duration(seconds: 5)) {
      return ConnectionDiagnostic(
        issue: ConnectionIssue.clientIsolation,
        suggestion: 'Your router may have client isolation enabled, blocking device discovery. Try these alternatives:',
        alternatives: ['Create a Hotspot', 'Use WiFi Direct', 'Scan QR Code', 'Enter IP manually'],
      );
    }

    return ConnectionDiagnostic(
      issue: ConnectionIssue.none,
      suggestion: '',
      alternatives: [],
    );
  }

  void dispose() {
    stop();
    _changeController.close();
  }
}

enum NetworkChangeType { connected, disconnected, wifiConnected, wifiLost }
enum ConnectionIssue { none, noWifi, clientIsolation, firewallBlocking }

class NetworkChangeEvent {
  final NetworkChangeType type;
  final bool hasWifi;
  final String message;

  NetworkChangeEvent({required this.type, required this.hasWifi, required this.message});
}

class ConnectionDiagnostic {
  final ConnectionIssue issue;
  final String suggestion;
  final List<String> alternatives;

  ConnectionDiagnostic({required this.issue, required this.suggestion, required this.alternatives});
}
