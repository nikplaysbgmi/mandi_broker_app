import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../services/cloud_sync_service.dart';

/// Wraps the entire application at the MaterialApp level to enforce a strict
/// full-screen internet lock whenever network connectivity is lost.
class StrictInternetLockWrapper extends StatefulWidget {
  final Widget child;

  const StrictInternetLockWrapper({
    super.key,
    required this.child,
  });

  @override
  State<StrictInternetLockWrapper> createState() =>
      _StrictInternetLockWrapperState();
}

class _StrictInternetLockWrapperState extends State<StrictInternetLockWrapper> {
  StreamSubscription<dynamic>? _connectivitySubscription;
  bool _isOffline = false;
  bool _isChecking = false;
  String? _retryMessage;

  @override
  void initState() {
    super.initState();
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    // 1. Initial connectivity check
    _checkInitialConnectivity();

    // 2. Real-time stream subscription
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (dynamic event) {
          if (!mounted) return;
          final offline = _determineIfOffline(event);
          if (offline != _isOffline) {
            setState(() {
              _isOffline = offline;
              if (!offline) {
                _retryMessage = null;
              }
            });
          }
        },
        onError: (err) {
          debugPrint('Connectivity stream error: $err');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Connectivity listener init failed: $e');
    }
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final dynamic results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      final offline = _determineIfOffline(results);
      setState(() => _isOffline = offline);
    } catch (e) {
      debugPrint('Initial connectivity check failed: $e');
    }
  }

  /// Safely resolves whether the device is offline across older and newer connectivity_plus versions
  bool _determineIfOffline(dynamic event) {
    if (event == null) return false;

    // Handled as List<ConnectivityResult> (connectivity_plus v6+)
    if (event is Iterable) {
      if (event.isEmpty) return false;
      return event.every((r) => r == ConnectivityResult.none);
    }

    // Handled as single ConnectivityResult (legacy fallback)
    if (event is ConnectivityResult) {
      return event == ConnectivityResult.none;
    }

    return false;
  }

  Future<void> _retryConnectivity() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _retryMessage = null;
    });

    try {
      final dynamic results = await Connectivity().checkConnectivity();
      final bool offlineByPlugin = _determineIfOffline(results);

      if (offlineByPlugin) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isChecking = false;
            _retryMessage =
                '⚠️ इंटरनेट नहीं मिला। कृपया अपना वाई-फ़ाई या मोबाइल डेटा चालू करें।';
          });
        }
        return;
      }

      // If network adapter is active, verify server reachability
      bool activeNet = true;
      try {
        activeNet = await CloudSyncService.hasActiveInternet();
      } catch (_) {
        activeNet = true;
      }

      if (mounted) {
        setState(() {
          _isOffline = !activeNet;
          _isChecking = false;
          if (!activeNet) {
            _retryMessage =
                '⚠️ नेटवर्क कनेक्टेड है पर इंटरनेट नहीं चल रहा है। कृपया डेटा कनेक्शन जांचें।';
          } else {
            _retryMessage = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _retryMessage = 'जांच में त्रुटि हुई। कृपया पुनः प्रयास करें।';
        });
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline)
          Positioned.fill(
            child: _buildLockScreen(context),
          ),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1320),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: const Color(0xFF16253B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Disconnected Icon
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.redAccent,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title
                  const Text(
                    'इंटरनेट कनेक्शन आवश्यक है',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'STRICT OFFLINE LOCK • INTERNET REQUIRED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Description
                  const Text(
                    'Mandi Trade Portal एक लाइव सुरक्षित क्लाउड सेवा है। डेटा सुरक्षा एवं रियल-टाइम सौदों के लिए बिना सक्रिय इंटरनेट के ऐप का उपयोग बंद (Locked) कर दिया गया है।',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Troubleshooting Checklist
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1320),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'कृपया निम्नलिखित जांचें:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 6),
                        _CheckItem(
                            text: 'मोबाइल डेटा (Mobile Data) या वाई-फ़ाई ऑन है?'),
                        _CheckItem(
                            text: 'एरोप्लेन मोड (Airplane Mode) बंद है?'),
                        _CheckItem(text: 'सिग्नल व इंटरनेट स्पीड सही है?'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Retry Feedback Message
                  if (_retryMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _retryMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  // Retry Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isChecking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 20),
                      label: Text(
                        _isChecking
                            ? 'कनेक्शन जांच रहे हैं...'
                            : 'पुनः प्रयास करें (Retry Connection)',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isChecking ? null : _retryConnectivity,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final String text;

  const _CheckItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF10B981),
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Backwards-compatible alias for any legacy references
typedef OfflineBannerWrapper = StrictInternetLockWrapper;
