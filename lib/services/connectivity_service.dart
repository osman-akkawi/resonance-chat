import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors real connectivity and exposes events for the engine
class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;

  bool _isOnline = true;
  bool _hasWifi = false;
  bool _hasMobile = false;
  List<ConnectivityResult> _lastResults = [];

  bool get isOnline => _isOnline;
  bool get hasWifi => _hasWifi;
  bool get hasMobile => _hasMobile;
  List<ConnectivityResult> get lastResults => _lastResults;

  /// Start monitoring
  Future<void> startMonitoring() async {
    // Initial check
    final results = await _connectivity.checkConnectivity();
    _updateFromResults(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _updateFromResults(results);
    });
  }

  void _updateFromResults(List<ConnectivityResult> results) {
    _lastResults = results;
    _hasWifi = results.contains(ConnectivityResult.wifi);
    _hasMobile = results.contains(ConnectivityResult.mobile);
    _isOnline = !results.contains(ConnectivityResult.none) &&
        (results.contains(ConnectivityResult.wifi) ||
         results.contains(ConnectivityResult.mobile) ||
         results.contains(ConnectivityResult.ethernet));
    notifyListeners();
  }

  /// Stop monitoring
  void stopMonitoring() {
    _subscription?.cancel();
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
