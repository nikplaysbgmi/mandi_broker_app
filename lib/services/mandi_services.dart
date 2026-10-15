import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';

// =============================================================
// 1. LOCAL PERSISTENT STORAGE SERVICE
// =============================================================
class StorageService {
  static SharedPreferences? _prefs;

  /// Initializes persistent storage on app startup.
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Saves a string key-value pair to persistent storage.
  static void save(String key, String value) {
    if (_prefs == null) {
      SharedPreferences.getInstance().then((p) {
        _prefs = p;
        p.setString(key, value);
      });
    } else {
      _prefs?.setString(key, value);
    }
  }

  /// Reads a string value from persistent storage.
  static String? get(String key) {
    return _prefs?.getString(key);
  }

  /// Removes a key from persistent storage.
  static void remove(String key) {
    if (_prefs == null) {
      SharedPreferences.getInstance().then((p) {
        _prefs = p;
        p.remove(key);
      });
    } else {
      _prefs?.remove(key);
    }
  }

  /// Helper to get the currently active broker key (phone or UID).
  static String get currentBrokerKey {
    final sessionBrokerMobile = get('session_BROKER_mobile');
    if (sessionBrokerMobile != null && sessionBrokerMobile.trim().isNotEmpty) {
      return sessionBrokerMobile.trim();
    }
    final sessionBroker = get('session_BROKER');
    if (sessionBroker != null && sessionBroker.trim().isNotEmpty) {
      return sessionBroker.trim();
    }
    return FirebaseAuth.instance.currentUser?.phoneNumber ??
        FirebaseAuth.instance.currentUser?.uid ??
        'default_broker';
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
class WhatsAppService {
  /// Generates the default deal confirmation template.
  static String getDefaultTemplate() {
    return '''
🌾 *{appName} - (TRADE CONFIRMATION)* 🌾
-----------------------------------
*{partyName}* ({roleText}),
आपका सौदा ब्रोकर द्वारा दर्ज कर लिया गया है:

📅 *Date:* {dateStr}
📦 *Jins:* {jins}
⚖️ *Bags/Weight:* {bags}
💰 *Rate:* ₹{rate}
🏢 *To:* {oppParty}
-----------------------------------
📋 *ब्रोकर फर्म:* {brokerFirmName}
📞 *संपर्क:* {brokerMobile}

_कृपया अपने पोर्टल में लॉगिन कर सौदे की पुष्टि (Confirm) करें।_
''';
  }

  /// Robust multi-tier URL dispatcher for WhatsApp & WhatsApp Business
  static Future<bool> _launchWhatsAppUrl({
    required String cleanMobile,
    required String message,
  }) async {
    final encodedText = Uri.encodeComponent(message);

    final nativeUri =
        Uri.parse('whatsapp://send?phone=$cleanMobile&text=$encodedText');
    final apiUri = Uri.parse(
        'https://api.whatsapp.com/send?phone=$cleanMobile&text=$encodedText');
    final waMeUri = Uri.parse('https://wa.me/$cleanMobile?text=$encodedText');

    try {
      if (await canLaunchUrl(nativeUri)) {
        return await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      }
      if (await canLaunchUrl(apiUri)) {
        return await launchUrl(apiUri, mode: LaunchMode.externalApplication);
      }
      if (await canLaunchUrl(waMeUri)) {
        return await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(nativeUri,
          mode: LaunchMode.externalNonBrowserApplication);
    } catch (e) {
      debugPrint(
          'WhatsApp primary dispatch failed ($e), attempting web fallback...');
      try {
        return await launchUrl(waMeUri, mode: LaunchMode.externalApplication);
      } catch (err) {
        debugPrint('WhatsApp final dispatch error: $err');
        return false;
      }
    }
  }

  /// Dispatches the trade confirmation message via WhatsApp.
  static Future<void> sendSaudaAlert({
    required String recipientMobile,
    required String role,
    required MandiSaudaModel sauda,
    required String brokerFirmName,
    required String brokerMobile,
  }) async {
    String cleanMobile = recipientMobile.replaceAll(RegExp(r'\D'), '');
    if (cleanMobile.length == 10) cleanMobile = '91$cleanMobile';

    if (cleanMobile.isEmpty) {
      debugPrint('WhatsAppService: Invalid or empty recipient mobile number');
      return;
    }

    final partyName = role == 'BUYER' ? sauda.buyer : sauda.seller;
    final roleText = role == 'BUYER' ? 'खरीदार (Buyer)' : 'विक्रेता (Seller)';
    final dateStr =
        '${sauda.date.day.toString().padLeft(2, '0')}/${sauda.date.month.toString().padLeft(2, '0')}/${sauda.date.year}';

    String template = getDefaultTemplate();
    final rawProfile = StorageService.get('mandi_profile');
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        final profile = BrokerFirmProfileModel.fromJson(jsonDecode(rawProfile));
        if (profile.whatsappMessageTemplate.trim().isNotEmpty) {
          template = profile.whatsappMessageTemplate;
        }
      } catch (_) {}
    }

    final message = template
        .replaceAll('{appName}', kAppName)
        .replaceAll('{partyName}', partyName)
        .replaceAll('{roleText}', roleText)
        .replaceAll('{dateStr}', dateStr)
        .replaceAll('{jins}', sauda.jins)
        .replaceAll('{bags}', sauda.bags.toString())
        .replaceAll('{rate}', sauda.rate.toStringAsFixed(0))
        .replaceAll('{oppParty}', role == 'BUYER' ? sauda.seller : sauda.buyer)
        .replaceAll(
          '{brokerFirmName}',
          brokerFirmName.isNotEmpty ? brokerFirmName : 'MANDI BROKER',
        )
        .replaceAll('{brokerMobile}', brokerMobile);

    await _launchWhatsAppUrl(cleanMobile: cleanMobile, message: message);
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
    final message = '''
⚠️ *$kAppName - सौदा विलोपन सूचना (SAUDA DELETED)* ⚠️
-----------------------------------
*$recipientName*,
ब्रोकर द्वारा निम्न सौदा बही से हटा (Delete) दिया गया है:

📅 *दिनांक:* $dateStr
📦 *जिंस:* ${sauda.jins}
⚖️ *बोरी:* ${sauda.bags}
💰 *भाव:* ₹${sauda.rate.toStringAsFixed(0)}
-----------------------------------
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
  static const String currentVersion = '1.0.6';

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
    final cleanCurrent = current.split('+').first.trim();
    final cleanLatest = latest.split('+').first.trim();

    final List<int> currParts =
        cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final List<int> latestParts =
        cleanLatest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final int curr = i < currParts.length ? currParts[i] : 0;
      final int lat = i < latestParts.length ? latestParts[i] : 0;
      if (lat > curr) return true;
      if (lat < curr) return false;
    }
    return false;
  }
}
