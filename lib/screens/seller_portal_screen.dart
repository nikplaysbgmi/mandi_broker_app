import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/mandi_services.dart';
import 'bill_print_screen.dart';
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
  late UserAccount _currentUser;
  StreamSubscription<bool>? _lockSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _resolveCompleteUser(widget.user);
    _loadLocalDeals();
    _startLiveAccountLockListener();
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
    final raw = StorageService.get('mandi_saudas');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw);
        final all = list.map((e) => MandiSaudaModel.fromJson(e)).toList();
        setState(() {
          _allDeals = all
              .where((s) => s.sellerMobile.trim() == _currentUser.mobile.trim())
              .toList();
        });
      } catch (_) {}
    }
  }

  void _confirmSauda(MandiSaudaModel sauda) async {
    setState(() {
      sauda.sellerConfirmed = true;
    });

    // 1. Update local storage
    updateSaudaInStorage(sauda);

    // 2. Sync to Firestore (both broker folder & shared ledger)
    try {
      await CloudSyncService.updateSauda(
        sauda.id,
        sauda.toJson(),
        brokerKey: sauda.brokerMobile,
      );

      // 3. Notify broker of seller confirmation
      await CloudSyncService.sendNotification(
        targetMobile: sauda.brokerMobile,
        title: '✅ विक्रय सौदे की पुष्टि हुई (Seller Confirmed)',
        message:
            '${_currentUser.name} ने ${sauda.jins} (${sauda.bags} बोरी @ ₹${sauda.rate.toStringAsFixed(0)}) के सौदे की पुष्टि कर दी है।',
        brokerKey: sauda.brokerMobile,
      );
    } catch (e) {
      debugPrint('Cloud sync sauda confirmation error: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sale for ${sauda.jins} (${sauda.bags} Bags) Confirmed and saved in Broker Account!',
        ),
        backgroundColor: Colors.teal.shade800,
      ),
    );
  }

  void _requestCancelDialog(MandiSaudaModel sauda) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Request Cancellation (रद्दीकरण अनुरोध)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request cancellation for ${sauda.jins} (${sauda.bags} Bags @ ₹${sauda.rate.toStringAsFixed(0)})?',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason for Cancellation (वजह)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('BACK'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final reason = reasonCtrl.text.trim().isEmpty
                  ? 'Requested by Seller'
                  : reasonCtrl.text.trim();
              Navigator.pop(ctx);

              setState(() {
                sauda.cancelRequested = true;
                sauda.cancelRequestedBy = 'Seller';
                sauda.cancellationReason = reason;
              });

              // 1. Update locally
              updateSaudaInStorage(sauda);

              // 2. Sync cancellation request to Firestore
              try {
                await CloudSyncService.updateSauda(
                  sauda.id,
                  sauda.toJson(),
                  brokerKey: sauda.brokerMobile,
                );

                // 3. Notify broker directly
                await CloudSyncService.sendNotification(
                  targetMobile: sauda.brokerMobile,
                  title:
                      '⚠️ Cancellation Requested by Seller (${_currentUser.name})',
                  message:
                      'Seller requested cancellation for ${sauda.jins} (${sauda.bags} Bags). Reason: "$reason". Please review and process.',
                  brokerKey: sauda.brokerMobile,
                );
              } catch (_) {}

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cancellation request sent to Broker!'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('SEND REQUEST'),
          ),
        ],
      ),
    );
  }

  Map<String, List<MandiSaudaModel>> _getConfirmedDealsByBroker() {
    final confirmed = _allDeals.where((s) => s.sellerConfirmed).toList();
    final Map<String, List<MandiSaudaModel>> grouped = {};
    for (var s in confirmed) {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CloudSyncService.streamSellerSaudas(_currentUser.mobile),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _allDeals = snapshot.data!
              .map((data) => MandiSaudaModel.fromJson(data))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
        }

        final pendingDeals =
            _allDeals.where((s) => !s.sellerConfirmed).toList();
        final brokerAccounts = _getConfirmedDealsByBroker();
        final userNotifications = NotificationService.getForMobile(
          _currentUser.mobile,
        );

        // Overall Seller Metrics (using 'acc' instead of 'sum')
        final int totalConfirmedBags = _allDeals
            .where((s) => s.sellerConfirmed)
            .fold<int>(0, (acc, item) => acc + item.bags);
        final double totalConfirmedTurnover = _allDeals
            .where((s) => s.sellerConfirmed)
            .fold<double>(0.0, (acc, item) => acc + (item.bags * item.rate));
        final double totalSellerDalali = _allDeals
            .where((s) => s.sellerConfirmed)
            .fold<double>(0.0, (acc, item) => acc + item.totalSellerDalali);

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          appBar: AppBar(
            title: Text(
              'SELLER PORTAL (${_currentUser.name})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search Registered Brokers',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BrokerDirectorySearchScreen(),
                    ),
                  );
                },
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
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile Header Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Welcome, ${_currentUser.name}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
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
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Edit Profile'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Registered Mobile: ${_currentUser.mobile}  |  Gmail: ${_currentUser.email}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Mandi / Village Address: ${_currentUser.address}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick Financial Metrics Banner
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                const Text(
                                  'Sold Bags',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$totalConfirmedBags',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                              width: 1, height: 26, color: Colors.black12),
                          Expanded(
                            child: Column(
                              children: [
                                const Text(
                                  'Brokerage Due',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${totalSellerDalali.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F766E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                              width: 1, height: 26, color: Colors.black12),
                          Expanded(
                            child: Column(
                              children: [
                                const Text(
                                  'Gross Proceeds',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${totalConfirmedTurnover.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pending Saudas Section
                    if (pendingDeals.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.pending_actions_rounded,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pending Broker Sales (${pendingDeals.length}) - पुष्टि अथवा रद्दीकरण',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pendingDeals.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final s = pendingDeals[index];
                          final dateStr =
                              '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year}';
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.orange.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$dateStr - ${s.jins}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Colors.teal.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          'Broker: ${s.brokerFirmName.isNotEmpty ? s.brokerFirmName : "Broker"} (${s.brokerMobile})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${s.bags} Bags/Weight @ Rate ₹${s.rate.toStringAsFixed(0)} (Gross: ₹${(s.bags * s.rate).toStringAsFixed(0)})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Buyer: ${s.buyer} (${s.buyerMobile}) | Brokerage: ₹${s.totalSellerDalali.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (s.cancelRequested) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.red.shade200,
                                        ),
                                      ),
                                      child: Text(
                                        '⚠️ Cancellation Requested by ${s.cancelRequestedBy}: ${s.cancellationReason}',
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (!s.cancelRequested)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            side: const BorderSide(
                                              color: Colors.red,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                          ),
                                          onPressed: () =>
                                              _requestCancelDialog(s),
                                          icon: const Icon(
                                            Icons.cancel_outlined,
                                            size: 16,
                                          ),
                                          label: const Text(
                                            'REQUEST CANCEL',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () => _confirmSauda(s),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'CONFIRM SALE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Broker Khata Ledgers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Broker Accounts in Your Books (ब्रोकर वार विक्रय बही)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Text(
                            '${brokerAccounts.length} ACTIVE BROKER LEDGERS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (brokerAccounts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(28),
                        alignment: Alignment.center,
                        child: const Text(
                          'No confirmed sales in any broker ledger yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: brokerAccounts.keys.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final brokerName =
                              brokerAccounts.keys.elementAt(index);
                          final deals = brokerAccounts[brokerName]!;
                          final totalBags = deals.fold<int>(
                            0,
                            (acc, d) => acc + d.bags,
                          );
                          final totalValue = deals.fold<double>(
                            0.0,
                            (acc, d) => acc + (d.bags * d.rate),
                          );
                          final totalDalali = deals.fold<double>(
                            0.0,
                            (acc, d) => acc + d.totalSellerDalali,
                          );

                          final brokerProfile = BrokerFirmProfileModel(
                            firmName: brokerName,
                            address: deals.first.brokerMobile,
                            mobile: deals.first.brokerMobile,
                          );

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                                Icons.account_balance,
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
                                                    brokerName,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'Mobile: ${deals.first.brokerMobile} | Deals: ${deals.length} | Bags: $totalBags',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: Colors.black54,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFF59E0B),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  MandiBillPrintScreen(
                                                party: MandiPartyModel(
                                                  name: _currentUser.name,
                                                  mobile: _currentUser.mobile,
                                                  address: _currentUser.address,
                                                  type: 'Seller',
                                                ),
                                                isBuyer: false,
                                                deals: deals,
                                                selectedPeriod:
                                                    'Account: $brokerName',
                                                brokerProfile: brokerProfile,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.print, size: 16),
                                        label: const Text(
                                          'PRINT KHATA',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: deals.length,
                                    itemBuilder: (ctx, dIdx) {
                                      final d = deals[dIdx];
                                      final dateStr =
                                          '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}';
                                      return ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '$dateStr - ${d.jins} (${d.bags} Bags @ ₹${d.rate.toStringAsFixed(0)})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Buyer: ${d.buyer} (${d.buyerMobile}) | Brokerage: ₹${d.totalSellerDalali.toStringAsFixed(0)}',
                                        ),
                                        trailing: Text(
                                          '₹${(d.bags * d.rate).toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.green,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Broker Dalali: ₹${totalDalali.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                        Text(
                                          'Gross Proceeds: ₹${totalValue.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
