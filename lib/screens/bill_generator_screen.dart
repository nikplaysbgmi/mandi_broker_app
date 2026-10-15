import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/email_service.dart';
import '../services/mandi_services.dart';
import 'main_dashboard_screen.dart';

// =============================================================
// 1. ENGLISH TO HINDI TRANSLITERATOR
// =============================================================
class HindiPhoneticTransliteration {
  static final Map<String, String> _vowels = {
    'aa': 'ा',
    'ai': 'ै',
    'au': 'ौ',
    'ee': 'ी',
    'oo': 'ू',
    'a': '',
    'i': 'ि',
    'u': 'ु',
    'e': 'े',
    'o': 'ो',
  };

  static final Map<String, String> _initialVowels = {
    'aa': 'आ',
    'ai': 'ऐ',
    'au': 'औ',
    'ee': 'ई',
    'oo': 'ऊ',
    'a': 'अ',
    'i': 'इ',
    'u': 'उ',
    'e': 'ए',
    'o': 'ओ',
  };

  static final Map<String, String> _consonants = {
    'kh': 'ख',
    'gh': 'घ',
    'ch': 'च',
    'chh': 'छ',
    'jh': 'झ',
    'th': 'थ',
    'dh': 'ध',
    'ph': 'फ',
    'bh': 'भ',
    'sh': 'श',
    'shh': 'ष',
    'k': 'क',
    'g': 'ग',
    'j': 'ज',
    't': 'त',
    'd': 'द',
    'n': 'न',
    'p': 'प',
    'b': 'ब',
    'm': 'म',
    'y': 'य',
    'r': 'र',
    'l': 'ल',
    'v': 'व',
    'w': 'व',
    's': 'स',
    'h': 'ह',
  };

  static final Map<String, String> _commonMandiVocabulary = {
    'ramesh': 'रमेश',
    'suresh': 'सुरेश',
    'mahesh': 'महेश',
    'dinesh': 'दिनेश',
    'mukesh': 'मुकेश',
    'om': 'ओम',
    'prakash': 'प्रकाश',
    'kailash': 'कैलाश',
    'mohan': 'मोहन',
    'sohan': 'सोहन',
    'radheshyam': 'राधेश्याम',
    'shyam': 'श्याम',
    'ram': 'राम',
    'kishan': 'किशन',
    'shrawan': 'श्रवण',
    'bhanwar': 'भंवर',
    'karan': 'करण',
    'arjun': 'अर्जुन',
    'prem': 'प्रेम',
    'sita': 'सीता',
    'gita': 'गीता',
    'lalit': 'ललित',
    'anil': 'अनिल',
    'sunil': 'सुनील',
    'vikram': 'विक्रम',
    'pappu': 'पप्पू',
    'vijay': 'विजय',
    'santosh': 'संतोष',
    'bharat': 'भरत',
    'devendra': 'देवेन्द्र',
    'manoj': 'मनोज',
    'ravindra': 'रवीन्द्र',
    'rajendra': 'राजेन्द्र',
    'nirmal': 'निर्मल',
    'kumar': 'कुमार',
    'singh': 'सिंह',
    'lal': 'लाल',
    'patel': 'पटेल',
    'choudhary': 'चौधरी',
    'jat': 'जाट',
    'jeera': 'जीरा',
    'chana': 'चना',
    'moong': 'मूंग',
    'moth': 'मोठ',
    'rayda': 'रायड़ा',
    'isabgol': 'ईसबगोल',
    'bajra': 'बाजरा',
    'til': 'तिल',
    'taramira': 'तारामीरा',
    'saunf': 'सौंफ',
    'kapas': 'कपास',
    'gehun': 'गेहूं',
    'sarson': 'सरसों',
    'methi': 'मेथी',
    'dhaniya': 'धनिया',
    'suwa': 'सुवा',
    'arandi': 'अरंडी',
    'guar': 'ग्वार',
    'majuri': 'मजदूरी',
    'hamali': 'हम्माली',
    'tola': 'तौला',
    'kanta': 'कांटा खर्च',
    'tulayi': 'तुलाई',
    'palledari': 'पल्लेदारी',
    'chanayi': 'छनाई',
    'safai': 'सफाई खर्च',
    'grading': 'ग्रेडिंग',
    'cess': 'मंडी सेस',
    'bhada': 'भाड़ा',
    'loading': 'भरती / लोडिंग',
  };

  static String convert(String englishText) {
    if (englishText.trim().isEmpty) return '';

    final words = englishText.trim().toLowerCase().split(RegExp(r'\s+'));
    final List<String> resultWords = [];

    for (final word in words) {
      if (_commonMandiVocabulary.containsKey(word)) {
        resultWords.add(_commonMandiVocabulary[word]!);
        continue;
      }

      String buffer = '';
      int i = 0;
      while (i < word.length) {
        if (i + 3 <= word.length &&
            _consonants.containsKey(word.substring(i, i + 3))) {
          buffer += _consonants[word.substring(i, i + 3)]!;
          i += 3;
        } else if (i + 2 <= word.length &&
            _consonants.containsKey(word.substring(i, i + 2))) {
          buffer += _consonants[word.substring(i, i + 2)]!;
          i += 2;
        } else if (i + 2 <= word.length &&
            (i == 0 ? _initialVowels : _vowels)
                .containsKey(word.substring(i, i + 2))) {
          buffer +=
              (i == 0 ? _initialVowels : _vowels)[word.substring(i, i + 2)]!;
          i += 2;
        } else if (_consonants.containsKey(word[i])) {
          buffer += _consonants[word[i]]!;
          i++;
        } else if ((i == 0 ? _initialVowels : _vowels).containsKey(word[i])) {
          buffer += (i == 0 ? _initialVowels : _vowels)[word[i]]!;
          i++;
        } else {
          buffer += word[i];
          i++;
        }
      }
      resultWords.add(buffer);
    }

    return resultWords.join(' ');
  }
}

// =============================================================
// 2. COMMODITY LOT DATA MODEL
// =============================================================
class KisanCommodityLot {
  final TextEditingController commodityEnglishCtrl;
  final TextEditingController commodityHindiCtrl;
  final TextEditingController totalBagsCtrl;
  final TextEditingController fullBagsCtrl;
  final TextEditingController bagWeightCtrl;
  final TextEditingController looseWeightCtrl;
  final TextEditingController rateCtrl;

  KisanCommodityLot({
    String commodityEnglish = 'JEERA',
    String commodityHindi = 'जीरा',
    String totalBags = '0',
    String fullBags = '0',
    String bagWeight = '0',
    String looseWeight = '0',
    String rate = '0',
  })  : commodityEnglishCtrl = TextEditingController(text: commodityEnglish),
        commodityHindiCtrl = TextEditingController(text: commodityHindi),
        totalBagsCtrl = TextEditingController(text: totalBags),
        fullBagsCtrl = TextEditingController(text: fullBags),
        bagWeightCtrl = TextEditingController(text: bagWeight),
        looseWeightCtrl = TextEditingController(text: looseWeight),
        rateCtrl = TextEditingController(text: rate);

  void dispose() {
    commodityEnglishCtrl.dispose();
    commodityHindiCtrl.dispose();
    totalBagsCtrl.dispose();
    fullBagsCtrl.dispose();
    bagWeightCtrl.dispose();
    looseWeightCtrl.dispose();
    rateCtrl.dispose();
  }

  int get totalBags => int.tryParse(totalBagsCtrl.text.trim()) ?? 0;
  int get fullBags => int.tryParse(fullBagsCtrl.text.trim()) ?? 0;
  double get bagWeight => double.tryParse(bagWeightCtrl.text.trim()) ?? 0.0;
  double get looseWeight => double.tryParse(looseWeightCtrl.text.trim()) ?? 0.0;
  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0.0;

  double get totalKg => (fullBags * bagWeight) + looseWeight;
  double get totalQuintal => totalKg / 100.0;
  double get grossAmount => totalQuintal * rate;

  String _formatNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toStringAsFixed(0);
    }
    return val.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  String get formulaDisplay {
    final bagWtStr = _formatNumber(bagWeight);
    final looseStr = _formatNumber(looseWeight);
    final totalKgStr = _formatNumber(totalKg);
    return '$fullBags X $bagWtStr + $looseStr = $totalKgStr';
  }

  String get displayName => commodityHindiCtrl.text.trim().isNotEmpty
      ? commodityHindiCtrl.text.trim()
      : commodityEnglishCtrl.text.trim().toUpperCase();

  Map<String, dynamic> toMap() => {
        'commodityEnglish': commodityEnglishCtrl.text.trim().toUpperCase(),
        'commodityHindi': commodityHindiCtrl.text.trim(),
        'commodity': displayName,
        'totalBags': totalBags,
        'fullBags': fullBags,
        'bagWeight': bagWeight,
        'looseWeight': looseWeight,
        'rate': rate,
        'totalKg': totalKg,
        'grossAmount': grossAmount,
        'formula': formulaDisplay,
      };
}

// =============================================================
// 3. MAIN PORTAL WITH CLOUD & SUBSCRIPTION LOCK GATE
// =============================================================
class BillGeneratorSectionPortal extends StatefulWidget {
  final String username;

  const BillGeneratorSectionPortal({super.key, required this.username});

  @override
  State<BillGeneratorSectionPortal> createState() =>
      _BillGeneratorSectionPortalState();
}

class _BillGeneratorSectionPortalState
    extends State<BillGeneratorSectionPortal> {
  bool _isAuthenticated = false;
  bool _isChecking = true;
  bool _noInternet = false;
  bool _subscriptionLocked = false;
  bool _adminMasterLocked = false;

  final TextEditingController _keyController = TextEditingController();
  static const String _defaultBillingKey = '2850';
  static const String adminSupportPhone = '+919983325558';

  late String _currentUsername;

  @override
  void initState() {
    super.initState();
    _currentUsername = widget.username;
    _runCloudSecurityCheck();
  }

  Future<void> _runCloudSecurityCheck() async {
    setState(() {
      _isChecking = true;
      _noInternet = false;
      _subscriptionLocked = false;
      _adminMasterLocked = false;
    });

    final bool isOnline = await CloudSyncService.hasActiveInternet();
    if (!isOnline) {
      if (mounted) {
        setState(() {
          _isChecking = false;
          _noInternet = true;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('service_switches')
          .doc('config')
          .get(const GetOptions(source: Source.server));
      final data = doc.data() ?? {};
      if (data['bill_generator'] == false) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _adminMasterLocked = true;
          });
        }
        return;
      }
    } catch (_) {}

    final savedMobile = StorageService.get('session_BILL GENERATOR_mobile') ??
        StorageService.get('session_BILL GENERATOR') ??
        '';

    if (savedMobile.toString().isNotEmpty) {
      final bool isLocked = await CloudSyncService.isUserSubscriptionLocked(
          savedMobile.toString());
      if (isLocked) {
        if (mounted) {
          setState(() {
            _isChecking = false;
            _subscriptionLocked = true;
          });
        }
        return;
      }
    }

    final activeKeySession =
        StorageService.get('session_BILL_GENERATOR_UNLOCKED');
    if (mounted) {
      setState(() {
        _isChecking = false;
        if (activeKeySession == 'true') {
          _isAuthenticated = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _verifyKeyAndEnter() async {
    final bool isOnline = await CloudSyncService.hasActiveInternet();
    if (!isOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Internet connection lost! Please connect to internet.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _noInternet = true);
      return;
    }

    final enteredKey = _keyController.text.trim();
    final savedPin =
        StorageService.get('billing_security_pin') ?? _defaultBillingKey;
    final activeAcc = AccountService.getSessionUser('BILL GENERATOR');
    final accPassword = activeAcc?.password.trim() ?? '';

    if (enteredKey == savedPin ||
        enteredKey == _defaultBillingKey ||
        (accPassword.isNotEmpty && enteredKey == accPassword)) {
      StorageService.save('session_BILL_GENERATOR_UNLOCKED', 'true');
      setState(() => _isAuthenticated = true);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid Security PIN! Please enter your billing key.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _requestKeyResetViaWhatsApp() async {
    String cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final savedMobile = StorageService.get('session_BILL GENERATOR_mobile') ??
        StorageService.get('session_BILL GENERATOR') ??
        '';

    final message = savedMobile.toString().isNotEmpty
        ? 'नमस्ते Mandi Support Team, मैं Bill Generator ऑपरेटर ($_currentUsername) हूँ। मेरा पंजीकृत मोबाइल $savedMobile है। मैं अपना बिलिंग सिक्योरिटी PIN भूल गया हूँ, कृपया रीसेट करने में सहायता करें।'
        : 'नमस्ते Mandi Support Team, मैं Bill Generator ऑपरेटर ($_currentUsername) हूँ। मैं अपना बिलिंग सिक्योरिटी PIN भूल गया हूँ, कृपया रीसेट करने में सहायता करें।';

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

  void _logout() {
    StorageService.remove('session_BILL_GENERATOR_UNLOCKED');
    StorageService.remove('session_BILL GENERATOR');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MainDashboardScreen()),
      (route) => false,
    );
  }

  void _openProfileSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ProfileEditSettingsDialog(
        currentUsername: _currentUsername,
        onProfileUpdated: (newName) {
          setState(() {
            _currentUsername = newName;
          });
        },
        onAccountDeleted: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                builder: (context) => const MainDashboardScreen()),
            (route) => false,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1320),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFA855F7)),
              SizedBox(height: 16),
              Text(
                'Verifying cloud security and subscription status...',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_noInternet) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1320),
        appBar: AppBar(
          title: const Text('OFFLINE LOCK'),
          backgroundColor: const Color(0xFF16253B),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 54, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'INTERNET CONNECTION REQUIRED',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bill Generator cannot be used offline. Please connect to internet to verify real-time server permissions and subscription.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA855F7),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _runCloudSecurityCheck,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY CONNECTION'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_subscriptionLocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1320),
        appBar: AppBar(
          title: const Text('SUBSCRIPTION DUE'),
          backgroundColor: const Color(0xFF16253B),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_rounded,
                    size: 54, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'SUBSCRIPTION OVERDUE',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Access for operator "$_currentUsername" is locked because subscription payment is due. Please contact Mandi Admin to renew access.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('BACK TO DASHBOARD'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_adminMasterLocked) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1320),
        appBar: AppBar(
          title: const Text('SERVICE LOCKED'),
          backgroundColor: const Color(0xFF16253B),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_rounded,
                    size: 54, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'BILL GENERATOR DISABLED BY ADMIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This service has been temporarily disabled through the Firebase Admin console.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('BACK TO DASHBOARD'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isAuthenticated) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1320),
        appBar: AppBar(
          title: const Text('BILL GENERATOR SECURITY ACCESS'),
          backgroundColor: const Color(0xFF16253B),
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor:
                        const Color(0xFFA855F7).withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.key_rounded,
                      size: 34,
                      color: Color(0xFFA855F7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'BILLING DESK VERIFICATION',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Operator: $_currentUsername',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: const InputDecoration(
                      labelText: 'Enter Billing Security PIN / Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  // =====================================================
                  // WHATSAPP PIN RESET ACTION
                  // =====================================================
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _requestKeyResetViaWhatsApp,
                      icon: const Icon(Icons.chat,
                          size: 14, color: Color(0xFF25D366)),
                      label: const Text(
                        'पासवर्ड / PIN भूल गए? (WhatsApp रीसेट)',
                        style: TextStyle(
                          color: Color(0xFF25D366),
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA855F7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _verifyKeyAndEnter,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'UNLOCK BILLING DESK',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (context) => const MainDashboardScreen()),
                (route) => false,
              );
            },
          ),
          title: Text(
            'BILL GENERATOR (${_currentUsername.toUpperCase()})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: const Color(0xFFA855F7),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.manage_accounts_rounded),
              tooltip: 'Profile & Retention Settings',
              onPressed: _openProfileSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Lock & Logout',
              onPressed: _logout,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            indicatorWeight: 3.5,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: 'Farmer Bill (Parcha)'),
              Tab(icon: Icon(Icons.calculate), text: 'Majuri & Deductions'),
              Tab(icon: Icon(Icons.history_toggle_off), text: 'Local Archive'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            KisanBillGeneratorTab(),
            MajuriCalculatorTab(),
            ParchaHistoryArchiveTab(),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 4. PROFILE EDIT, RETENTION DAYS & ACCOUNT DELETION DIALOG
// =============================================================
class ProfileEditSettingsDialog extends StatefulWidget {
  final String currentUsername;
  final ValueChanged<String> onProfileUpdated;
  final VoidCallback onAccountDeleted;

  const ProfileEditSettingsDialog({
    super.key,
    required this.currentUsername,
    required this.onProfileUpdated,
    required this.onAccountDeleted,
  });

  @override
  State<ProfileEditSettingsDialog> createState() =>
      _ProfileEditSettingsDialogState();
}

class _ProfileEditSettingsDialogState extends State<ProfileEditSettingsDialog> {
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  int _retentionDays = 3;
  bool _obscurePin = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.currentUsername;
    _mobileCtrl.text = StorageService.get('session_BILL GENERATOR_mobile') ??
        StorageService.get('session_BILL GENERATOR') ??
        '';
    _emailCtrl.text = StorageService.get('session_BILL GENERATOR_email') ?? '';
    _pinCtrl.text = StorageService.get('billing_security_pin') ?? '2850';

    final savedDays = StorageService.get('local_retention_days');
    if (savedDays != null) {
      _retentionDays = int.tryParse(savedDays) ?? 3;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    final mobile = _mobileCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final pin = _pinCtrl.text.trim().isNotEmpty ? _pinCtrl.text.trim() : '2850';

    if (name.isEmpty || mobile.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid Name and 10-digit Mobile number!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final oldMobile = StorageService.get('session_BILL GENERATOR_mobile') ??
        StorageService.get('session_BILL GENERATOR') ??
        mobile;
    final oldEmail =
        StorageService.get('session_BILL GENERATOR_email') ?? email;

    StorageService.save('session_BILL GENERATOR_name', name);
    StorageService.save('session_BILL GENERATOR_mobile', mobile);
    StorageService.save('session_BILL GENERATOR', mobile);
    StorageService.save('session_BILL GENERATOR_email', email);
    StorageService.save('billing_security_pin', pin);
    StorageService.save('local_retention_days', _retentionDays.toString());

    // Update local AccountService
    final address = StorageService.get('session_BILL GENERATOR_address') ??
        'MANDI BILLING DESK';
    final updatedAccount = UserAccount(
      name: name,
      mobile: mobile,
      email: email,
      address: address.toString(),
      password: pin,
      section: 'BILL GENERATOR',
    );
    AccountService.updateAccountWithOldCredentials(
      oldMobile: oldMobile.toString(),
      oldEmail: oldEmail.toString(),
      updatedAccount: updatedAccount,
    );

    // Sync updated profile and PIN/password to Firebase Firestore
    try {
      await CloudSyncService.ensureAuthSession();
      await CloudSyncService.saveAccount(updatedAccount.toJson());

      final firestore = FirebaseFirestore.instance;
      await firestore.collection('accounts').doc(mobile).set({
        'name': name,
        'mobile': mobile,
        'email': email,
        'password': pin,
        'section': 'BILL GENERATOR',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase sync warning in Bill Generator profile: $e');
    }

    _purgeOldLocalParchas(_retentionDays);

    if (!mounted) return;
    setState(() => _isSaving = false);

    widget.onProfileUpdated(name);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Profile & PIN synced to Firebase! Retention set to $_retentionDays days.'),
        backgroundColor: const Color(0xFF0F766E),
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text(
              'Delete Account Permanently?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'This action is irreversible. All local bills, credentials, and settings will be permanently erased from this device.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmCtx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final mob = _mobileCtrl.text.trim();
              Navigator.pop(confirmCtx);
              Navigator.pop(context);

              if (mob.isNotEmpty) {
                try {
                  await CloudSyncService.purgeUserAccount(mob,
                      section: 'BILL GENERATOR');
                } catch (_) {}
                AccountService.removeAccount(
                    mobile: mob, section: 'BILL GENERATOR');
              }

              StorageService.remove('local_parcha_archive_3days');
              StorageService.remove('local_retention_days');
              StorageService.remove('session_BILL_GENERATOR_UNLOCKED');
              StorageService.remove('session_BILL GENERATOR');
              StorageService.remove('session_BILL GENERATOR_name');
              StorageService.remove('session_BILL GENERATOR_mobile');
              StorageService.remove('session_BILL GENERATOR_email');
              StorageService.remove('billing_security_pin');

              widget.onAccountDeleted();
            },
            child: const Text('YES, DELETE PERMANENTLY',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void _purgeOldLocalParchas(int days) {
    final rawList = StorageService.get('local_parcha_archive_3days');
    if (rawList == null) return;
    try {
      final List<dynamic> decoded = jsonDecode(rawList);
      final cutoffDate = DateTime.now().subtract(Duration(days: days));

      final active = decoded.where((item) {
        if (item is Map<String, dynamic> && item['savedAt'] != null) {
          final savedDate = DateTime.tryParse(item['savedAt'].toString());
          if (savedDate != null) return savedDate.isAfter(cutoffDate);
        }
        return false;
      }).toList();

      StorageService.save('local_parcha_archive_3days', jsonEncode(active));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.manage_accounts, color: Color(0xFFA855F7)),
          SizedBox(width: 8),
          Text(
            'Profile & Storage Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Operator / Firm Name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mobileCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Mobile Number (Login ID)',
                prefixIcon: Icon(Icons.phone_android),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address (Gmail / Brevo)',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtrl,
              obscureText: _obscurePin,
              keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: 'Billing Security PIN / Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePin ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFA855F7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFA855F7).withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_delete_outlined,
                          size: 18, color: Color(0xFFA855F7)),
                      SizedBox(width: 6),
                      Text(
                        'Keep Saved Bills In Storage For:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _retentionDays,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 1, child: Text('1 Day (24 Hours)')),
                      DropdownMenuItem(
                          value: 3, child: Text('3 Days (Recommended)')),
                      DropdownMenuItem(
                          value: 7, child: Text('7 Days (1 Week)')),
                      DropdownMenuItem(value: 15, child: Text('15 Days')),
                      DropdownMenuItem(
                          value: 30, child: Text('30 Days (1 Month)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _retentionDays = val);
                    },
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Older bills will be automatically cleared to keep app storage fast and clean.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _confirmDeleteAccount,
              icon: const Icon(Icons.delete_forever),
              label: const Text(
                'DELETE ACCOUNT PERMANENTLY',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFA855F7),
            foregroundColor: Colors.white,
          ),
          onPressed: _isSaving ? null : _saveProfile,
          child: Text(_isSaving ? 'SAVING...' : 'SAVE CHANGES'),
        ),
      ],
    );
  }
}

// =============================================================
// 5. TAB 1: KISAN BILL GENERATOR (WITH WHATSAPP & BREVO EMAIL)
// =============================================================
class KisanBillGeneratorTab extends StatefulWidget {
  const KisanBillGeneratorTab({super.key});

  @override
  State<KisanBillGeneratorTab> createState() => _KisanBillGeneratorTabState();
}

class _KisanBillGeneratorTabState extends State<KisanBillGeneratorTab> {
  DateTime _billDate = DateTime.now();

  final _nameEnglishCtrl = TextEditingController();
  final _nameHindiCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  final List<KisanCommodityLot> _lots = [KisanCommodityLot()];

  final _majuriRateCtrl = TextEditingController(text: '0');
  final _kantaChargeCtrl = TextEditingController(text: '0');
  final _cleanChargeCtrl = TextEditingController(text: '0');
  final _cessChargeCtrl = TextEditingController(text: '0');

  int _totalAllBags = 0;
  double _totalAllWeightKg = 0.0;
  double _totalAllWeightQuintal = 0.0;
  double _grossAllCropAmount = 0.0;
  double _totalMajuri = 0.0;
  double _kantaCharge = 0.0;
  double _cleanCharge = 0.0;
  double _cessCharge = 0.0;
  double _totalOtherDeductions = 0.0;
  double _grandTotal = 0.0;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _recalculateTotals();
  }

  @override
  void dispose() {
    _nameEnglishCtrl.dispose();
    _nameHindiCtrl.dispose();
    _mobileCtrl.dispose();
    for (var lot in _lots) {
      lot.dispose();
    }
    _majuriRateCtrl.dispose();
    _kantaChargeCtrl.dispose();
    _cleanChargeCtrl.dispose();
    _cessChargeCtrl.dispose();
    super.dispose();
  }

  void _recalculateTotals() {
    int bagsSum = 0;
    double kgSum = 0.0;
    double grossSum = 0.0;

    for (var lot in _lots) {
      bagsSum += lot.totalBags;
      kgSum += lot.totalKg;
      grossSum += lot.grossAmount;
    }

    final double perBagMajuri =
        double.tryParse(_majuriRateCtrl.text.trim()) ?? 0.0;
    final double kanta = double.tryParse(_kantaChargeCtrl.text.trim()) ?? 0.0;
    final double clean = double.tryParse(_cleanChargeCtrl.text.trim()) ?? 0.0;
    final double cess = double.tryParse(_cessChargeCtrl.text.trim()) ?? 0.0;

    final double majuri = bagsSum * perBagMajuri;
    final double otherDeductions = kanta + clean + cess;
    double netPayable = grossSum - majuri - otherDeductions;
    if (netPayable < 0) netPayable = 0.0;

    setState(() {
      _totalAllBags = bagsSum;
      _totalAllWeightKg = kgSum;
      _totalAllWeightQuintal = kgSum / 100.0;
      _grossAllCropAmount = grossSum;
      _totalMajuri = majuri;
      _kantaCharge = kanta;
      _cleanCharge = clean;
      _cessCharge = cess;
      _totalOtherDeductions = otherDeductions;
      _grandTotal = netPayable;
    });
  }

  void _addNewLot() {
    setState(() {
      _lots.add(KisanCommodityLot(
        commodityEnglish: '',
        commodityHindi: '',
        totalBags: '0',
        fullBags: '0',
        bagWeight: '0',
        looseWeight: '0',
        rate: '0',
      ));
    });
    _recalculateTotals();
  }

  void _removeLot(int index) {
    if (_lots.length <= 1) return;
    setState(() {
      final removed = _lots.removeAt(index);
      removed.dispose();
    });
    _recalculateTotals();
  }

  void _clearForm() {
    for (var lot in _lots) {
      lot.dispose();
    }
    _lots.clear();
    _lots.add(KisanCommodityLot(
      commodityEnglish: 'JEERA',
      commodityHindi: 'जीरा',
      totalBags: '0',
      fullBags: '0',
      bagWeight: '0',
      looseWeight: '0',
      rate: '0',
    ));

    setState(() {
      _billDate = DateTime.now();
      _nameEnglishCtrl.clear();
      _nameHindiCtrl.clear();
      _mobileCtrl.clear();
      _majuriRateCtrl.text = '0';
      _kantaChargeCtrl.text = '0';
      _cleanChargeCtrl.text = '0';
      _cessChargeCtrl.text = '0';
    });
    _recalculateTotals();
  }

  bool _saveParchaToLocalStorage() {
    final displayName = _nameHindiCtrl.text.trim().isNotEmpty
        ? _nameHindiCtrl.text.trim()
        : _nameEnglishCtrl.text.trim().toUpperCase();

    if (displayName.isEmpty || _grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please enter Farmer Name and calculate a valid bill before saving!'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    try {
      final now = DateTime.now();
      final docId = now.millisecondsSinceEpoch.toString();

      final newParcha = {
        'id': docId,
        'date': _billDate.toIso8601String(),
        'savedAt': now.toIso8601String(),
        'farmerName': displayName,
        'mobile': _mobileCtrl.text.trim(),
        'lots': _lots.map((l) => l.toMap()).toList(),
        'totalBags': _totalAllBags,
        'totalWeightKg': _totalAllWeightKg,
        'totalWeightQuintal': _totalAllWeightQuintal,
        'totalGross': _grossAllCropAmount,
        'majuriDeduction': _totalMajuri,
        'otherDeductions': _totalOtherDeductions,
        'kantaCharge': _kantaCharge,
        'cleanCharge': _cleanCharge,
        'cessCharge': _cessCharge,
        'grandTotal': _grandTotal,
      };

      final savedDays = StorageService.get('local_retention_days');
      final int days = savedDays != null ? (int.tryParse(savedDays) ?? 3) : 3;

      final rawList = StorageService.get('local_parcha_archive_3days');
      List<dynamic> localList = rawList != null ? jsonDecode(rawList) : [];

      final cutoffDate = now.subtract(Duration(days: days));

      List<dynamic> activeList = localList.where((item) {
        if (item is Map<String, dynamic> && item['savedAt'] != null) {
          final savedDate = DateTime.tryParse(item['savedAt'].toString());
          if (savedDate != null) return savedDate.isAfter(cutoffDate);
        }
        return false;
      }).toList();

      activeList.insert(0, newParcha);
      StorageService.save('local_parcha_archive_3days', jsonEncode(activeList));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bill saved locally! (Retained for $days days)'),
          backgroundColor: const Color(0xFF0F766E),
          duration: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Local save error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to save locally: $e'),
            backgroundColor: Colors.red),
      );
      return false;
    }
  }

  void _listenVoiceParcha() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
      );

      if (available) {
        setState(() => _isListening = true);
        // ignore: deprecated_member_use
        _speech.listen(
          // ignore: deprecated_member_use
          localeId: 'en_IN',
          onResult: (val) {
            final recognized = val.recognizedWords;
            _parseSpokenMandiText(recognized);
          },
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Microphone not available or permission denied.')),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _parseSpokenMandiText(String text) {
    final numbers = RegExp(r'\d+(\.\d+)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(0)!) ?? 0.0)
        .toList();

    if (numbers.length >= 5) {
      setState(() {
        _lots[0].totalBagsCtrl.text = numbers[0].toInt().toString();
        _lots[0].rateCtrl.text = numbers[1].toString();
        _lots[0].fullBagsCtrl.text = numbers[2].toInt().toString();
        _lots[0].bagWeightCtrl.text = numbers[3].toString();
        _lots[0].looseWeightCtrl.text = numbers[4].toString();
      });
      _recalculateTotals();
    } else if (text.toLowerCase().contains('jeera')) {
      _lots[0].commodityEnglishCtrl.text = 'JEERA';
      _lots[0].commodityHindiCtrl.text = 'जीरा';
    } else if (text.toLowerCase().contains('chana')) {
      _lots[0].commodityEnglishCtrl.text = 'CHANA';
      _lots[0].commodityHindiCtrl.text = 'चना';
    }
  }

  void _openDhadaWeighmentSheet(KisanCommodityLot lot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DhadaWeighmentSheetModal(
        commodityName: lot.displayName,
        onApplyFormula:
            (int fullBags, double bagWeight, double looseKg, int totalBags) {
          setState(() {
            lot.totalBagsCtrl.text = totalBags.toString();
            lot.fullBagsCtrl.text = fullBags.toString();
            lot.bagWeightCtrl.text = bagWeight.toStringAsFixed(0);
            lot.looseWeightCtrl.text =
                looseKg.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
          });
          _recalculateTotals();
        },
      ),
    );
  }

  // ===========================================================
  // EMAIL BILL DISPATCH (POWERED BY BREVO API)
  // ===========================================================
  Future<void> _sendBillViaEmailDialog() async {
    final farmer = _nameHindiCtrl.text.trim().isNotEmpty
        ? _nameHindiCtrl.text.trim()
        : _nameEnglishCtrl.text.trim().toUpperCase();

    if (farmer.isEmpty || _grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('कृपया पहले किसान का नाम भरें और बिल राशि की गणना करें!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.email_outlined, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text(
              'ईमेल पर बिल भेजें (Brevo)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'किसान/व्यापारी "$farmer" के लिए ईमेल पता दर्ज करें:',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'प्राप्तकर्ता का ईमेल (Recipient Email)',
                prefixIcon: Icon(Icons.alternate_email),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('रद्द करें'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final targetEmail = emailController.text.trim();
              if (targetEmail.isEmpty || !targetEmail.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('कृपया एक वैध ईमेल पता दर्ज करें!'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(dlgCtx);
              _saveParchaToLocalStorage();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Brevo से ईमेल भेजा जा रहा है...'),
                  duration: Duration(seconds: 2),
                ),
              );

              final StringBuffer lotsHtml = StringBuffer();
              for (var lot in _lots) {
                lotsHtml.writeln('''
                  <tr style="border-bottom: 1px solid #ddd;">
                    <td style="padding: 8px;">${lot.displayName} (${lot.totalBagsCtrl.text} Bags)</td>
                    <td style="padding: 8px;">₹${lot.rateCtrl.text}</td>
                    <td style="padding: 8px;">${lot.formulaDisplay} kg</td>
                    <td style="padding: 8px; font-weight: bold; text-align: right;">₹${lot.grossAmount.toStringAsFixed(0)}</td>
                  </tr>
                ''');
              }

              final htmlBill = '''
                <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 20px; border: 1px solid #ddd; border-radius: 8px;">
                  <h2 style="color: #0F766E; text-align: center; margin-bottom: 4px;">किसान मंडी पर्चा (MANDI BILL)</h2>
                  <p style="text-align: center; color: #666; margin-top: 0; font-size: 13px;">दिनांक: ${_billDate.day}/${_billDate.month}/${_billDate.year}</p>
                  <hr style="border: none; border-top: 1px solid #eee;" />
                  <p style="font-size: 15px;"><b>किसान / व्यापारी:</b> $farmer</p>
                  <p style="font-size: 14px;"><b>मोबाइल नंबर:</b> ${_mobileCtrl.text.trim().isNotEmpty ? _mobileCtrl.text.trim() : 'N/A'}</p>
                  
                  <table style="width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 14px;">
                    <thead>
                      <tr style="background: #f4f4f4; text-align: left;">
                        <th style="padding: 8px;">जिंस (Crop)</th>
                        <th style="padding: 8px;">भाव</th>
                        <th style="padding: 8px;">वजन सूत्र</th>
                        <th style="padding: 8px; text-align: right;">सकल रकम</th>
                      </tr>
                    </thead>
                    <tbody>
                      $lotsHtml
                    </tbody>
                  </table>

                  <div style="margin-top: 15px; background: #fafafa; padding: 12px; border-radius: 6px; font-size: 14px;">
                    <div style="display: flex; justify-content: space-between; margin-bottom: 6px;">
                      <span>कुल सकल रकम:</span>
                      <b>₹${_grossAllCropAmount.toStringAsFixed(0)}</b>
                    </div>
                    <div style="display: flex; justify-content: space-between; margin-bottom: 6px; color: #d32f2f;">
                      <span>मजदूरी (कटौती - $_totalAllBags Bags):</span>
                      <b>- ₹${_totalMajuri.toStringAsFixed(0)}</b>
                    </div>
                    ${_kantaCharge > 0 ? '<div style="display: flex; justify-content: space-between; margin-bottom: 6px; color: #d32f2f;"><span>कांटा खर्च:</span><b>- ₹${_kantaCharge.toStringAsFixed(0)}</b></div>' : ''}
                    ${_cleanCharge > 0 ? '<div style="display: flex; justify-content: space-between; margin-bottom: 6px; color: #d32f2f;"><span>छनाई/सफाई खर्च:</span><b>- ₹${_cleanCharge.toStringAsFixed(0)}</b></div>' : ''}
                    ${_cessCharge > 0 ? '<div style="display: flex; justify-content: space-between; margin-bottom: 6px; color: #d32f2f;"><span>मंडी सेस/भाड़ा:</span><b>- ₹${_cessCharge.toStringAsFixed(0)}</b></div>' : ''}
                    <hr style="border: none; border-top: 1px dashed #ccc; margin: 10px 0;" />
                    <div style="display: flex; justify-content: space-between; font-size: 17px; color: #0F766E;">
                      <b>कुल शुद्ध देय (TOTAL PAYABLE):</b>
                      <b>₹${_grandTotal.toStringAsFixed(0)}</b>
                    </div>
                  </div>
                  <p style="text-align: center; color: #999; font-size: 12px; margin-top: 20px;">Kisan Mandi App द्वारा जनरेट किया गया डिजिटल बिल।</p>
                </div>
              ''';

              final bool success = await EmailService.sendBillEmail(
                recipientEmail: targetEmail,
                recipientName: farmer,
                subject:
                    'मंडी बिल रसीद - $farmer (${_billDate.day}/${_billDate.month}/${_billDate.year})',
                htmlContent: htmlBill,
              );

              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ बिल ईमेल सफलतापूर्वक भेज दिया गया!'),
                    backgroundColor: Color(0xFF0F766E),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '❌ ईमेल भेजने में विफलता! कृपया Brevo API जांचें।'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('भेजें (SEND)'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _generateDualLanguagePdfReceipt(
      PdfPageFormat format) async {
    final pdf = pw.Document();

    pw.Font hindiFont;
    pw.Font hindiFontBold;
    try {
      hindiFont = await PdfGoogleFonts.notoSansDevanagariRegular();
      hindiFontBold = await PdfGoogleFonts.notoSansDevanagariBold();
    } catch (_) {
      hindiFont = pw.Font.helvetica();
      hindiFontBold = pw.Font.helveticaBold();
    }

    final dateStr =
        '${_billDate.day.toString().padLeft(2, '0')}/${_billDate.month.toString().padLeft(2, '0')}/${_billDate.year}';
    final nameStr = _nameHindiCtrl.text.trim().isNotEmpty
        ? _nameHindiCtrl.text.trim()
        : (_nameEnglishCtrl.text.trim().isEmpty
            ? 'NAME'
            : _nameEnglishCtrl.text.trim().toUpperCase());
    final majuriStr = _totalMajuri.toStringAsFixed(0);
    final totalStr = _grandTotal.toStringAsFixed(0);

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: hindiFont, bold: hindiFontBold),
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(22),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text(
                    'DATE / दिनांक: $dateStr',
                    style: const pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'NAME / नाम: $nameStr',
                  style: const pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 18),
                ..._lots.map((lot) {
                  final cName = lot.displayName;
                  final bTotal = lot.totalBagsCtrl.text.trim();
                  final rBhav = lot.rateCtrl.text.trim();
                  final grossStr = lot.grossAmount.toStringAsFixed(0);

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 12),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.only(right: 12),
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  right: pw.BorderSide(
                                      color: PdfColors.black, width: 1.5),
                                ),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'AMOUNT / रकम',
                                    style: const pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Rs $grossStr',
                                    style: const pw.TextStyle(
                                        fontSize: 16,
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            pw.Expanded(
                              child: pw.Text(
                                '$cName BAG / बोरी $bTotal',
                                style: const pw.TextStyle(
                                    fontSize: 17,
                                    fontWeight: pw.FontWeight.bold),
                              ),
                            ),
                            pw.Text(
                              '< RATE: Rs $rBhav',
                              style: const pw.TextStyle(
                                  fontSize: 15, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 5),
                        pw.Center(
                          child: pw.Text(
                            lot.formulaDisplay,
                            style: const pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                pw.Divider(thickness: 1.3, color: PdfColors.black),
                pw.SizedBox(height: 8),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.only(right: 12),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          right: pw.BorderSide(
                            color: PdfColors.black,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'AMOUNT / रकम',
                            style: const pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '- $majuriStr',
                            style: const pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Text(
                        'MAJURI / मजदूरी ($_totalAllBags Bags @ Rs ${_majuriRateCtrl.text.trim()})',
                        style: const pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (_kantaCharge > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.only(right: 12),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              right: pw.BorderSide(
                                  color: PdfColors.black, width: 1.5)),
                        ),
                        child: pw.Text(
                          '- ${_kantaCharge.toStringAsFixed(0)}',
                          style: const pw.TextStyle(
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(
                        'WEIGHBRIDGE / कांटा खर्च',
                        style: const pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                if (_cleanCharge > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.only(right: 12),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              right: pw.BorderSide(
                                  color: PdfColors.black, width: 1.5)),
                        ),
                        child: pw.Text(
                          '- ${_cleanCharge.toStringAsFixed(0)}',
                          style: const pw.TextStyle(
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(
                        'CLEANING / छनाई व सफाई खर्च',
                        style: const pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                if (_cessCharge > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.only(right: 12),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              right: pw.BorderSide(
                                  color: PdfColors.black, width: 1.5)),
                        ),
                        child: pw.Text(
                          '- ${_cessCharge.toStringAsFixed(0)}',
                          style: const pw.TextStyle(
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.red900),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Text(
                        'MANDI CESS / मंडी सेस व भाड़ा',
                        style: const pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 14),
                pw.Divider(thickness: 1.5, color: PdfColors.black),
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColors.black, width: 2)),
                        ),
                        child: pw.Text(
                          'TOTAL / कुल शुद्ध रकम',
                          style: const pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 2),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Rs $totalStr',
                        style: const pw.TextStyle(
                            fontSize: 26, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  void _openPrintPreview() {
    final hasName = _nameHindiCtrl.text.trim().isNotEmpty ||
        _nameEnglishCtrl.text.trim().isNotEmpty;
    if (!hasName || _grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please enter Farmer Name and calculate a valid bill before printing!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _saveParchaToLocalStorage();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Farmer Bill Print Slip'),
            backgroundColor: const Color(0xFFA855F7),
            foregroundColor: Colors.white,
          ),
          body: PdfPreview(
            build: (format) => _generateDualLanguagePdfReceipt(format),
            canChangeOrientation: false,
            canChangePageFormat: false,
            initialPageFormat: PdfPageFormat.a5,
          ),
        ),
      ),
    );
  }

  Future<void> _shareOnWhatsApp() async {
    final mob = _mobileCtrl.text.trim();
    final farmer = _nameHindiCtrl.text.trim().isNotEmpty
        ? _nameHindiCtrl.text.trim()
        : _nameEnglishCtrl.text.trim().toUpperCase();

    _saveParchaToLocalStorage();

    final StringBuffer lotsBuffer = StringBuffer();
    for (int i = 0; i < _lots.length; i++) {
      final lot = _lots[i];
      final cName = lot.displayName;
      lotsBuffer.writeln('$cName BAG ${lot.totalBagsCtrl.text.trim()}');
      lotsBuffer.writeln('< RATE: Rs ${lot.rateCtrl.text.trim()}');
      lotsBuffer.writeln(lot.formulaDisplay);
      lotsBuffer.writeln('रकम: Rs ${lot.grossAmount.toStringAsFixed(0)}');
      if (i < _lots.length - 1) lotsBuffer.writeln('---');
    }

    final message = '''
*मंडी किसान पर्चा (MANDI FARMER BILL)*
---------------------------------
DATE: ${_billDate.day}/${_billDate.month}/${_billDate.year}
NAME: $farmer
---------------------------------
$lotsBuffer---------------------------------
सकल फसल रकम: Rs ${_grossAllCropAmount.toStringAsFixed(0)}
मजदूरी (MAJURI): -Rs ${_totalMajuri.toStringAsFixed(0)} ($_totalAllBags Bags)
${_kantaCharge > 0 ? "कांटा खर्च: -Rs ${_kantaCharge.toStringAsFixed(0)}\n" : ""}${_cleanCharge > 0 ? "छनाई/सफाई: -Rs ${_cleanCharge.toStringAsFixed(0)}\n" : ""}${_cessCharge > 0 ? "मंडी सेस/भाड़ा: -Rs ${_cessCharge.toStringAsFixed(0)}\n" : ""}---------------------------------
*TOTAL PAYABLE (शुद्ध रकम): Rs ${_grandTotal.toStringAsFixed(0)}*
---------------------------------
''';

    final uri = Uri.parse(
        'https://wa.me/${mob.isNotEmpty ? "91$mob" : ""}?text=${Uri.encodeComponent(message)}');
    final canLaunch = await canLaunchUrl(uri);
    if (!mounted) return;

    if (canLaunch) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('WhatsApp cannot be launched on this device')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Colors.red.shade50
                      : const Color(0xFFA855F7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isListening
                        ? Colors.red
                        : const Color(0xFFA855F7).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening
                              ? Colors.red
                              : const Color(0xFFA855F7)),
                      onPressed: _listenVoiceParcha,
                    ),
                    Expanded(
                      child: Text(
                        _isListening
                            ? 'Listening... (e.g., Ramesh 14 bags Jeera 28000 rate 13 into 55 plus 10.5)'
                            : 'Voice-to-Parcha (Speak Bill Details)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Date: ${_billDate.day}/${_billDate.month}/${_billDate.year}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _clearForm,
                                icon: const Icon(Icons.refresh, size: 15),
                                label: const Text('Clear',
                                    style: TextStyle(fontSize: 12)),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _billDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() => _billDate = picked);
                                  }
                                },
                                icon:
                                    const Icon(Icons.calendar_month, size: 15),
                                label: const Text('Change Date',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _nameEnglishCtrl,
                              textCapitalization: TextCapitalization.words,
                              onChanged: (text) {
                                final converted =
                                    HindiPhoneticTransliteration.convert(text);
                                setState(() {
                                  _nameHindiCtrl.text = converted;
                                });
                              },
                              decoration: const InputDecoration(
                                labelText: 'English Name',
                                prefixIcon:
                                    Icon(Icons.keyboard_outlined, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _nameHindiCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Hindi / नाम (Auto)',
                                prefixIcon: Icon(Icons.translate, size: 20),
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _mobileCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number (Optional for WhatsApp)',
                          prefixIcon: Icon(Icons.phone_android, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Commodity Lots (${_lots.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFA855F7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _lots.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, index) {
                          final lot = _lots[index];

                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 11,
                                      backgroundColor: const Color(0xFFA855F7),
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: lot.commodityEnglishCtrl,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        onChanged: (text) {
                                          final converted =
                                              HindiPhoneticTransliteration
                                                  .convert(text);
                                          setState(() {
                                            lot.commodityHindiCtrl.text =
                                                converted;
                                          });
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'English Item',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: lot.commodityHindiCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'जिंस (हिंदी)',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: lot.totalBagsCtrl,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onChanged: (val) {
                                          final total =
                                              int.tryParse(val.trim()) ?? 0;
                                          if (total > 0 &&
                                              (lot.fullBagsCtrl.text.isEmpty ||
                                                  lot.fullBagsCtrl.text ==
                                                      '0')) {
                                            lot.fullBagsCtrl.text =
                                                (total - 1).toString();
                                          }
                                          _recalculateTotals();
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Bags',
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                        ),
                                      ),
                                    ),
                                    if (_lots.length > 1) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red, size: 20),
                                        tooltip: 'Remove Lot',
                                        onPressed: () => _removeLot(index),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFA855F7)
                                        .withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFA855F7)
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: lot.fullBagsCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly
                                          ],
                                          onChanged: (_) =>
                                              _recalculateTotals(),
                                          decoration: const InputDecoration(
                                            labelText: 'Full Bags',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 3),
                                        child: Text('X',
                                            style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: lot.bagWeightCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          onChanged: (_) =>
                                              _recalculateTotals(),
                                          decoration: const InputDecoration(
                                            labelText: 'Kg/Bag',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 3),
                                        child: Text('+',
                                            style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: lot.looseWeightCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          onChanged: (_) =>
                                              _recalculateTotals(),
                                          decoration: const InputDecoration(
                                            labelText: 'Loose (kg)',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton.filled(
                                        style: IconButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF0F766E),
                                          padding: const EdgeInsets.all(8),
                                        ),
                                        icon: const Icon(Icons.scale, size: 16),
                                        tooltip: 'Dhada Weighment Sheet',
                                        onPressed: () =>
                                            _openDhadaWeighmentSheet(lot),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: lot.rateCtrl,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        onChanged: (_) => _recalculateTotals(),
                                        decoration: const InputDecoration(
                                          labelText: 'Rate (Rs/Qntl)',
                                          prefixIcon: Icon(Icons.currency_rupee,
                                              size: 16),
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${lot.formulaDisplay} kg',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Rs ${lot.grossAmount.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (index == _lots.length - 1) ...[
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFFA855F7),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        elevation: 1,
                                      ),
                                      onPressed: _addNewLot,
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text(
                                        'ADD COMMODITY (+)',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Majuri & Deductions / मजदूरी व कटौतियां:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: Color(0xFFA855F7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _majuriRateCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _recalculateTotals(),
                              decoration: const InputDecoration(
                                labelText: 'Majuri (Rs/Bag)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _kantaChargeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _recalculateTotals(),
                              decoration: const InputDecoration(
                                labelText: 'Weighbridge (Rs)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _cleanChargeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _recalculateTotals(),
                              decoration: const InputDecoration(
                                labelText: 'Cleaning (Rs)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _cessChargeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _recalculateTotals(),
                              decoration: const InputDecoration(
                                labelText: 'Mandi Cess (Rs)',
                                isDense: true,
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

              // =======================================================
              // ON-SCREEN PAPER SLIP (EXACT NOTEBOOK FORMAT)
              // =======================================================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFBF9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.brown.shade300, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _nameHindiCtrl.text.trim().isNotEmpty
                                ? 'NAME: ${_nameHindiCtrl.text.trim()}'
                                : (_nameEnglishCtrl.text.trim().isEmpty
                                    ? 'NAME'
                                    : 'NAME: ${_nameEnglishCtrl.text.trim().toUpperCase()}'),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'DATE: ${_billDate.day}/${_billDate.month}/${_billDate.year}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(
                        height: 18, color: Colors.brown, thickness: 1.2),
                    ..._lots.map((lot) {
                      final cName = lot.displayName;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.only(right: 10),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                        right: BorderSide(
                                            color: Colors.brown, width: 1.5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'AMOUNT / रकम',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black54),
                                      ),
                                      Text(
                                        'Rs ${lot.grossAmount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F766E)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$cName BAG ${lot.totalBagsCtrl.text.trim()}',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '< RATE: ${lot.rateCtrl.text.trim()}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Center(
                              child: Text(
                                lot.formulaDisplay,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(
                        height: 18, color: Colors.brown, thickness: 1.2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.only(right: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                                right: BorderSide(
                                    color: Colors.brown, width: 1.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'AMOUNT',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black54),
                              ),
                              Text(
                                '- Rs ${_totalMajuri.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'MAJURI / मजदूरी ($_totalAllBags Bags @ Rs ${_majuriRateCtrl.text.trim()})',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_kantaCharge > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(right: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                  right: BorderSide(
                                      color: Colors.brown, width: 1.5)),
                            ),
                            child: Text(
                              '- Rs ${_kantaCharge.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('WEIGHBRIDGE / कांटा खर्च',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    if (_cleanCharge > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(right: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                  right: BorderSide(
                                      color: Colors.brown, width: 1.5)),
                            ),
                            child: Text(
                              '- Rs ${_cleanCharge.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('CLEANING / छनाई व सफाई',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    if (_cessCharge > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(right: 10),
                            decoration: const BoxDecoration(
                              border: Border(
                                  right: BorderSide(
                                      color: Colors.brown, width: 1.5)),
                            ),
                            child: Text(
                              '- Rs ${_cessCharge.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text('MANDI CESS / मंडी सेस व भाड़ा',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    const Divider(
                        height: 20, color: Colors.brown, thickness: 1.5),
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.only(bottom: 2),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Colors.black87, width: 2)),
                            ),
                            child: const Text(
                              'TOTAL / कुल शुद्ध रकम',
                              style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Rs ${_grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F766E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // =======================================================
              // ACTION BUTTONS (SAVE, WHATSAPP, BREVO EMAIL, PRINT)
              // =======================================================
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 44) / 2 > 140
                        ? (MediaQuery.of(context).size.width - 44) / 2
                        : double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _saveParchaToLocalStorage,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('SAVE BILL',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 44) / 2 > 140
                        ? (MediaQuery.of(context).size.width - 44) / 2
                        : double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF25D366),
                        side: const BorderSide(
                            color: Color(0xFF25D366), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _shareOnWhatsApp,
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('WHATSAPP',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 44) / 2 > 140
                        ? (MediaQuery.of(context).size.width - 44) / 2
                        : double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _sendBillViaEmailDialog,
                      icon: const Icon(Icons.email_outlined, size: 16),
                      label: const Text('EMAIL BILL',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - 44) / 2 > 140
                        ? (MediaQuery.of(context).size.width - 44) / 2
                        : double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA855F7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _openPrintPreview,
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('PRINT',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// 6. DHADA WEIGHMENT TALLY SHEET MODAL
// =============================================================
class DhadaWeighmentSheetModal extends StatefulWidget {
  final String commodityName;
  final Function(int fullBags, double bagWeight, double looseKg, int totalBags)
      onApplyFormula;

  const DhadaWeighmentSheetModal({
    super.key,
    required this.commodityName,
    required this.onApplyFormula,
  });

  @override
  State<DhadaWeighmentSheetModal> createState() =>
      _DhadaWeighmentSheetModalState();
}

class _DhadaWeighmentSheetModalState extends State<DhadaWeighmentSheetModal> {
  final List<TextEditingController> _dhadaControllers = [];
  final TextEditingController _targetWeightPerBagCtrl =
      TextEditingController(text: '55');
  final TextEditingController _tarePerBagCtrl =
      TextEditingController(text: '1.0');

  int _bagsPerDhada = 4;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 6; i++) {
      _dhadaControllers.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    for (var c in _dhadaControllers) {
      c.dispose();
    }
    _targetWeightPerBagCtrl.dispose();
    _tarePerBagCtrl.dispose();
    super.dispose();
  }

  void _addMoreDhadaRows() {
    setState(() {
      for (int i = 0; i < 4; i++) {
        _dhadaControllers.add(TextEditingController());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double grossScaleKg = 0.0;
    int filledDhadaCount = 0;

    for (var ctrl in _dhadaControllers) {
      final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
      if (val > 0) {
        grossScaleKg += val;
        filledDhadaCount++;
      }
    }

    final double tarePerBag =
        double.tryParse(_tarePerBagCtrl.text.trim()) ?? 0.0;
    final int totalEstimatedBags = filledDhadaCount * _bagsPerDhada;
    final double totalTareWeight = totalEstimatedBags * tarePerBag;
    final double netWeightKg = (grossScaleKg - totalTareWeight) > 0
        ? (grossScaleKg - totalTareWeight)
        : 0.0;

    final double standardBag =
        double.tryParse(_targetWeightPerBagCtrl.text.trim()) ?? 55.0;
    int fullBagsCalculated = standardBag > 0 ? (netWeightKg ~/ standardBag) : 0;
    double looseCalculated =
        standardBag > 0 ? (netWeightKg % standardBag) : 0.0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dhada Weighment Sheet: ${widget.commodityName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F766E),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _bagsPerDhada,
                  decoration: const InputDecoration(
                    labelText: 'Bags / Drop',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Bag')),
                    DropdownMenuItem(value: 2, child: Text('2 Bags')),
                    DropdownMenuItem(value: 4, child: Text('4 Bags')),
                    DropdownMenuItem(value: 5, child: Text('5 Bags')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _bagsPerDhada = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _targetWeightPerBagCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Std Bag (kg)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tarePerBagCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Tare/Bag (kg)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              itemCount: _dhadaControllers.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.1,
              ),
              itemBuilder: (ctx, idx) {
                return TextField(
                  controller: _dhadaControllers[idx],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Drop #${idx + 1}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                );
              },
            ),
          ),
          TextButton.icon(
            onPressed: _addMoreDhadaRows,
            icon: const Icon(Icons.add),
            label: const Text('Add More Scale Drops (+4)'),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'Gross Scale: ${grossScaleKg.toStringAsFixed(1)} kg | Net Weight: ${netWeightKg.toStringAsFixed(2)} kg',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Formula Result: $fullBagsCalculated X ${standardBag.toStringAsFixed(0)} + ${looseCalculated.toStringAsFixed(2)} = ${netWeightKg.toStringAsFixed(2)} kg',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F766E),
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              widget.onApplyFormula(
                fullBagsCalculated,
                standardBag,
                looseCalculated,
                totalEstimatedBags > 0
                    ? totalEstimatedBags
                    : fullBagsCalculated,
              );
              Navigator.pop(context);
            },
            child: const Text('APPLY FORMULA TO BILL'),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 7. 3-DAY LOCAL PARCHA ARCHIVE (WITH SELECT, VIEW, PRINT & DELETE)
// =============================================================
class ParchaHistoryArchiveTab extends StatefulWidget {
  const ParchaHistoryArchiveTab({super.key});

  @override
  State<ParchaHistoryArchiveTab> createState() =>
      _ParchaHistoryArchiveTabState();
}

class _ParchaHistoryArchiveTabState extends State<ParchaHistoryArchiveTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _activeBills = [];
  final Set<String> _selectedBillIds = {};
  int _activeRetentionDays = 3;

  @override
  void initState() {
    super.initState();
    _loadAndPurgeLocalArchive();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadAndPurgeLocalArchive() {
    final savedDays = StorageService.get('local_retention_days');
    _activeRetentionDays =
        savedDays != null ? (int.tryParse(savedDays) ?? 3) : 3;

    final rawList = StorageService.get('local_parcha_archive_3days');
    if (rawList == null) {
      setState(() {
        _activeBills = [];
        _selectedBillIds.clear();
      });
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(rawList);
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: _activeRetentionDays));

      final List<Map<String, dynamic>> validBills = [];
      for (var item in decoded) {
        if (item is Map<String, dynamic> && item['savedAt'] != null) {
          final savedDate = DateTime.tryParse(item['savedAt'].toString());
          if (savedDate != null && savedDate.isAfter(cutoffDate)) {
            validBills.add(Map<String, dynamic>.from(item));
          }
        }
      }

      StorageService.save('local_parcha_archive_3days', jsonEncode(validBills));

      setState(() {
        _activeBills = validBills;
        _selectedBillIds
            .removeWhere((id) => !validBills.any((b) => b['id'] == id));
      });
    } catch (e) {
      debugPrint('Error reading local archive: $e');
    }
  }

  Future<Uint8List> _generateArchivedBillPdf(
    PdfPageFormat format,
    Map<String, dynamic> data,
  ) async {
    final pdf = pw.Document();

    pw.Font hindiFont;
    pw.Font hindiFontBold;
    try {
      hindiFont = await PdfGoogleFonts.notoSansDevanagariRegular();
      hindiFontBold = await PdfGoogleFonts.notoSansDevanagariBold();
    } catch (_) {
      hindiFont = pw.Font.helvetica();
      hindiFontBold = pw.Font.helveticaBold();
    }

    final billDate =
        DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now();
    final dateStr =
        '${billDate.day.toString().padLeft(2, '0')}/${billDate.month.toString().padLeft(2, '0')}/${billDate.year}';
    final nameStr = data['farmerName']?.toString() ?? 'NAME';
    final lots = data['lots'] as List<dynamic>? ?? [];
    final majuriVal = (data['majuriDeduction'] as num?)?.toDouble() ?? 0.0;
    final kantaVal = (data['kantaCharge'] as num?)?.toDouble() ?? 0.0;
    final cleanVal = (data['cleanCharge'] as num?)?.toDouble() ?? 0.0;
    final cessVal = (data['cessCharge'] as num?)?.toDouble() ?? 0.0;
    final grandTotalVal = (data['grandTotal'] as num?)?.toDouble() ?? 0.0;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: hindiFont, bold: hindiFontBold),
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(22),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Align(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text(
                    'DATE / दिनांक: $dateStr',
                    style: const pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'NAME / नाम: $nameStr',
                  style: const pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 18),
                ...lots.map((lot) {
                  final cName = lot['commodity']?.toString() ?? '';
                  final bTotal = lot['totalBags']?.toString() ?? '0';
                  final rBhav = lot['rate']?.toString() ?? '0';
                  final grossStr =
                      ((lot['grossAmount'] as num?)?.toDouble() ?? 0.0)
                          .toStringAsFixed(0);
                  final formulaStr = lot['formula']?.toString() ?? '';

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 12),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.only(right: 12),
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  right: pw.BorderSide(
                                      color: PdfColors.black, width: 1.5),
                                ),
                              ),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'AMOUNT / रकम',
                                    style: const pw.TextStyle(
                                        fontSize: 11,
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Rs $grossStr',
                                    style: const pw.TextStyle(
                                        fontSize: 16,
                                        fontWeight: pw.FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            pw.Expanded(
                              child: pw.Text(
                                '$cName BAG / बोरी $bTotal',
                                style: const pw.TextStyle(
                                    fontSize: 17,
                                    fontWeight: pw.FontWeight.bold),
                              ),
                            ),
                            pw.Text(
                              '< RATE: Rs $rBhav',
                              style: const pw.TextStyle(
                                  fontSize: 15, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 5),
                        pw.Center(
                          child: pw.Text(
                            formulaStr,
                            style: const pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                pw.Divider(thickness: 1.3, color: PdfColors.black),
                pw.SizedBox(height: 8),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.only(right: 12),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          right: pw.BorderSide(
                            color: PdfColors.black,
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: pw.Text(
                        '- ${majuriVal.toStringAsFixed(0)}',
                        style: const pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red900,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Text(
                        'MAJURI / मजदूरी (${data['totalBags'] ?? 0} Bags)',
                        style: const pw.TextStyle(
                            fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (kantaVal > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'WEIGHBRIDGE / कांटा खर्च: - Rs ${kantaVal.toStringAsFixed(0)}',
                    style: const pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900),
                  ),
                ],
                if (cleanVal > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'CLEANING / छनाई व सफाई: - Rs ${cleanVal.toStringAsFixed(0)}',
                    style: const pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900),
                  ),
                ],
                if (cessVal > 0) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'MANDI CESS / मंडी सेस: - Rs ${cessVal.toStringAsFixed(0)}',
                    style: const pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red900),
                  ),
                ],
                pw.SizedBox(height: 14),
                pw.Divider(thickness: 1.5, color: PdfColors.black),
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'TOTAL / कुल शुद्ध रकम',
                        style: const pw.TextStyle(
                            fontSize: 20, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Rs ${grandTotalVal.toStringAsFixed(0)}',
                        style: const pw.TextStyle(
                            fontSize: 26, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  void _deleteSingleBill(String id, String farmerName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Saved Bill?'),
        content:
            Text('Are you sure you want to delete the bill for "$farmerName"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _activeBills.removeWhere((b) => b['id'] == id);
                _selectedBillIds.remove(id);
              });
              StorageService.save(
                  'local_parcha_archive_3days', jsonEncode(_activeBills));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Bill deleted from local storage.')),
              );
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedBills() {
    if (_selectedBillIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedBillIds.length} Selected Bills?'),
        content: const Text(
            'These bills will be permanently removed from local storage.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _activeBills
                    .removeWhere((b) => _selectedBillIds.contains(b['id']));
                _selectedBillIds.clear();
              });
              StorageService.save(
                  'local_parcha_archive_3days', jsonEncode(_activeBills));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Selected bills deleted successfully.')),
              );
            },
            child:
                const Text('DELETE ALL', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll(List<Map<String, dynamic>> filteredList) {
    setState(() {
      if (_selectedBillIds.length == filteredList.length) {
        _selectedBillIds.clear();
      } else {
        _selectedBillIds.clear();
        for (var bill in filteredList) {
          if (bill['id'] != null) {
            _selectedBillIds.add(bill['id'].toString());
          }
        }
      }
    });
  }

  void _viewBillDetails(Map<String, dynamic> data) {
    final lots = data['lots'] as List<dynamic>? ?? [];
    final savedAtDate = DateTime.tryParse(data['savedAt'] ?? '')?.toLocal();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Bill: ${data['farmerName']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (savedAtDate != null)
                  Text(
                    'Saved on: ${savedAtDate.day}/${savedAtDate.month}/${savedAtDate.year} at ${savedAtDate.hour}:${savedAtDate.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                if (data['mobile'] != null &&
                    data['mobile'].toString().isNotEmpty)
                  Text('Mobile: ${data['mobile']}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                const Divider(height: 18),
                const Text('Commodity Lots:',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 6),
                ...lots.map((lot) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '${lot['commodity']} (${lot['totalBags']} Bags)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5)),
                            Text('Rate: Rs ${lot['rate']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Formula: ${lot['formula']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                        Text('Gross Amount: Rs ${lot['grossAmount']}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E))),
                      ],
                    ),
                  );
                }),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Net Weight:'),
                    Text(
                        '${(data['totalWeightKg'] as num?)?.toStringAsFixed(2)} kg (${(data['totalWeightQuintal'] as num?)?.toStringAsFixed(3)} Qntl)',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gross Produce Amount:'),
                    Text('Rs ${data['totalGross']}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Majuri Deduction:'),
                    Text('- Rs ${data['majuriDeduction']}',
                        style: const TextStyle(color: Colors.red)),
                  ],
                ),
                if ((data['otherDeductions'] as num? ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Other Deductions (Kanta/Cess):'),
                      Text('- Rs ${data['otherDeductions']}',
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ],
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL PAYABLE:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F766E)),
                    ),
                    Text(
                      'Rs ${data['grandTotal']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA855F7),
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      title: Text('Bill: ${data['farmerName']}'),
                      backgroundColor: const Color(0xFFA855F7),
                      foregroundColor: Colors.white,
                    ),
                    body: PdfPreview(
                      build: (format) => _generateArchivedBillPdf(format, data),
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      initialPageFormat: PdfPageFormat.a5,
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('PRINT'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _activeBills.where((d) {
      final name = d['farmerName']?.toString().toLowerCase() ?? '';
      final mob = d['mobile']?.toString() ?? '';
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || mob.contains(q);
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.brown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Local Archive: Bills kept on device for $_activeRetentionDays days. Use Checkboxes to Select and Delete.',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.brown),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search by Farmer Name or Mobile Number...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (filtered.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _selectedBillIds.isNotEmpty &&
                              _selectedBillIds.length == filtered.length,
                          tristate: _selectedBillIds.isNotEmpty &&
                              _selectedBillIds.length < filtered.length,
                          onChanged: (_) => _toggleSelectAll(filtered),
                        ),
                        Text(
                          _selectedBillIds.isEmpty
                              ? 'Select All'
                              : '${_selectedBillIds.length} Selected',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    if (_selectedBillIds.isNotEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        onPressed: _deleteSelectedBills,
                        icon: const Icon(Icons.delete, size: 16),
                        label: Text(
                            'Delete Selected (${_selectedBillIds.length})'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No saved bills found in the last $_activeRetentionDays days.',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) {
                    final data = filtered[idx];
                    final billId = data['id']?.toString() ?? idx.toString();
                    final lots = data['lots'] as List<dynamic>? ?? [];
                    final isSelected = _selectedBillIds.contains(billId);

                    return Card(
                      elevation: 1.5,
                      color: isSelected
                          ? const Color(0xFFA855F7).withValues(alpha: 0.08)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFFA855F7)
                              : Colors.black12,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedBillIds.add(billId);
                              } else {
                                _selectedBillIds.remove(billId);
                              }
                            });
                          },
                        ),
                        title: Text(
                          '${data['farmerName']} (Rs ${data['grandTotal']})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Total Bags: ${data['totalBags']} | Net Weight: ${(data['totalWeightKg'] as num?)?.toStringAsFixed(2)} kg\nLots: ${lots.map((l) => l['commodity']).join(', ')}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility_outlined,
                                  color: Color(0xFF0F766E)),
                              tooltip: 'View Bill Details',
                              onPressed: () => _viewBillDetails(data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              tooltip: 'Delete Bill',
                              onPressed: () => _deleteSingleBill(
                                  billId, data['farmerName'] ?? 'Bill'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================
// 8. MAJURI (LABOUR) CALCULATION SHEET
// =============================================================
class MajuriCalculatorTab extends StatefulWidget {
  const MajuriCalculatorTab({super.key});

  @override
  State<MajuriCalculatorTab> createState() => _MajuriCalculatorTabState();
}

class _MajuriCalculatorTabState extends State<MajuriCalculatorTab> {
  final _bagsCtrl = TextEditingController();
  final _perBagLabourCtrl = TextEditingController(text: '12.0');
  final _handlingChargesCtrl = TextEditingController(text: '0');
  final _loadingChargesCtrl = TextEditingController(text: '0');

  double _totalLabour = 0.0;
  double _grandLabourTotal = 0.0;

  @override
  void dispose() {
    _bagsCtrl.dispose();
    _perBagLabourCtrl.dispose();
    _handlingChargesCtrl.dispose();
    _loadingChargesCtrl.dispose();
    super.dispose();
  }

  void _calculateLabour() {
    final int bags = int.tryParse(_bagsCtrl.text.trim()) ?? 0;
    final double perBag = double.tryParse(_perBagLabourCtrl.text.trim()) ?? 0.0;
    final double handling =
        double.tryParse(_handlingChargesCtrl.text.trim()) ?? 0.0;
    final double loading =
        double.tryParse(_loadingChargesCtrl.text.trim()) ?? 0.0;

    setState(() {
      _totalLabour = bags * perBag;
      _grandLabourTotal = _totalLabour + handling + loading;
    });
  }

  void _clearLabour() {
    setState(() {
      _bagsCtrl.clear();
      _perBagLabourCtrl.text = '12.0';
      _handlingChargesCtrl.text = '0';
      _loadingChargesCtrl.text = '0';
      _totalLabour = 0.0;
      _grandLabourTotal = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Labour / Hamali Work Sheet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFA855F7),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _clearLabour,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reset'),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      TextField(
                        controller: _bagsCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        onChanged: (_) => _calculateLabour(),
                        decoration: const InputDecoration(
                          labelText: 'Total Number of Bags Handled',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _perBagLabourCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => _calculateLabour(),
                        decoration: const InputDecoration(
                          labelText: 'Labour Rate (Rs per Bag)',
                          prefixIcon: Icon(Icons.currency_rupee),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _handlingChargesCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _calculateLabour(),
                              decoration: const InputDecoration(
                                labelText: 'Weighbridge / Handling Charge (Rs)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _loadingChargesCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => _calculateLabour(),
                              decoration: const InputDecoration(
                                labelText: 'Vehicle Loading Charge (Rs)',
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Bag Labour Total:'),
                        Text(
                          'Rs ${_totalLabour.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Weighing & Handling:'),
                        Text(
                          'Rs ${(double.tryParse(_handlingChargesCtrl.text) ?? 0.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vehicle Loading:'),
                        Text(
                          'Rs ${(double.tryParse(_loadingChargesCtrl.text) ?? 0.0).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TOTAL LABOUR PAYABLE:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFA855F7),
                          ),
                        ),
                        Text(
                          'Rs ${_grandLabourTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFA855F7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
