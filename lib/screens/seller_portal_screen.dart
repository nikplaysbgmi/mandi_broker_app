import '../widgets/search_link_sauda_dialog.dart';
import '../widgets/manual_add_sauda_dialog.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/mandi_services.dart';
import 'bill_print_screen.dart';
import 'broker_account_detail_screen.dart';
import 'buyer_portal_screen.dart';
import 'main_dashboard_screen.dart';

// =============================================================
// 3. SELLER SECTION (WITH LIVE FIRESTORE STREAMING & BROKER SYNC)
// =============================================================
class SellerSectionPortal extends StatefulWidget {
  final UserAccount user;

  const SellerSectionPortal({super.key, required this.user});

  @override
  State<SellerSectionPortal> createState() => _SellerSectionPortalState();
}

class _SellerSectionPortalState extends State<SellerSectionPortal> {
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
  int _activeTab = 0; // 0: All Sales, 1: Broker Ledgers

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
        CloudSyncService.streamAccountLockStatus('SELLER', _currentUser.mobile)
            .listen((isLocked) {
      if (isLocked && mounted) {
        _forceLogoutDueToLock();
      }
    });
  }

  void _forceLogoutDueToLock() {
    _lockSubscription?.cancel();

    StorageService.remove('session_SELLER');
    StorageService.remove('session_SELLER_mobile');

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
          'Your seller account has been locked or requires plan renewal.\nPlease contact the Mandi administration office.',
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
        : (StorageService.get('session_SELLER_name') ?? 'SELLER USER');
    final mobile = incoming.mobile.trim().isNotEmpty
        ? incoming.mobile
        : (StorageService.get('session_SELLER_mobile') ??
            StorageService.get('session_SELLER') ??
            '');
    final email = incoming.email.trim().isNotEmpty
        ? incoming.email
        : (StorageService.get('session_SELLER_email') ?? '');
    final address = incoming.address.trim().isNotEmpty
        ? incoming.address
        : (StorageService.get('session_SELLER_address') ?? 'MANDI / VILLAGE');

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
    final raw = StorageService.get('seller_records_${_currentUser.mobile}');
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
      'seller_records_${_currentUser.mobile}',
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
          isBuyer: false,
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

// Filter sales based on Search query, Date filter, and Commodity selection
  List<MandiSaudaModel> _applyFilters(List<MandiSaudaModel> source) {
    final now = DateTime.now();

    return source.where((s) {
      // 1. Text Search Filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchJins = s.jins.toLowerCase().contains(q);
        final matchBuyer = s.buyer.toLowerCase().contains(q);
        final matchBuyerMob = s.buyerMobile.contains(q);
        final matchBroker = s.brokerFirmName.toLowerCase().contains(q);
        final matchBrokerMob = s.brokerMobile.contains(q);
        if (!matchJins &&
            !matchBuyer &&
            !matchBuyerMob &&
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

  // Computes commodity analytics from confirmed sales
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
              primary: Color(0xFFF59E0B),
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
      stream: CloudSyncService.streamSellerSaudas(_currentUser.mobile),
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

        final userNotifications = NotificationService.getForMobile(
          _currentUser.mobile,
        );

        return Theme(
          data: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF1F5F9),
            canvasColor: const Color(0xFFF1F5F9),
            cardColor: Colors.white,
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD97706),
              surface: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            appBar: AppBar(
              title: Text(
                'SELLER PORTAL (${_currentUser.name})',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              elevation: 1,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'बही में सौदा जोड़ें (Add Deal to Book)',
                  onPressed: () => showManualAddSaudaDialog(
                    context: context,
                    currentUser: _currentUser,
                    userRole: 'SELLER',
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
                            type: 'Seller',
                          ),
                          isBuyer: false,
                          deals: _allDeals,
                          selectedPeriod:
                              'विक्रेता बही खाता (${_currentUser.name})',
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
                    userRole: 'SELLER',
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
                    StorageService.remove('session_SELLER');
                    StorageService.remove('session_SELLER_name');
                    StorageService.remove('session_SELLER_mobile');
                    StorageService.remove('session_SELLER_email');
                    StorageService.remove('session_SELLER_address');
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
                              color: const Color(0xFFF59E0B)
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
                                color: const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.receipt_long_rounded,
                                  color: Color(0xFFF59E0B), size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'बही में सौदा जोड़ें (ADD DEALS)',
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
                                    backgroundColor: const Color(0xFFF59E0B),
                                    foregroundColor: Colors.white,
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
                                    userRole: 'SELLER',
                                    existingDeals: _allDeals,
                                    onSaudaAdded: () => setState(() {}),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFF59E0B),
                                    side: const BorderSide(
                                        color: Color(0xFFF59E0B)),
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
                                    userRole: 'SELLER',
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
                                              Colors.amber.shade100,
                                          child: const Icon(
                                            Icons.storefront_rounded,
                                            color: Colors.brown,
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
                                '📍 Mandi / Village: ${_currentUser.address}',
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

                      // 3. Commodity Breakdown Chips (जिंस-वार सारांश)
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
                                      'जिंस-वार बिक्री (Filter by Commodity):',
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
                                            ? const Color(0xFFF59E0B)
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
                                                const Color(0xFFF59E0B),
                                            backgroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              side: BorderSide(
                                                color: isSelected
                                                    ? const Color(0xFFF59E0B)
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
                                      'खोजें (जिंस, खरीदार, ब्रोकर, मोबाइल)...',
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
                                        color: const Color(0xFFD97706)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Row(
                                        children: [
                                          Icon(Icons.calendar_today,
                                              size: 13,
                                              color: Color(0xFFD97706)),
                                          SizedBox(width: 4),
                                          Text(
                                            'वित्त वर्ष (FY):',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFD97706),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    ChoiceChip(
                                      label: const Text('सभी वर्ष (All Years)'),
                                      selected: _selectedFinancialYear == 'ALL',
                                      selectedColor: const Color(0xFFD97706),
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
                                              const Color(0xFFD97706),
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
                                                    ? const Color(0xFFF59E0B)
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
                                label: 'सभी विक्रय (${filteredDeals.length})',
                                icon: Icons.list_alt_rounded,
                              ),
                            ),
                            Expanded(
                              child: _buildTabButton(
                                index: 1,
                                label:
                                    'ब्रोकर बही (${brokerAccounts.keys.length})',
                                icon: Icons.account_balance_wallet_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6. Tab Views
                      if (_activeTab == 0) ...[
                        // TAB 0: ALL SALES
                        if (filteredDeals.isEmpty)
                          _buildEmptyState(
                              'कोई विक्रय नहीं मिला (No Sales Found)')
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
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_shopping_cart, size: 20),
              label: const Text(
                '+ सौदा जोड़ें (Add Deal)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () => showManualAddSaudaDialog(
                context: context,
                currentUser: _currentUser,
                userRole: 'SELLER',
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
      selectedColor: const Color(0xFFF59E0B),
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
                      : const Color(0xFFF59E0B))
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
                          : const Color(0xFFF59E0B))
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
          color: Colors.amber.shade300,
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
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s.jins,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
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
                          color: const Color(0xFFD97706).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color:
                                const Color(0xFFD97706).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          s.financialYear,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.amber.shade300,
                      ),
                    ),
                    child: Text(
                      'ID: #${s.id}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
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
                      color: Colors.green,
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
                            '🏢 खरीदार: ${s.buyer.isNotEmpty ? s.buyer : "Buyer"}',
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
                'देय दलाली: ₹${s.totalSellerDalali.toStringAsFixed(0)} (₹${s.sellerDalaliPerBag.toStringAsFixed(0)}/बोरी)',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFD97706),
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
                        backgroundColor: Colors.amber.shade100,
                        child: const Icon(
                          Icons.account_balance,
                          color: Colors.brown,
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

            // View Broker Account button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
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
