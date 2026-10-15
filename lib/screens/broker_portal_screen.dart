import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/email_service.dart';
import '../services/mandi_services.dart';
import 'bill_print_screen.dart';
import 'main_dashboard_screen.dart';

// =============================================================
// 4. COMPLETE BROKER MODULE (ISOLATED BROKER DIRECTORY)
// =============================================================
class BrokerSectionPortal extends StatefulWidget {
  const BrokerSectionPortal({super.key});

  @override
  State<BrokerSectionPortal> createState() => _BrokerSectionPortalState();
}

class _BrokerSectionPortalState extends State<BrokerSectionPortal> {
  int _currentIndex = 0;
  List<MandiSaudaModel> _saudaRecords = [];
  List<MandiPartyModel> _parties = [];
  BrokerFirmProfileModel _brokerProfile = BrokerFirmProfileModel();
  UserAccount? _currentUser;
  StreamSubscription<bool>? _lockSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _partiesSubscription;

  String get _activeBrokerKey {
    final mob = _currentUser?.mobile ??
        StorageService.get('session_BROKER_mobile') ??
        StorageService.get('session_BROKER') ??
        '';
    return CloudSyncService.getActiveBrokerKey(mob.isNotEmpty ? mob : null);
  }

  @override
  void initState() {
    super.initState();
    _loadAllFromStorage();
    _startLiveAccountLockListener();
  }

  void _startLiveAccountLockListener() {
    final mobile = _currentUser?.mobile ??
        StorageService.get('session_BROKER_mobile') ??
        StorageService.get('session_BROKER') ??
        '';

    if (mobile.isEmpty) return;

    _lockSubscription =
        CloudSyncService.streamAccountLockStatus('BROKER', mobile)
            .listen((isLocked) {
      if (isLocked && mounted) {
        _forceLogoutDueToLock();
      }
    });
  }

  void _forceLogoutDueToLock() {
    _lockSubscription?.cancel();
    _partiesSubscription?.cancel();

    StorageService.remove('session_BROKER');
    StorageService.remove('session_BROKER_mobile');

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
          'Your account has been locked or your subscription has expired.\nPlease renew your plan or contact the mandi admin office.',
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
    _partiesSubscription?.cancel();
    super.dispose();
  }

  void _loadAllFromStorage() async {
    _currentUser = AccountService.getSessionUser('BROKER');

    final fallbackMobile = StorageService.get('session_BROKER_mobile') ??
        StorageService.get('session_BROKER') ??
        '';
    final fallbackName =
        StorageService.get('session_BROKER_name') ?? 'BROKER ADMIN';
    final fallbackEmail = StorageService.get('session_BROKER_email') ?? '';
    final fallbackAddress =
        StorageService.get('session_BROKER_address') ?? 'MAIN MANDI OFFICE';

    if (_currentUser == null && fallbackMobile.isNotEmpty) {
      _currentUser = UserAccount(
        name: fallbackName,
        mobile: fallbackMobile,
        email: fallbackEmail,
        address: fallbackAddress,
        password: '',
        section: 'BROKER',
      );
    }

    final activeMobile = _currentUser?.mobile ?? fallbackMobile;

    if (activeMobile.isNotEmpty) {
      final cloudProfile = await CloudSyncService.getBrokerProfile(
        activeMobile,
      );
      if (cloudProfile != null) {
        _brokerProfile = BrokerFirmProfileModel.fromJson(cloudProfile);
      }
    }

    if (_brokerProfile.firmName.isEmpty) {
      _brokerProfile.firmName = _currentUser?.name.isNotEmpty == true
          ? _currentUser!.name
          : fallbackName;
    }
    if (_brokerProfile.mobile.isEmpty) {
      _brokerProfile.mobile = activeMobile;
    }
    if (_brokerProfile.email.isEmpty) {
      _brokerProfile.email = _currentUser?.email.isNotEmpty == true
          ? _currentUser!.email
          : fallbackEmail;
    }
    if (_brokerProfile.address.isEmpty) {
      _brokerProfile.address = _currentUser?.address.isNotEmpty == true
          ? _currentUser!.address
          : fallbackAddress;
    }

    _partiesSubscription?.cancel();
    _partiesSubscription =
        CloudSyncService.streamBrokerParties(_activeBrokerKey)
            .listen((partiesData) {
      if (mounted) {
        setState(() {
          _parties =
              partiesData.map((p) => MandiPartyModel.fromJson(p)).toList();
        });
        _persistParties();
      }
    });

    if (mounted) setState(() {});
  }

  void _persistSaudas() {
    final data = jsonEncode(_saudaRecords.map((s) => s.toJson()).toList());
    StorageService.save('mandi_saudas', data);
  }

  void _persistParties() {
    final data = jsonEncode(_parties.map((p) => p.toJson()).toList());
    StorageService.save('mandi_parties', data);
  }

  void _persistProfile() {
    final data = jsonEncode(_brokerProfile.toJson());
    StorageService.save('mandi_profile', data);
  }

  void _addSauda(MandiSaudaModel sauda) {
    setState(() => _saudaRecords.insert(0, sauda));
    _persistSaudas();
  }

  void _editSauda(MandiSaudaModel updated) {
    setState(() {
      final index = _saudaRecords.indexWhere((s) => s.id == updated.id);
      if (index != -1) _saudaRecords[index] = updated;
    });
    _persistSaudas();
    CloudSyncService.updateSauda(
      updated.id,
      updated.toJson(),
      brokerKey: _activeBrokerKey,
    );
  }

  void _deleteSauda(String id) {
    final saudaIndex = _saudaRecords.indexWhere((s) => s.id == id);
    if (saudaIndex != -1) {
      final s = _saudaRecords[saudaIndex];

      CloudSyncService.sendNotification(
        targetMobile: s.buyerMobile,
        title: '⚠️ Sauda Deleted by Broker (${_brokerProfile.firmName})',
        message:
            'Deal for ${s.jins} (${s.bags} Bags) has been removed by broker.',
        brokerKey: _activeBrokerKey,
      );

      CloudSyncService.sendNotification(
        targetMobile: s.sellerMobile,
        title: '⚠️ Sauda Deleted by Broker (${_brokerProfile.firmName})',
        message:
            'Deal for ${s.jins} (${s.bags} Bags) has been removed by broker.',
        brokerKey: _activeBrokerKey,
      );

      CloudSyncService.deleteSauda(id, brokerKey: _activeBrokerKey);
    }

    setState(() => _saudaRecords.removeWhere((s) => s.id == id));
    _persistSaudas();
  }

  void _addParty(MandiPartyModel party) {
    setState(() => _parties.add(party));
    _persistParties();
    CloudSyncService.saveBrokerParty(
      brokerKey: _activeBrokerKey,
      partyData: party.toJson(),
    );
  }

  void _editParty(String oldMobile, MandiPartyModel updatedParty) {
    setState(() {
      final partyIndex = _parties.indexWhere((p) => p.mobile == oldMobile);
      if (partyIndex != -1) _parties[partyIndex] = updatedParty;

      for (var s in _saudaRecords) {
        if (s.buyerMobile == oldMobile) {
          s.buyerMobile = updatedParty.mobile;
          s.buyer = updatedParty.name;
        }
        if (s.sellerMobile == oldMobile) {
          s.sellerMobile = updatedParty.mobile;
          s.seller = updatedParty.name;
        }
      }
    });
    _persistParties();
    _persistSaudas();

    if (oldMobile != updatedParty.mobile) {
      CloudSyncService.deleteBrokerParty(_activeBrokerKey, oldMobile);
    }
    CloudSyncService.saveBrokerParty(
      brokerKey: _activeBrokerKey,
      partyData: updatedParty.toJson(),
    );
  }

  void _deleteParty(String mobile) {
    setState(() => _parties.removeWhere((p) => p.mobile == mobile));
    _persistParties();
    CloudSyncService.deleteBrokerParty(_activeBrokerKey, mobile);
  }

  void _updateProfile(BrokerFirmProfileModel updated) {
    setState(() => _brokerProfile = updated);
    _persistProfile();
  }

  void _logout() {
    _partiesSubscription?.cancel();
    _lockSubscription?.cancel();

    StorageService.remove('last_active_section');
    StorageService.remove('session_BROKER');
    StorageService.remove('session_BROKER_name');
    StorageService.remove('session_BROKER_mobile');
    StorageService.remove('session_BROKER_email');
    StorageService.remove('session_BROKER_address');

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MainDashboardScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CloudSyncService.streamBrokerSaudas(_activeBrokerKey),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _saudaRecords = snapshot.data!
              .map((data) => MandiSaudaModel.fromJson(data))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
        }

        final screens = [
          BrokerDealEntryTab(
            saudaRecords: _saudaRecords,
            parties: _parties,
            brokerProfile: _brokerProfile,
            currentUser: _currentUser,
            brokerKey: _activeBrokerKey,
            onSaudaSaved: _addSauda,
            onSaudaEdited: _editSauda,
            onSaudaDeleted: _deleteSauda,
            onPartyAdded: _addParty,
            onProfileUpdated: _updateProfile,
            onLogout: _logout,
          ),
          BrokerKhataDirectoryTab(
            saudaRecords: _saudaRecords,
            parties: _parties,
            brokerProfile: _brokerProfile,
            brokerKey: _activeBrokerKey,
            onPartyAdded: _addParty,
            onPartyEdited: _editParty,
            onPartyDeleted: _deleteParty,
            onSaudaEdited: _editSauda,
            onSaudaDeleted: _deleteSauda,
          ),
        ];

        return Scaffold(
          body: screens[_currentIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) =>
                setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.edit_note),
                label: 'Sauda Entry',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Party Khata (खाता)',
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// BROKER DEAL ENTRY TAB
// -------------------------------------------------------------
class BrokerDealEntryTab extends StatefulWidget {
  final List<MandiSaudaModel> saudaRecords;
  final List<MandiPartyModel> parties;
  final BrokerFirmProfileModel brokerProfile;
  final UserAccount? currentUser;
  final String brokerKey;
  final Function(MandiSaudaModel) onSaudaSaved;
  final Function(MandiSaudaModel) onSaudaEdited;
  final Function(String) onSaudaDeleted;
  final Function(MandiPartyModel) onPartyAdded;
  final Function(BrokerFirmProfileModel) onProfileUpdated;
  final VoidCallback onLogout;

  const BrokerDealEntryTab({
    super.key,
    required this.saudaRecords,
    required this.parties,
    required this.brokerProfile,
    required this.currentUser,
    required this.brokerKey,
    required this.onSaudaSaved,
    required this.onSaudaEdited,
    required this.onSaudaDeleted,
    required this.onPartyAdded,
    required this.onProfileUpdated,
    required this.onLogout,
  });

  @override
  State<BrokerDealEntryTab> createState() => _BrokerDealEntryTabState();
}

class _BrokerDealEntryTabState extends State<BrokerDealEntryTab> {
  TextEditingController? _buyerController;
  TextEditingController? _sellerController;
  TextEditingController? _jinsController;

  MandiPartyModel? _selectedBuyer;
  MandiPartyModel? _selectedSeller;

  final _bagsController = TextEditingController();
  final _rateController = TextEditingController();
  late TextEditingController _buyerDalaliRateController;
  late TextEditingController _sellerDalaliRateController;

  DateTime _selectedDate = DateTime.now();

  double _liveBuyerDalali = 0.0;
  double _liveSellerDalali = 0.0;
  double _liveTotalDalali = 0.0;

  @override
  void initState() {
    super.initState();
    _buyerDalaliRateController = TextEditingController(
      text: widget.brokerProfile.defaultBuyerDalali > 0
          ? widget.brokerProfile.defaultBuyerDalali.toStringAsFixed(0)
          : '0',
    );
    _sellerDalaliRateController = TextEditingController(
      text: widget.brokerProfile.defaultSellerDalali > 0
          ? widget.brokerProfile.defaultSellerDalali.toStringAsFixed(0)
          : '0',
    );
  }

  @override
  void dispose() {
    _bagsController.dispose();
    _rateController.dispose();
    _buyerDalaliRateController.dispose();
    _sellerDalaliRateController.dispose();
    super.dispose();
  }

  void _calculateLiveDalali() {
    int bags = int.tryParse(_bagsController.text) ?? 0;
    double bRate = double.tryParse(_buyerDalaliRateController.text) ?? 0.0;
    double sRate = double.tryParse(_sellerDalaliRateController.text) ?? 0.0;

    setState(() {
      _liveBuyerDalali = bags * bRate;
      _liveSellerDalali = bags * sRate;
      _liveTotalDalali = _liveBuyerDalali + _liveSellerDalali;
    });
  }

  Future<MandiPartyModel?> _showAddPartyPopup({required String role}) async {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String selectedType = role;

    return await showDialog<MandiPartyModel>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Add $role Details',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Party Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mobileCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameCtrl.text.trim().toUpperCase();
                final mobile = mobileCtrl.text.trim();
                final address = addressCtrl.text.trim().toUpperCase();

                if (name.isEmpty || mobile.length != 10 || address.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please check fields (Mobile must be 10 digits)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (widget.parties.any((p) => p.mobile == mobile)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Mobile $mobile is already registered!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final newParty = MandiPartyModel(
                  name: name,
                  mobile: mobile,
                  address: address,
                  type: selectedType,
                );
                widget.onPartyAdded(newParty);
                Navigator.pop(ctx, newParty);
              },
              child: const Text('SAVE & SELECT'),
            ),
          ],
        ),
      ),
    );
  }

  Future<MandiPartyModel?> _resolveParty({
    required TextEditingController? controller,
    required MandiPartyModel? selectedParty,
    required String role,
  }) async {
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty) return null;

    if (selectedParty != null &&
        (selectedParty.name.toUpperCase() == text.toUpperCase() ||
            selectedParty.mobile == text)) {
      return selectedParty;
    }

    final matches = widget.parties
        .where(
          (p) => p.name.toUpperCase() == text.toUpperCase() || p.mobile == text,
        )
        .toList();
    if (matches.isNotEmpty) return matches.first;

    return await _showAddPartyPopup(role: role);
  }

  void _showWhatsAppDispatchDialog(MandiSaudaModel sauda) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text(
              'Sauda Saved Successfully!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deal recorded for ${sauda.jins} (${sauda.bags} Bags @ ₹${sauda.rate.toStringAsFixed(0)}).',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Text(
                'Send deal confirmation to Buyer and Seller on WhatsApp (uses custom template if set):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
              ),
              onPressed: () {
                WhatsAppService.sendSaudaAlert(
                  recipientMobile: sauda.buyerMobile,
                  role: 'BUYER',
                  sauda: sauda,
                  brokerFirmName: widget.brokerProfile.firmName,
                  brokerMobile: widget.brokerProfile.mobile,
                );
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                'Send to Buyer: ${sauda.buyer} (${sauda.buyerMobile})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF128C7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 14,
                ),
              ),
              onPressed: () {
                WhatsAppService.sendSaudaAlert(
                  recipientMobile: sauda.sellerMobile,
                  role: 'SELLER',
                  sauda: sauda,
                  brokerFirmName: widget.brokerProfile.firmName,
                  brokerMobile: widget.brokerProfile.mobile,
                );
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                'Send to Seller: ${sauda.seller} (${sauda.sellerMobile})',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DONE (पूरा हुआ)'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSauda() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    if (selectedDay.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot generate sauda for a future date!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    MandiPartyModel? buyerParty = await _resolveParty(
      controller: _buyerController,
      selectedParty: _selectedBuyer,
      role: 'Buyer',
    );
    if (buyerParty == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or register Buyer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _selectedBuyer = buyerParty;
      _buyerController?.text = buyerParty.name;
    });

    MandiPartyModel? sellerParty = await _resolveParty(
      controller: _sellerController,
      selectedParty: _selectedSeller,
      role: 'Seller',
    );
    if (sellerParty == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or register Seller'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _selectedSeller = sellerParty;
      _sellerController?.text = sellerParty.name;
    });

    if (buyerParty.mobile == sellerParty.mobile) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buyer and Seller cannot be the same party!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final jinsVal = _jinsController?.text.trim() ?? '';
    if (jinsVal.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Jins / Commodity'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    int bags = int.tryParse(_bagsController.text) ?? 0;
    double rate = double.tryParse(_rateController.text) ?? 0.0;

    if (bags <= 0 || rate <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid Bags / Weight and Rate'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newSauda = MandiSaudaModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _selectedDate,
      buyer: buyerParty.name,
      buyerMobile: buyerParty.mobile,
      seller: sellerParty.name,
      sellerMobile: sellerParty.mobile,
      jins: jinsVal.toUpperCase(),
      bags: bags,
      rate: rate,
      buyerDalaliPerBag:
          double.tryParse(_buyerDalaliRateController.text) ?? 0.0,
      sellerDalaliPerBag:
          double.tryParse(_sellerDalaliRateController.text) ?? 0.0,
      buyerConfirmed: false,
      sellerConfirmed: false,
      brokerFirmName: widget.brokerProfile.firmName,
      brokerMobile: widget.brokerProfile.mobile,
    );

    widget.onSaudaSaved(newSauda);
    await CloudSyncService.bookSauda(
      saudaData: newSauda.toJson(),
      brokerKey: widget.brokerKey,
    );

    if (!mounted) return;

    setState(() {
      _buyerController?.clear();
      _sellerController?.clear();
      _jinsController?.clear();
      _selectedBuyer = null;
      _selectedSeller = null;
      _bagsController.clear();
      _rateController.clear();
      _buyerDalaliRateController.text =
          widget.brokerProfile.defaultBuyerDalali > 0
              ? widget.brokerProfile.defaultBuyerDalali.toStringAsFixed(0)
              : '0';
      _sellerDalaliRateController.text =
          widget.brokerProfile.defaultSellerDalali > 0
              ? widget.brokerProfile.defaultSellerDalali.toStringAsFixed(0)
              : '0';
      _liveBuyerDalali = 0.0;
      _liveSellerDalali = 0.0;
      _liveTotalDalali = 0.0;
    });

    _showWhatsAppDispatchDialog(newSauda);
  }

  Widget _buildPartySearchField({
    required String label,
    required IconData icon,
    required String role,
    required MandiPartyModel? selectedParty,
    required Function(TextEditingController) onControllerReady,
    required Function(MandiPartyModel?) onPartySelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<MandiPartyModel>(
          displayStringForOption: (party) => party.name,
          optionsBuilder: (TextEditingValue textEditingValue) {
            final query = textEditingValue.text.trim();
            if (query.isEmpty) return const Iterable<MandiPartyModel>.empty();

            return widget.parties.where((p) {
              final matchesRole = (role == 'Buyer' &&
                      (p.type == 'Buyer' || p.type == 'Both')) ||
                  (role == 'Seller' &&
                      (p.type == 'Seller' || p.type == 'Both'));
              final matchesQuery = p.name.contains(query.toUpperCase()) ||
                  p.mobile.contains(query);
              return matchesRole && matchesQuery;
            });
          },
          onSelected: (party) => onPartySelected(party),
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4.0,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 250,
                    maxWidth: 360,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final party = options.elementAt(index);
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              const Color(0xFF0F766E).withValues(alpha: 0.15),
                          child: Text(
                            party.name.isNotEmpty ? party.name[0] : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ),
                        title: Text(
                          party.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '📞 ${party.mobile} | 📍 ${party.address}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => onSelected(party),
                      );
                    },
                  ),
                ),
              ),
            );
          },
          fieldViewBuilder:
              (context, controller, focusNode, onEditingComplete) {
            onControllerReady(controller);
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseTextFormatter()],
              onChanged: (text) {
                if (selectedParty != null && text != selectedParty.name) {
                  onPartySelected(null);
                }
              },
              onEditingComplete: onEditingComplete,
              decoration: InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
                border: const OutlineInputBorder(),
              ),
            );
          },
        ),
        if (selectedParty != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF0F766E).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, size: 16, color: Color(0xFF0F766E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'MOB: ${selectedParty.mobile}  |  ADDR: ${selectedParty.address}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final profilePhotoBytes = decodeBase64Image(
      widget.brokerProfile.photoBase64,
    );
    final brokerNotifications = NotificationService.getForMobile(
      widget.brokerProfile.mobile,
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Home',
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (context) => const MainDashboardScreen()),
                (route) => false,
              );
            }
          },
        ),
        title: const Text(
          'Broker Sauda Bahi',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: brokerNotifications.isNotEmpty,
              label: Text('${brokerNotifications.length}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Cancellation Requests',
            onPressed: () =>
                showNotificationDialog(context, widget.brokerProfile.mobile),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BrokerProfileScreen(
                      profile: widget.brokerProfile,
                      saudaRecords: widget.saudaRecords,
                      parties: widget.parties,
                      currentUser: widget.currentUser,
                      brokerKey: widget.brokerKey,
                      onProfileUpdated: (updated) {
                        widget.onProfileUpdated(updated);
                        setState(() {
                          if (_buyerDalaliRateController.text == '0' ||
                              _buyerDalaliRateController.text.isEmpty) {
                            _buyerDalaliRateController.text =
                                updated.defaultBuyerDalali.toStringAsFixed(0);
                          }
                          if (_sellerDalaliRateController.text == '0' ||
                              _sellerDalaliRateController.text.isEmpty) {
                            _sellerDalaliRateController.text =
                                updated.defaultSellerDalali.toStringAsFixed(0);
                          }
                        });
                      },
                      onLogout: widget.onLogout,
                    ),
                  ),
                );
              },
              child: profilePhotoBytes != null
                  ? CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.white,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundImage: MemoryImage(profilePhotoBytes),
                      ),
                    )
                  : const CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.account_circle,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate.isAfter(now)
                                      ? now
                                      : _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: now,
                                );
                                if (picked != null) {
                                  setState(() => _selectedDate = picked);
                                }
                              },
                              icon: const Icon(Icons.calendar_month),
                              label: const Text('Change Date'),
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildPartySearchField(
                                label: 'Buyer (खरीदार)',
                                icon: Icons.storefront_outlined,
                                role: 'Buyer',
                                selectedParty: _selectedBuyer,
                                onControllerReady: (c) => _buyerController = c,
                                onPartySelected: (p) =>
                                    setState(() => _selectedBuyer = p),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPartySearchField(
                                label: 'Seller (विक्रेता)',
                                icon: Icons.person_outline,
                                role: 'Seller',
                                selectedParty: _selectedSeller,
                                onControllerReady: (c) => _sellerController = c,
                                onPartySelected: (p) =>
                                    setState(() => _selectedSeller = p),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue val) {
                            final query = val.text.trim().toUpperCase();
                            if (query.isEmpty) {
                              return widget.brokerProfile.commonJins;
                            }
                            return widget.brokerProfile.commonJins.where(
                              (jins) => jins.toUpperCase().contains(query),
                            );
                          },
                          onSelected: (selection) =>
                              _jinsController?.text = selection,
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                borderRadius: BorderRadius.circular(8),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 220,
                                    maxWidth: 360,
                                  ),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder:
                                        (BuildContext context, int index) {
                                      final item = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(
                                          Icons.inventory_2_outlined,
                                          size: 18,
                                          color: Color(0xFF0F766E),
                                        ),
                                        title: Text(
                                          item,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        onTap: () => onSelected(item),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                          fieldViewBuilder: (
                            context,
                            controller,
                            focusNode,
                            onEditingComplete,
                          ) {
                            _jinsController = controller;
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [UpperCaseTextFormatter()],
                              onEditingComplete: onEditingComplete,
                              decoration: const InputDecoration(
                                labelText: 'Jins / Commodity (जिंस)',
                                prefixIcon: Icon(
                                  Icons.inventory_2_outlined,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _bagsController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => _calculateLiveDalali(),
                                decoration: const InputDecoration(
                                  labelText: 'Bags / Weight (बोरी)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _rateController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Rate / Bhav (भाव)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _buyerDalaliRateController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _calculateLiveDalali(),
                                decoration: const InputDecoration(
                                  labelText: 'Buyer Brokerage (₹/Bag)',
                                  helperText: 'Bags × ₹/Bag',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _sellerDalaliRateController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => _calculateLiveDalali(),
                                decoration: const InputDecoration(
                                  labelText: 'Seller Brokerage (₹/Bag)',
                                  helperText: 'Bags × ₹/Bag',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Buyer Dalali',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_liveBuyerDalali.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.black12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Seller Dalali',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_liveSellerDalali.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.black12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Total Dalali',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_liveTotalDalali.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saveSauda,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'SAVE SAUDA (सौदा दर्ज करें)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Sauda Ledger (${widget.saudaRecords.length})",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.saudaRecords.isNotEmpty)
                      Text(
                        "Total Dalali: ₹${widget.saudaRecords.fold<double>(0.0, (acc, item) => acc + item.totalDalaliEarned).toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (widget.saudaRecords.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: const Text(
                      'No transactions recorded yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.saudaRecords.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final s = widget.saudaRecords[index];
                      final allConfirmed =
                          s.buyerConfirmed && s.sellerConfirmed;

                      return Card(
                        elevation: 1.5,
                        color: s.cancelRequested ? Colors.amber.shade50 : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Buyer: ${s.buyer}  |  Seller: ${s.seller}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${s.jins} | ${s.bags} Bags @ Rate ₹${s.rate}\nBuyer Dalali: ₹${s.totalBuyerDalali.toStringAsFixed(0)} | Seller Dalali: ₹${s.totalSellerDalali.toStringAsFixed(0)}',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '₹${s.totalDalaliEarned.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                      const Text(
                                        'Brokerage',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.share,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            tooltip: 'WhatsApp Slip',
                                            onPressed: () =>
                                                _showWhatsAppDispatchDialog(s),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.edit,
                                              size: 18,
                                              color: allConfirmed
                                                  ? Colors.grey
                                                  : const Color(0xFF0F766E),
                                            ),
                                            tooltip: allConfirmed
                                                ? 'Confirmed sauda cannot be edited'
                                                : 'Edit Sauda',
                                            onPressed: () {
                                              if (allConfirmed) {
                                                showDialog(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text(
                                                      'Edit Locked (सौदा लॉक है)',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    content: const Text(
                                                      'This sauda has been confirmed by both parties. Confirmed saudas cannot be edited; they can only be deleted by the broker.',
                                                    ),
                                                    actions: [
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(ctx),
                                                        child: const Text('OK'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                return;
                                              }
                                              showEditSaudaDialog(
                                                context,
                                                s,
                                                widget.onSaudaEdited,
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            tooltip:
                                                'Delete Sauda (Only Broker)',
                                            onPressed: () =>
                                                showDeleteSaudaDialog(
                                              context,
                                              s.id,
                                              widget.onSaudaDeleted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 10),
                              if (s.cancelRequested) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.red,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '⚠️ CANCELLATION REQUESTED BY ${s.cancelRequestedBy?.toUpperCase()}! Reason: "${s.cancellationReason}". Please delete this sauda.',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: s.buyerConfirmed
                                            ? Colors.green.shade50
                                            : Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: s.buyerConfirmed
                                              ? Colors.green.shade300
                                              : Colors.amber.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            s.buyerConfirmed
                                                ? Icons.check_circle
                                                : Icons.hourglass_top,
                                            size: 12,
                                            color: s.buyerConfirmed
                                                ? Colors.green
                                                : Colors.amber.shade800,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            s.buyerConfirmed
                                                ? 'Buyer: Confirmed ✓'
                                                : 'Buyer: Pending ⏳',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: s.buyerConfirmed
                                                  ? Colors.green.shade900
                                                  : Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: s.sellerConfirmed
                                            ? Colors.green.shade50
                                            : Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: s.sellerConfirmed
                                              ? Colors.green.shade300
                                              : Colors.amber.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            s.sellerConfirmed
                                                ? Icons.check_circle
                                                : Icons.hourglass_top,
                                            size: 12,
                                            color: s.sellerConfirmed
                                                ? Colors.green
                                                : Colors.amber.shade800,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            s.sellerConfirmed
                                                ? 'Seller: Confirmed ✓'
                                                : 'Seller: Pending ⏳',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: s.sellerConfirmed
                                                  ? Colors.green.shade900
                                                  : Colors.amber.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (allConfirmed) ...[
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade700,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'ALL CONFIRMED ✓ (LOCKED)',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
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
  }
}

// -------------------------------------------------------------
// BROKER KHATA DIRECTORY TAB
// -------------------------------------------------------------
class BrokerKhataDirectoryTab extends StatefulWidget {
  final List<MandiSaudaModel> saudaRecords;
  final List<MandiPartyModel> parties;
  final BrokerFirmProfileModel brokerProfile;
  final String brokerKey;
  final Function(MandiPartyModel) onPartyAdded;
  final Function(String, MandiPartyModel) onPartyEdited;
  final Function(String) onPartyDeleted;
  final Function(MandiSaudaModel) onSaudaEdited;
  final Function(String) onSaudaDeleted;

  const BrokerKhataDirectoryTab({
    super.key,
    required this.saudaRecords,
    required this.parties,
    required this.brokerProfile,
    required this.brokerKey,
    required this.onPartyAdded,
    required this.onPartyEdited,
    required this.onPartyDeleted,
    required this.onSaudaEdited,
    required this.onSaudaDeleted,
  });

  @override
  State<BrokerKhataDirectoryTab> createState() =>
      _BrokerKhataDirectoryTabState();
}

class _BrokerKhataDirectoryTabState extends State<BrokerKhataDirectoryTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int _selectedMonth = 0;
  int _selectedYear = DateTime.now().year;

  final List<String> _months = [
    'All Months',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<int> get _activeYears {
    final years = widget.saudaRecords.map((d) => d.date.year).toSet().toList();
    if (years.isEmpty) return [DateTime.now().year];
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  List<int> _getActiveMonths(int year) {
    final months = widget.saudaRecords
        .where((d) => d.date.year == year)
        .map((d) => d.date.month)
        .toSet()
        .toList();
    if (months.isEmpty) return [DateTime.now().month];
    months.sort();
    return months;
  }

  List<MandiSaudaModel> _getFilteredDeals(int year, int month) {
    return widget.saudaRecords.where((deal) {
      final matchesYear = deal.date.year == year;
      final matchesMonth = month == 0 || deal.date.month == month;
      return matchesYear && matchesMonth;
    }).toList();
  }

  void _openAddPartyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    String selectedType = _tabController.index == 0 ? 'Buyer' : 'Seller';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text(
            'Add New Party',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Party Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mobileCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Buyer',
                      child: Text('Buyer (खरीदार)'),
                    ),
                    DropdownMenuItem(
                      value: 'Seller',
                      child: Text('Seller (विक्रेता)'),
                    ),
                    DropdownMenuItem(
                      value: 'Both',
                      child: Text('Both (दोनों)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
              ],
            ),
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
                final name = nameCtrl.text.trim().toUpperCase();
                final mobile = mobileCtrl.text.trim();
                final address = addressCtrl.text.trim().toUpperCase();

                if (name.isEmpty || mobile.length != 10 || address.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please check fields (Mobile must be 10 digits)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (widget.parties.any((p) => p.mobile == mobile)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Mobile $mobile is already registered!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                widget.onPartyAdded(
                  MandiPartyModel(
                    name: name,
                    mobile: mobile,
                    address: address,
                    type: selectedType,
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('SAVE PARTY'),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, Map<String, dynamic>> _aggregatePartyData(
    List<MandiSaudaModel> deals,
    bool isBuyer,
  ) {
    final Map<String, Map<String, dynamic>> map = {};

    for (var p in widget.parties) {
      if ((isBuyer && (p.type == 'Buyer' || p.type == 'Both')) ||
          (!isBuyer && (p.type == 'Seller' || p.type == 'Both'))) {
        map[p.mobile] = {
          'party': p,
          'bags': 0,
          'dalaliDue': 0.0,
          'dealsCount': 0,
        };
      }
    }

    for (var d in deals) {
      final mobile = isBuyer ? d.buyerMobile : d.sellerMobile;
      final name = isBuyer ? d.buyer : d.seller;

      if (!map.containsKey(mobile)) {
        map[mobile] = {
          'party': MandiPartyModel(
            name: name,
            mobile: mobile,
            address: 'NOT SPECIFIED',
            type: isBuyer ? 'Buyer' : 'Seller',
          ),
          'bags': 0,
          'dalaliDue': 0.0,
          'dealsCount': 0,
        };
      }
      map[mobile]!['bags'] += d.bags;
      map[mobile]!['dalaliDue'] +=
          isBuyer ? d.totalBuyerDalali : d.totalSellerDalali;
      map[mobile]!['dealsCount'] += 1;
    }

    return map;
  }

  Widget _buildPartyTable({
    required Map<String, Map<String, dynamic>> partyData,
    required bool isBuyerTab,
    required List<MandiSaudaModel> deals,
  }) {
    final mobiles = partyData.keys.toList();

    if (mobiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No ${isBuyerTab ? "Buyer" : "Seller"} accounts found.\nTap "+ Add Party" below to create one.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: mobiles.length,
      itemBuilder: (context, index) {
        final mobile = mobiles[index];
        final info = partyData[mobile]!;
        final party = info['party'] as MandiPartyModel;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isBuyerTab
                  ? const Color(0xFF0F766E).withValues(alpha: 0.15)
                  : Colors.orange.shade100,
              child: Text(
                party.name.isNotEmpty ? party.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isBuyerTab
                      ? const Color(0xFF0F766E)
                      : Colors.orange.shade900,
                ),
              ),
            ),
            title: Text(
              party.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              'Mobile: ${party.mobile} | Addr: ${party.address}\nDeals: ${info['dealsCount']} | Total Bags/Weight: ${info['bags']}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${(info['dalaliDue'] as double).toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
                Text(
                  isBuyerTab ? 'Buyer Dalali' : 'Seller Dalali',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BrokerPartyDetailScreen(
                    party: party,
                    isBuyer: isBuyerTab,
                    allSauda: widget.saudaRecords,
                    allParties: widget.parties,
                    brokerProfile: widget.brokerProfile,
                    onPartyEdited: widget.onPartyEdited,
                    onPartyDeleted: widget.onPartyDeleted,
                    onSaudaEdited: widget.onSaudaEdited,
                    onSaudaDeleted: widget.onSaudaDeleted,
                  ),
                ),
              ).then((_) => setState(() {}));
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableYears = _activeYears;
    if (!availableYears.contains(_selectedYear)) {
      _selectedYear = availableYears.first;
    }

    final activeMonths = _getActiveMonths(_selectedYear);
    final allowedMonthValues = [0, ...activeMonths];

    if (!allowedMonthValues.contains(_selectedMonth)) {
      _selectedMonth = 0;
    }

    final filtered = _getFilteredDeals(_selectedYear, _selectedMonth);
    final buyerData = _aggregatePartyData(filtered, true);
    final sellerData = _aggregatePartyData(filtered, false);

    double totalBuyerDalali = buyerData.values.fold<double>(
      0.0,
      (acc, e) => acc + (e['dalaliDue'] as double),
    );
    double totalSellerDalali = sellerData.values.fold<double>(
      0.0,
      (acc, e) => acc + (e['dalaliDue'] as double),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Party Khata Directory',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          tabs: [
            Tab(text: 'Buyers (${buyerData.length}) [खरीदार]'),
            Tab(text: 'Sellers (${sellerData.length}) [विक्रेता]'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddPartyDialog(context),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Party'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF0F766E).withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.filter_alt_outlined, color: Color(0xFF0F766E)),
                const SizedBox(width: 8),
                const Text(
                  'Period: ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedMonth,
                      isDense: true,
                      items: allowedMonthValues.map((monthIndex) {
                        return DropdownMenuItem<int>(
                          value: monthIndex,
                          child: Text(
                            monthIndex == 0
                                ? 'All Months'
                                : _months[monthIndex],
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedMonth = val);
                      },
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYear,
                    isDense: true,
                    items: availableYears.map((year) {
                      return DropdownMenuItem(
                        value: year,
                        child: Text(
                          '$year',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedYear = val;
                          _selectedMonth = 0;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF0F766E).withValues(alpha: 0.12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Saudas: ${filtered.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Buyer: ₹${totalBuyerDalali.toStringAsFixed(0)} | Seller: ₹${totalSellerDalali.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPartyTable(
                  partyData: buyerData,
                  isBuyerTab: true,
                  deals: filtered,
                ),
                _buildPartyTable(
                  partyData: sellerData,
                  isBuyerTab: false,
                  deals: filtered,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// BROKER PARTY DETAIL SCREEN
// -------------------------------------------------------------
class BrokerPartyDetailScreen extends StatefulWidget {
  final MandiPartyModel party;
  final bool isBuyer;
  final List<MandiSaudaModel> allSauda;
  final List<MandiPartyModel> allParties;
  final BrokerFirmProfileModel brokerProfile;
  final Function(String, MandiPartyModel) onPartyEdited;
  final Function(String) onPartyDeleted;
  final Function(MandiSaudaModel) onSaudaEdited;
  final Function(String) onSaudaDeleted;

  const BrokerPartyDetailScreen({
    super.key,
    required this.party,
    required this.isBuyer,
    required this.allSauda,
    required this.allParties,
    required this.brokerProfile,
    required this.onPartyEdited,
    required this.onPartyDeleted,
    required this.onSaudaEdited,
    required this.onSaudaDeleted,
  });

  @override
  State<BrokerPartyDetailScreen> createState() =>
      _BrokerPartyDetailScreenState();
}

class _BrokerPartyDetailScreenState extends State<BrokerPartyDetailScreen> {
  late MandiPartyModel _currentParty;
  int _selectedMonth = 0;
  int _selectedYear = DateTime.now().year;

  final List<String> _months = [
    'All Months',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _currentParty = widget.party;
  }

  List<MandiSaudaModel> get _partyAllDeals {
    return widget.allSauda.where((s) {
      return widget.isBuyer
          ? s.buyerMobile == _currentParty.mobile
          : s.sellerMobile == _currentParty.mobile;
    }).toList();
  }

  List<int> get _partyActiveYears {
    final years = _partyAllDeals.map((d) => d.date.year).toSet().toList();
    if (years.isEmpty) return [DateTime.now().year];
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  List<int> _getPartyActiveMonths(int year) {
    final months = _partyAllDeals
        .where((d) => d.date.year == year)
        .map((d) => d.date.month)
        .toSet()
        .toList();
    if (months.isEmpty) return [DateTime.now().month];
    months.sort();
    return months;
  }

  List<MandiSaudaModel> get _filteredDeals {
    return _partyAllDeals.where((deal) {
      final matchesYear = deal.date.year == _selectedYear;
      final matchesMonth =
          _selectedMonth == 0 || deal.date.month == _selectedMonth;
      return matchesYear && matchesMonth;
    }).toList();
  }

  void _editPartyDialog() {
    final nameCtrl = TextEditingController(text: _currentParty.name);
    final mobileCtrl = TextEditingController(text: _currentParty.mobile);
    final addressCtrl = TextEditingController(text: _currentParty.address);
    String selectedType = _currentParty.type;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            'Edit ${_currentParty.name} Details',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Party Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mobileCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Buyer',
                      child: Text('Buyer (खरीदार)'),
                    ),
                    DropdownMenuItem(
                      value: 'Seller',
                      child: Text('Seller (विक्रेता)'),
                    ),
                    DropdownMenuItem(
                      value: 'Both',
                      child: Text('Both (दोनों)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedType = val);
                  },
                ),
              ],
            ),
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
                final name = nameCtrl.text.trim().toUpperCase();
                final mobile = mobileCtrl.text.trim();
                final address = addressCtrl.text.trim().toUpperCase();

                if (name.isEmpty || mobile.length != 10 || address.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please check fields (Mobile must be 10 digits)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (mobile != _currentParty.mobile &&
                    widget.allParties.any((p) => p.mobile == mobile)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Mobile $mobile is already used by another party!',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final updated = MandiPartyModel(
                  name: name,
                  mobile: mobile,
                  address: address,
                  type: selectedType,
                );
                widget.onPartyEdited(_currentParty.mobile, updated);

                setState(() => _currentParty = updated);
                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Party details updated!'),
                    backgroundColor: Color(0xFF0F766E),
                  ),
                );
              },
              child: const Text('UPDATE PARTY'),
            ),
          ],
        ),
      ),
    );
  }

  void _deletePartyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Party Account?'),
        content: Text(
          'Are you sure you want to delete ${_currentParty.name}?\n\nPast sauda transactions in the ledger will remain intact.',
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
            onPressed: () {
              widget.onPartyDeleted(_currentParty.mobile);
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${_currentParty.name} deleted successfully.'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableYears = _partyActiveYears;
    if (!availableYears.contains(_selectedYear)) {
      _selectedYear = availableYears.first;
    }

    final activeMonths = _getPartyActiveMonths(_selectedYear);
    final allowedMonthValues = [0, ...activeMonths];
    if (!allowedMonthValues.contains(_selectedMonth)) {
      _selectedMonth = 0;
    }

    final deals = _filteredDeals;
    double totalDalali = deals.fold<double>(
      0.0,
      (acc, d) =>
          acc + (widget.isBuyer ? d.totalBuyerDalali : d.totalSellerDalali),
    );
    int totalBags = deals.fold<int>(0, (acc, d) => acc + d.bags);
    String currentPeriodText = '${_months[_selectedMonth]} $_selectedYear';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_currentParty.name} (${widget.isBuyer ? "Buyer" : "Seller"})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Statement (प्रिंट पर्चा)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MandiBillPrintScreen(
                    party: _currentParty,
                    isBuyer: widget.isBuyer,
                    deals: deals,
                    selectedPeriod: currentPeriodText,
                    brokerProfile: widget.brokerProfile,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Party Info',
            onPressed: _editPartyDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete Party Account',
            onPressed: _deletePartyDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Text(
                  'MOBILE: ${_currentParty.mobile}  |  ADDRESS: ${_currentParty.address}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            'Total Bags / Weight',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalBags',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 32, color: Colors.black12),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${widget.isBuyer ? "Buyer" : "Seller"} Dalali Due',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹${totalDalali.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: deals.isEmpty
                ? const Center(
                    child: Text('No transactions recorded in this period.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: deals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final d = deals[index];
                      final dalali = widget.isBuyer
                          ? d.totalBuyerDalali
                          : d.totalSellerDalali;

                      return Card(
                        elevation: 1,
                        child: ListTile(
                          title: Text(
                            '${d.date.day}/${d.date.month}/${d.date.year} - ${d.jins}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${d.bags} Bags @ Rate ₹${d.rate}\nOpposite Party: ${widget.isBuyer ? d.seller : d.buyer}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₹${dalali.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share,
                                    size: 18, color: Colors.green),
                                tooltip: 'WhatsApp Slip',
                                onPressed: () async {
                                  final targetMobile = widget.isBuyer
                                      ? d.buyerMobile
                                      : d.sellerMobile;
                                  final fallbackMobile = widget.party.mobile;
                                  final mobileToUse =
                                      targetMobile.trim().isNotEmpty
                                          ? targetMobile.trim()
                                          : fallbackMobile.trim();

                                  if (mobileToUse.isEmpty) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'No mobile number found for this party.'),
                                        backgroundColor: Colors.red,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Opening WhatsApp for $mobileToUse...'),
                                      backgroundColor: const Color(0xFF0F766E),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );

                                  await WhatsAppService.sendSaudaAlert(
                                    recipientMobile: mobileToUse,
                                    role: widget.isBuyer ? 'BUYER' : 'SELLER',
                                    sauda: d,
                                    brokerFirmName:
                                        widget.brokerProfile.firmName,
                                    brokerMobile: widget.brokerProfile.mobile,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                tooltip: 'Delete Sauda',
                                onPressed: () {
                                  showDeleteSaudaDialog(
                                    context,
                                    d.id,
                                    (deletedId) {
                                      widget.onSaudaDeleted(deletedId);
                                      setState(() {
                                        widget.allSauda.removeWhere(
                                            (s) => s.id == deletedId);
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Sauda deleted from party khata.'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// BROKER PROFILE SCREEN (WITH FIREBASE PASSWORD SYNC & WHATSAPP)
// -------------------------------------------------------------
class BrokerProfileScreen extends StatefulWidget {
  final BrokerFirmProfileModel profile;
  final List<MandiSaudaModel> saudaRecords;
  final List<MandiPartyModel> parties;
  final UserAccount? currentUser;
  final String brokerKey;
  final Function(BrokerFirmProfileModel) onProfileUpdated;
  final VoidCallback onLogout;

  const BrokerProfileScreen({
    super.key,
    required this.profile,
    required this.saudaRecords,
    required this.parties,
    required this.currentUser,
    required this.brokerKey,
    required this.onProfileUpdated,
    required this.onLogout,
  });

  @override
  State<BrokerProfileScreen> createState() => _BrokerProfileScreenState();
}

class _BrokerProfileScreenState extends State<BrokerProfileScreen> {
  static const String adminSupportPhone = '+919876543210';

  late TextEditingController _firmCtrl;
  late TextEditingController _addrCtrl;
  late TextEditingController _mobCtrl;
  late TextEditingController _panCtrl;
  late TextEditingController _licCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _bankCtrl;
  late TextEditingController _accCtrl;
  late TextEditingController _ifscCtrl;
  late TextEditingController _bDalaliCtrl;
  late TextEditingController _sDalaliCtrl;
  late TextEditingController _termsCtrl;
  late TextEditingController _whatsappTemplateCtrl;
  final _newJinsCtrl = TextEditingController();

  late List<String> _jinsList;
  String? _photoBase64;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _firmCtrl = TextEditingController(text: p.firmName);
    _addrCtrl = TextEditingController(text: p.address);
    _mobCtrl = TextEditingController(text: p.mobile);
    _panCtrl = TextEditingController(text: p.panNo);
    _licCtrl = TextEditingController(text: p.licenseNo);
    _emailCtrl = TextEditingController(text: p.email);
    _bankCtrl = TextEditingController(text: p.bankName);
    _accCtrl = TextEditingController(text: p.accountNo);
    _ifscCtrl = TextEditingController(text: p.ifscCode);
    _bDalaliCtrl = TextEditingController(
      text: p.defaultBuyerDalali > 0
          ? p.defaultBuyerDalali.toStringAsFixed(0)
          : '',
    );
    _sDalaliCtrl = TextEditingController(
      text: p.defaultSellerDalali > 0
          ? p.defaultSellerDalali.toStringAsFixed(0)
          : '',
    );
    _termsCtrl = TextEditingController(text: p.termsAndConditions);
    _whatsappTemplateCtrl = TextEditingController(
      text: p.whatsappMessageTemplate.isNotEmpty
          ? p.whatsappMessageTemplate
          : WhatsAppService.getDefaultTemplate(),
    );
    _jinsList = List.from(p.commonJins);
    _photoBase64 = p.photoBase64;
  }

  @override
  void dispose() {
    _firmCtrl.dispose();
    _addrCtrl.dispose();
    _mobCtrl.dispose();
    _panCtrl.dispose();
    _licCtrl.dispose();
    _emailCtrl.dispose();
    _bankCtrl.dispose();
    _accCtrl.dispose();
    _ifscCtrl.dispose();
    _bDalaliCtrl.dispose();
    _sDalaliCtrl.dispose();
    _termsCtrl.dispose();
    _whatsappTemplateCtrl.dispose();
    _newJinsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (image != null) {
        final Uint8List bytes = await image.readAsBytes();
        setState(() {
          _photoBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image selection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _requestPasswordResetViaWhatsApp() async {
    final cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final brokerMob = _mobCtrl.text.trim().isNotEmpty
        ? _mobCtrl.text.trim()
        : (widget.currentUser?.mobile ?? '');
    final firm = _firmCtrl.text.trim().isNotEmpty
        ? _firmCtrl.text.trim()
        : widget.profile.firmName;

    final message =
        'नमस्ते Mandi Support Team, मैं ब्रोकर ($firm, मोबाइल: $brokerMob) हूँ। कृपया मेरा ब्रोकर पोर्टल पासवर्ड / PIN रीसेट या अपडेट करने में सहायता करें।';

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

  Future<void> _syncPasswordToFirebase({
    required String mobile,
    required String email,
    required String newPassword,
  }) async {
    await CloudSyncService.ensureAuthSession();
    final firestore = FirebaseFirestore.instance;
    final cleanMobile = mobile.trim();
    final cleanEmail = email.trim().toLowerCase();

    final user = widget.currentUser ??
        UserAccount(
          name: _firmCtrl.text.trim().toUpperCase(),
          mobile: cleanMobile,
          email: cleanEmail,
          address: _addrCtrl.text.trim().toUpperCase(),
          password: newPassword,
          section: 'BROKER',
        );
    user.password = newPassword;

    await CloudSyncService.saveAccount(user.toJson());

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

      await firestore.collection('broker_profiles').doc(cleanMobile).set({
        'password': newPassword,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await firestore.collection('brokers').doc(cleanMobile).set({
        'password': newPassword,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

    AccountService.updateAccount(user);
    StorageService.save('session_BROKER_password', newPassword);
  }

  void _openChangePasswordDialog() {
    final currentEmail = _emailCtrl.text.trim().isNotEmpty
        ? _emailCtrl.text.trim()
        : (widget.profile.email.isNotEmpty
            ? widget.profile.email
            : (widget.currentUser?.email ?? ''));

    final currentMobile = _mobCtrl.text.trim().isNotEmpty
        ? _mobCtrl.text.trim()
        : (widget.profile.mobile.isNotEmpty
            ? widget.profile.mobile
            : (widget.currentUser?.mobile ?? ''));

    if (currentEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please save a valid Gmail address in profile first!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.password_rounded, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text(
              'Change Password',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verification OTP will be sent to your Gmail:\n$currentEmail',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: Icon(Icons.lock_reset),
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
                SnackBar(content: Text('Sending OTP to $currentEmail...')),
              );

              final sent = await EmailService.sendOtpEmail(
                recipientEmail: currentEmail,
                recipientName: widget.profile.firmName,
                otp: otp,
                purpose: 'Broker Password Change',
              );

              if (!mounted) return;

              if (sent) {
                _showGenericOtpDialog(
                  title: 'Verify Password Change',
                  email: currentEmail,
                  otp: otp,
                  onVerified: () async {
                    try {
                      await _syncPasswordToFirebase(
                        mobile: currentMobile,
                        email: currentEmail,
                        newPassword: newPass,
                      );

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
                          content:
                              Text('Failed to sync password to Firebase: $e'),
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
            child: const Text('REQUEST GMAIL OTP'),
          ),
        ],
      ),
    );
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
              'A 6-digit verification code has been sent to:\n$email',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),
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
                    content: Text('Invalid OTP! Please check your Gmail.'),
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

  void _trySaveProfile() async {
    final newEmail = _emailCtrl.text.trim().toLowerCase();
    final newMobile = _mobCtrl.text.trim();

    final originalEmail = widget.profile.email.toLowerCase();
    final originalMobile = widget.profile.mobile;

    if (newMobile.isNotEmpty && newMobile != originalMobile) {
      final isTaken = await CloudSyncService.isMobileRegistered(newMobile);
      if (!mounted) return;
      if (isTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mobile number $newMobile is already used by another account in the Mandi Network!',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    if (newEmail.isNotEmpty &&
        originalEmail.isNotEmpty &&
        (newEmail != originalEmail || newMobile != originalMobile)) {
      final otp = (100000 + Random().nextInt(900000)).toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sending security OTP to $originalEmail...')),
      );

      final sent = await EmailService.sendOtpEmail(
        recipientEmail: originalEmail,
        recipientName: widget.profile.firmName,
        otp: otp,
        purpose: 'Broker Contact Update',
      );

      if (!mounted) return;

      if (sent) {
        _showGenericOtpDialog(
          title: 'Authorize Contact Update',
          email: originalEmail,
          otp: otp,
          onVerified: () {
            if (widget.currentUser != null) {
              widget.currentUser!.email = newEmail;
              widget.currentUser!.mobile = newMobile;
              AccountService.updateAccount(widget.currentUser!);
            }
            _completeSaveProfile();
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to deliver OTP. Check internet connection.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _completeSaveProfile();
  }

  void _completeSaveProfile() async {
    final newFirmName = _firmCtrl.text.trim().toUpperCase();
    final newAddress = _addrCtrl.text.trim().toUpperCase();
    final newMobile = _mobCtrl.text.trim();
    final newEmail = _emailCtrl.text.trim().toLowerCase();

    final originalMobile = widget.profile.mobile.isNotEmpty
        ? widget.profile.mobile
        : (widget.currentUser?.mobile ?? newMobile);
    final originalEmail = widget.profile.email.isNotEmpty
        ? widget.profile.email.toLowerCase()
        : (widget.currentUser?.email.toLowerCase() ?? newEmail);

    final updated = BrokerFirmProfileModel(
      firmName: newFirmName,
      address: newAddress,
      mobile: newMobile,
      panNo: _panCtrl.text.trim().toUpperCase(),
      licenseNo: _licCtrl.text.trim().toUpperCase(),
      email: newEmail,
      bankName: _bankCtrl.text.trim().toUpperCase(),
      accountNo: _accCtrl.text.trim(),
      ifscCode: _ifscCtrl.text.trim().toUpperCase(),
      defaultBuyerDalali: double.tryParse(_bDalaliCtrl.text) ?? 0.0,
      defaultSellerDalali: double.tryParse(_sDalaliCtrl.text) ?? 0.0,
      commonJins: _jinsList,
      photoBase64: _photoBase64,
      termsAndConditions: _termsCtrl.text.trim(),
      whatsappMessageTemplate: _whatsappTemplateCtrl.text.trim(),
    );

    try {
      await CloudSyncService.updateProfile(
        section: 'BROKER',
        oldMobile: originalMobile,
        newMobile: newMobile,
        oldEmail: originalEmail,
        newEmail: newEmail,
        newName: newFirmName,
        address: newAddress,
      );

      await CloudSyncService.saveBrokerProfile(newMobile, updated.toJson());

      if (originalMobile.isNotEmpty && originalMobile != newMobile) {
        AccountService.removeAccount(mobile: originalMobile, section: 'BROKER');
        StorageService.remove('session_BROKER_$originalMobile');

        final oldParties = StorageService.get('broker_parties_$originalMobile');
        if (oldParties != null) {
          StorageService.save('broker_parties_$newMobile', oldParties);
          StorageService.remove('broker_parties_$originalMobile');
        }
      }

      StorageService.save('session_BROKER', newMobile);
      StorageService.save('session_BROKER_name', newFirmName);
      StorageService.save('session_BROKER_mobile', newMobile);
      StorageService.save('session_BROKER_email', newEmail);
      StorageService.save('session_BROKER_address', newAddress);

      if (widget.currentUser != null) {
        widget.currentUser!.name = newFirmName;
        widget.currentUser!.mobile = newMobile;
        widget.currentUser!.email = newEmail;
        widget.currentUser!.address = newAddress;
        AccountService.updateAccount(widget.currentUser!);
      }

      if (originalMobile.isNotEmpty && originalMobile != newMobile) {
        for (var s in widget.saudaRecords) {
          if (s.brokerMobile == originalMobile) {
            s.brokerMobile = newMobile;
            s.brokerFirmName = newFirmName;
          }
        }
        final data =
            jsonEncode(widget.saudaRecords.map((s) => s.toJson()).toList());
        StorageService.save('mandi_saudas', data);
      }

      widget.onProfileUpdated(updated);

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Profile updated & synchronized! All data migrated to new number.'),
          backgroundColor: Color(0xFF0F766E),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmDeleteBrokerAccount() {
    final brokerMobile = widget.profile.mobile.isNotEmpty
        ? widget.profile.mobile
        : (widget.currentUser?.mobile ?? '');

    final brokerEmail = widget.profile.email.isNotEmpty
        ? widget.profile.email
        : (widget.currentUser?.email ?? '');

    if (brokerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please save a valid email in profile before deleting account.',
          ),
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
              'Delete Broker Account?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete your broker account (${widget.profile.firmName} - $brokerMobile)?\n\n'
          'A 6-digit confirmation code will be dispatched to your Gmail ($brokerEmail).',
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
                  content: Text('Sending deletion OTP to $brokerEmail...'),
                ),
              );

              final sent = await EmailService.sendOtpEmail(
                recipientEmail: brokerEmail,
                recipientName: widget.profile.firmName,
                otp: otp,
                purpose: 'Broker Account Deletion',
              );

              if (!mounted) return;

              if (sent) {
                _showGenericOtpDialog(
                  title: 'Authorize Broker Deletion',
                  email: brokerEmail,
                  otp: otp,
                  onVerified: () async {
                    await CloudSyncService.purgeUserAccount(brokerMobile);

                    AccountService.removeAccount(
                      mobile: brokerMobile,
                      section: 'BROKER',
                    );

                    StorageService.remove('last_active_section');
                    StorageService.remove('session_BROKER');
                    StorageService.remove('session_BROKER_name');
                    StorageService.remove('session_BROKER_mobile');
                    StorageService.remove('session_BROKER_email');
                    StorageService.remove('session_BROKER_address');

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
                        content: Text('Broker account permanently deleted.'),
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
    int totalBags = widget.saudaRecords.fold<int>(0, (acc, e) => acc + e.bags);
    double totalDalali = widget.saudaRecords.fold<double>(
      0.0,
      (acc, e) => acc + e.totalDalaliEarned,
    );
    final photoBytes = decodeBase64Image(_photoBase64);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Broker Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout of Broker Section',
            onPressed: widget.onLogout,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E),
              ),
              onPressed: _trySaveProfile,
              icon: const Icon(Icons.check, size: 18),
              label: const Text(
                'SAVE PROFILE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Parties',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.parties.length}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.black12),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Total Bags',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalBags',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.black12),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'Lifetime Dalali',
                              style: TextStyle(
                                color: Color(0xFF0F766E),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${totalDalali.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor:
                              const Color(0xFF0F766E).withValues(alpha: 0.1),
                          backgroundImage: photoBytes != null
                              ? MemoryImage(photoBytes)
                              : null,
                          child: photoBytes == null
                              ? const Icon(
                                  Icons.business,
                                  size: 36,
                                  color: Color(0xFF0F766E),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Firm Logo / Profile Photo (फर्म लोगो)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Text(
                                'Displays on bill headers and watermark.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _pickProfileImage,
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      size: 15,
                                    ),
                                    label: Text(
                                      photoBytes == null
                                          ? 'ADD PHOTO'
                                          : 'CHANGE PHOTO',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (photoBytes != null) ...[
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _photoBase64 = null),
                                      child: const Text(
                                        'Remove',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Broker Firm Details (विवरण)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.teal.shade200),
                              ),
                              child: const Text(
                                'SYNCED',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _firmCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Broker Firm Name',
                            prefixIcon: Icon(Icons.business),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addrCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Mandi Office Address',
                            prefixIcon: Icon(Icons.location_on),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _mobCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Firm Mobile',
                                  prefixIcon: Icon(Icons.phone),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _panCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [UpperCaseTextFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'PAN Card No.',
                                  prefixIcon: Icon(Icons.credit_card),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _licCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [UpperCaseTextFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'License No.',
                                  prefixIcon: Icon(
                                    Icons.verified_user_outlined,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _emailCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Gmail Address',
                                  prefixIcon: Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Custom WhatsApp Message Template (व्हाट्सएप टेम्पलेट)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tags: {appName}, {partyName}, {roleText}, {dateStr}, {jins}, {bags}, {rate}, {oppParty}, {brokerFirmName}, {brokerMobile}',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _whatsappTemplateCtrl,
                          maxLines: 7,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp Template Content',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Security & Password (सुरक्षा प्रबंधन)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Change password via Gmail OTP (updates Firebase) or request via WhatsApp.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black54,
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _openChangePasswordDialog,
                              icon: const Icon(Icons.lock_reset, size: 18),
                              label: const Text(
                                'CHANGE PASSWORD (GMAIL OTP)',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF25D366),
                                side: const BorderSide(
                                  color: Color(0xFF25D366),
                                  width: 1.4,
                                ),
                              ),
                              onPressed: _requestPasswordResetViaWhatsApp,
                              icon: const Icon(Icons.chat, size: 18),
                              label: const Text(
                                'WHATSAPP PASSWORD RESET',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Default Brokerage Rates (डिफ़ॉल्ट दलाली)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Pre-fills on the New Sauda screen.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black54,
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _bDalaliCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Buyer Dalali (₹/Bag)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _sDalaliCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Seller Dalali (₹/Bag)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Commodity Master (जिंस सूची)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newJinsCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [UpperCaseTextFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'Add New Commodity',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                final val =
                                    _newJinsCtrl.text.trim().toUpperCase();
                                if (val.isNotEmpty &&
                                    !_jinsList.contains(val)) {
                                  setState(() {
                                    _jinsList.add(val);
                                    _newJinsCtrl.clear();
                                  });
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('ADD'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: _jinsList.map((jins) {
                            return Chip(
                              label: Text(
                                jins,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: const Color(0xFF0F766E)
                                  .withValues(alpha: 0.1),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () =>
                                  setState(() => _jinsList.remove(jins)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bank Account for Invoices (बैंक खाता)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bankCtrl,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Bank Name',
                            prefixIcon: Icon(Icons.account_balance),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _accCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Account Number',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _ifscCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: [UpperCaseTextFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'IFSC Code',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Terms & Conditions (नियम एवं शर्तें)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _termsCtrl,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Invoice Terms & Conditions',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _trySaveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(
                    'SAVE ALL SETTINGS',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout, color: Colors.red),
                  label: const Text(
                    'LOG OUT OF BROKER SECTION',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _confirmDeleteBrokerAccount,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text(
                    'DELETE BROKER ACCOUNT PERMANENTLY',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// HELPER DIALOGS (EDIT / DELETE SAUDA)
// -------------------------------------------------------------
void showEditSaudaDialog(
  BuildContext context,
  MandiSaudaModel sauda,
  Function(MandiSaudaModel) onSaudaEdited,
) {
  final bagsCtrl = TextEditingController(text: sauda.bags.toString());
  final rateCtrl = TextEditingController(text: sauda.rate.toString());
  final jinsCtrl = TextEditingController(text: sauda.jins);
  final buyerDalaliCtrl = TextEditingController(
    text: sauda.buyerDalaliPerBag.toString(),
  );
  final sellerDalaliCtrl = TextEditingController(
    text: sauda.sellerDalaliPerBag.toString(),
  );
  DateTime selectedDate = sauda.date;
  final now = DateTime.now();

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text(
          'Edit Sauda Details',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            selectedDate.isAfter(now) ? now : selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: now,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: const Text('Change Date'),
                  ),
                ],
              ),
              const Divider(),
              TextField(
                controller: jinsCtrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Jins / Commodity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bagsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Bags / Weight (बोरी)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: rateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Rate (भाव)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: buyerDalaliCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Buyer Dalali (₹/Bag)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: sellerDalaliCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Seller Dalali (₹/Bag)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
              int bags = int.tryParse(bagsCtrl.text) ?? 0;
              double rate = double.tryParse(rateCtrl.text) ?? 0.0;

              if (bags <= 0 || rate <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter valid bags/weight and rate'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final updated = MandiSaudaModel(
                id: sauda.id,
                date: selectedDate,
                buyer: sauda.buyer,
                buyerMobile: sauda.buyerMobile,
                seller: sauda.seller,
                sellerMobile: sauda.sellerMobile,
                jins: jinsCtrl.text.trim().toUpperCase(),
                bags: bags,
                rate: rate,
                buyerDalaliPerBag: double.tryParse(buyerDalaliCtrl.text) ?? 0.0,
                sellerDalaliPerBag:
                    double.tryParse(sellerDalaliCtrl.text) ?? 0.0,
                buyerConfirmed: sauda.buyerConfirmed,
                sellerConfirmed: sauda.sellerConfirmed,
                brokerFirmName: sauda.brokerFirmName,
                brokerMobile: sauda.brokerMobile,
                cancelRequested: sauda.cancelRequested,
                cancelRequestedBy: sauda.cancelRequestedBy,
                cancellationReason: sauda.cancellationReason,
              );

              onSaudaEdited(updated);
              Navigator.pop(ctx);
            },
            child: const Text('SAVE CHANGES'),
          ),
        ],
      ),
    ),
  );
}

void showDeleteSaudaDialog(
  BuildContext context,
  String id,
  Function(String) onSaudaDeleted,
) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Sauda?'),
      content: const Text(
        'Are you sure you want to delete this transaction from the ledger? Notifications will be sent to the Buyer and Seller.',
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
          onPressed: () {
            onSaudaDeleted(id);
            Navigator.pop(ctx);
          },
          child: const Text('DELETE'),
        ),
      ],
    ),
  );
}
