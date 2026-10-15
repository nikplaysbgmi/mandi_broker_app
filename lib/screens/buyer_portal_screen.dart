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
        : (StorageService.get('session_BUYER_address') ?? 'MANDI YARD');

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
              .where((s) => s.buyerMobile.trim() == _currentUser.mobile.trim())
              .toList();
        });
      } catch (_) {}
    }
  }

  void _confirmSauda(MandiSaudaModel sauda) async {
    setState(() {
      sauda.buyerConfirmed = true;
    });

    // 1. Update local storage
    updateSaudaInStorage(sauda);

    // 2. Sync to cloud Firestore (updates both global and broker folder)
    await CloudSyncService.updateSauda(
      sauda.id,
      sauda.toJson(),
      brokerKey: sauda.brokerMobile,
    );

    // 3. Notify broker of confirmation
    await CloudSyncService.sendNotification(
      targetMobile: sauda.brokerMobile,
      title: '✅ सौदे की पुष्टि हुई (Buyer Confirmed)',
      message:
          '${_currentUser.name} ने ${sauda.jins} (${sauda.bags} बोरी @ ₹${sauda.rate.toStringAsFixed(0)}) के सौदे की पुष्टि कर दी है।',
      brokerKey: sauda.brokerMobile,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sauda for ${sauda.jins} (${sauda.bags} Bags) Confirmed and synced with Broker!',
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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Request cancellation for ${sauda.jins} (${sauda.bags} Bags @ ₹${sauda.rate.toStringAsFixed(0)})?',
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
                  ? 'Requested by Buyer'
                  : reasonCtrl.text.trim();
              Navigator.pop(ctx);

              setState(() {
                sauda.cancelRequested = true;
                sauda.cancelRequestedBy = 'Buyer';
                sauda.cancellationReason = reason;
              });

              // 1. Update locally
              updateSaudaInStorage(sauda);

              // 2. Sync cancellation flag to Firestore
              await CloudSyncService.updateSauda(
                sauda.id,
                sauda.toJson(),
                brokerKey: sauda.brokerMobile,
              );

              // 3. Send notification to broker
              await CloudSyncService.sendNotification(
                targetMobile: sauda.brokerMobile,
                title:
                    '⚠️ Cancellation Requested by Buyer (${_currentUser.name})',
                message:
                    'Buyer requested cancellation for ${sauda.jins} (${sauda.bags} Bags). Reason: "$reason". Please review in portal.',
                brokerKey: sauda.brokerMobile,
              );

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
    final confirmed = _allDeals.where((s) => s.buyerConfirmed).toList();
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
      stream: CloudSyncService.streamBuyerSaudas(_currentUser.mobile),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _allDeals = snapshot.data!
              .map((data) => MandiSaudaModel.fromJson(data))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
        }

        final pendingDeals = _allDeals.where((s) => !s.buyerConfirmed).toList();
        final brokerAccounts = _getConfirmedDealsByBroker();
        final userNotifications =
            NotificationService.getForMobile(_currentUser.mobile);

        // Calculate overall metrics (using 'acc' instead of 'sum')
        final int totalConfirmedBags = _allDeals
            .where((s) => s.buyerConfirmed)
            .fold<int>(0, (acc, item) => acc + item.bags);
        final double totalConfirmedTurnover = _allDeals
            .where((s) => s.buyerConfirmed)
            .fold<double>(0.0, (acc, item) => acc + (item.bags * item.rate));
        final double totalBuyerDalali = _allDeals
            .where((s) => s.buyerConfirmed)
            .fold<double>(0.0, (acc, item) => acc + item.totalBuyerDalali);

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          appBar: AppBar(
            title: Text(
              'BUYER PORTAL (${_currentUser.name})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            backgroundColor: const Color(0xFF38BDF8),
            foregroundColor: Colors.black87,
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
                                Text(
                                  'Welcome, ${_currentUser.name}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Office Address: ${_currentUser.address}',
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

                    // Quick Metrics Banner
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
                                  'Confirmed Bags',
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
                                  'Buyer Dalali Due',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₹${totalBuyerDalali.toStringAsFixed(0)}',
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
                                  'Purchase Value',
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
                                    color: Colors.blueAccent,
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
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pending Broker Saudas (${pendingDeals.length}) - पुष्टि अथवा रद्दीकरण',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
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
                              '${s.date.day}/${s.date.month}/${s.date.year}';
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
                                      Text(
                                        '$dateStr - ${s.jins}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
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
                                            fontSize: 11.5,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${s.bags} Bags/Weight @ Rate ₹${s.rate.toStringAsFixed(0)} (Total: ₹${(s.bags * s.rate).toStringAsFixed(0)})',
                                  ),
                                  Text(
                                    'Seller: ${s.seller} (${s.sellerMobile}) | Brokerage: ₹${s.totalBuyerDalali.toStringAsFixed(0)}',
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
                                            color: Colors.red.shade200),
                                      ),
                                      child: Text(
                                        '⚠️ Cancellation Requested by ${s.cancelRequestedBy}: "${s.cancellationReason}"',
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
                                      const SizedBox(width: 10),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => _confirmSauda(s),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'CONFIRM SAUDA',
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

                    // Broker Ledgers
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Broker Accounts in Your Books (ब्रोकर वार खाता)',
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
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Text(
                            '${brokerAccounts.length} ACTIVE BROKER LEDGERS',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
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
                          'No confirmed saudas in any broker ledger yet.',
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
                            (acc, d) => acc + d.totalBuyerDalali,
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
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                const Color(0xFF0F766E)
                                                    .withValues(alpha: 0.12),
                                            child: const Icon(
                                              Icons.account_balance,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                brokerName,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'Mobile: ${deals.first.brokerMobile} | Deals: ${deals.length} | Bags: $totalBags',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0F766E),
                                          foregroundColor: Colors.white,
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
                                                  type: 'Buyer',
                                                ),
                                                isBuyer: true,
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
                                          '${d.date.day}/${d.date.month}/${d.date.year}';
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
                                          'Seller: ${d.seller} (${d.sellerMobile}) | Brokerage: ₹${d.totalBuyerDalali.toStringAsFixed(0)}',
                                        ),
                                        trailing: Text(
                                          '₹${(d.bags * d.rate).toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.blue,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
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
                                          'Broker Dalali Due: ₹${totalDalali.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                        Text(
                                          'Total Purchase Value: ₹${totalValue.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
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

// =============================================================
// BROKER DIRECTORY SEARCH SCREEN
// =============================================================
class BrokerDirectorySearchScreen extends StatelessWidget {
  const BrokerDirectorySearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brokers = AccountService.getAccountsBySection('BROKER');

    return Scaffold(
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
  static const String adminSupportPhone = '+919876543210';

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
