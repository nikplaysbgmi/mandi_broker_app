import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // Uses marketViewDb as safe fallback

class LiveUsersCounter extends StatefulWidget {
  final FirebaseFirestore? db;
  const LiveUsersCounter({super.key, this.db});

  @override
  State<LiveUsersCounter> createState() => _LiveUsersCounterState();
}

class _LiveUsersCounterState extends State<LiveUsersCounter> {
  late final String _sessionId;
  Timer? _heartbeatTimer;
  Timer? _tickerTimer;
  Timer? _pruneTimer;

  FirebaseFirestore get _effectiveDb => widget.db ?? marketViewDb;

  @override
  void initState() {
    super.initState();
    // Unique session ID per app view
    _sessionId =
        'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    _sendHeartbeat();

    // Heartbeat every 30 seconds to maintain presence
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _sendHeartbeat();
    });

    // Local UI tick every 15 seconds to recalculate cutoff and drop inactive users
    _tickerTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });

    // Prune stale sessions (> 5 minutes old) every 3 minutes
    _pruneTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      if (mounted) _pruneStaleSessions();
    });
  }

  Future<void> _sendHeartbeat() async {
    final payload = {
      'lastSeen': FieldValue.serverTimestamp(),
      'clientTime': DateTime.now().millisecondsSinceEpoch,
      'platform': kIsWeb ? 'Web' : defaultTargetPlatform.name,
    };
    try {
      await _effectiveDb
          .collection('live_presence')
          .doc(_sessionId)
          .set(payload, SetOptions(merge: true));
    } catch (_) {}

    try {
      if (_effectiveDb != FirebaseFirestore.instance) {
        await FirebaseFirestore.instance
            .collection('live_presence')
            .doc(_sessionId)
            .set(payload, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _removeSession() async {
    try {
      await _effectiveDb.collection('live_presence').doc(_sessionId).delete();
    } catch (_) {}
    try {
      if (_effectiveDb != FirebaseFirestore.instance) {
        await FirebaseFirestore.instance
            .collection('live_presence')
            .doc(_sessionId)
            .delete();
      }
    } catch (_) {}
  }

  Future<void> _pruneStaleSessions() async {
    try {
      final staleCutoff = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );
      final snap = await _effectiveDb
          .collection('live_presence')
          .where('lastSeen', isLessThan: staleCutoff)
          .limit(10)
          .get();
      for (final doc in snap.docs) {
        if (doc.id != _sessionId) {
          doc.reference.delete().catchError((_) {});
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _tickerTimer?.cancel();
    _pruneTimer?.cancel();
    _removeSession();
    super.dispose();
  }

  void _showLiveUsersDialog(BuildContext context, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.people_alt_rounded, color: Color(0xFF29B6F6), size: 24),
            SizedBox(width: 8),
            Text(
              'लाइव यूज़र्स',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'वर्तमान में $count यूज़र इस समय लाइव मार्केट देख रहे हैं।',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 10),
            const Text(
              'यह संख्या रियल-टाइम में स्वतः अपडेट होती है।',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ठीक है',
              style: TextStyle(color: Color(0xFFFF5722)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          _effectiveDb.collection('market_watch').doc('live_users').snapshots(),
      builder: (context, configSnapshot) {
        Map<String, dynamic> configMap = {};
        if (configSnapshot.hasData && configSnapshot.data?.data() != null) {
          configMap = configSnapshot.data!.data()!;
        }
        final String mode = (configMap['mode'] ?? 'auto').toString();
        final int baseCount =
            int.tryParse(configMap['baseCount']?.toString() ?? '0') ?? 0;
        final int? fixedCount = int.tryParse(
          configMap['fixedCount']?.toString() ??
              configMap['count']?.toString() ??
              configMap['active']?.toString() ??
              configMap['users']?.toString() ??
              '',
        );

        return StreamBuilder<dynamic>(
          stream: _effectiveDb.collection('live_presence').snapshots(),
          builder: (context, presenceSnapshot) {
            final DateTime now = DateTime.now();
            final DateTime activeCutoff =
                now.subtract(const Duration(seconds: 120));

            int realActiveCount = 0;
            try {
              final querySnap = presenceSnapshot.data;
              if (querySnap != null && querySnap.docs != null) {
                for (final doc in querySnap.docs) {
                  if (doc.id == _sessionId) {
                    realActiveCount++;
                    continue;
                  }
                  dynamic rawData;
                  try {
                    rawData = doc.data();
                  } catch (_) {}
                  final Map<String, dynamic> data =
                      rawData is Map ? Map<String, dynamic>.from(rawData) : {};
                  final lastSeenRaw = data['lastSeen'];
                  DateTime? seenTime;
                  if (lastSeenRaw is Timestamp) {
                    seenTime = lastSeenRaw.toDate();
                  } else if (lastSeenRaw is int) {
                    seenTime = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
                  } else if (data['clientTime'] is int) {
                    seenTime = DateTime.fromMillisecondsSinceEpoch(
                        (data['clientTime'] as num).toInt());
                  }

                  if (seenTime != null &&
                      (seenTime.isAfter(activeCutoff) ||
                       now.difference(seenTime).abs().inSeconds < 120)) {
                    realActiveCount++;
                  }
                }
              }
            } catch (_) {}

            // At least 1 (the current user)
            if (realActiveCount < 1) realActiveCount = 1;

            int displayCount = realActiveCount;
            if (mode == 'manual' && fixedCount != null && fixedCount > 0) {
              displayCount = fixedCount;
            } else if (mode == 'boost' || baseCount > 0) {
              displayCount = realActiveCount + baseCount;
            } else if (fixedCount != null &&
                fixedCount > 0 &&
                configMap['mode'] == null &&
                configMap['count'] != null) {
              displayCount = fixedCount;
            }

            if (displayCount < 1) displayCount = 1;

            return Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showLiveUsersDialog(context, displayCount),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility,
                        size: 13,
                        color: Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$displayCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
