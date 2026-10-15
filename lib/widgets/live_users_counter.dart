import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // Uses marketViewDb

class LiveUsersCounter extends StatefulWidget {
  const LiveUsersCounter({super.key});

  @override
  State<LiveUsersCounter> createState() => _LiveUsersCounterState();
}

class _LiveUsersCounterState extends State<LiveUsersCounter> {
  late final String _sessionId;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    // Unique session ID per app launch
    _sessionId =
        'user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    _sendHeartbeat();

    // Heartbeat sent every 50 seconds to keep session alive
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 50), (_) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    try {
      await marketViewDb.collection('live_presence').doc(_sessionId).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'platform': 'Android/Flutter',
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _removeSession() async {
    try {
      await marketViewDb.collection('live_presence').doc(_sessionId).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
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
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'वर्तमान में $count यूज़र इस समय ऐप देख रहे हैं।',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 10),
            const Text(
              'यह संख्या हर 60 सेकंड में रियल-टाइम अपडेट होती है।',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ठीक है',
                style: TextStyle(color: Color(0xFFFF5722))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cut-off threshold: users who sent heartbeat in the last 2 minutes
    final DateTime cutoff = DateTime.now().subtract(const Duration(minutes: 2));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: marketViewDb
          .collection('live_presence')
          .where('lastSeen', isGreaterThan: Timestamp.fromDate(cutoff))
          .snapshots(),
      builder: (context, snapshot) {
        // Fallback count to at least 1 (the current user)
        final int liveCount =
            (snapshot.hasData && snapshot.data!.docs.isNotEmpty)
                ? snapshot.data!.docs.length
                : 1;

        return InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showLiveUsersDialog(context, liveCount),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF29B6F6).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.person,
                  color: Color(0xFF29B6F6),
                  size: 15,
                ),
                const SizedBox(width: 4),
                Text(
                  '$liveCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
