import '../widgets/search_link_sauda_dialog.dart';
import '../widgets/manual_add_sauda_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/email_service.dart';
import '../services/mandi_services.dart';
import 'bill_print_screen.dart';
import 'broker_account_detail_screen.dart';
import 'main_dashboard_screen.dart';

// =============================================================
// 2. BUYER SECTION (LIVE CLOUD SYNC & ISOLATED LEDGERS)
// =============================================================
class BuyerSectionPortal extends StatefulWidget {
  final UserAccount user;

  const BuyerSectionPortal({super.key, required this.user});

  @override
  State<BuyerSectionPortal> createState() => _BuyerSectionPortalState();
}

class _BuyerSectionPortalState extends State<BuyerSectionPortal> {
  List<MandiSaudaModel> _allDeals = [];
  final Set<String> _locallyDeletedIds = {};
  late UserAccount _currentUser;
  StreamSubscription<bool>? _lockSubscription;

  // Search & Filter State
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _dateFilter =
      'ALL'; // 'ALL', 'TODAY', 'THIS_MONTH', 'LAST_30', 'CUSTOM'
  String _selectedFinancialYear = 'ALL'; // 'ALL' or 'FY 2026-27'
  DateTimeRange? _customDateRange;
  String? _selectedJins;
  int _activeTab = 0; // 0: All Deals, 1: Broker Ledgers

  List<String> get _availableFinancialYears {
    final currentFY = MandiSaudaModel.computeFinancialYear(DateTime.now());
    final set = <String>{currentFY};
    for (final d in _allDeals) {
      set.add(d.financialYear);
    }
    final list = set.toList();
    list.sort((a, b) => b.compareTo(a));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _currentUser = _resolveCompleteUser(widget.user);
    _loadLocalDeals();
    _startLiveAccountLockListener();
    // CloudSyncService.syncUserPersonalFolder decoupled
  }

  void _startLiveAccountLockListener() {
    if (_currentUser.mobile.isEmpty) return;

    _lockSubscription =
        CloudSyncService.streamAccountLockStatus('BUYER', _currentUser.mobile)
            .listen((isLocked) {
      if (isLocked && mounted) {
        _forceLogoutDueToLock();
      }
    });
  }

  void _forceLogoutDueToLock() {
    _lockSubscription?.cancel();

    StorageService.remove('session_BUYER');
    StorageService.remove('session_BUYER_mobile');

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.payment_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Text(
              'Subscription Due',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Your buyer account has been locked or requires renewal.\nPlease contact the Mandi administration.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (context) => const MainDashboardScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lockSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Fallback to saved session keys if widget.user has empty fields
  UserAccount _resolveCompleteUser(UserAccount incoming) {
    final name = incoming.name.trim().isNotEmpty
        ? incoming.name
        : (StorageService.get('session_BUYER_name') ?? 'BUYER USER');
    final mobile = incoming.mobile.trim().isNotEmpty
        ? incoming.mobile
        : (StorageService.get('session_BUYER_mobile') ??
            StorageService.get('session_BUYER') ??
            '');
    final email = incoming.email.trim().isNotEmpty
        ? incoming.email
        : (StorageService.get('session_BUYER_email') ?? '');
    final address = incoming.address.trim().isNotEmpty
        ? incoming.address
        : (StorageService.get('session_BUYER_address') ?? 'Address');

    return UserAccount(
      name: name,
      mobile: mobile,
      email: email,
      address: address,
      password: incoming.password,
      section: incoming.section,
    );
  }

  void _loadLocalDeals() {
    final raw = StorageService.get('buyer_records_${_currentUser.mobile}');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw);
        final all = list.map((e) => MandiSaudaModel.fromJson(e)).toList();
        setState(() {
          _allDeals = all;
        });
      } catch (_) {}
    }
  }

  void _persistLocalDeals() {
    StorageService.save(
      'buyer_records_${_currentUser.mobile}',
      jsonEncode(_allDeals.map((s) => s.toJson()).toList()),
    );
  }

  void _openBrokerAccountScreen({
    required String brokerFirmName,
    required String brokerMobile,
    required List<MandiSaudaModel> relatedDeals,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BrokerAccountDetailScreen(
          brokerFirmName: brokerFirmName,
          brokerMobile: brokerMobile,
          initialDeals: relatedDeals,
          currentUser: _currentUser,
          isBuyer: true,
          onSaudaEdited: (updated) {
            setState(() {
              final idx = _allDeals.indexWhere((x) => x.id == updated.id);
              if (idx != -1) {
                _allDeals[idx] = updated;
              } else {
                _allDeals.insert(0, updated);
              }
            });
            _persistLocalDeals();
          },
          onSaudaDeleted: (saudaId) {
            _locallyDeletedIds.add(saudaId);
            _locallyDeletedIds.add(saudaId.replaceAll('#', '').trim());
            setState(() {
              _allDeals.removeWhere((x) =>
                  x.id == saudaId ||
                  x.id == saudaId.replaceAll('#', '').trim());
            });
            _persistLocalDeals();
          },
        ),
      ),
    );
  }

// Filter deals based on Search query, Date filter, and Commodity selection
  List<MandiSaudaModel> _applyFilters(List<MandiSaudaModel> source) {
    final now = DateTime.now();

    return source.where((s) {
      // 1. Text Search Filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchJins = s.jins.toLowerCase().contains(q);
        final matchSeller = s.seller.toLowerCase().contains(q);
        final matchSellerMob = s.sellerMobile.contains(q);
        final matchBroker = s.brokerFirmName.toLowerCase().contains(q);
        final matchBrokerMob = s.brokerMobile.contains(q);
        if (!matchJins &&
            !matchSeller &&
            !matchSellerMob &&
            !matchBroker &&
            !matchBrokerMob) {
          return false;
        }
      }

      // 2. Commodity Filter
      if (_selectedJins != null && _selectedJins!.isNotEmpty) {
        if (s.jins.trim().toUpperCase() !=
            _selectedJins!.trim().toUpperCase()) {
          return false;
        }
      }

      // 3. Financial Year Filter
      if (_selectedFinancialYear != 'ALL') {
        if (s.financialYear != _selectedFinancialYear) {
          return false;
        }
      }

      // 4. Date Filter
      if (_dateFilter == 'TODAY') {
        if (s.date.year != now.year ||
            s.date.month != now.month ||
            s.date.day != now.day) {
          return false;
        }
      } else if (_dateFilter == 'THIS_MONTH') {
        if (s.date.year != now.year || s.date.month != now.month) {
          return false;
        }
      } else if (_dateFilter == 'LAST_30') {
        final cutoff = now.subtract(const Duration(days: 30));
        if (s.date.isBefore(cutoff)) {
          return false;
        }
      } else if (_dateFilter == 'CUSTOM' && _customDateRange != null) {
        final start = DateTime(_customDateRange!.start.year,
            _customDateRange!.start.month, _customDateRange!.start.day);
        final end = DateTime(_customDateRange!.end.year,
            _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
        if (s.date.isBefore(start) || s.date.isAfter(end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Computes commodity analytics from confirmed deals
  Map<String, Map<String, num>> _computeCommodityAnalytics(
      List<MandiSaudaModel> deals) {
    final Map<String, Map<String, num>> stats = {};

    for (var s in deals) {
      final crop = s.jins.trim().toUpperCase();
      if (crop.isEmpty) continue;

      if (!stats.containsKey(crop)) {
        stats[crop] = {'bags': 0, 'amount': 0.0, 'deals': 0};
      }
      stats[crop]!['bags'] = (stats[crop]!['bags']! + s.bags);
      stats[crop]!['amount'] = (stats[crop]!['amount']! + (s.bags * s.rate));
      stats[crop]!['deals'] = (stats[crop]!['deals']! + 1);
    }
    return stats;
  }

  Map<String, List<MandiSaudaModel>> _groupConfirmedDealsByBroker(
      List<MandiSaudaModel> deals) {
    final Map<String, List<MandiSaudaModel>> grouped = {};
    for (var s in deals) {
      final key = s.brokerFirmName.isNotEmpty
          ? s.brokerFirmName
          : (s.brokerMobile.isNotEmpty
              ? 'Broker (${s.brokerMobile})'
              : 'General Broker');
      if (!grouped.containsKey(key)) grouped[key] = [];
      grouped[key]!.add(s);
    }
    return grouped;
  }

  // Opens Custom Date Range Picker
  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F766E),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _customDateRange = picked;
        _dateFilter = 'CUSTOM';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CloudSyncService.streamBuyerSaudas(_currentUser.mobile),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _allDeals = snapshot.data!
              .map((data) => MandiSaudaModel.fromJson(data))
              .where((s) =>
                  !_locallyDeletedIds.contains(s.id) &&
                  !_locallyDeletedIds.contains(s.id.replaceAll('#', '').trim()))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
        }

        // Apply filters
        final filteredDeals = _applyFilters(_allDeals);
        final brokerAccounts = _groupConfirmedDealsByBroker(filteredDeals);

        // Commodity Analytics Map
        final commodityStats = _computeCommodityAnalytics(_allDeals);

        final userNotifications =
            NotificationService.getForMobile(_currentUser.mobile);

        return Theme(
          data: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF1F5F9),
            canvasColor: const Color(0xFFF1F5F9),
            cardColor: Colors.white,
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0284C7),
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            appBar: AppBar(
              title: Text(
                'BUYER PORTAL (${_currentUser.name})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black87,
              elevation: 1,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'बही में सौदा जोड़ें (Add Deal to Book)',
                  onPressed: () => showManualAddSaudaDialog(
                    context: context,
                    currentUser: _currentUser,
                    userRole: 'BUYER',
                    existingDeals: _allDeals,
                    onSaudaAdded: () => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  tooltip: 'ब्रोकर खाते (View Broker Accounts)',
                  onPressed: () => setState(() => _activeTab = 1),
                ),
                IconButton(
                  icon: const Icon(Icons.print_outlined),
                  tooltip: 'प्रिंट बही (Print Khata)',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MandiBillPrintScreen(
                          party: MandiPartyModel(
                            name: _currentUser.name,
                            mobile: _currentUser.mobile,
                            address: _currentUser.address,
                            type: 'Buyer',
                          ),
                          isBuyer: true,
                          deals: _allDeals,
                          selectedPeriod:
                              'क्रेता बही खाता (${_currentUser.name})',
                          brokerProfile: BrokerFirmProfileModel(
                            firmName: 'MANDI TRADE PORTAL',
                            mobile: _currentUser.mobile,
                            address: _currentUser.address,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add_link_rounded),
                  tooltip: 'Search Sauda Code (सौदा कोड से खोजें)',
                  onPressed: () => showSearchAndLinkSaudaDialog(
                    context: context,
                    currentUser: _currentUser,
                    userRole: 'BUYER',
                    onSaudaLinked: () => setState(() {}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.manage_accounts_rounded),
                  tooltip: 'Edit Profile & Password',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileEditScreen(
                          user: _currentUser,
                          onProfileUpdated: (updated) =>
                              setState(() => _currentUser = updated),
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: Badge(
                    isLabelVisible: userNotifications.isNotEmpty,
                    label: Text('${userNotifications.length}'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  tooltip: 'Notifications',
                  onPressed: () =>
                      showNotificationDialog(context, _currentUser.mobile),
                ),
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () {
                    _lockSubscription?.cancel();
                    StorageService.remove('last_active_section');
                    StorageService.remove('session_BUYER');
                    StorageService.remove('session_BUYER_name');
                    StorageService.remove('session_BUYER_mobile');
                    StorageService.remove('session_BUYER_email');
                    StorageService.remove('session_BUYER_address');

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainDashboardScreen(),
                      ),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Quick Link Sauda By ID Card
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF38BDF8)
                                  .withValues(alpha: 0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF38BDF8)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.receipt_long_rounded,
                                  color: Color(0xFF38BDF8), size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ADD DEALS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'सीधा सौदा दर्ज करें या ब्रोकर द्वारा दिया गया 6-अंकीय कोड सर्च करके बही में जोड़ें',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF38BDF8),
                                    foregroundColor: const Color(0xFF0F172A),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.add_circle, size: 16),
                                  label: const Text(
                                    '+ सौदा जोड़ें',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  onPressed: () => showManualAddSaudaDialog(
                                    context: context,
                                    currentUser: _currentUser,
                                    userRole: 'BUYER',
                                    existingDeals: _allDeals,
                                    onSaudaAdded: () => setState(() {}),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF38BDF8),
                                    side: const BorderSide(
                                        color: Color(0xFF38BDF8)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(Icons.search, size: 16),
                                  label: const Text(
                                    'सर्च कोड',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  onPressed: () => showSearchAndLinkSaudaDialog(
                                    context: context,
                                    currentUser: _currentUser,
                                    userRole: 'BUYER',
                                    onSaudaLinked: () => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 1. Profile Header Card
                      Card(
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor:
                                              const Color(0xFF38BDF8)
                                                  .withValues(alpha: 0.2),
                                          child: const Icon(
                                            Icons.shopping_bag_rounded,
                                            color: Color(0xFF0369A1),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ', ${_currentUser.name}',
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                '📱 ${_currentUser.mobile} | ✉️ ${_currentUser.email}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              UserProfileEditScreen(
                                            user: _currentUser,
                                            onProfileUpdated: (updated) =>
                                                setState(
                                              () => _currentUser = updated,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit, size: 15),
                                    label: const Text('Edit Profile'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Address: ${_currentUser.address}',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 3. Commodity-Wise Breakdown Chips (जिंस-वार सारांश)
                      if (commodityStats.isNotEmpty) ...[
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'जिंस-वार सारांश (Filter by Commodity):',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    if (_selectedJins != null)
                                      TextButton(
                                        onPressed: () => setState(
                                            () => _selectedJins = null),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('Clear Crop Filter'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      ActionChip(
                                        label: const Text('सभी जिंस (All)'),
                                        backgroundColor: _selectedJins == null
                                            ? const Color(0xFF0F766E)
                                            : Colors.grey.shade100,
                                        labelStyle: TextStyle(
                                          color: _selectedJins == null
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                        onPressed: () => setState(
                                            () => _selectedJins = null),
                                      ),
                                      const SizedBox(width: 8),
                                      ...commodityStats.entries.map((entry) {
                                        final crop = entry.key;
                                        final bags = entry.value['bags']!;
                                        final isSelected =
                                            _selectedJins == crop;

                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: FilterChip(
                                            selected: isSelected,
                                            selectedColor:
                                                const Color(0xFF0F766E),
                                            backgroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? const Color(0xFF0F766E)
                                                    : Colors.grey.shade300,
                                              ),
                                            ),
                                            label: Text(
                                              '$crop: $bags बोरी',
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                fontSize: 12,
                                              ),
                                            ),
                                            onSelected: (val) {
                                              setState(() {
                                                _selectedJins =
                                                    val ? crop : null;
                                              });
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // 4. Search & Date Filter Bar
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Column(
                            children: [
                              // Search Field
                              TextField(
                                controller: _searchCtrl,
                                onChanged: (val) =>
                                    setState(() => _searchQuery = val.trim()),
                                decoration: InputDecoration(
                                  hintText:
                                      'खोजें (जिंस, विक्रेता, ब्रोकर, मोबाइल)...',
                                  hintStyle: const TextStyle(fontSize: 13),
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            _searchCtrl.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8, horizontal: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Financial Year (वित्त वर्ष) Filter Chips
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.calendar_today,
                                              size: 13,
                                              color: Color(0xFF0284C7)),
                                          SizedBox(width: 4),
                                          Text(
                                            'वित्त वर्ष (FY):',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0284C7),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    ChoiceChip(
                                      label: const Text('सभी वर्ष (All Years)'),
                                      selected: _selectedFinancialYear == 'ALL',
                                      selectedColor: const Color(0xFF0284C7),
                                      backgroundColor: Colors.grey.shade100,
                                      labelStyle: TextStyle(
                                        color: _selectedFinancialYear == 'ALL'
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight:
                                            _selectedFinancialYear == 'ALL'
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                        fontSize: 11,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      onSelected: (val) {
                                        if (val) {
                                          setState(() =>
                                              _selectedFinancialYear = 'ALL');
                                        }
                                      },
                                    ),
                                    ..._availableFinancialYears.map((fy) {
                                      final isSelected =
                                          _selectedFinancialYear == fy;
                                      final count = _allDeals
                                          .where((d) => d.financialYear == fy)
                                          .length;
                                      return Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: ChoiceChip(
                                          label: Text('$fy ($count)'),
                                          selected: isSelected,
                                          selectedColor:
                                              const Color(0xFF0284C7),
                                          backgroundColor: Colors.grey.shade100,
                                          labelStyle: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 11,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          onSelected: (val) {
                                            if (val) {
                                              setState(() =>
                                                  _selectedFinancialYear = fy);
                                            }
                                          },
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Date Filter Chips
                              Row(
                                children: [
                                  const Text(
                                    'दिनांक: ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          _buildDateChip('सभी (All)', 'ALL'),
                                          const SizedBox(width: 6),
                                          _buildDateChip('आज (Today)', 'TODAY'),
                                          const SizedBox(width: 6),
                                          _buildDateChip(
                                              'इस माह (Month)', 'THIS_MONTH'),
                                          const SizedBox(width: 6),
                                          _buildDateChip('30 दिन', 'LAST_30'),
                                          const SizedBox(width: 6),
                                          ActionChip(
                                            avatar: const Icon(
                                                Icons.calendar_month,
                                                size: 14),
                                            label: Text(_dateFilter ==
                                                        'CUSTOM' &&
                                                    _customDateRange != null
                                                ? '${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}'
                                                : 'कैलेंडर'),
                                            backgroundColor:
                                                _dateFilter == 'CUSTOM'
                                                    ? const Color(0xFF0F766E)
                                                    : Colors.grey.shade100,
                                            labelStyle: TextStyle(
                                              color: _dateFilter == 'CUSTOM'
                                                  ? Colors.white
                                                  : Colors.black87,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            onPressed: _pickCustomDateRange,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 5. Segmented Navigation Tabs
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTabButton(
                                index: 0,
                                label: 'सभी सौदे (${filteredDeals.length})',
                                icon: Icons.list_alt_rounded,
                              ),
                            ),
                            Expanded(
                              child: _buildTabButton(
                                index: 1,
                                label:
                                    'ब्रोकर खाते (${brokerAccounts.keys.length})',
                                icon: Icons.account_balance_wallet_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6. Tab Views
                      if (_activeTab == 0) ...[
                        // TAB 0: ALL DEALS
                        if (filteredDeals.isEmpty)
                          _buildEmptyState(
                              'कोई सौदा नहीं मिला (No Deals Found)')
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredDeals.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _buildSaudaCard(filteredDeals[index]);
                            },
                          ),
                      ] else ...[
                        // TAB 2: BROKER LEDGERS
                        if (brokerAccounts.isEmpty)
                          _buildEmptyState(
                              'कोई ब्रोकर खाता उपलब्ध नहीं (No Broker Ledgers)')
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: brokerAccounts.keys.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              final brokerName =
                                  brokerAccounts.keys.elementAt(index);
                              final deals = brokerAccounts[brokerName]!;
                              return _buildBrokerLedgerCard(brokerName, deals);
                            },
                          ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_shopping_cart, size: 20),
              label: const Text(
                '+ सौदा जोड़ें (Add Deal)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () => showManualAddSaudaDialog(
                context: context,
                currentUser: _currentUser,
                userRole: 'BUYER',
                existingDeals: _allDeals,
                onSaudaAdded: () => setState(() {}),
              ),
            ),
          ),
        );
      },
    );
  }

  // Quick Date Filter Chip
  Widget _buildDateChip(String label, String key) {
    final isSelected = _dateFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF0F766E),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 11.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (val) {
        if (val) {
          setState(() {
            _dateFilter = key;
          });
        }
      },
    );
  }

  // Segment Tab Button
  Widget _buildTabButton({
    required int index,
    required String label,
    required IconData icon,
    int? badgeCount,
  }) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? (badgeCount != null && badgeCount > 0
                      ? Colors.orange.shade800
                      : const Color(0xFF0F766E))
                  : Colors.black54,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? (badgeCount != null && badgeCount > 0
                          ? Colors.orange.shade800
                          : const Color(0xFF0F766E))
                      : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modern Sauda Card with Direct Actions
  Widget _buildSaudaCard(MandiSaudaModel s) {
    final dateStr =
        '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year}';
    final totalAmount = (s.bags * s.rate);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.teal.shade200,
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openBrokerAccountScreen(
          brokerFirmName: s.brokerFirmName,
          brokerMobile: s.brokerMobile,
          relatedDeals: _allDeals
              .where((d) =>
                  (s.brokerMobile.isNotEmpty &&
                      d.brokerMobile == s.brokerMobile) ||
                  (s.brokerFirmName.isNotEmpty &&
                      d.brokerFirmName == s.brokerFirmName))
              .toList(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Date, Crop & Status Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s.jins,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF0284C7).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                const Color(0xFF0284C7).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          s.financialYear,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'ID: #${s.id}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Bags @ Rate & Total Value
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${s.bags} बोरी  @  ₹${s.rate.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '₹${totalAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Row 3: Parties Information
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '🚜 विक्रेता: ${s.seller.isNotEmpty ? s.seller : "Seller"}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '🤝 ब्रोकर: ${s.brokerFirmName.isNotEmpty ? s.brokerFirmName : "Broker"}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // Dalali Note
              Text(
                'देय दलाली: ₹${s.totalBuyerDalali.toStringAsFixed(0)} (₹${s.buyerDalaliPerBag.toStringAsFixed(0)}/बोरी)',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF0F766E),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Broker Ledger Card with View Broker Account Action
  Widget _buildBrokerLedgerCard(
      String brokerName, List<MandiSaudaModel> deals) {
    final totalBags = deals.fold<int>(0, (acc, d) => acc + d.bags);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            const Color(0xFF0F766E).withValues(alpha: 0.12),
                        child: const Icon(
                          Icons.account_balance,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              brokerName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '📞 ${deals.first.brokerMobile} | सौदे: ${deals.length} | बोरी: $totalBags',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // View Broker Details Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openBrokerAccountScreen(
                brokerFirmName: brokerName,
                brokerMobile: deals.first.brokerMobile,
                relatedDeals: deals,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const Text(
                'ब्रोकर खाता व सौदे देखें (View Broker Account & Saudas)',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =============================================================
// BROKER DIRECTORY SEARCH SCREEN
// =============================================================
class BrokerDirectorySearchScreen extends StatelessWidget {
  const BrokerDirectorySearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brokers = AccountService.getAccountsBySection('BROKER');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Registered Brokers Directory (ब्रोकर सूची)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: brokers.isEmpty
            ? const Center(
                child: Text(
                  'No brokers registered in the network yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.separated(
                itemCount: brokers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final b = brokers[index];
                  return Card(
                    elevation: 1.5,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF0F766E).withValues(alpha: 0.15),
                        child: Text(
                          b.name.isNotEmpty ? b.name[0] : 'B',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                      title: Text(
                        b.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '📞 Mobile: ${b.mobile}\n📍 Address: ${b.address}\n✉️ Gmail: ${b.email}',
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// =============================================================
// EDITABLE PROFILE SCREEN FOR BUYER & SELLER (WITH FIREBASE SYNC & WHATSAPP)
// =============================================================
class UserProfileEditScreen extends StatefulWidget {
  final UserAccount user;
  final Function(UserAccount) onProfileUpdated;

  const UserProfileEditScreen({
    super.key,
    required this.user,
    required this.onProfileUpdated,
  });

  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  static const String adminSupportPhone = '+919983325558';

  late TextEditingController _nameCtrl;
  late TextEditingController _addrCtrl;
  late TextEditingController _mobCtrl;
  late TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.name);
    _addrCtrl = TextEditingController(text: widget.user.address);
    _mobCtrl = TextEditingController(text: widget.user.mobile);
    _emailCtrl = TextEditingController(text: widget.user.email);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _mobCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPasswordResetViaWhatsApp() async {
    final cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final mobile = _mobCtrl.text.trim().isNotEmpty
        ? _mobCtrl.text.trim()
        : widget.user.mobile;
    final name = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()
        : widget.user.name;

    final message =
        'नमस्ते Mandi Support Team, मैं (${widget.user.section}) पोर्टल का उपयोगकर्ता ($name, मोबाइल: $mobile) हूँ। कृपया मेरा पासवर्ड / PIN रीसेट या अपडेट करने में सहायता करें।';

    final url = Uri.parse(
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    final canLaunch = await canLaunchUrl(url);
    if (!mounted) return;

    if (canLaunch) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('WhatsApp cannot be launched on this device')),
      );
    }
  }

  Future<void> _syncPasswordToFirebase(String newPassword) async {
    await CloudSyncService.ensureAuthSession();
    final firestore = FirebaseFirestore.instance;
    final cleanMobile = widget.user.mobile.trim();
    final cleanEmail = widget.user.email.trim().toLowerCase();

    widget.user.password = newPassword;

    // 1. Save updated UserAccount via CloudSyncService
    await CloudSyncService.saveAccount(widget.user.toJson());

    // 2. Update all matching documents in 'accounts' collection by mobile & email
    if (cleanMobile.isNotEmpty) {
      await firestore.collection('accounts').doc(cleanMobile).set({
        'password': newPassword,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final mobSnap = await firestore
          .collection('accounts')
          .where('mobile', isEqualTo: cleanMobile)
          .get();
      for (final doc in mobSnap.docs) {
        await doc.reference.update({
          'password': newPassword,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    }

    if (cleanEmail.isNotEmpty) {
      final emailSnap = await firestore
          .collection('accounts')
          .where('email', isEqualTo: cleanEmail)
          .get();
      for (final doc in emailSnap.docs) {
        await doc.reference.update({
          'password': newPassword,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    }

    // 3. Update local AccountService & session cache
    AccountService.updateAccount(widget.user);
    StorageService.save('session_${widget.user.section}_password', newPassword);
  }

  void _showGenericOtpDialog({
    required String title,
    required String email,
    required String otp,
    required VoidCallback onVerified,
  }) {
    final otpInput = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              color: Color(0xFF0F766E),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A 6-digit OTP has been sent to:\n$email',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpInput,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Enter 6-Digit OTP',
                prefixIcon: Icon(Icons.pin),
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (otpInput.text.trim() == otp) {
                Navigator.pop(ctx);
                onVerified();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid OTP! Please check your email inbox.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('VERIFY OTP'),
          ),
        ],
      ),
    );
  }

  void _openChangePasswordDialog() {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newPass = newPassCtrl.text.trim();
              if (newPass.length < 4 ||
                  newPass != confirmPassCtrl.text.trim()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Passwords must match and be at least 4 characters',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);

              final otp = (100000 + Random().nextInt(900000)).toString();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sending OTP to ${widget.user.email}...'),
                ),
              );

              final sent = await EmailService.sendOtpEmail(
                recipientEmail: widget.user.email,
                recipientName: widget.user.name,
                otp: otp,
                purpose: 'Password Change',
              );

              if (!mounted) return;

              if (sent) {
                _showGenericOtpDialog(
                  title: 'Verify Password Change',
                  email: widget.user.email,
                  otp: otp,
                  onVerified: () async {
                    try {
                      await _syncPasswordToFirebase(newPass);

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password updated in Firebase & local storage successfully!',
                          ),
                          backgroundColor: Colors.teal,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to sync password: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to deliver OTP. Check internet connection.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('REQUEST OTP'),
          ),
        ],
      ),
    );
  }

  void _saveProfile() async {
    final newName = _nameCtrl.text.trim().toUpperCase();
    final newAddr = _addrCtrl.text.trim().toUpperCase();
    final newMob = _mobCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim().toLowerCase();

    if (newName.isEmpty ||
        newAddr.isEmpty ||
        newMob.length != 10 ||
        newEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check all fields (Mobile must be 10 digits)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (newMob != widget.user.mobile) {
      final isTaken = await CloudSyncService.isMobileRegistered(newMob);
      if (!mounted) return;
      if (isTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mobile number $newMob is already registered by another user!',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Require email OTP if mobile or email was changed
    if (newMob != widget.user.mobile || newEmail != widget.user.email) {
      final otp = (100000 + Random().nextInt(900000)).toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sending security OTP to ${widget.user.email}...'),
        ),
      );

      final sent = await EmailService.sendOtpEmail(
        recipientEmail: widget.user.email,
        recipientName: widget.user.name,
        otp: otp,
        purpose: 'Profile Update Authorization',
      );

      if (!mounted) return;

      if (sent) {
        _showGenericOtpDialog(
          title: 'Authorize Profile Update',
          email: widget.user.email,
          otp: otp,
          onVerified: () {
            _persistUpdatedProfile(newName, newAddr, newMob, newEmail);
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to send authorization OTP. Check internet connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _persistUpdatedProfile(newName, newAddr, newMob, newEmail);
  }

  void _persistUpdatedProfile(
    String name,
    String address,
    String mobile,
    String email,
  ) async {
    final oldMobile = widget.user.mobile;
    final oldEmail = widget.user.email;
    final oldName = widget.user.name;
    final section = widget.user.section;

    widget.user.name = name;
    widget.user.address = address;
    widget.user.mobile = mobile;
    widget.user.email = email;

    // 1. Swap the record in local AccountService
    AccountService.updateAccountWithOldCredentials(
      oldMobile: oldMobile,
      oldEmail: oldEmail,
      updatedAccount: widget.user,
    );

    // 2. FULL CLOUD FIRESTORE MIGRATION
    try {
      await CloudSyncService.updateProfile(
        section: section,
        oldMobile: oldMobile,
        newMobile: mobile,
        oldEmail: oldEmail,
        newEmail: email,
        newName: name,
        address: address,
        password: widget.user.password,
        oldName: oldName,
      );
    } catch (e) {
      debugPrint('Cloud sync migration error during profile update: $e');
    }

    // 3. Update active session storage
    StorageService.save('session_$section', mobile);
    StorageService.save('session_${section}_name', name);
    StorageService.save('session_${section}_mobile', mobile);
    StorageService.save('session_${section}_email', email);
    StorageService.save('session_${section}_address', address);

    widget.onProfileUpdated(widget.user);
    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Profile updated! All transaction ledgers migrated to your new number.',
        ),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void _confirmDeleteAccountDialog() {
    final email = widget.user.email.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email found to send verification OTP.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'Delete Account?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete your account (${widget.user.name} - ${widget.user.mobile})?\n\n'
          'A 6-digit authorization OTP will be sent to your Gmail ($email) to confirm deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);

              final otp = (100000 + Random().nextInt(900000)).toString();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sending deletion authorization OTP to $email...',
                  ),
                ),
              );

              final sent = await EmailService.sendOtpEmail(
                recipientEmail: email,
                recipientName: widget.user.name,
                otp: otp,
                purpose: 'Permanent Account Deletion',
              );

              if (!mounted) return;

              if (sent) {
                _showGenericOtpDialog(
                  title: 'Authorize Account Deletion',
                  email: email,
                  otp: otp,
                  onVerified: () async {
                    final mobile = widget.user.mobile;
                    final section = widget.user.section;

                    // 1. Purge from Firestore
                    await CloudSyncService.purgeUserAccount(mobile,
                        section: section);

                    // 2. Remove from Local Accounts
                    AccountService.removeAccount(
                      mobile: mobile,
                      section: section,
                    );

                    // 3. Clear all active session tokens
                    StorageService.remove('last_active_section');
                    StorageService.remove('session_$section');
                    StorageService.remove('session_${section}_name');
                    StorageService.remove('session_${section}_mobile');
                    StorageService.remove('session_${section}_email');
                    StorageService.remove('session_${section}_address');

                    if (!mounted) return;

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainDashboardScreen(),
                      ),
                      (route) => false,
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account permanently deleted.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Failed to deliver OTP. Check internet connection.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('SEND OTP & DELETE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('${widget.user.section} Profile Settings'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Firestore Subscription Status for Buyer/Seller
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(CloudSyncService.cleanMobileNumber(
                          widget.user.mobile))
                      .snapshots(),
                  builder: (context, subSnap) {
                    if (!subSnap.hasData ||
                        subSnap.data == null ||
                        !subSnap.data!.exists) {
                      return const SizedBox.shrink();
                    }
                    final subData =
                        subSnap.data!.data() as Map<String, dynamic>? ?? {};
                    final renewalDate =
                        CloudSyncService.parseRenewalDate(subData);
                    final daysLeft =
                        renewalDate?.difference(DateTime.now()).inDays;
                    final plan = (subData['subscription_plan'] ??
                            (subData['subscription'] is Map
                                ? subData['subscription']['plan']
                                : null) ??
                            'Active Plan')
                        .toString();
                    final isLocked = subData['is_locked'] == true ||
                        subData['subscription_due'] == true ||
                        (daysLeft != null && daysLeft < 0);

                    final dateStr = renewalDate != null
                        ? '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}'
                        : 'Active / None';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? const Color(0xFFFEF2F2)
                            : (daysLeft != null && daysLeft <= 7)
                                ? const Color(0xFFFFFBEB)
                                : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isLocked
                              ? Colors.red.shade300
                              : (daysLeft != null && daysLeft <= 7)
                                  ? Colors.amber.shade400
                                  : const Color(0xFF10B981),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isLocked
                                ? Icons.lock_outline_rounded
                                : (daysLeft != null && daysLeft <= 7)
                                    ? Icons.notification_important_rounded
                                    : Icons.verified_user_rounded,
                            color: isLocked
                                ? Colors.red.shade700
                                : (daysLeft != null && daysLeft <= 7)
                                    ? Colors.amber.shade800
                                    : const Color(0xFF0F766E),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      isLocked
                                          ? 'Subscription Due'
                                          : (daysLeft != null && daysLeft <= 7)
                                              ? 'Renew Soon'
                                              : 'Active Plan',
                                      style: TextStyle(
                                        color: isLocked
                                            ? Colors.red.shade900
                                            : (daysLeft != null &&
                                                    daysLeft <= 7)
                                                ? Colors.amber.shade900
                                                : const Color(0xFF0F766E),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isLocked
                                            ? Colors.red
                                            : const Color(0xFF0F766E),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        plan,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  renewalDate != null
                                      ? 'Renewal Date: $dateStr (${daysLeft != null ? (daysLeft < 0 ? "Expired ${-daysLeft} days ago" : (daysLeft == 0 ? "Today" : "$daysLeft days left")) : ""})'
                                      : 'Active Account • Support: 9983325558',
                                  style: TextStyle(
                                    color: (daysLeft != null && daysLeft <= 7)
                                        ? Colors.red.shade800
                                        : Colors.black87,
                                    fontSize: 11,
                                    fontWeight:
                                        (daysLeft != null && daysLeft <= 7)
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _addrCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _mobCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number (Requires OTP to change)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gmail Address (Requires OTP to change)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _openChangePasswordDialog,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('CHANGE PASSWORD (VIA GMAIL OTP)'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side:
                        const BorderSide(color: Color(0xFF25D366), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _requestPasswordResetViaWhatsApp,
                  icon: const Icon(Icons.chat),
                  label: const Text(
                    'REQUEST PASSWORD RESET VIA WHATSAPP',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.check),
                  label: const Text(
                    'SAVE PROFILE CHANGES',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _confirmDeleteAccountDialog,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text(
                    'DELETE MY ACCOUNT PERMANENTLY',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
