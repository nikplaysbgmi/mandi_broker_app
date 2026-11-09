import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/edit_promo_dialog.dart';
import '../widgets/edit_live_users_dialog.dart';
import '../widgets/github_workflow_dialog.dart';
import '../widgets/live_users_counter.dart';
import '../widgets/market_analyzer_tab.dart';
import '../widgets/promo_dialog.dart';

// =============================================================
// UNIVERSAL SAFE HELPERS FOR iOS SAFARI WEBKIT
// =============================================================
String formatMandiRate(dynamic value) {
  if (value == null) return '0';
  final num? n = value is num ? value : num.tryParse(value.toString().trim());
  if (n != null) {
    if (n % 1 == 0) {
      return n.toInt().toString();
    }
    final s = n.toString();
    if (s.endsWith('.0')) return s.substring(0, s.length - 2);
    return s.replaceAll(RegExp(r'\.0+$'), '');
  }
  final str = value.toString().trim();
  if (str.endsWith('.0')) return str.substring(0, str.length - 2);
  return str.replaceAll(RegExp(r'\.0+$'), '');
}

DateTime? _safeParseDateTime(dynamic raw) {
  if (raw == null) return null;
  try {
    if (raw is Timestamp) return raw.toDate().toLocal();
    if (raw is DateTime) return raw.toLocal();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim())?.toLocal();
    }
    if (raw is Map && raw['seconds'] != null) {
      final int sec = int.tryParse(raw['seconds'].toString()) ?? 0;
      if (sec > 0) {
        return DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
      }
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic> _safeExtractDocMap(dynamic snapshotData) {
  if (snapshotData == null) return <String, dynamic>{};
  try {
    dynamic rawMap;
    if (snapshotData is DocumentSnapshot) {
      rawMap = snapshotData.data();
    } else if (snapshotData is Map) {
      rawMap = snapshotData;
    }
    if (rawMap is Map) {
      final Map<String, dynamic> result = <String, dynamic>{};
      rawMap.forEach((key, value) {
        if (key != null) {
          result[key.toString()] = value;
        }
      });
      return result;
    }
  } catch (_) {}
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _safeExtractList(dynamic rawList) {
  if (rawList is! Iterable) return <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> cleanList = <Map<String, dynamic>>[];
  for (final dynamic element in rawList) {
    if (element is Map) {
      final Map<String, dynamic> itemMap = <String, dynamic>{};
      element.forEach((k, v) {
        if (k != null) itemMap[k.toString()] = v;
      });
      cleanList.add(itemMap);
    }
  }
  return cleanList;
}

class MarketWatchScreen extends StatefulWidget {
  const MarketWatchScreen({super.key});

  @override
  State<MarketWatchScreen> createState() => _MarketWatchScreenState();
}

class _MarketWatchScreenState extends State<MarketWatchScreen> {
  FirebaseFirestore? _db;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _prepareMarketDb();
  }

  Future<void> _prepareMarketDb() async {
    try {
      const FirebaseOptions marketOptions = FirebaseOptions(
        apiKey: "AIzaSyAW5OMM6rgbWoHmoPIjQX_Up27QvbYNzbE",
        authDomain: "mandi-market-view.firebaseapp.com",
        projectId: "mandi-market-view",
        storageBucket: "mandi-market-view.firebasestorage.app",
        messagingSenderId: "535917182908",
        appId: "1:535917182908:web:5e90a61f763c30d4eab5b9",
      );

      FirebaseApp app;
      if (Firebase.apps.any((a) => a.name == 'marketViewApp')) {
        app = Firebase.app('marketViewApp');
      } else {
        app = await Firebase.initializeApp(
          name: 'marketViewApp',
          options: marketOptions,
        ).timeout(const Duration(seconds: 4));
      }
      _db = FirebaseFirestore.instanceFor(app: app);
    } catch (e) {
      debugPrint('MarketWatch DB fallback: $e');
      _db = FirebaseFirestore.instance;
    }

    if (mounted) {
      setState(() => _isReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          try {
            PromoDialog.showIfActive(context);
          } catch (_) {}
        }
      });
    }
  }

  void _promptAdminPin(BuildContext context) {
    final pinController = TextEditingController();
    const String masterPin = "1895";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Admin Access (2nd Firestore)',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter 4-digit PIN',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF2B2B2B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722),
            ),
            onPressed: () {
              if (pinController.text.trim() == masterPin) {
                Navigator.pop(ctx);
                _showAdminSheet(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect PIN! Access denied.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Enter', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAdminSheet(BuildContext context) {
    final activeDb = _db ?? FirebaseFirestore.instance;
    showModalBottomSheet(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading:
                  const Icon(Icons.currency_rupee, color: Color(0xFF00E676)),
              title: const Text(
                'स्थानीय मंडी भाव अपडेट करें',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'mandi-market-view में भाव सेव होंगे',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (context) => EditLocalMandiRatesDialog(db: activeDb),
                );
              },
            ),
            const Divider(color: Color(0xFF2B2B2B), height: 1),
            ListTile(
              leading: const Icon(Icons.auto_graph_rounded,
                  color: Color(0xFF38BDF8)),
              title: const Text(
                'कमोडिटी भाव प्रिडिक्टर (Analyzer) अपडेट करें',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Analyzer के भाव, टारगेट व सलाह बदलें',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (context) => EditRatePredictionsDialog(db: activeDb),
                );
              },
            ),
            const Divider(color: Color(0xFF2B2B2B), height: 1),
            ListTile(
              leading: const Icon(Icons.campaign, color: Colors.deepOrange),
              title: const Text(
                'प्रमोशन / पोस्टर बदलें',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'ImgBB API / Firebase 2 में अपलोड करें',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (context) => const EditPromoDialog(),
                );
              },
            ),
            const Divider(color: Color(0xFF2B2B2B), height: 1),
            ListTile(
              leading: const Icon(Icons.visibility_rounded, color: Color(0xFF38BDF8)),
              title: const Text(
                'लाइव व्यूअर्स संख्या (Live Count) सेट करें',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Auto / Boost (+ संख्या) / Manual फिक्स काउंट सेट करें',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (context) => EditLiveUsersCountDialog(db: activeDb),
                );
              },
            ),
            const Divider(color: Color(0xFF2B2B2B), height: 1),
            ListTile(
              leading: const Icon(Icons.play_circle_fill_rounded,
                  color: Color(0xFF38BDF8)),
              title: const Text(
                'GitHub NCDEX Workflow चलाएं (Run Workflow)',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'गिटहब एक्शन स्क्रैपर रन करके लाइव भाव तुरंत सिंक करें',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                showDialog(
                  context: context,
                  builder: (context) => const GitHubWorkflowDialog(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDb = _db ?? FirebaseFirestore.instance;

    return StreamBuilder<Map<String, dynamic>>(
      stream: CloudSyncService.streamServiceSwitches(),
      builder: (context, switchSnap) {
        bool showAnalyzer = true;
        if (switchSnap.hasData && switchSnap.data != null) {
          final data = switchSnap.data!;
          if (data.containsKey('show_analyzer')) {
            final v = data['show_analyzer'];
            showAnalyzer =
                v is bool ? v : (v.toString().toLowerCase() == 'true');
          }
        }

        final int tabCount = showAnalyzer ? 3 : 2;

        return DefaultTabController(
          key: ValueKey<int>(tabCount),
          length: tabCount,
          initialIndex: 0,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
              title: GestureDetector(
                onLongPress: () => _promptAdminPin(context),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Live Bhav',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.show_chart, color: Colors.white70, size: 20),
                  ],
                ),
              ),
              actions: [
                if (_isReady) LiveUsersCounter(db: activeDb),
                const SizedBox(width: 6),
                const Center(child: BlinkingLiveBadge()),
                const SizedBox(width: 12),
              ],
              bottom: TabBar(
                indicatorColor: const Color(0xFFFF5722),
                indicatorWeight: 3.5,
                labelColor: const Color(0xFFFF5722),
                unselectedLabelColor: const Color(0xFF00E676),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
                tabs: [
                  const Tab(text: 'LOCAL'),
                  const Tab(text: 'NCDEX'),
                  if (showAnalyzer) const Tab(text: 'ANALYZER'),
                ],
              ),
            ),
            body: !_isReady
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF5722)),
                  )
                : TabBarView(
                    children: [
                      LocalMandiWatchList(db: activeDb),
                      NcdexWatchList(db: activeDb),
                      if (showAnalyzer) AnalyzerWatchList(db: activeDb),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

// =============================================================
// iOS-SAFE LIVE USERS COUNTER BADGE
// =============================================================
class SafeLiveUsersBadge extends StatelessWidget {
  final FirebaseFirestore db;
  const SafeLiveUsersBadge({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return LiveUsersCounter(db: db);
  }
}

// =============================================================
// BLINKING LIVE / CLOSED BADGE (09:00 AM - 05:00 PM IST)
// =============================================================
class BlinkingLiveBadge extends StatefulWidget {
  const BlinkingLiveBadge({super.key});

  @override
  State<BlinkingLiveBadge> createState() => _BlinkingLiveBadgeState();
}

class _BlinkingLiveBadgeState extends State<BlinkingLiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _isMarketOpen() {
    final now = DateTime.now().toLocal();
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }
    final int hour = now.hour;
    return hour >= 9 && hour < 17;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMarketOpen()) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 3.5, backgroundColor: Colors.white38),
            SizedBox(width: 5),
            Text(
              'CLOSED',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _opacityAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 3.5, backgroundColor: Colors.greenAccent),
            SizedBox(width: 5),
            Text(
              'LIVE',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// TAB 1: MCX WATCHLIST
// =============================================================
class McxWatchList extends StatelessWidget {
  final FirebaseFirestore db;
  const McxWatchList({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: db.collection('market_watch').doc('mcx_summary').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Connecting to MCX Feed...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
        }

        final Map<String, dynamic> docData = _safeExtractDocMap(snapshot.data);
        final List<Map<String, dynamic>> rates =
            _safeExtractList(docData['rates']);

        if (rates.isEmpty) {
          return const Center(
            child: Text(
              'No MCX quotes available',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          );
        }

        return ListView.separated(
          itemCount: rates.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Color(0xFF141414), height: 1, thickness: 1),
          itemBuilder: (context, index) {
            final Map<String, dynamic> item = rates[index];
            final String symbol = (item['symbol'] ?? '').toString();
            final String expiry = (item['expiry'] ?? 'NEAR').toString();

            final double ltp = double.tryParse(
                    (item['ltp'] ?? item['lastPrice'] ?? '0')
                        .toString()
                        .replaceAll(',', '')) ??
                0.0;
            final double change = double.tryParse(
                    (item['change'] ?? '0').toString().replaceAll(',', '')) ??
                0.0;

            final bool isPositive = change >= 0;
            final Color changeColor = change == 0
                ? const Color(0xFF00E676)
                : (isPositive
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFF3B30));

            return Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        symbol,
                        style: const TextStyle(
                          color: Color(0xFF29B6F6),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF262626),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          expiry,
                          style: const TextStyle(
                            color: Color(0xFF9E9E9E),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ltp.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        change >= 0
                            ? "(+${change.toStringAsFixed(0)})"
                            : "(${change.toStringAsFixed(0)})",
                        style: TextStyle(
                          color: changeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// =============================================================
// TAB 2: NCDEX WATCHLIST
// =============================================================
class NcdexWatchList extends StatelessWidget {
  final FirebaseFirestore db;
  const NcdexWatchList({super.key, required this.db});

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: db.collection('market_watch').doc('live_summary').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Connecting to NCDEX Feed...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
        }

        final Map<String, dynamic> docData = _safeExtractDocMap(snapshot.data);
        final DateTime? updatedAt = _safeParseDateTime(
          docData['updatedAt'] ?? docData['last_updated'],
        );

        final List<Map<String, dynamic>> rates = _safeExtractList(
          docData['commodities'] ?? docData['rates'],
        );

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF262626), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.sync,
                        size: 15,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        updatedAt != null
                            ? '${_formatDate(updatedAt)}  ${_formatTime(updatedAt)}'
                            : 'NCDEX Live Market',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'कृषि जिंस (Agri Futures)',
                      style: TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rates.isEmpty
                  ? const Center(
                      child: Text(
                        'No NCDEX contracts available',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rates.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: Color(0xFF171717),
                        height: 1,
                        thickness: 1,
                      ),
                      itemBuilder: (context, index) {
                        final Map<String, dynamic> item = rates[index];

                        final String displayName = (item['symbol'] ??
                                item['name'] ??
                                item['commodity'] ??
                                '')
                            .toString();

                        final String expiryDate =
                            (item['expiry'] ?? item['contract'] ?? 'NEAR')
                                .toString()
                                .trim();

                        final String rawPrice =
                            (item['lastPrice'] ?? item['ltp'] ?? '0')
                                .toString()
                                .replaceAll(',', '')
                                .trim();
                        final double ltp = double.tryParse(rawPrice) ?? 0.0;

                        final String rawChange = (item['change'] ?? '+0')
                            .toString()
                            .replaceAll(',', '')
                            .trim();
                        final double numChange =
                            double.tryParse(rawChange.replaceAll('+', '')) ??
                                0.0;

                        final bool isPositive =
                            !rawChange.startsWith('-') && numChange >= 0;
                        final Color changeColor = isPositive
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444);

                        final String changeText = isPositive
                            ? '(+${numChange.toStringAsFixed(0)})'
                            : '(${numChange.toStringAsFixed(0)})';

                        return Container(
                          color: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF262626),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      expiryDate,
                                      style: const TextStyle(
                                        color: Color(0xFF9E9E9E),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ltp > 0 ? ltp.toStringAsFixed(0) : rawPrice,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    changeText,
                                    style: TextStyle(
                                      color: changeColor,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================
// TAB 1: LOCAL MANDI
// =============================================================
class LocalMandiWatchList extends StatelessWidget {
  final FirebaseFirestore db;
  const LocalMandiWatchList({super.key, required this.db});

  String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream:
          db.collection('market_watch').doc('local_mandi_summary').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Connecting to Local Mandi Feed...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          );
        }

        final Map<String, dynamic> docData = _safeExtractDocMap(snapshot.data);
        final DateTime? updatedAtDate =
            _safeParseDateTime(docData['updatedAt']);
        final List<Map<String, dynamic>> rawRates =
            _safeExtractList(docData['rates']);
        final List<Map<String, dynamic>> rates = List.from(rawRates);

        // Ensure Guar Seed and Guar Gum are present in Local Mandi
        final existingNames =
            rates.map((e) => (e['name'] ?? '').toString()).toSet();
        final hasGuarSeed = existingNames.any((n) =>
            n.contains('ग्वार सीड') || n.toLowerCase().contains('guar seed'));
        if (!hasGuarSeed) {
          rates.add({
            'name': 'ग्वार सीड',
            'unit': 'क्विंटल',
            'min': 5200,
            'max': 5450,
          });
        }
        final hasGuarGum = existingNames.any((n) =>
            n.contains('ग्वार गम') || n.toLowerCase().contains('guar gum'));
        if (!hasGuarGum) {
          rates.add({
            'name': 'ग्वार गम',
            'unit': 'क्विंटल',
            'min': 9800,
            'max': 10400,
          });
        }

        // Canonical order placing Guar Seed at #4 and Guar Gum at #5
        const canonicalOrder = [
          'मूंग',
          'तिल',
          'मोठ',
          'ग्वार सीड',
          'ग्वार गम',
          'चना',
          'जीरा मंडी जोधपुर',
          'रायड़ा',
          'ईसबगोल',
          'बाजरा',
          'तारामीरा',
          'सौंफ',
          'कपास',
        ];

        int getCommodityPriority(String name) {
          for (int i = 0; i < canonicalOrder.length; i++) {
            final c = canonicalOrder[i];
            if (c == name ||
                (name.contains('ग्वार सीड') && c == 'ग्वार सीड') ||
                (name.contains('ग्वार गम') && c == 'ग्वार गम') ||
                (name.toLowerCase().contains('guar seed') && c == 'ग्वार सीड') ||
                (name.toLowerCase().contains('guar gum') && c == 'ग्वार गम') ||
                (name.contains(c) || c.contains(name))) {
              return i;
            }
          }
          return canonicalOrder.length;
        }

        rates.sort((a, b) {
          final nameA = (a['name'] ?? '').toString();
          final nameB = (b['name'] ?? '').toString();
          return getCommodityPriority(nameA).compareTo(getCommodityPriority(nameB));
        });

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                border: Border(
                  bottom: BorderSide(color: Color(0xFF262626), width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        updatedAtDate != null
                            ? _formatDate(updatedAtDate)
                            : _formatDate(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF00E676).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 3.5,
                          backgroundColor: Color(0xFF00E676),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          updatedAtDate != null
                              ? 'अपडेट: ${_formatTime(updatedAtDate)}'
                              : 'लाइव भाव',
                          style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rates.isEmpty
                  ? const Center(
                      child: Text(
                        'कोई मंडी भाव उपलब्ध नहीं है',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rates.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Color(0xFF141414), height: 1),
                      itemBuilder: (context, index) {
                        final Map<String, dynamic> item = rates[index];
                        String name = (item['name'] ?? '').toString();
                        if (name.contains('ग्वार सीड')) name = 'ग्वार सीड';
                        if (name.contains('ग्वार गम')) name = 'ग्वार गम';
                        final String unit =
                            (item['unit'] ?? 'क्विंटल').toString();
                        final String minRate = formatMandiRate(item['min']);
                        final String maxRate = formatMandiRate(item['max']);

                        return Container(
                          color: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Color(0xFF29B6F6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '($unit)',
                                    style: const TextStyle(
                                      color: Color(0xFF8E8E93),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "₹$minRate - ₹$maxRate",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    "मंडी भाव",
                                    style: TextStyle(
                                      color: Color(0xFF00E676),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================
// ADMIN DIALOG: LOCAL MANDI RATES
// =============================================================
class EditLocalMandiRatesDialog extends StatefulWidget {
  final FirebaseFirestore db;
  const EditLocalMandiRatesDialog({super.key, required this.db});

  @override
  State<EditLocalMandiRatesDialog> createState() =>
      _EditLocalMandiRatesDialogState();
}

class _EditLocalMandiRatesDialogState extends State<EditLocalMandiRatesDialog> {
  final List<String> commodities = [
    'मूंग',
    'तिल',
    'मोठ',
    'ग्वार सीड',
    'ग्वार गम',
    'चना',
    'जीरा मंडी जोधपुर',
    'रायड़ा',
    'ईसबगोल',
    'बाजरा',
    'तारामीरा',
    'सौंफ',
    'कपास',
  ];

  late Map<String, TextEditingController> minControllers;
  late Map<String, TextEditingController> maxControllers;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    minControllers = {for (var c in commodities) c: TextEditingController()};
    maxControllers = {for (var c in commodities) c: TextEditingController()};
    _loadExistingRates();
  }

  @override
  void dispose() {
    for (var c in minControllers.values) {
      c.dispose();
    }
    for (var c in maxControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingRates() async {
    try {
      final doc = await widget.db
          .collection('market_watch')
          .doc('local_mandi_summary')
          .get();
      if (!mounted) return;
      final map = _safeExtractDocMap(doc);
      final rates = _safeExtractList(map['rates']);
      for (var r in rates) {
        final name = (r['name'] ?? '').toString().trim();
        for (var c in commodities) {
          if (c == name ||
              (name.contains('ग्वार सीड') && c == 'ग्वार सीड') ||
              (name.contains('ग्वार गम') && c == 'ग्वार गम') ||
              (name.toLowerCase().contains('guar seed') && c == 'ग्वार सीड') ||
              (name.toLowerCase().contains('guar gum') && c == 'ग्वार गम')) {
            minControllers[c]?.text = formatMandiRate(r['min']);
            maxControllers[c]?.text = formatMandiRate(r['max']);
          } else if (minControllers.containsKey(name)) {
            minControllers[name]!.text = formatMandiRate(r['min']);
            maxControllers[name]!.text = formatMandiRate(r['max']);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveRates() async {
    setState(() => isSaving = true);
    final List<Map<String, dynamic>> rateList = [];

    for (var name in commodities) {
      final minVal = double.tryParse(minControllers[name]!.text.trim()) ?? 0;
      final maxVal = double.tryParse(maxControllers[name]!.text.trim()) ?? 0;
      rateList.add({
        'name': name,
        'unit': 'क्विंटल',
        'min': minVal % 1 == 0 ? minVal.toInt() : minVal,
        'max': maxVal % 1 == 0 ? maxVal.toInt() : maxVal,
      });
    }

    try {
      await widget.db
          .collection('market_watch')
          .doc('local_mandi_summary')
          .set({
        'rates': rateList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => isSaving = false);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text('स्थानीय मंडी भाव अपडेट करें',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: commodities.map((c) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      c,
                      style: const TextStyle(
                        color: Color(0xFF29B6F6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: minControllers[c],
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Min',
                        hintStyle: TextStyle(color: Colors.white38),
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: maxControllers[c],
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Max',
                        hintStyle: TextStyle(color: Colors.white38),
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : _saveRates,
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722)),
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('सेव करें', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
