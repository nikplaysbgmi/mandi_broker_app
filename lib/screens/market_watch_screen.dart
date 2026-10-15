import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../main.dart'; // Uses marketViewDb bound to mandi-market-view
import '../widgets/edit_promo_dialog.dart';
import '../widgets/live_users_counter.dart';
import '../widgets/offline_banner_wrapper.dart';
import '../widgets/promo_dialog.dart';

class MarketWatchScreen extends StatefulWidget {
  const MarketWatchScreen({super.key});

  @override
  State<MarketWatchScreen> createState() => _MarketWatchScreenState();
}

class _MarketWatchScreenState extends State<MarketWatchScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PromoDialog.showIfActive(context);
      }
    });
  }

  void _promptAdminPin(BuildContext context) {
    final pinController = TextEditingController();
    const String masterPin = "2000";

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
                backgroundColor: const Color(0xFFFF5722)),
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
                  builder: (context) => const EditLocalMandiRatesDialog(),
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OfflineBannerWrapper(
      child: DefaultTabController(
        length: 3,
        initialIndex: 1, // Default to NCDEX tab
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
                children: [
                  Text(
                    'MarketWatch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.show_chart, color: Colors.white70, size: 22),
                ],
              ),
            ),
            actions: const [
              LiveUsersCounter(),
              SizedBox(width: 4),
              Center(child: BlinkingLiveBadge()),
              SizedBox(width: 14),
            ],
            bottom: const TabBar(
              indicatorColor: Color(0xFFFF5722),
              indicatorWeight: 3.5,
              labelColor: Color(0xFFFF5722),
              unselectedLabelColor: Color(0xFF00E676),
              labelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.8,
              ),
              unselectedLabelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 0.8,
              ),
              tabs: [
                Tab(text: 'MCX'),
                Tab(text: 'NCDEX'),
                Tab(text: 'OTHERS'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              McxWatchList(),
              NcdexWatchList(),
              LocalMandiWatchList(),
            ],
          ),
        ),
      ),
    );
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
  const McxWatchList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: marketViewDb
          .collection('market_watch')
          .doc('mcx_summary')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        final docData = snapshot.data?.data();
        final List<dynamic> rates =
            (docData != null && docData['rates'] is List)
                ? docData['rates'] as List<dynamic>
                : <dynamic>[];

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
            final item = rates[index] as Map<String, dynamic>;
            final String symbol = item['symbol']?.toString() ?? '';
            final String expiry = item['expiry']?.toString() ?? '';
            final double ltp =
                (item['ltp'] is num) ? (item['ltp'] as num).toDouble() : 0.0;
            final double change = (item['change'] is num)
                ? (item['change'] as num).toDouble()
                : 0.0;

            final bool isPositive = change > 0;
            final Color changeColor = change == 0
                ? const Color(0xFF00E676)
                : (isPositive
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFF3B30));

            return Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                      const SizedBox(width: 10),
                      Text(
                        expiry,
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
                        ltp.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        change == 0
                            ? "(+0)"
                            : (isPositive
                                ? "(+${change.toStringAsFixed(0)})"
                                : "(${change.toStringAsFixed(0)})"),
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
// TAB 2: NCDEX WATCHLIST (PRESERVES GENUINE EXCHANGE EXPIRY)
// =============================================================
class NcdexWatchList extends StatelessWidget {
  const NcdexWatchList({super.key});

  static String _resolveExpiry(String? rawExpiry, int index, String symbol,
      Map<String, int> symbolCounts) {
    final count = symbolCounts[symbol] ?? 0;
    symbolCounts[symbol] = count + 1;

    final cleaned = rawExpiry?.replaceAll('-', ' ').trim().toUpperCase() ?? '';
    // If Firestore already has a real date (e.g. "19 OCT 2026"), use it directly
    if (cleaned.isNotEmpty &&
        !cleaned.contains('NEAR') &&
        !cleaned.contains('FAR')) {
      return cleaned;
    }

    // Fallback automatic calculation only if rawExpiry is missing or 'NEAR'/'FAR'
    final now = DateTime.now();
    final nearBase = now.day > 20
        ? DateTime(now.year, now.month + 1, 20)
        : DateTime(now.year, now.month, 20);

    const monthNames = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];

    final targetDate = (count == 0)
        ? nearBase
        : DateTime(nearBase.year, nearBase.month + 1, 20);

    return '20 ${monthNames[targetDate.month - 1]} ${targetDate.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: marketViewDb
          .collection('market_watch')
          .doc('live_summary')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        final docData = snapshot.data?.data();
        final List<dynamic> rates =
            (docData != null && docData['rates'] is List)
                ? docData['rates'] as List<dynamic>
                : <dynamic>[];

        if (rates.isEmpty) {
          return const Center(
            child: Text(
              'No NCDEX contracts available',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          );
        }

        final Map<String, int> symbolCounts = {};

        return ListView.separated(
          itemCount: rates.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Color(0xFF141414), height: 1, thickness: 1),
          itemBuilder: (context, index) {
            final item = rates[index] as Map<String, dynamic>;
            final String symbol = item['symbol']?.toString() ?? '';
            final String expiry = _resolveExpiry(
                item['expiry']?.toString(), index, symbol, symbolCounts);
            final double ltp =
                (item['ltp'] is num) ? (item['ltp'] as num).toDouble() : 0.0;
            final double change = (item['change'] is num)
                ? (item['change'] as num).toDouble()
                : 0.0;

            final bool isPositive = change > 0;
            final bool isZero = change == 0;
            final Color changeColor = isZero
                ? const Color(0xFF00E676)
                : (isPositive
                    ? const Color(0xFF00E676)
                    : const Color(0xFFFF3B30));

            return Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          symbol,
                          style: const TextStyle(
                            color: Color(0xFF29B6F6),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            expiry,
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ltp.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isZero
                            ? "(+0)"
                            : (isPositive
                                ? "(+${change.toStringAsFixed(0)})"
                                : "(${change.toStringAsFixed(0)})"),
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
// TAB 3: OTHERS / LOCAL MANDI (WITH DATE & UPDATE TIME BAR)
// =============================================================
class LocalMandiWatchList extends StatelessWidget {
  const LocalMandiWatchList({super.key});

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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: marketViewDb
          .collection('market_watch')
          .doc('local_mandi_summary')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF5722)),
          );
        }

        final docData = snapshot.data?.data();
        final Timestamp? timestamp = docData?['updatedAt'] as Timestamp?;
        final List<dynamic> rates =
            (docData != null && docData['rates'] is List)
                ? docData['rates'] as List<dynamic>
                : <dynamic>[];

        final DateTime? updatedAtDate = timestamp?.toDate().toLocal();

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
                        final item = rates[index] as Map<String, dynamic>;
                        final String name = item['name']?.toString() ?? '';
                        final String unit =
                            item['unit']?.toString() ?? 'क्विंटल';
                        final num minRate =
                            (item['min'] is num) ? item['min'] as num : 0;
                        final num maxRate =
                            (item['max'] is num) ? item['max'] as num : 0;

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
  const EditLocalMandiRatesDialog({super.key});

  @override
  State<EditLocalMandiRatesDialog> createState() =>
      _EditLocalMandiRatesDialogState();
}

class _EditLocalMandiRatesDialogState extends State<EditLocalMandiRatesDialog> {
  final List<String> commodities = [
    'मूंग',
    'तिल',
    'मोठ',
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
      final doc = await marketViewDb
          .collection('market_watch')
          .doc('local_mandi_summary')
          .get();
      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final List rates = doc.data()!['rates'] ?? [];
        for (var r in rates) {
          final name = r['name'];
          if (minControllers.containsKey(name)) {
            minControllers[name]!.text = r['min']?.toString() ?? '';
            maxControllers[name]!.text = r['max']?.toString() ?? '';
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveRates() async {
    setState(() => isSaving = true);
    final List<Map<String, dynamic>> rateList = [];

    for (var name in commodities) {
      rateList.add({
        'name': name,
        'unit': 'क्विंटल',
        'min': double.tryParse(minControllers[name]!.text.trim()) ?? 0,
        'max': double.tryParse(maxControllers[name]!.text.trim()) ?? 0,
      });
    }

    try {
      await marketViewDb
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
