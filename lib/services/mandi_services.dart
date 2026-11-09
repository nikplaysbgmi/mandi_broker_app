import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';

// =============================================================
// 1. LOCAL STORAGE SERVICE WITH WEBKIT SAFE IN-MEMORY FALLBACK
// =============================================================
class StorageService {
  static SharedPreferences? _prefs;
  static final Map<String, String> _memoryStore = {};

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('WebKit storage restriction encountered: $e');
      _prefs = null;
    }
  }

  static void save(String key, String value) {
    _memoryStore[key] = value;
    try {
      if (_prefs != null) {
        _prefs!.setString(key, value);
      } else {
        SharedPreferences.getInstance().then((p) {
          _prefs = p;
          p.setString(key, value);
        }).catchError((_) {});
      }
    } catch (_) {}
  }

  static void set(String key, String value) => save(key, value);

  static String? get(String key) {
    try {
      if (_prefs != null && _prefs!.containsKey(key)) {
        return _prefs!.getString(key);
      }
    } catch (_) {}
    return _memoryStore[key];
  }

  static void remove(String key) {
    _memoryStore.remove(key);
    try {
      if (_prefs != null) {
        _prefs!.remove(key);
      }
    } catch (_) {}
  }

  static String get currentBrokerKey {
    final sessionBrokerMobile = get('session_BROKER_mobile');
    if (sessionBrokerMobile != null && sessionBrokerMobile.trim().isNotEmpty) {
      return sessionBrokerMobile.trim();
    }
    final sessionBroker = get('session_BROKER');
    if (sessionBroker != null && sessionBroker.trim().isNotEmpty) {
      return sessionBroker.trim();
    }
    final lastLoggedMobile = get('last_logged_in_mobile');
    if (lastLoggedMobile != null && lastLoggedMobile.trim().isNotEmpty) {
      return lastLoggedMobile.trim();
    }
    try {
      final authPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
      if (authPhone != null && authPhone.trim().isNotEmpty) {
        return authPhone.trim();
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.trim().isNotEmpty) {
        return uid.trim();
      }
      return 'default_broker';
    } catch (_) {
      return 'default_broker';
    }
  }
}

// =============================================================
// 2. ACCOUNT MANAGEMENT SERVICE
// =============================================================
class AccountService {
  /// Fetches all registered accounts stored in local memory.
  static List<UserAccount> getAllAccounts() {
    final raw = StorageService.get('mandi_registered_accounts');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw);
        return list.map((e) => UserAccount.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error parsing registered accounts: $e');
      }
    }
    return [];
  }

  /// Saves accounts list to local storage.
  static void saveAccounts(List<UserAccount> accounts) {
    final data = jsonEncode(accounts.map((a) => a.toJson()).toList());
    StorageService.save('mandi_registered_accounts', data);
  }

  /// Finds an existing user account by mobile or email address.
  static UserAccount? findExistingAccount(String identifier) {
    final accounts = getAllAccounts();
    final clean = identifier.trim().toLowerCase();
    for (var acc in accounts) {
      if (acc.mobile.trim() == clean ||
          acc.email.trim().toLowerCase() == clean) {
        return acc;
      }
    }
    return null;
  }

  /// Returns accounts belonging to a specific portal section.
  static List<UserAccount> getAccountsBySection(String section) {
    final targetSection = section.trim().toUpperCase();
    return getAllAccounts()
        .where((a) => a.section.trim().toUpperCase() == targetSection)
        .toList();
  }

  /// Retrieves the active logged-in user for a specific portal section.
  static UserAccount? getSessionUser(String section) {
    final targetSection = section.trim().toUpperCase();
    final sessionIdentifier =
        StorageService.get('session_${targetSection}_mobile') ??
            StorageService.get('session_$targetSection');
    if (sessionIdentifier == null ||
        sessionIdentifier.toString().trim().isEmpty) {
      return null;
    }

    final clean = sessionIdentifier.toString().trim().toLowerCase();
    final accounts = getAllAccounts();

    for (final a in accounts) {
      if (a.section.trim().toUpperCase() == targetSection &&
          (a.mobile.trim() == clean || a.email.trim().toLowerCase() == clean)) {
        return a;
      }
    }

    // Fallback to session keys if account list cache was cleared
    final savedName = StorageService.get('session_${targetSection}_name');
    final savedMobile = StorageService.get('session_${targetSection}_mobile') ??
        sessionIdentifier.toString().trim();
    if (savedName != null && savedName.trim().isNotEmpty) {
      return UserAccount(
        name: savedName.trim(),
        mobile: savedMobile.trim(),
        email:
            (StorageService.get('session_${targetSection}_email') ?? '').trim(),
        address: (StorageService.get('session_${targetSection}_address') ?? '')
            .trim(),
        password:
            (StorageService.get('session_${targetSection}_password') ?? '')
                .trim(),
        section: targetSection,
      );
    }

    return null;
  }

  /// Updates or inserts an account in local storage (deduplicating any stale entries).
  static void updateAccount(UserAccount updated) {
    final accounts = getAllAccounts();
    final targetSection = updated.section.trim().toUpperCase();
    final cleanMobile = updated.mobile.trim();
    final cleanEmail = updated.email.trim().toLowerCase();

    accounts.removeWhere(
      (a) =>
          a.section.trim().toUpperCase() == targetSection &&
          (a.mobile.trim() == cleanMobile ||
              (cleanEmail.isNotEmpty &&
                  a.email.trim().toLowerCase() == cleanEmail)),
    );

    accounts.add(updated);
    saveAccounts(accounts);
  }

  /// Removes user from local persistent memory.
  static void removeAccount({required String mobile, required String section}) {
    final accounts = getAllAccounts();
    final targetSection = section.trim().toUpperCase();
    final cleanMobile = mobile.trim();

    accounts.removeWhere(
      (a) =>
          a.mobile.trim() == cleanMobile &&
          a.section.trim().toUpperCase() == targetSection,
    );
    saveAccounts(accounts);
  }

  /// Migrates user account when contact numbers or email addresses are altered.
  static void updateAccountWithOldCredentials({
    required String oldMobile,
    required String oldEmail,
    required UserAccount updatedAccount,
  }) {
    final accounts = getAllAccounts();
    final cleanOldMobile = oldMobile.trim();
    final cleanOldEmail = oldEmail.trim().toLowerCase();
    final cleanNewMobile = updatedAccount.mobile.trim();
    final cleanNewEmail = updatedAccount.email.trim().toLowerCase();
    final targetSection = updatedAccount.section.trim().toUpperCase();

    accounts.removeWhere(
      (a) =>
          a.section.trim().toUpperCase() == targetSection &&
          (a.mobile.trim() == cleanOldMobile ||
              a.mobile.trim() == cleanNewMobile ||
              (cleanOldEmail.isNotEmpty &&
                  a.email.trim().toLowerCase() == cleanOldEmail) ||
              (cleanNewEmail.isNotEmpty &&
                  a.email.trim().toLowerCase() == cleanNewEmail)),
    );

    accounts.add(updatedAccount);
    saveAccounts(accounts);
  }
}

// =============================================================
// 3. BROKER-ISOLATED PARTY SERVICE (LOCAL CACHE)
// =============================================================
class BrokerPartyService {
  static String _getPartyStorageKey([String? brokerKey]) {
    final key = (brokerKey != null && brokerKey.isNotEmpty)
        ? brokerKey.trim()
        : StorageService.currentBrokerKey;
    return 'broker_parties_$key';
  }

  /// Retrieves only this broker's buyers and sellers from local cache.
  static List<Map<String, dynamic>> getParties([String? brokerKey]) {
    final raw = StorageService.get(_getPartyStorageKey(brokerKey));
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        debugPrint('Error parsing broker parties: $e');
      }
    }
    return [];
  }

  /// Saves a party (buyer or seller) to the broker's local list.
  static void saveParty(Map<String, dynamic> partyData, [String? brokerKey]) {
    final list = getParties(brokerKey);
    final mobile = (partyData['mobile'] ?? '').toString().trim();
    final index =
        list.indexWhere((p) => p['mobile'].toString().trim() == mobile);

    if (index != -1) {
      list[index] = partyData;
    } else {
      list.add(partyData);
    }

    StorageService.save(
      _getPartyStorageKey(brokerKey),
      jsonEncode(list),
    );
  }

  /// Removes a party from this broker's local directory.
  static void deleteParty(String partyMobile, [String? brokerKey]) {
    final list = getParties(brokerKey);
    final clean = partyMobile.trim();
    list.removeWhere((p) => p['mobile'].toString().trim() == clean);
    StorageService.save(
      _getPartyStorageKey(brokerKey),
      jsonEncode(list),
    );
  }

  /// Finds a specific party by mobile for this broker.
  static Map<String, dynamic>? findPartyByMobile(String mobile,
      [String? brokerKey]) {
    final clean = mobile.trim();
    final list = getParties(brokerKey);
    for (final p in list) {
      if (p['mobile'].toString().trim() == clean) {
        return p;
      }
    }
    return null;
  }
}

// =============================================================
// 4. NOTIFICATION SERVICE
// =============================================================
class NotificationService {
  /// Loads all notifications from local storage.
  static List<AppNotification> getAllNotifications() {
    final raw = StorageService.get('mandi_notifications');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List list = jsonDecode(raw);
        return list.map((e) => AppNotification.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error parsing notifications: $e');
      }
    }
    return [];
  }

  /// Appends an in-app notification.
  static void addNotification({
    required String targetMobile,
    required String title,
    required String message,
  }) {
    final list = getAllNotifications();
    list.insert(
      0,
      AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        targetMobile: targetMobile.trim(),
        title: title.trim(),
        message: message.trim(),
        timestamp: DateTime.now(),
      ),
    );
    StorageService.save(
      'mandi_notifications',
      jsonEncode(list.map((n) => n.toJson()).toList()),
    );
  }

  /// Returns unread/active notifications targeted to a phone number.
  static List<AppNotification> getForMobile(String mobile) {
    final cleanMobile = mobile.trim();
    return getAllNotifications()
        .where((n) => n.targetMobile.trim() == cleanMobile)
        .toList();
  }

  /// Returns notifications targeted to the active broker session.
  static List<AppNotification> getForCurrentBroker() {
    return getForMobile(StorageService.currentBrokerKey);
  }

  /// Clears notifications targeted to a specific phone number (both local and Firestore).
  static Future<void> clearForMobile(String mobile) async {
    final cleanMobile = mobile.trim();
    final list = getAllNotifications();
    list.removeWhere((n) => n.targetMobile.trim() == cleanMobile);
    StorageService.save(
      'mandi_notifications',
      jsonEncode(list.map((n) => n.toJson()).toList()),
    );

    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('targetMobile', isEqualTo: cleanMobile)
          .get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
    } catch (_) {}
  }
}

// =============================================================
// 5. WHATSAPP TRANSACTION MESSAGING SERVICE
// =============================================================
class WhatsAppTemplateModel {
  final int id;
  final String title;
  final String subtitle;
  final String rawTemplate;

  const WhatsAppTemplateModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.rawTemplate,
  });
}

class WhatsAppService {
  /// 4 Distinct WhatsApp Templates for Brokers
  static const List<WhatsAppTemplateModel> templates = [
    // Template 1: विस्तृत सौदा पत्र (Detailed Trade Contract)
    WhatsAppTemplateModel(
      id: 0,
      title: '1. Detailed',
      subtitle: 'नियम, सौदा कोड व संपूर्ण विवरण सहित',
      rawTemplate: ''' *Trade Confirmation* 
━━━━━━━━━━━━━━━━━━━━
 
 *दिनांक:* {dateStr}

 *खरीदार:* {buyerName}
 *विक्रेता:* {sellerName}
 *जिंस:* {jins}
 *बोरी:* {bags} बोरी
 *सौदा भाव:* ₹{rate} प्रति क्विंटल

━━━━━━━━━━━━━━━━━━━━
*सौदा कोड:*#{saudaId}
🤝 *दलाल फर्म:* {brokerFirmName}
📞 *संपर्क:* {brokerMobile}''',
    ),

    // Template 2: संक्षिप्त व्यावसायिक (Modern Business)
    WhatsAppTemplateModel(
      id: 1,
      title: '2. English Modern',
      subtitle: 'मोबाइल फ्रेंडली, संक्षिप्त बुलेट पॉइंट्स',
      rawTemplate: ''' * Trade Confirmation*
━━━━━━━━━━━━━━━━━━━━
• *Date:* {dateStr}
• *Item:* {jins}
• *Quantity:* {bags} Bags
• *Rate:* ₹{rate}/-
• *Buyer:* {buyerName}
• *Seller:* {sellerName}
━━━━━━━━━━━━━━━━━━━━
*Sauda Code:*#{saudaId}
🤝 *Broker:* {brokerFirmName}
📞 *Call/WA:* {brokerMobile}''',
    ),

    // Template 3: पारंपरिक मंडी चिट्ठी (Traditional Mandi Slip)
    WhatsAppTemplateModel(
      id: 2,
      title: '3. Hindi Mandi',
      subtitle: 'श्री गणेशाय नमः व पारंपरिक मंडी शैली',
      rawTemplate: '''॥ श्री गणेशाय नमः ॥
 *Trade Confirmation*
━━━━━━━━━━━━━━━━━━━━
दिनांक: *{dateStr}*

*{partyName}* ({roleText}),
 *जिंस:* {jins}
 *बोरी:* {bags}
 *सौदा भाव:* ₹{rate} प्रति क्विंटल
 *पार्टी:* {oppParty}
━━━━━━━━━━━━━━━━━━━━
👉 *सौदा कोड:* #{saudaId}
*{brokerFirmName}*
📞 *फोन:* {brokerMobile}''',
    ),

    // Template 4: त्वरित पुष्टि स्लिप (Quick SMS Slip)
    WhatsAppTemplateModel(
      id: 3,
      title: '4. SMS Quick',
      subtitle: 'अत्यंत संक्षिप्त, त्वरित पुष्टि हेतु',
      rawTemplate: ''' *Trade Confirmation*
━━━━━━━━━━━━━━━━━━━━
 *{jins}* | *{bags} Bags* @ *₹{rate}*
Buyer: {buyerName}
Seller: {sellerName}
Date: {dateStr}
━━━━━━━━━━━━━━━━━━━━
*Sauda Code:* #{saudaId}
Broker: {brokerFirmName} ({brokerMobile})''',
    ),
  ];

  /// Generates the default deal confirmation template.
  static String getDefaultTemplate() => templates[0].rawTemplate;

  /// Formats a template string by populating real sauda and broker values.
  static String formatSaudaMessage({
    required String template,
    required MandiSaudaModel sauda,
    required String role,
    required String brokerFirmName,
    required String brokerMobile,
  }) {
    final partyName = role == 'BUYER' ? sauda.buyer : sauda.seller;
    final roleText = role == 'BUYER' ? 'खरीदार (Buyer)' : 'विक्रेता (Seller)';
    final dateStr =
        '${sauda.date.day.toString().padLeft(2, '0')}/${sauda.date.month.toString().padLeft(2, '0')}/${sauda.date.year}';
    final buyerDalali = sauda.buyerDalaliPerBag > 0
        ? '₹${sauda.buyerDalaliPerBag.toStringAsFixed(0)}/बोरी (क्रेता)'
        : '';
    final sellerDalali = sauda.sellerDalaliPerBag > 0
        ? '₹${sauda.sellerDalaliPerBag.toStringAsFixed(0)}/बोरी (विक्रेता)'
        : '';
    final brokerageText =
        [buyerDalali, sellerDalali].where((s) => s.isNotEmpty).join(' | ');

    final code = sauda.id.trim().toUpperCase();

    return template
        .replaceAll('{appName}', kAppName)
        .replaceAll('{partyName}', partyName)
        .replaceAll('{roleText}', roleText)
        .replaceAll('{dateStr}', dateStr)
        .replaceAll('{saudaId}', code)
        .replaceAll('{saudaCode}', code)
        .replaceAll('{code}', code)
        .replaceAll('{jins}', sauda.jins)
        .replaceAll('{bags}', sauda.bags.toString())
        .replaceAll('{rate}', sauda.rate.toStringAsFixed(0))
        .replaceAll('{buyerName}', sauda.buyer)
        .replaceAll('{sellerName}', sauda.seller)
        .replaceAll('{oppParty}', role == 'BUYER' ? sauda.seller : sauda.buyer)
        .replaceAll(
          '{brokerageText}',
          brokerageText.isNotEmpty ? brokerageText : 'मंडी नियमानुसार',
        )
        .replaceAll(
          '{brokerFirmName}',
          brokerFirmName.isNotEmpty ? brokerFirmName : 'MANDI BROKER',
        )
        .replaceAll('{brokerMobile}', brokerMobile);
  }

  /// Robust multi-tier URL dispatcher for WhatsApp & WhatsApp Business across Web and Mobile
  static Future<bool> _launchWhatsAppUrl({
    String cleanMobile = '',
    required String message,
  }) async {
    final cleanDigits = cleanMobile.replaceAll(RegExp(r'\D'), '');
    String targetPhone = cleanDigits;
    if (targetPhone.length == 10) {
      targetPhone = '91$targetPhone';
    } else if (targetPhone.length == 11 && targetPhone.startsWith('0')) {
      targetPhone = '91${targetPhone.substring(1)}';
    }

    final encodedText = Uri.encodeComponent(message);

    final apiUri = targetPhone.isNotEmpty
        ? Uri.parse(
            'https://api.whatsapp.com/send?phone=$targetPhone&text=$encodedText')
        : Uri.parse('https://api.whatsapp.com/send?text=$encodedText');

    final waMeUri = targetPhone.isNotEmpty
        ? Uri.parse('https://wa.me/$targetPhone?text=$encodedText')
        : Uri.parse('https://wa.me/?text=$encodedText');

    final nativeUri = targetPhone.isNotEmpty
        ? Uri.parse('whatsapp://send?phone=$targetPhone&text=$encodedText')
        : Uri.parse('whatsapp://send?text=$encodedText');

    // Web handling: directly open api.whatsapp.com or wa.me in _blank
    if (kIsWeb) {
      try {
        final opened = await launchUrl(
          apiUri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
        if (opened) return true;
      } catch (e) {
        debugPrint('WhatsApp web launch 1 note: $e');
      }

      try {
        return await launchUrl(
          waMeUri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_blank',
        );
      } catch (e) {
        debugPrint('WhatsApp web launch 2 note: $e');
        return false;
      }
    }

    // Mobile (Android / iOS): Ladder of dispatch without brittle canLaunchUrl
    try {
      final ok =
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    try {
      final ok = await launchUrl(apiUri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    try {
      final ok = await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {}

    try {
      return await launchUrl(apiUri, mode: LaunchMode.platformDefault);
    } catch (e) {
      debugPrint('WhatsApp final dispatch error: $e');
      return false;
    }
  }

  /// Launch a direct phone call using tel: URI scheme
  static Future<void> launchPhoneCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return;
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not dial phone ($clean): $e');
    }
  }

  /// Dispatches a formatted trade slip via WhatsApp for Buyer or Seller
  static Future<void> sharePartySaudaSlip({
    required MandiSaudaModel sauda,
    required bool isBuyer,
    String? recipientMobile,
  }) async {
    String cleanMobile = (recipientMobile ?? '').replaceAll(RegExp(r'\D'), '');
    if (cleanMobile.length == 10) cleanMobile = '91$cleanMobile';

    final dateStr =
        '${sauda.date.day.toString().padLeft(2, '0')}/${sauda.date.month.toString().padLeft(2, '0')}/${sauda.date.year}';
    final totalAmount = (sauda.bags * sauda.rate).toStringAsFixed(0);
    final brokerageDue = isBuyer
        ? sauda.totalBuyerDalali.toStringAsFixed(0)
        : sauda.totalSellerDalali.toStringAsFixed(0);

    final saudaCode = sauda.id.trim().toUpperCase();

    final message = '''
🌾 *$kAppName - TRADE SLIP* 🌾
━━━━━━━━━━━━━━━━━━━━
🔑 *सौदा कोड (Sauda Code):* #$saudaCode (1 माह तक मान्य)
📅 *दिनांक:* $dateStr
📦 *जिंस:* ${sauda.jins}
⚖️ *बोरी / वजन:* ${sauda.bags} बोरी
💰 *सौदा भाव:* ₹${sauda.rate.toStringAsFixed(0)} / क्विंटल
💵 *कुल रकम:* ₹$totalAmount
📌 *स्थिति:* ✅ फाइनल सौदा (Recorded)
━━━━━━━━━━━━━━━━━━━━
🏢 *खरीदार:* ${sauda.buyer}
🚜 *विक्रेता:* ${sauda.seller}
🤝 *ब्रोकर फर्म:* ${sauda.brokerFirmName.isNotEmpty ? sauda.brokerFirmName : 'MANDI BROKER'} (${sauda.brokerMobile})
💼 *दलाली:* ₹$brokerageDue
━━━━━━━━━━━━━━━━━━━━
👉 *Mandi Portal पर 'सर्च कोड' में कोड #$saudaCode डालकर अपने खाते में सुरक्षित जोड़ें (वैधता: 1 माह)।*''';

    await _launchWhatsAppUrl(cleanMobile: cleanMobile, message: message);
  }

  /// Shares a complete ledger statement with a broker via WhatsApp
  static Future<void> shareBrokerKhataStatement({
    required String brokerFirmName,
    required String brokerMobile,
    required String partyName,
    required String partyMobile,
    required bool isBuyer,
    required List<MandiSaudaModel> deals,
    String? recipientMobile,
  }) async {
    String cleanMobile = (recipientMobile ?? '').replaceAll(RegExp(r'\D'), '');
    if (cleanMobile.length == 10) cleanMobile = '91$cleanMobile';

    final int totalBags = deals.fold<int>(0, (acc, d) => acc + d.bags);
    final double totalValue =
        deals.fold<double>(0.0, (acc, d) => acc + (d.bags * d.rate));
    final double totalDalali = deals.fold<double>(0.0,
        (acc, d) => acc + (isBuyer ? d.totalBuyerDalali : d.totalSellerDalali));

    final roleTitle = isBuyer ? 'खरीदार (BUYER)' : 'विक्रेता (SELLER)';

    final dealsSummary = deals.take(5).map((d) {
      final dStr =
          '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}';
      return '• $dStr: ${d.jins} - ${d.bags} बोरी @ ₹${d.rate.toStringAsFixed(0)} = ₹${(d.bags * d.rate).toStringAsFixed(0)}';
    }).join('\n');

    final message = '''
📜 *$kAppName - खाता विवरण (KHATA STATEMENT)* 📜
━━━━━━━━━━━━━━━━━━━━
🏢 *ब्रोकर फर्म:* $brokerFirmName ($brokerMobile)
👤 *पार्टी:* $partyName ($partyMobile) [$roleTitle]
━━━━━━━━━━━━━━━━━━━━
📊 *कुल सौदे:* ${deals.length}
⚖️ *कुल बोरी:* $totalBags
💰 *कुल व्यापार मूल्य:* ₹${totalValue.toStringAsFixed(0)}
🤝 *कुल देय दलाली:* ₹${totalDalali.toStringAsFixed(0)}
━━━━━━━━━━━━━━━━━━━━
*हालिया सौदे:*
$dealsSummary
${deals.length > 5 ? '\n(+ ${deals.length - 5} अन्य सौदे)' : ''}
━━━━━━━━━━━━━━━━━━━━
_मंडी व्यापार डिजिटल पोर्टल_''';

    await _launchWhatsAppUrl(cleanMobile: cleanMobile, message: message);
  }

  /// Dispatches the trade confirmation message via WhatsApp.
  static Future<bool> sendSaudaAlert({
    required String recipientMobile,
    required String role,
    required MandiSaudaModel sauda,
    required String brokerFirmName,
    required String brokerMobile,
    int? templateIndex,
    String? customTemplate,
  }) async {
    String cleanMobile = recipientMobile.replaceAll(RegExp(r'\D'), '');
    if (cleanMobile.length == 10) cleanMobile = '91$cleanMobile';
    if (cleanMobile.length == 11 && cleanMobile.startsWith('0')) {
      cleanMobile = '91${cleanMobile.substring(1)}';
    }

    if (cleanMobile.isEmpty) {
      debugPrint('WhatsAppService: Invalid or empty recipient mobile number');
      return false;
    }

    String chosenTemplate = customTemplate ?? '';
    if (chosenTemplate.isEmpty) {
      if (templateIndex != null &&
          templateIndex >= 0 &&
          templateIndex < templates.length) {
        chosenTemplate = templates[templateIndex].rawTemplate;
      } else {
        final savedCustom =
            StorageService.get('broker_custom_whatsapp_template');
        if (savedCustom != null && savedCustom.isNotEmpty) {
          chosenTemplate = savedCustom;
        } else {
          final rawProfile = StorageService.get('mandi_profile');
          if (rawProfile != null && rawProfile.isNotEmpty) {
            try {
              final profile =
                  BrokerFirmProfileModel.fromJson(jsonDecode(rawProfile));
              if (profile.whatsappMessageTemplate.trim().isNotEmpty) {
                chosenTemplate = profile.whatsappMessageTemplate;
              }
            } catch (_) {}
          }
        }
        if (chosenTemplate.isEmpty) {
          final savedIdx = StorageService.get('broker_whatsapp_template_index');
          final idx = int.tryParse(savedIdx?.toString() ?? '0') ?? 0;
          chosenTemplate = (idx >= 0 && idx < templates.length)
              ? templates[idx].rawTemplate
              : templates[0].rawTemplate;
        }
      }
    }

    final message = formatSaudaMessage(
      template: chosenTemplate,
      sauda: sauda,
      role: role,
      brokerFirmName: brokerFirmName,
      brokerMobile: brokerMobile,
    );

    return await _launchWhatsAppUrl(cleanMobile: cleanMobile, message: message);
  }

  /// Sends a WhatsApp confirmation notice from Buyer or Seller back to Broker
  static Future<bool> sendConfirmationAck({
    required String brokerMobile,
    required String partyName,
    required String role,
    required MandiSaudaModel sauda,
  }) async {
    String targetMobile = brokerMobile.replaceAll(RegExp(r'\D'), '');
    if (targetMobile.length == 10) targetMobile = '91$targetMobile';

    final dateStr =
        '${sauda.date.day.toString().padLeft(2, '0')}/${sauda.date.month.toString().padLeft(2, '0')}/${sauda.date.year}';
    final roleText = role == 'BUYER' ? 'खरीदार (Buyer)' : 'विक्रेता (Seller)';
    final code = sauda.id.trim().toUpperCase();

    final message = '''
✅ *सौदा स्वीकृति पुष्टि (DEAL CONFIRMED)*
━━━━━━━━━━━━━━━━━━━━
🔑 *सौदा कोड:* #$code
दिनांक: $dateStr
जिंस: ${sauda.jins}
बोरी: ${sauda.bags}
भाव: ₹${sauda.rate.toStringAsFixed(0)}

स्वीकृतिकर्ता: $partyName ($roleText)
_यह सौदा मेरे खाते में सुरक्षित दर्ज हो चुका है।_''';

    return await _launchWhatsAppUrl(
        cleanMobile: targetMobile, message: message);
  }

  /// Dispatches a cancellation/deletion notice via WhatsApp.
  static Future<void> sendDeletionNotice({
    required String recipientMobile,
    required String recipientName,
    required MandiSaudaModel sauda,
    required String brokerFirmName,
  }) async {
    String cleanMobile = recipientMobile.replaceAll(RegExp(r'\D'), '');
    if (cleanMobile.length == 10) cleanMobile = '91$cleanMobile';

    if (cleanMobile.isEmpty) {
      debugPrint(
          'WhatsAppService: Invalid or empty recipient mobile number for deletion notice');
      return;
    }

    final dateStr =
        '${sauda.date.day.toString().padLeft(2, '0')}/${sauda.date.month.toString().padLeft(2, '0')}/${sauda.date.year}';
    final code = sauda.id.trim().toUpperCase();
    final message = '''
⚠️ *$kAppName - सौदा विलोपन सूचना (SAUDA DELETED)* ⚠️
━━━━━━━━━━━━━━━━━━━━
*$recipientName*,
ब्रोकर द्वारा निम्न सौदा बही से हटा (Delete) दिया गया है:

🔑 *सौदा कोड:* #$code
📅 *दिनांक:* $dateStr
📦 *जिंस:* ${sauda.jins}
⚖️ *बोरी:* ${sauda.bags}
💰 *भाव:* ₹${sauda.rate.toStringAsFixed(0)}
━━━━━━━━━━━━━━━━━━━━
ब्रोकर फर्म: $brokerFirmName
''';

    await _launchWhatsAppUrl(cleanMobile: cleanMobile, message: message);
  }
}

// =============================================================
// 6. SAUDA STORAGE HELPERS (BROKER-SCOPED)
// =============================================================

/// Updates or creates a trade record in local storage.
void updateSaudaInStorage(MandiSaudaModel updated) {
  final raw = StorageService.get('mandi_saudas');
  List<MandiSaudaModel> all = [];
  if (raw != null && raw.isNotEmpty) {
    try {
      final List list = jsonDecode(raw);
      all = list.map((e) => MandiSaudaModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error reading saudas from local storage: $e');
    }
  }

  final index = all.indexWhere((s) => s.id == updated.id);
  if (index != -1) {
    all[index] = updated;
  } else {
    all.add(updated);
  }

  StorageService.save(
    'mandi_saudas',
    jsonEncode(all.map((s) => s.toJson()).toList()),
  );
}

/// Retrieves saudas belonging specifically to a broker from local storage.
List<MandiSaudaModel> getSaudasForBroker([String? brokerMobile]) {
  final raw = StorageService.get('mandi_saudas');
  if (raw == null || raw.isEmpty) return [];

  final cleanBroker = (brokerMobile != null && brokerMobile.isNotEmpty)
      ? brokerMobile.trim()
      : StorageService.currentBrokerKey;

  try {
    final List list = jsonDecode(raw);
    return list
        .map((e) => MandiSaudaModel.fromJson(e))
        .where((s) =>
            s.brokerMobile.trim().isEmpty ||
            s.brokerMobile.trim() == cleanBroker)
        .toList();
  } catch (e) {
    debugPrint('Error getting saudas for broker: $e');
    return [];
  }
}

/// Displays an in-app notifications modal dialog (merges live Firestore + local notifications).
void showNotificationDialog(BuildContext context, String userMobile) {
  final cleanMobile = userMobile.trim();

  showDialog(
    context: context,
    builder: (ctx) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('targetMobile', isEqualTo: cleanMobile)
          .snapshots(),
      builder: (context, snapshot) {
        final localList = NotificationService.getForMobile(cleanMobile);
        final Map<String, AppNotification> mergedMap = {
          for (var n in localList) n.id: n,
        };

        if (snapshot.hasData && snapshot.data != null) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data();
            data['id'] = doc.id;
            final notif = AppNotification.fromJson(data);
            mergedMap[notif.id] = notif;
          }
        }

        final notifications = mergedMap.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.notifications_active, color: Color(0xFF0F766E)),
                  SizedBox(width: 8),
                  Text(
                    'Notifications',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              if (notifications.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await NotificationService.clearForMobile(cleanMobile);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text(
                    'Clear All',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: notifications.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'No notifications right now.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          n.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '${n.message}\n${n.timestamp.day.toString().padLeft(2, '0')}/${n.timestamp.month.toString().padLeft(2, '0')}/${n.timestamp.year} ${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    ),
  );
}

// =============================================================
// 7. APP UPDATE SERVICE (FIRESTORE VERSION CHECK)
// =============================================================
class AppUpdateService {
  static const String currentVersion = '1.0.14';

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version_control')
          .get();

      if (!doc.exists || doc.data() == null) return;

      final data = doc.data()!;
      final String latestVersion =
          (data['latest_version'] ?? currentVersion).toString().trim();
      final bool forceUpdate = data['force_update'] == true;
      final String downloadUrl = (data['download_url'] ?? '').toString().trim();
      final String releaseNotes = (data['release_notes'] ??
              'A new update is available with improvements.')
          .toString();

      if (_isUpdateAvailable(currentVersion, latestVersion) &&
          context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: !forceUpdate,
          builder: (ctx) => PopScope(
            canPop: !forceUpdate,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.system_update_rounded, color: Color(0xFF0F766E)),
                  SizedBox(width: 8),
                  Text('Update Available',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'A new version ($latestVersion) of Mandi Trade Portal is ready to install.'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      releaseNotes,
                      style:
                          TextStyle(color: Colors.grey.shade800, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Colors.amber.shade900),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'सुझाव: यदि Android में "App not installed" आए, तो पहले पुराना ऐप Uninstall कर लें, फिर नया APK इंस्टॉल करें। (डाटा क्लाउड में सुरक्षित है)',
                            style: TextStyle(
                                fontSize: 11, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (!forceUpdate)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Later'),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (downloadUrl.isNotEmpty) {
                      final uri = Uri.parse(downloadUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  child: const Text('Update Now'),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('App update check error: $e');
    }
  }

  static bool _isUpdateAvailable(String current, String latest) {
    try {
      final cleanCurrent = current.split('+').first.trim();
      final cleanLatest = latest.split('+').first.trim();

      final List<int> currParts = cleanCurrent
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
          .toList();
      final List<int> latestParts = cleanLatest
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'\D'), '')) ?? 0)
          .toList();

      for (int i = 0; i < 3; i++) {
        final int curr = i < currParts.length ? currParts[i] : 0;
        final int lat = i < latestParts.length ? latestParts[i] : 0;
        if (lat > curr) return true;
        if (lat < curr) return false;
      }
    } catch (_) {}
    return false;
  }
}
