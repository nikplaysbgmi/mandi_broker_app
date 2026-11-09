import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_collections.dart';
import 'sauda_encryption_service.dart';
import 'telegram_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'mandi_services.dart';

/// Auto-chunking Firestore batch runner that guarantees never exceeding
/// Firestore's hard limit of 500 operations per batch.
class SafeBatchRunner {
  final FirebaseFirestore _db;
  final int maxOpsPerBatch;
  WriteBatch _currentBatch;
  int _opCount = 0;
  int _totalCommitted = 0;

  SafeBatchRunner([FirebaseFirestore? db, this.maxOpsPerBatch = 400])
      : _db = db ?? FirebaseFirestore.instance,
        _currentBatch = (db ?? FirebaseFirestore.instance).batch();

  int get totalCommitted => _totalCommitted;
  int get pendingOps => _opCount;
  bool get hasPendingOps => _opCount > 0;

  Future<void> set(DocumentReference ref, Map<String, dynamic> data, [SetOptions? options]) async {
    if (options != null) {
      _currentBatch.set(ref, data, options);
    } else {
      _currentBatch.set(ref, data);
    }
    _opCount++;
    if (_opCount >= maxOpsPerBatch) {
      await commit();
    }
  }

  Future<void> update(DocumentReference ref, Map<String, dynamic> data) async {
    _currentBatch.update(ref, data);
    _opCount++;
    if (_opCount >= maxOpsPerBatch) {
      await commit();
    }
  }

  Future<void> delete(DocumentReference ref) async {
    _currentBatch.delete(ref);
    _opCount++;
    if (_opCount >= maxOpsPerBatch) {
      await commit();
    }
  }

  Future<void> commit() async {
    if (_opCount > 0) {
      await _currentBatch.commit();
      _totalCommitted += _opCount;
      _opCount = 0;
      _currentBatch = _db.batch();
    }
  }
}

class CloudSyncService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Normalizes any mobile number string to a standard 10-digit format for personal folder keys.
  static String cleanMobileNumber(String? mobile) {
    if (mobile == null) return '';
    final cleaned = mobile.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (cleaned.length > 10) {
      return cleaned.substring(cleaned.length - 10);
    }
    return cleaned;
  }

  /// Ensures the client has an active Firebase Auth session before read/write operations.
  static Future<void> ensureAuthSession() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('FirebaseAuth session init error: $e');
    }
  }

  /// Verifies active internet connectivity using a forced server ping to Firestore.
  /// Returns false immediately if device is offline, has DNS failure, or times out.
  static Future<bool> hasActiveInternet() async {
    try {
      await _db
          .collection('app_config')
          .doc('services')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      return true;
    } catch (_) {
      try {
        // Fallback secondary check against root directory
        await _db
            .collection('service_switches')
            .doc('config')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 3));
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Helper to get the active broker identifier (prefers phone, falls back to UID).
  static String getActiveBrokerKey([String? explicitKey]) {
    if (explicitKey != null && explicitKey.trim().isNotEmpty) {
      return explicitKey.trim();
    }
    return FirebaseAuth.instance.currentUser?.phoneNumber ??
        FirebaseAuth.instance.currentUser?.uid ??
        'default_broker';
  }

  /// Listens to live changes on the current user's document in Firestore.
  /// Emits `true` immediately when `is_locked == true` or `account_status == 'locked'`.
  static Stream<bool> streamAccountLockStatus(String section, String mobile) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    return _db.collection(FirestoreCollections.users).doc(phone).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data() ?? {};
      final sub = data['subscription'] as Map<String, dynamic>?;
      return data['is_locked'] == true ||
          data['is_blocked'] == true ||
          data['subscription_due'] == true ||
          data['account_status'] == 'locked' ||
          data['account_status'] == 'suspended' ||
          (sub != null &&
              (sub['is_locked'] == true ||
                  sub['subscription_due'] == true ||
                  sub['status'] == 'due' ||
                  sub['status'] == 'locked'));
    });
  }

  /// Checks if a user's subscription is overdue or administrative lock is active.
  /// Returns true if locked, or true if network unreachable.
  static Future<bool> isUserSubscriptionLocked(String identifier) async {
    try {
      final accountDoc = await getAccountByIdentifier(identifier);
      if (accountDoc == null) return false;
      final sub = accountDoc['subscription'] as Map<String, dynamic>?;
      return accountDoc['is_locked'] == true ||
          accountDoc['subscription_due'] == true ||
          accountDoc['is_blocked'] == true ||
          accountDoc['account_status'] == 'locked' ||
          accountDoc['account_status'] == 'suspended' ||
          (sub != null &&
              (sub['is_locked'] == true ||
                  sub['subscription_due'] == true ||
                  sub['status'] == 'due' ||
                  sub['status'] == 'locked'));
    } catch (_) {
      return true;
    }
  }

  /// Streams real-time status of the Bill Generator master switch.
  static Stream<bool> streamBillGeneratorServiceSwitch() {
    return _db.collection('app_config').doc('services').snapshots().map((doc) {
      final data = doc.data() ?? {};
      return data['bill_generator'] ?? true;
    });
  }

  /// Checks if a mobile number is already registered across ANY section or in the brokers directory.
  static Future<bool> isMobileRegistered(String mobile) async {
    try {
      await ensureAuthSession();
      final cleanMob = cleanMobileNumber(mobile);
      final clean = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
      if (clean.isEmpty) return false;

      // 1. Direct check on personal user folder document: users/{clean}
      final personalDoc = await _db.collection(FirestoreCollections.users).doc(clean).get();
      if (personalDoc.exists) return true;

      // 2. Query check across users collection by mobile
      final userQuery = await _db
          .collection(FirestoreCollections.users)
          .where('mobile', isEqualTo: clean)
          .limit(1)
          .get();
      if (userQuery.docs.isNotEmpty) return true;

      // 3. Legacy check across section document IDs
      const sections = ['BROKER', 'BUYER', 'SELLER', 'BILL GENERATOR', 'DEFAULT'];
      for (final section in sections) {
        final doc = await _db.collection(FirestoreCollections.users).doc('${section}_$clean').get();
        if (doc.exists) return true;
      }

      return false;
    } catch (e) {
      debugPrint('CloudSyncService isMobileRegistered error: $e');
      return false;
    }
  }

  // =============================================================
  // 1. BROKER ACCOUNT INITIALIZATION & PROFILE (brokers collection)
  // =============================================================

  /// Initializes or updates the root document for a broker.
  static Future<void> initializeBrokerAccount({
    required String brokerKey,
    required String brokerName,
    required String phone,
    String? email,
    String? address,
    String mandiName = 'Local Mandi',
  }) async {
    try {
      await ensureAuthSession();
      final cleanKey = brokerKey.trim();
      final docRef = _db.collection('brokers').doc(cleanKey);

      await docRef.set({
        'brokerKey': cleanKey,
        'name': brokerName.trim(),
        'firmName': brokerName.trim(),
        'phone': phone.trim(),
        'mobile': phone.trim(),
        'email': (email ?? '').trim().toLowerCase(),
        'address': (address ?? '').trim(),
        'mandiName': mandiName.trim(),
        'role': 'broker',
        'isActive': true,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));

      debugPrint(
          '✅ CloudSync: Broker directory initialized at brokers/$cleanKey');
    } catch (e) {
      debugPrint('❌ CloudSync initializeBrokerAccount error: $e');
    }
  }

  /// Saves user registration details or updates existing account credentials in Firestore.
  /// Populates the canonical "1 User = 1 Personal Folder" at users/{mobile} alongside section records.
  static Future<void> saveAccount(Map<String, dynamic> accountData) async {
    try {
      await ensureAuthSession();

      final String rawMobile = (accountData['mobile'] ?? '').toString().trim();
      final String cleanMob = cleanMobileNumber(rawMobile);
      final String mobile = cleanMob.isNotEmpty ? cleanMob : rawMobile;
      final String email =
          (accountData['email'] ?? '').toString().trim().toLowerCase();
      final String password = (accountData['password'] ?? '').toString().trim();
      final String section =
          (accountData['section'] ?? 'DEFAULT').toString().trim().toUpperCase();
      if (mobile.isEmpty) return;

      final personalDocRef = _db.collection(FirestoreCollections.users).doc(mobile);
      final legacyDocRef = _db.collection(FirestoreCollections.users).doc('${section}_$mobile');

      final existingPersonalSnap = await personalDocRef.get();
      final legacySnap = await legacyDocRef.get();

      final existingData = existingPersonalSnap.data() ?? legacySnap.data() ?? {};
      final existingSubscription = existingData['subscription'] as Map<String, dynamic>?;

      final Map<String, dynamic> subscriptionPayload = {
        'status': existingSubscription?['status'] ?? 'active',
        'plan': existingSubscription?['plan'] ?? (accountData['subscriptionPlan'] ?? 'STANDARD').toString(),
        'is_locked': existingSubscription?['is_locked'] ?? false,
        'subscription_due': existingSubscription?['subscription_due'] ?? false,
        'lock_reason': existingSubscription?['lock_reason'] ?? 'subscription_due',
        'valid_until': existingSubscription?['valid_until'],
        'updated_at': FieldValue.serverTimestamp(),
      };

      final Map<String, dynamic> payload = {
        'name': (accountData['name'] ?? '').toString().trim(),
        'mobile': mobile,
        'email': email,
        'address': (accountData['address'] ?? '').toString().trim(),
        'password': password,
        'section': section,
        'role': section.toLowerCase(),
        'subscription': subscriptionPayload,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (!existingPersonalSnap.exists && !legacySnap.exists) {
        payload['is_locked'] = false;
        payload['subscription_due'] = false;
        payload['lock_reason'] = 'subscription_due';
        payload['account_status'] = 'active';
        payload['is_blocked'] = false;
        payload['created_at'] = FieldValue.serverTimestamp();
      }

      // Save to SINGLE canonical personal user folder: users/{mobile}
      // Eliminates duplicate document creation in users collection
      final batch = _db.batch();
      batch.set(personalDocRef, payload, SetOptions(merge: true));

      // Clean up legacy section doc if it exists so duplicate is removed
      if (legacySnap.exists) {
        batch.delete(legacyDocRef);
      }

      await batch.commit().timeout(const Duration(seconds: 8));

      // Sync password across any remaining documents with same mobile
      if (password.isNotEmpty) {
        final mobileQuery = await _db
            .collection(FirestoreCollections.users)
            .where('mobile', isEqualTo: mobile)
            .get();
        for (final doc in mobileQuery.docs) {
          if (doc.id != mobile) {
            await doc.reference.update({
              'password': password,
              'updated_at': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      debugPrint('✅ CloudSync: Saved single personal user folder users/$mobile');
    } catch (e) {
      debugPrint('❌ CloudSync saveAccount error: $e');
      rethrow;
    }
  }

  /// Universal password updater across `users`, `brokers`, and `accounts` collections.
  static Future<void> updateAccountPassword({
    required String identifier,
    required String newPassword,
    String? section,
  }) async {
    try {
      await ensureAuthSession();
      final cleanId = identifier.trim();
      final cleanPass = newPassword.trim();
      if (cleanId.isEmpty || cleanPass.isEmpty) return;

      // 0. Update canonical personal user folder users/{cleanMob} directly
      final cleanMob = cleanMobileNumber(cleanId);
      if (cleanMob.isNotEmpty) {
        final personalDocRef = _db.collection(FirestoreCollections.users).doc(cleanMob);
        await personalDocRef.set({
          'password': cleanPass,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 1. Direct section_mobile doc update if section is known
      if (section != null &&
          section.trim().isNotEmpty &&
          !cleanId.contains('@')) {
        final docId = '${section.trim().toUpperCase()}_$cleanId';
        final docRef = _db.collection('users').doc(docId);
        final snap = await docRef.get();
        if (snap.exists) {
          await docRef.update({
            'password': cleanPass,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }

      // 2. Query 'users' collection by mobile and email
      final byMobile = await _db
          .collection('users')
          .where('mobile', isEqualTo: cleanId)
          .get();
      for (final doc in byMobile.docs) {
        await doc.reference.update({
          'password': cleanPass,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      final byEmail = await _db
          .collection('users')
          .where('email', isEqualTo: cleanId.toLowerCase())
          .get();
      for (final doc in byEmail.docs) {
        await doc.reference.update({
          'password': cleanPass,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      // 3. Update 'brokers' collection if present
      if (!cleanId.contains('@')) {
        final brokerRef = _db.collection('brokers').doc(cleanId);
        final brokerSnap = await brokerRef.get();
        if (brokerSnap.exists) {
          await brokerRef.update({
            'password': cleanPass,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('❌ CloudSync updateAccountPassword error: $e');
      rethrow;
    }
  }

  /// Searches for an account by mobile or email address.
  static Future<Map<String, dynamic>?> getAccountByIdentifier(
    String identifier, {
    String? section,
  }) async {
    try {
      await ensureAuthSession();
      final clean = identifier.trim().toLowerCase();
      final cleanMob = cleanMobileNumber(identifier);
      if (clean.isEmpty) return null;

      // 1. Direct personal folder check: users/{cleanMob}
      if (cleanMob.isNotEmpty) {
        final personalDoc = await _db
            .collection(FirestoreCollections.users)
            .doc(cleanMob)
            .get()
            .timeout(const Duration(seconds: 6));
        if (personalDoc.exists && personalDoc.data() != null) {
          return personalDoc.data();
        }
      }

      // 2. If section is specified and identifier is a mobile number, check direct section doc ID
      if (section != null &&
          section.trim().isNotEmpty &&
          !clean.contains('@')) {
        final phoneKey = cleanMob.isNotEmpty ? cleanMob : clean;
        final directDoc = await _db
            .collection(FirestoreCollections.users)
            .doc('${section.trim().toUpperCase()}_$phoneKey')
            .get()
            .timeout(const Duration(seconds: 6));
        if (directDoc.exists && directDoc.data() != null) {
          return directDoc.data();
        }
      }

      // 3. Query by mobile across users collection
      final queryByMobile = await _db
          .collection(FirestoreCollections.users)
          .where('mobile', isEqualTo: cleanMob.isNotEmpty ? cleanMob : clean)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6));

      if (queryByMobile.docs.isNotEmpty) {
        return queryByMobile.docs.first.data();
      }

      // 4. Query by email
      final queryByEmail = await _db
          .collection(FirestoreCollections.users)
          .where('email', isEqualTo: clean)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6));

      if (queryByEmail.docs.isNotEmpty) {
        return queryByEmail.docs.first.data();
      }
    } catch (e) {
      debugPrint('CloudSyncService getAccountByIdentifier lookup error: $e');
    }
    return null;
  }

  /// Updates user profile details, migrates credentials across collections,
  /// moves all sub-collections (saudas, parties, notifications) to the new mobile,
  /// and updates associated ledger records atomically.
  static Future<void> updateProfile({
    required String section,
    required String oldMobile,
    required String newMobile,
    required String oldEmail,
    required String newEmail,
    required String newName,
    required String address,
    String? password,
    String? oldName,
  }) async {
    try {
      await ensureAuthSession();

      final cleanOldMob = cleanMobileNumber(oldMobile).isNotEmpty
          ? cleanMobileNumber(oldMobile)
          : oldMobile.trim();
      final cleanNewMob = cleanMobileNumber(newMobile).isNotEmpty
          ? cleanMobileNumber(newMobile)
          : newMobile.trim();
      final cleanNewEmail = newEmail.trim().toLowerCase();
      final cleanOldEmail = oldEmail.trim().toLowerCase();
      final cleanSection = section.trim().toUpperCase();

      final oldDocId = '${cleanSection}_$cleanOldMob';
      final newDocId = '${cleanSection}_$cleanNewMob';

      // 1. Check duplicate mobile if changed
      if (cleanNewMob != cleanOldMob) {
        final bool isTaken = await isMobileRegistered(cleanNewMob);
        if (isTaken) {
          throw Exception(
              'Mobile number $cleanNewMob is already registered in the Mandi Network!');
        }
      }

      // 2. Read existing user document from CANONICAL personal folder users/{cleanOldMob} first
      final Map<String, dynamic> oldData = {};
      try {
        final oldPersonalSnap =
            await _db.collection(FirestoreCollections.users).doc(cleanOldMob).get();
        if (oldPersonalSnap.exists && oldPersonalSnap.data() is Map) {
          oldData.addAll(Map<String, dynamic>.from(oldPersonalSnap.data() as Map));
        }
      } catch (_) {}

      try {
        final oldLegacySnap =
            await _db.collection(FirestoreCollections.users).doc(oldDocId).get();
        if (oldLegacySnap.exists && oldLegacySnap.data() is Map) {
          final leg = Map<String, dynamic>.from(oldLegacySnap.data() as Map);
          leg.forEach((k, v) {
            oldData.putIfAbsent(k, () => v);
          });
        }
      } catch (_) {}

      final String firestoreOldName =
          (oldData['name'] ?? oldData['firmName'] ?? '').toString().trim();
      final String firestoreOldEmail =
          (oldData['email'] ?? '').toString().trim().toLowerCase();
      final String resolvedOldName = (oldName != null && oldName.trim().isNotEmpty)
          ? oldName.trim()
          : firestoreOldName;
      final String resolvedOldEmail = cleanOldEmail.isNotEmpty
          ? cleanOldEmail
          : firestoreOldEmail;

      // 3. Resolve Password strictly so it is NEVER lost or displayed as N/A
      String resolvedPassword = (password ?? '').toString().trim();
      if (resolvedPassword.isEmpty) {
        resolvedPassword =
            (oldData['password'] ?? oldData['pin'] ?? '').toString().trim();
      }
      if (resolvedPassword.isEmpty) {
        try {
          final localAcc = AccountService.findExistingAccount(cleanOldMob) ??
              AccountService.findExistingAccount(oldMobile.trim());
          if (localAcc != null && localAcc.password.trim().isNotEmpty) {
            resolvedPassword = localAcc.password.trim();
          }
        } catch (_) {}
      }
      if (resolvedPassword.isEmpty) {
        try {
          final sessPass = StorageService.get('session_${cleanSection}_password');
          if (sessPass != null && sessPass.toString().trim().isNotEmpty) {
            resolvedPassword = sessPass.toString().trim();
          }
        } catch (_) {}
      }

      final batch = _db.batch();

      if (cleanNewMob != cleanOldMob) {
        // Create new user document in canonical folder users/{cleanNewMob}
        final newPersonalRef =
            _db.collection(FirestoreCollections.users).doc(cleanNewMob);
        final updatePayload = {
          ...oldData,
          'name': newName.trim(),
          'mobile': cleanNewMob,
          'email': cleanNewEmail,
          'address': address.trim(),
          'section': cleanSection,
          'role': cleanSection.toLowerCase(),
          'updated_at': FieldValue.serverTimestamp(),
        };

        if (resolvedPassword.isNotEmpty) {
          updatePayload['password'] = resolvedPassword;
        }

        batch.set(newPersonalRef, updatePayload, SetOptions(merge: true));

        // Delete old user documents
        final oldPersonalRef =
            _db.collection(FirestoreCollections.users).doc(cleanOldMob);
        batch.delete(oldPersonalRef);
        batch.delete(_db.collection(FirestoreCollections.users).doc(oldDocId));
        batch.delete(_db.collection(FirestoreCollections.users).doc(newDocId));

        // Migrate broker profile if broker
        if (cleanSection == 'BROKER') {
          final oldBrokerRef = _db.collection('brokers').doc(cleanOldMob);
          final newBrokerRef = _db.collection('brokers').doc(cleanNewMob);
          final brokerSnap = await oldBrokerRef.get();

          final brokerData = brokerSnap.exists ? brokerSnap.data()! : <String, dynamic>{};
          batch.set(
            newBrokerRef,
            {
              ...brokerData,
              'brokerKey': cleanNewMob,
              'name': newName.trim(),
              'firmName': newName.trim(),
              'phone': cleanNewMob,
              'mobile': cleanNewMob,
              'email': cleanNewEmail,
              'address': address.trim(),
              if (resolvedPassword.isNotEmpty) 'password': resolvedPassword,
              'updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          if (brokerSnap.exists) {
            batch.delete(oldBrokerRef);
          }
        }

        await batch.commit().timeout(const Duration(seconds: 10));

        // 4. Update local AccountService so local memory has the password for the new mobile
        try {
          final localAcc = AccountService.findExistingAccount(cleanOldMob) ??
              AccountService.findExistingAccount(oldMobile.trim());
          if (localAcc != null) {
            localAcc.mobile = cleanNewMob;
            localAcc.name = newName.trim();
            localAcc.email = cleanNewEmail;
            localAcc.address = address.trim();
            if (resolvedPassword.isNotEmpty) {
              localAcc.password = resolvedPassword;
            }
            AccountService.updateAccountWithOldCredentials(
              oldMobile: cleanOldMob,
              oldEmail: oldEmail.trim(),
              updatedAccount: localAcc,
            );
          }
        } catch (_) {}

        // 5. TRANSFER SUB-COLLECTIONS & GLOBAL TRANSACTIONS
        await _migratePersonalFolderSubCollections(
          oldMobile: cleanOldMob,
          newMobile: cleanNewMob,
        );

        if (cleanSection == 'BROKER') {
          await _migrateBrokerSubCollectionsAndLedger(
            oldBrokerKey: cleanOldMob,
            newBrokerKey: cleanNewMob,
            newBrokerFirmName: newName.trim(),
          );
        } else {
          await _transferAllAssociatedSaudas(
            oldMobile: cleanOldMob,
            newMobile: cleanNewMob,
            newName: newName.trim(),
            section: cleanSection,
          );
        }
      } else {
        // Mobile remained same, only profile fields changed
        final personalRef =
            _db.collection(FirestoreCollections.users).doc(cleanOldMob);
        final profileFields = {
          'name': newName.trim(),
          'email': cleanNewEmail,
          'address': address.trim(),
          'updated_at': FieldValue.serverTimestamp(),
        };
        if (resolvedPassword.isNotEmpty) {
          profileFields['password'] = resolvedPassword;
        }
        batch.set(personalRef, profileFields, SetOptions(merge: true));
        batch.delete(_db.collection(FirestoreCollections.users).doc(oldDocId));

        if (cleanSection == 'BROKER') {
          final brokerRef = _db.collection('brokers').doc(cleanOldMob);
          batch.set(
            brokerRef,
            {
              'name': newName.trim(),
              'firmName': newName.trim(),
              'email': cleanNewEmail,
              'address': address.trim(),
              if (resolvedPassword.isNotEmpty) 'password': resolvedPassword,
              'updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit().timeout(const Duration(seconds: 10));
      }

      debugPrint('✅ CloudSync: Profile & credentials migrated cleanly to $cleanNewMob with password preserved');

      // Send Telegram notification if mobile, name, or email/gmail was updated
      final bool mobileChanged = cleanOldMob.isNotEmpty &&
          cleanNewMob.isNotEmpty &&
          cleanOldMob != cleanNewMob;
      final bool nameChanged = resolvedOldName.isNotEmpty &&
          newName.trim().isNotEmpty &&
          resolvedOldName.toLowerCase() != newName.trim().toLowerCase();
      final bool emailChanged = resolvedOldEmail.isNotEmpty &&
          cleanNewEmail.isNotEmpty &&
          resolvedOldEmail != cleanNewEmail;

      if (mobileChanged || nameChanged || emailChanged) {
        TelegramNotificationService.notifyProfileUpdated(
          section: cleanSection,
          oldMobile: cleanOldMob,
          newMobile: cleanNewMob,
          oldName: resolvedOldName,
          newName: newName.trim(),
          oldEmail: resolvedOldEmail,
          newEmail: cleanNewEmail,
          address: address.trim(),
          updatedBy: '$cleanSection (Profile Edit)',
        );
      }
    } catch (e) {
      debugPrint('❌ CloudSync updateProfile error: $e');
      rethrow;
    }
  }

  /// Recursively moves saudas, parties, and notifications to the new broker folder
  /// and updates the global saudas collection.
  static Future<void> _migrateBrokerSubCollectionsAndLedger({
    required String oldBrokerKey,
    required String newBrokerKey,
    required String newBrokerFirmName,
  }) async {
    try {
      final oldBrokerRef = _db.collection('brokers').doc(oldBrokerKey);
      final newBrokerRef = _db.collection('brokers').doc(newBrokerKey);

      // A. Migrate Parties sub-collection
      final partiesSnap = await oldBrokerRef.collection('parties').get();
      if (partiesSnap.docs.isNotEmpty) {
        final partyBatch = SafeBatchRunner(_db);
        for (var doc in partiesSnap.docs) {
          final data = doc.data();
          await partyBatch.set(
            newBrokerRef.collection('parties').doc(doc.id),
            {...data, 'brokerKey': newBrokerKey},
            SetOptions(merge: true),
          );
          await partyBatch.delete(doc.reference);
        }
        await partyBatch.commit();
      }

      // B. Migrate Saudas sub-collection & update global saudas
      final saudasSnap = await oldBrokerRef.collection('saudas').get();
      if (saudasSnap.docs.isNotEmpty) {
        final saudaBatch = SafeBatchRunner(_db);
        for (var doc in saudasSnap.docs) {
          final data = doc.data();
          final updatedData = {
            ...data,
            'brokerKey': newBrokerKey,
            'brokerMobile': newBrokerKey,
            'brokerFirmName': newBrokerFirmName,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          // 1. Move to new sub-collection
          await saudaBatch.set(
            newBrokerRef.collection('saudas').doc(doc.id),
            updatedData,
            SetOptions(merge: true),
          );
          await saudaBatch.delete(doc.reference);

          // 2. Update copy in global saudas
          await saudaBatch.set(
            _db.collection('saudas').doc(doc.id),
            updatedData,
            SetOptions(merge: true),
          );
        }
        await saudaBatch.commit();
      }

      // C. Catch any orphaned global saudas that referenced oldBrokerKey
      final globalSaudasSnap = await _db
          .collection('saudas')
          .where('brokerMobile', isEqualTo: oldBrokerKey)
          .get();

      if (globalSaudasSnap.docs.isNotEmpty) {
        final globalBatch = SafeBatchRunner(_db);
        for (var doc in globalSaudasSnap.docs) {
          await globalBatch.update(doc.reference, {
            'brokerMobile': newBrokerKey,
            'brokerKey': newBrokerKey,
            'brokerFirmName': newBrokerFirmName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await globalBatch.commit();
      }

      // D. Migrate Notifications sub-collection
      final notifsSnap = await oldBrokerRef.collection('notifications').get();
      if (notifsSnap.docs.isNotEmpty) {
        final notifBatch = SafeBatchRunner(_db);
        for (var doc in notifsSnap.docs) {
          await notifBatch.set(
            newBrokerRef.collection('notifications').doc(doc.id),
            doc.data(),
            SetOptions(merge: true),
          );
          await notifBatch.delete(doc.reference);
        }
        await notifBatch.commit();
      }

      debugPrint(
          '📦 Successfully moved all saudas and parties to brokers/$newBrokerKey');
    } catch (e) {
      debugPrint('❌ Error migrating broker sub-collections: $e');
    }
  }

  /// Updates transaction records when a Buyer or Seller changes their contact number.
  static Future<void> _transferAllAssociatedSaudas({
    required String oldMobile,
    required String newMobile,
    required String newName,
    required String section,
  }) async {
    try {
      final saudaBatch = SafeBatchRunner(_db);
      bool hasUpdates = false;

      if (section == 'BUYER') {
        final query = await _db
            .collection('saudas')
            .where('buyerMobile', isEqualTo: oldMobile)
            .get();
        for (var doc in query.docs) {
          await saudaBatch.update(doc.reference, {
            'buyerMobile': newMobile,
            'buyer': newName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      } else if (section == 'SELLER') {
        final query = await _db
            .collection('saudas')
            .where('sellerMobile', isEqualTo: oldMobile)
            .get();
        for (var doc in query.docs) {
          await saudaBatch.update(doc.reference, {
            'sellerMobile': newMobile,
            'seller': newName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      if (hasUpdates) {
        await saudaBatch.commit();
        debugPrint('🚚 CloudSync: Migrated transaction records to $newMobile');
      }
    } catch (e) {
      debugPrint('❌ CloudSync _transferAllAssociatedSaudas error: $e');
    }
  }

  // =============================================================
  // 2. ISOLATED BROKER PARTIES (brokers/{brokerKey}/parties)
  // =============================================================

  /// Saves a buyer or seller privately inside the broker's own sub-collection and personal folder.
  static Future<void> saveBrokerParty({
    required String brokerKey,
    required Map<String, dynamic> partyData,
  }) async {
    try {
      await ensureAuthSession();
      final cleanBroker = cleanMobileNumber(brokerKey).isNotEmpty
          ? cleanMobileNumber(brokerKey)
          : brokerKey.trim();
      final String partyMobile = cleanMobileNumber(partyData['mobile']?.toString());
      final String docId = partyMobile.isNotEmpty
          ? partyMobile
          : ((partyData['mobile'] ?? '').toString().trim().isNotEmpty
              ? partyData['mobile'].toString().trim()
              : DateTime.now().millisecondsSinceEpoch.toString());

      final payload = {
        ...partyData,
        'brokerKey': cleanBroker,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save directly into the user's single personal folder: users/{cleanBroker}/parties/{docId}
      // Ensure the parent users/{cleanBroker} document exists so it never becomes a phantom document
      final partyBatch = _db.batch();
      partyBatch.set(
        _db.collection(FirestoreCollections.users).doc(cleanBroker),
        {
          'mobile': cleanBroker,
          'role': 'broker',
          'section': 'BROKER',
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      partyBatch.set(
        _db.collection(FirestoreCollections.users).doc(cleanBroker).collection(FirestoreCollections.userParties).doc(docId),
        payload,
        SetOptions(merge: true),
      );
      await partyBatch.commit().timeout(const Duration(seconds: 8));

      debugPrint('✅ CloudSync: Saved party under users/$cleanBroker/parties/$docId');
    } catch (e) {
      debugPrint('❌ CloudSync saveBrokerParty error: $e');
    }
  }

  /// Streams only the parties (buyers & sellers) belonging to this specific broker.
  static Stream<List<Map<String, dynamic>>> streamBrokerParties(
    String brokerKey, {
    String? type,
  }) {
    final cleanBroker = cleanMobileNumber(brokerKey).isNotEmpty
        ? cleanMobileNumber(brokerKey)
        : brokerKey.trim();
    Query query = _db
        .collection(FirestoreCollections.users)
        .doc(cleanBroker)
        .collection(FirestoreCollections.userParties);

    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type.trim());
    }

    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) =>
                  {...doc.data() as Map<String, dynamic>, 'id': doc.id})
              .toList(),
        );
  }

  /// Deletes a party from the broker's private directory and personal folder.
  static Future<void> deleteBrokerParty(
      String brokerKey, String partyDocOrMobile) async {
    try {
      await ensureAuthSession();
      final cleanBroker = cleanMobileNumber(brokerKey).isNotEmpty
          ? cleanMobileNumber(brokerKey)
          : brokerKey.trim();
      final partyId = partyDocOrMobile.trim();

      await _db
          .collection(FirestoreCollections.users)
          .doc(cleanBroker)
          .collection(FirestoreCollections.userParties)
          .doc(partyId)
          .delete()
          .timeout(const Duration(seconds: 6));

      // Clean from legacy brokers collection if present
      try {
        await _db
            .collection(FirestoreCollections.brokers)
            .doc(cleanBroker)
            .collection(FirestoreCollections.parties)
            .doc(partyId)
            .delete()
            .timeout(const Duration(seconds: 4));
      } catch (_) {}

      // Also clean any unauthenticated contact stub in root users collection
      try {
        final cleanParty = cleanMobileNumber(partyId);
        final stubRef = _db.collection(FirestoreCollections.users).doc(cleanParty.isNotEmpty ? cleanParty : partyId);
        final snap = await stubRef.get();
        if (snap.exists) {
          final data = snap.data() ?? {};
          final pwd = (data['password'] ?? data['pin'] ?? '').toString().trim();
          final role = (data['role'] ?? data['section'] ?? '').toString().toLowerCase();
          if (role != 'broker' && (pwd.isEmpty || pwd == 'N/A')) {
            await stubRef.delete();
          }
        }
      } catch (_) {}

      debugPrint('🗑️ CloudSync: Deleted party $partyId from users/$cleanBroker/parties');
    } catch (e) {
      debugPrint('❌ CloudSync deleteBrokerParty error: $e');
    }
  }

  // =============================================================
    /// Updates a Buyer/Seller party inside a Broker's personal directory AND seamlessly
  /// migrates the party's user account, password, contracts, and past saudas across Firestore.
  /// Prevents duplicate / blank accounts from being spawned when mobile numbers are updated.
  static Future<void> updateBrokerPartyAndMigrateAccount({
    required String brokerKey,
    required String oldMobile,
    required Map<String, dynamic> updatedPartyData,
  }) async {
    try {
      await ensureAuthSession();
      final cleanBroker = cleanMobileNumber(brokerKey).isNotEmpty
          ? cleanMobileNumber(brokerKey)
          : brokerKey.trim();
      final cleanOldMob = cleanMobileNumber(oldMobile).isNotEmpty
          ? cleanMobileNumber(oldMobile)
          : oldMobile.trim();
      final cleanNewMob = cleanMobileNumber(updatedPartyData['mobile']?.toString()).isNotEmpty
          ? cleanMobileNumber(updatedPartyData['mobile']?.toString())
          : (updatedPartyData['mobile'] ?? '').toString().trim();
      final String newName = (updatedPartyData['name'] ?? '').toString().trim();
      final String newAddress = (updatedPartyData['address'] ?? '').toString().trim();
      final String partyType = (updatedPartyData['type'] ?? 'Buyer').toString().trim();
      final String role = partyType.toLowerCase() == 'seller' ? 'seller' : 'buyer';
      final String section = partyType.toUpperCase() == 'SELLER' ? 'SELLER' : 'BUYER';

      // Fetch existing party data before update to detect changes
      Map<String, dynamic> oldPartyRecord = {};
      if (cleanOldMob.isNotEmpty) {
        try {
          final oldPartySnap = await _db
              .collection(FirestoreCollections.users)
              .doc(cleanBroker)
              .collection(FirestoreCollections.userParties)
              .doc(cleanOldMob)
              .get();
          if (oldPartySnap.exists && oldPartySnap.data() is Map) {
            oldPartyRecord = Map<String, dynamic>.from(oldPartySnap.data() as Map);
          }
        } catch (_) {}
      }

      // 1. Update party inside broker's personal folder: users/{cleanBroker}/parties/
      if (cleanOldMob.isNotEmpty && cleanOldMob != cleanNewMob) {
        await deleteBrokerParty(cleanBroker, cleanOldMob);
      }
      await saveBrokerParty(brokerKey: cleanBroker, partyData: updatedPartyData);

      // 2. If mobile number changed, migrate the user account
      if (cleanOldMob.isNotEmpty && cleanNewMob.isNotEmpty && cleanOldMob != cleanNewMob) {
        debugPrint('🚚 CloudSync: Migrating party user account from $cleanOldMob to $cleanNewMob');

        // Fetch old user account data to preserve password, pin, status, etc.
        Map<String, dynamic> oldData = {};
        try {
          final oldSnap = await _db.collection(FirestoreCollections.users).doc(cleanOldMob).get();
          if (oldSnap.exists && oldSnap.data() is Map) {
            oldData = Map<String, dynamic>.from(oldSnap.data() as Map);
          }
        } catch (_) {}

        // Also check legacy section documents
        try {
          final oldBuyerSnap = await _db.collection(FirestoreCollections.users).doc('BUYER_$cleanOldMob').get();
          if (oldBuyerSnap.exists && oldBuyerSnap.data() is Map) {
            oldData.addAll(Map<String, dynamic>.from(oldBuyerSnap.data() as Map));
          }
        } catch (_) {}
        try {
          final oldSellerSnap = await _db.collection(FirestoreCollections.users).doc('SELLER_$cleanOldMob').get();
          if (oldSellerSnap.exists && oldSellerSnap.data() is Map) {
            oldData.addAll(Map<String, dynamic>.from(oldSellerSnap.data() as Map));
          }
        } catch (_) {}

        // Resolve password so it is never lost or shown as N/A
        String resolvedPassword = (oldData['password'] ?? oldData['pin'] ?? '').toString().trim();
        if (resolvedPassword.isEmpty) {
          try {
            final localAcc = AccountService.findExistingAccount(cleanOldMob) ??
                AccountService.findExistingAccount(oldMobile.trim());
            if (localAcc != null && localAcc.password.trim().isNotEmpty) {
              resolvedPassword = localAcc.password.trim();
            }
          } catch (_) {}
        }

        final bool isGenuineRegisteredAccount =
            resolvedPassword.isNotEmpty && resolvedPassword != 'N/A';

        final batch = _db.batch();
        final newPersonalRef = _db.collection(FirestoreCollections.users).doc(cleanNewMob);
        final oldPersonalRef = _db.collection(FirestoreCollections.users).doc(cleanOldMob);

        if (isGenuineRegisteredAccount) {
          // Genuinely registered user account with password: migrate account doc
          final updatePayload = {
            ...oldData,
            'mobile': cleanNewMob,
            'name': newName.isNotEmpty ? newName : (oldData['name'] ?? 'Party $cleanNewMob'),
            'address': newAddress.isNotEmpty ? newAddress : (oldData['address'] ?? ''),
            'role': role,
            'section': section,
            'account_status': oldData['account_status'] ?? 'active',
            'updated_at': FieldValue.serverTimestamp(),
            'password': resolvedPassword,
          };

          batch.set(newPersonalRef, updatePayload, SetOptions(merge: true));
          batch.delete(oldPersonalRef);
        } else {
          // Party contact ONLY (no password): NEVER create a root user account in 'users'!
          // And purge any unauthenticated stubs left behind from 'users' root collection.
          debugPrint('🛡️ CloudSync: Party $cleanNewMob is a broker contact without credentials. Not creating root user doc.');
          batch.delete(oldPersonalRef);
          try {
            final newSnap = await newPersonalRef.get();
            if (newSnap.exists) {
              final newSnapData = newSnap.data() ?? {};
              final newPwd = (newSnapData['password'] ?? newSnapData['pin'] ?? '').toString().trim();
              if (newPwd.isEmpty || newPwd == 'N/A') {
                batch.delete(newPersonalRef);
              }
            }
          } catch (_) {}
        }

        batch.delete(_db.collection(FirestoreCollections.users).doc('BUYER_$cleanOldMob'));
        batch.delete(_db.collection(FirestoreCollections.users).doc('SELLER_$cleanOldMob'));
        batch.delete(_db.collection(FirestoreCollections.users).doc('BUYER_$cleanNewMob'));
        batch.delete(_db.collection(FirestoreCollections.users).doc('SELLER_$cleanNewMob'));

        await batch.commit().timeout(const Duration(seconds: 10));

        // Update local AccountService only if this was an actual registered account
        if (isGenuineRegisteredAccount) {
          try {
            final localAcc = AccountService.findExistingAccount(cleanOldMob) ??
                AccountService.findExistingAccount(oldMobile.trim());
            if (localAcc != null) {
              localAcc.mobile = cleanNewMob;
              if (newName.isNotEmpty) localAcc.name = newName;
              if (newAddress.isNotEmpty) localAcc.address = newAddress;
              if (resolvedPassword.isNotEmpty) localAcc.password = resolvedPassword;
              AccountService.updateAccountWithOldCredentials(
                oldMobile: cleanOldMob,
                oldEmail: localAcc.email,
                updatedAccount: localAcc,
              );
            }
          } catch (_) {}
        }

        // Migrate personal subcollections (records, notifications, parties, subscriptions)
        await _migratePersonalFolderSubCollections(
          oldMobile: cleanOldMob,
          newMobile: cleanNewMob,
          newName: newName,
        );

        // Update all associated global saudas in collection 'saudas'
        await _transferAllAssociatedSaudasAcrossRoles(
          oldMobile: cleanOldMob,
          newMobile: cleanNewMob,
          newName: newName,
        );

        // Update sauda records in broker's personal folder: users/{cleanBroker}/records
        // AND mirror immediately into global saudas collection
        try {
          final brokerRecordsSnap = await _db
              .collection(FirestoreCollections.users)
              .doc(cleanBroker)
              .collection(FirestoreCollections.userRecords)
              .get();
          if (brokerRecordsSnap.docs.isNotEmpty) {
            final bBatch = SafeBatchRunner(_db);
            bool hasBrokerUpdates = false;
            for (var doc in brokerRecordsSnap.docs) {
              final d = SaudaEncryptionService.decryptSauda(doc.data());
              Map<String, dynamic> updates = {};
              final dBuyerClean = cleanMobileNumber(d['buyerMobile']?.toString());
              final dBuyerRaw = (d['buyerMobile'] ?? '').toString().trim();
              if (dBuyerClean == cleanOldMob || dBuyerRaw == cleanOldMob || dBuyerRaw == oldMobile.trim()) {
                updates['buyerMobile'] = cleanNewMob;
                if (newName.isNotEmpty) updates['buyer'] = newName;
              }
              final dSellerClean = cleanMobileNumber(d['sellerMobile']?.toString());
              final dSellerRaw = (d['sellerMobile'] ?? '').toString().trim();
              if (dSellerClean == cleanOldMob || dSellerRaw == cleanOldMob || dSellerRaw == oldMobile.trim()) {
                updates['sellerMobile'] = cleanNewMob;
                if (newName.isNotEmpty) updates['seller'] = newName;
              }
              if (updates.isNotEmpty) {
                final merged = {...d, ...updates, 'updatedAt': FieldValue.serverTimestamp()};
                final encrypted = SaudaEncryptionService.encryptSauda(merged);
                await bBatch.set(doc.reference, encrypted, SetOptions(merge: true));
                // Also mirror update to global saudas collection
                await bBatch.set(
                  _db.collection(FirestoreCollections.saudas).doc(doc.id),
                  encrypted,
                  SetOptions(merge: true),
                );
                // Also mirror to legacy broker collection if present
                try {
                  await bBatch.set(
                    _db.collection(FirestoreCollections.brokers).doc(cleanBroker).collection(FirestoreCollections.saudas).doc(doc.id),
                    encrypted,
                    SetOptions(merge: true),
                  );
                } catch (_) {}
                hasBrokerUpdates = true;
              }
            }
            if (hasBrokerUpdates) {
              await bBatch.commit();
            }
          }
        } catch (e) {
          debugPrint('CloudSync: broker userRecords update warning: $e');
        }

        debugPrint('✅ CloudSync: Successfully migrated party account from $cleanOldMob to $cleanNewMob');
      }

      // Send Telegram notification if party's mobile, name, or email/gmail was updated by broker
      final String oldPartyName = (oldPartyRecord['name'] ?? '').toString().trim();
      final String oldPartyEmail = (oldPartyRecord['email'] ?? '').toString().trim().toLowerCase();
      final String newEmail = (updatedPartyData['email'] ?? '').toString().trim().toLowerCase();

      final bool mobileChanged = cleanOldMob.isNotEmpty &&
          cleanNewMob.isNotEmpty &&
          cleanOldMob != cleanNewMob;
      final bool nameChanged = oldPartyName.isNotEmpty &&
          newName.isNotEmpty &&
          oldPartyName.toLowerCase() != newName.toLowerCase();
      final bool emailChanged = oldPartyEmail.isNotEmpty &&
          newEmail.isNotEmpty &&
          oldPartyEmail != newEmail;

      if (mobileChanged || nameChanged || emailChanged) {
        TelegramNotificationService.notifyProfileUpdated(
          section: '$section (Party)',
          oldMobile: cleanOldMob,
          newMobile: cleanNewMob,
          oldName: oldPartyName,
          newName: newName,
          oldEmail: oldPartyEmail,
          newEmail: newEmail,
          address: newAddress,
          updatedBy: 'Broker $cleanBroker (Party List)',
        );
      }
    } catch (e) {
      debugPrint('❌ CloudSync updateBrokerPartyAndMigrateAccount error: $e');
    }
  }

  /// Updates all sauda documents in global collection 'saudas' where either buyerMobile
  /// or sellerMobile matches the old mobile number.
  static Future<void> _transferAllAssociatedSaudasAcrossRoles({
    required String oldMobile,
    required String newMobile,
    required String newName,
  }) async {
    try {
      final cleanOld = cleanMobileNumber(oldMobile).isNotEmpty ? cleanMobileNumber(oldMobile) : oldMobile.trim();
      final cleanNew = cleanMobileNumber(newMobile).isNotEmpty ? cleanMobileNumber(newMobile) : newMobile.trim();

      final saudaBatch = SafeBatchRunner(_db);
      bool hasUpdates = false;
      final Set<String> updatedDocIds = {};

      // Check Buyer deals by cleanOld
      final buyerQuery = await _db
          .collection(FirestoreCollections.saudas)
          .where('buyerMobile', isEqualTo: cleanOld)
          .get();
      for (var doc in buyerQuery.docs) {
        if (!updatedDocIds.contains(doc.id)) {
          updatedDocIds.add(doc.id);
          await saudaBatch.update(doc.reference, {
            'buyerMobile': cleanNew,
            if (newName.isNotEmpty) 'buyer': newName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      // Check Buyer deals by raw oldMobile if different
      if (oldMobile.trim() != cleanOld) {
        final rawBuyerQuery = await _db
            .collection(FirestoreCollections.saudas)
            .where('buyerMobile', isEqualTo: oldMobile.trim())
            .get();
        for (var doc in rawBuyerQuery.docs) {
          if (!updatedDocIds.contains(doc.id)) {
            updatedDocIds.add(doc.id);
            await saudaBatch.update(doc.reference, {
              'buyerMobile': cleanNew,
              if (newName.isNotEmpty) 'buyer': newName,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            hasUpdates = true;
          }
        }
      }

      // Check Seller deals by cleanOld
      final sellerQuery = await _db
          .collection(FirestoreCollections.saudas)
          .where('sellerMobile', isEqualTo: cleanOld)
          .get();
      for (var doc in sellerQuery.docs) {
        if (!updatedDocIds.contains(doc.id)) {
          updatedDocIds.add(doc.id);
          await saudaBatch.update(doc.reference, {
            'sellerMobile': cleanNew,
            if (newName.isNotEmpty) 'seller': newName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasUpdates = true;
        }
      }

      // Check Seller deals by raw oldMobile if different
      if (oldMobile.trim() != cleanOld) {
        final rawSellerQuery = await _db
            .collection(FirestoreCollections.saudas)
            .where('sellerMobile', isEqualTo: oldMobile.trim())
            .get();
        for (var doc in rawSellerQuery.docs) {
          if (!updatedDocIds.contains(doc.id)) {
            updatedDocIds.add(doc.id);
            await saudaBatch.update(doc.reference, {
              'sellerMobile': cleanNew,
              if (newName.isNotEmpty) 'seller': newName,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            hasUpdates = true;
          }
        }
      }

      if (hasUpdates) {
        await saudaBatch.commit();
        debugPrint('🚚 CloudSync: Migrated ${updatedDocIds.length} sauda records to $cleanNew');
      }
    } catch (e) {
      debugPrint('❌ CloudSync _transferAllAssociatedSaudasAcrossRoles error: $e');
    }
  }

  // 3. ISOLATED BROKER SAUDAS (brokers/{brokerKey}/saudas)
  // =============================================================

  /// Saves a sauda across all personal folders (Broker, Buyer, Seller) and public registry.
  /// 1 User = 1 Personal Folder architecture: writes to users/{mobile}/records/{saudaId}.
  static Future<void> bookSauda({
    required Map<String, dynamic> saudaData,
    String? brokerKey,
  }) async {
    try {
      await ensureAuthSession();
      final key = getActiveBrokerKey(
          brokerKey ?? saudaData['brokerMobile']?.toString());
      final String saudaId =
          (saudaData['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
              .toString().trim();

      final String cleanBroker = cleanMobileNumber(key);
      final String cleanBuyer = cleanMobileNumber(saudaData['buyerMobile']?.toString());
      final String cleanSeller = cleanMobileNumber(saudaData['sellerMobile']?.toString());

      final saudaPayload = {
        ...saudaData,
        'id': saudaId,
        'brokerKey': key,
        'brokerMobile': cleanBroker.isNotEmpty ? cleanBroker : (saudaData['brokerMobile'] ?? key),
        'buyerMobile': cleanBuyer.isNotEmpty ? cleanBuyer : (saudaData['buyerMobile'] ?? ''),
        'sellerMobile': cleanSeller.isNotEmpty ? cleanSeller : (saudaData['sellerMobile'] ?? ''),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Encrypt sensitive trade details with AES-256 before saving to Firebase
      final encryptedPayload = SaudaEncryptionService.encryptSauda(saudaPayload);

      final batch = _db.batch();

      // 1. Personal Folder - Broker: users/{brokerMobile}/records/{saudaId}
      if (cleanBroker.isNotEmpty) {
        batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanBroker),
          {
            'mobile': cleanBroker,
            'name': (saudaData['brokerFirmName'] ?? saudaData['brokerName'] ?? 'Broker $cleanBroker').toString().trim(),
            'role': 'broker',
            'section': 'BROKER',
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanBroker).collection(FirestoreCollections.userRecords).doc(saudaId),
          encryptedPayload,
          SetOptions(merge: true),
        );
      }

      // 2. Global Registry Ledger: saudas/{saudaId}
      final globalSaudaRef = _db.collection(FirestoreCollections.saudas).doc(saudaId);
      batch.set(globalSaudaRef, encryptedPayload, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 8));
      debugPrint('🔒 CloudSync: Sauda $saudaId stored with AES-256 encryption in users/$cleanBroker/records');
    } catch (e) {
      debugPrint('❌ CloudSync bookSauda error: $e');
    }
  }

  /// Streams saudas belonging strictly to this broker's sub-collection.
  /// Automatically decrypts AES-256 encrypted records for display.
  static Stream<List<Map<String, dynamic>>> streamBrokerSaudas(
      String brokerKey) {
    final cleanBroker = cleanMobileNumber(brokerKey).isNotEmpty
        ? cleanMobileNumber(brokerKey)
        : brokerKey.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(cleanBroker)
        .collection(FirestoreCollections.userRecords)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SaudaEncryptionService.decryptSauda(doc.data()))
            .toList());
  }

  /// Updates a sauda both in the broker's folder, all personal folders, and the shared ledger.
  static Future<void> updateSauda(
    String saudaId,
    Map<String, dynamic> saudaData, {
    String? brokerKey,
  }) async {
    try {
      await ensureAuthSession();
      final cleanSaudaId = saudaId.trim();
      final key = getActiveBrokerKey(
          brokerKey ?? saudaData['brokerMobile']?.toString());
      final cleanBroker = cleanMobileNumber(key);

      String cleanBuyer = cleanMobileNumber(saudaData['buyerMobile']?.toString());
      String cleanSeller = cleanMobileNumber(saudaData['sellerMobile']?.toString());
      String oldCleanBuyer = '';
      String oldCleanSeller = '';

      try {
        final existingSnap = await _db.collection(FirestoreCollections.saudas).doc(cleanSaudaId).get();
        if (existingSnap.exists && existingSnap.data() != null) {
          final data = existingSnap.data()!;
          oldCleanBuyer = cleanMobileNumber(data['buyerMobile']?.toString());
          oldCleanSeller = cleanMobileNumber(data['sellerMobile']?.toString());
          if (cleanBuyer.isEmpty) cleanBuyer = oldCleanBuyer;
          if (cleanSeller.isEmpty) cleanSeller = oldCleanSeller;
        }
      } catch (_) {}

      final updatePayload = {
        ...saudaData,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Encrypt sensitive trade details with AES-256 before updating Firestore
      final encryptedPayload = SaudaEncryptionService.encryptSauda(updatePayload);

      final batch = _db.batch();
      final globalRef = _db.collection(FirestoreCollections.saudas).doc(cleanSaudaId);
      batch.set(globalRef, encryptedPayload, SetOptions(merge: true));

      if (cleanBroker.isNotEmpty) {
        batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanBroker).collection(FirestoreCollections.userRecords).doc(cleanSaudaId),
          encryptedPayload,
          SetOptions(merge: true),
        );
      }

      // Sync into new Buyer personal folder & cleanup from old Buyer folder if changed
      if (cleanBuyer.isNotEmpty) {
        batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanBuyer).collection(FirestoreCollections.userRecords).doc(cleanSaudaId),
          encryptedPayload,
          SetOptions(merge: true),
        );
      }
      if (oldCleanBuyer.isNotEmpty && oldCleanBuyer != cleanBuyer) {
        batch.delete(
          _db.collection(FirestoreCollections.users).doc(oldCleanBuyer).collection(FirestoreCollections.userRecords).doc(cleanSaudaId),
        );
      }

      // Sync into new Seller personal folder & cleanup from old Seller folder if changed
      if (cleanSeller.isNotEmpty) {
        batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanSeller).collection(FirestoreCollections.userRecords).doc(cleanSaudaId),
          encryptedPayload,
          SetOptions(merge: true),
        );
      }
      if (oldCleanSeller.isNotEmpty && oldCleanSeller != cleanSeller) {
        batch.delete(
          _db.collection(FirestoreCollections.users).doc(oldCleanSeller).collection(FirestoreCollections.userRecords).doc(cleanSaudaId),
        );
      }

      await batch.commit().timeout(const Duration(seconds: 8));
      debugPrint('✅ CloudSync: Sauda $cleanSaudaId updated across personal folders');
    } catch (e) {
      debugPrint('❌ CloudSync updateSauda error: $e');
    }
  }

  /// Deletes a sauda from all personal folders, the broker folder, and the shared ledger.
  static Future<void> deleteSauda(String saudaId, {String? brokerKey}) async {
    try {
      await ensureAuthSession();
      final cleanSaudaId = saudaId.trim();
      final key = getActiveBrokerKey(brokerKey);
      final cleanBroker = cleanMobileNumber(key);

      String cleanBuyer = '';
      String cleanSeller = '';

      try {
        final existingSnap = await _db.collection(FirestoreCollections.saudas).doc(cleanSaudaId).get();
        if (existingSnap.exists && existingSnap.data() != null) {
          final data = existingSnap.data()!;
          cleanBuyer = cleanMobileNumber(data['buyerMobile']?.toString());
          cleanSeller = cleanMobileNumber(data['sellerMobile']?.toString());
        }
      } catch (_) {}

      final batch = _db.batch();
      batch.delete(_db.collection(FirestoreCollections.saudas).doc(cleanSaudaId));

      if (cleanBroker.isNotEmpty) {
        batch.delete(_db.collection(FirestoreCollections.users).doc(cleanBroker).collection(FirestoreCollections.userRecords).doc(cleanSaudaId));
      }
      if (cleanBuyer.isNotEmpty && cleanBuyer != cleanBroker) {
        batch.delete(_db.collection(FirestoreCollections.users).doc(cleanBuyer).collection(FirestoreCollections.userRecords).doc(cleanSaudaId));
      }
      if (cleanSeller.isNotEmpty && cleanSeller != cleanBroker && cleanSeller != cleanBuyer) {
        batch.delete(_db.collection(FirestoreCollections.users).doc(cleanSeller).collection(FirestoreCollections.userRecords).doc(cleanSaudaId));
      }

      // Clean from legacy brokers collection if present
      try {
        batch.delete(_db.collection('brokers').doc(key).collection('saudas').doc(cleanSaudaId));
      } catch (_) {}

      await batch.commit().timeout(const Duration(seconds: 6));
      debugPrint('🗑️ CloudSync: Sauda $cleanSaudaId deleted from personal folders and global ledger');
    } catch (e) {
      debugPrint('❌ CloudSync deleteSauda error: $e');
      rethrow;
    }
  }

  /// Deletes a sauda directly from a specific user's personal records folder: users/{cleanMob}/records/{cleanId}
  static Future<void> deleteSaudaFromUserFolder({
    required String userMobile,
    required String saudaId,
  }) async {
    try {
      await ensureAuthSession();
      final cleanMob = cleanMobileNumber(userMobile);
      final rawMob = userMobile.trim();
      final cleanId = saudaId.replaceAll('#', '').trim();
      if (cleanId.isEmpty) return;

      final Set<String> targetPhones = {
        if (cleanMob.isNotEmpty) cleanMob,
        if (rawMob.isNotEmpty) rawMob,
      };

      for (final phone in targetPhones) {
        final recordsCol = _db
            .collection(FirestoreCollections.users)
            .doc(phone)
            .collection(FirestoreCollections.userRecords);

        // 1. Direct doc deletion (both cleanId and uppercase)
        try {
          await recordsCol.doc(cleanId).delete();
        } catch (_) {}
        if (cleanId != cleanId.toUpperCase()) {
          try {
            await recordsCol.doc(cleanId.toUpperCase()).delete();
          } catch (_) {}
        }

        // 2. Query any records where field 'id' matches cleanId or uppercase
        try {
          final querySnap = await recordsCol
              .where('id', isEqualTo: cleanId)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final doc in querySnap.docs) {
            await doc.reference.delete();
          }
        } catch (_) {}

        if (cleanId != cleanId.toUpperCase()) {
          try {
            final queryUpperSnap = await recordsCol
                .where('id', isEqualTo: cleanId.toUpperCase())
                .get()
                .timeout(const Duration(seconds: 4));
            for (final doc in queryUpperSnap.docs) {
              await doc.reference.delete();
            }
          } catch (_) {}
        }
      }
      debugPrint('🗑️ CloudSync: Sauda $cleanId deleted from user records for phones $targetPhones');
    } catch (e) {
      debugPrint('❌ CloudSync deleteSaudaFromUserFolder error: $e');
      rethrow;
    }
  }

  /// Searches for a sauda across Firestore by custom Sauda ID (exact, uppercase, or shortId).
  static Future<Map<String, dynamic>?> findSaudaById(String saudaId) async {
    try {
      await ensureAuthSession();
      final cleanId = saudaId.trim();
      if (cleanId.isEmpty) return null;

      // 1. Direct check in global saudas collection by ID
      final docDirect = await _db.collection(FirestoreCollections.saudas).doc(cleanId).get();
      if (docDirect.exists && docDirect.data() != null) {
        return SaudaEncryptionService.decryptSauda(docDirect.data()!);
      }

      // 2. Direct check in uppercase format
      final docUpper = await _db.collection(FirestoreCollections.saudas).doc(cleanId.toUpperCase()).get();
      if (docUpper.exists && docUpper.data() != null) {
        return SaudaEncryptionService.decryptSauda(docUpper.data()!);
      }

      // 3. Query global saudas where 'id' == cleanId or uppercase
      final q1 = await _db.collection(FirestoreCollections.saudas)
          .where('id', isEqualTo: cleanId)
          .limit(1)
          .get();
      if (q1.docs.isNotEmpty) {
        return SaudaEncryptionService.decryptSauda(q1.docs.first.data());
      }

      final q2 = await _db.collection(FirestoreCollections.saudas)
          .where('id', isEqualTo: cleanId.toUpperCase())
          .limit(1)
          .get();
      if (q2.docs.isNotEmpty) {
        return SaudaEncryptionService.decryptSauda(q2.docs.first.data());
      }

      // 4. Search across collection group of user records
      try {
        final cg = await _db.collectionGroup(FirestoreCollections.userRecords)
            .where('id', isEqualTo: cleanId.toUpperCase())
            .limit(1)
            .get();
        if (cg.docs.isNotEmpty) {
          return SaudaEncryptionService.decryptSauda(cg.docs.first.data());
        }
      } catch (_) {}

      return null;
    } catch (e) {
      debugPrint('CloudSync findSaudaById error: $e');
      return null;
    }
  }

  /// Links a sauda to a Buyer or Seller's personal records folder and updates confirmation.
  static Future<void> saveSaudaToUserRecords({
    required String userMobile,
    required String userName,
    required String userRole, // 'BUYER' or 'SELLER'
    required Map<String, dynamic> saudaData,
  }) async {
    try {
      await ensureAuthSession();
      final cleanUserMob = cleanMobileNumber(userMobile);
      final phone = cleanUserMob.isNotEmpty ? cleanUserMob : userMobile.trim();
      final saudaId = (saudaData['id'] ?? '').toString().trim();
      if (phone.isEmpty || saudaId.isEmpty) return;

      final updatedSauda = Map<String, dynamic>.from(saudaData);
      if (userRole == 'BUYER') {
        updatedSauda['buyerMobile'] = phone;
        if ((updatedSauda['buyer'] ?? '').toString().trim().isEmpty) {
          updatedSauda['buyer'] = userName;
        }
        updatedSauda['buyerConfirmed'] = true;
      } else if (userRole == 'SELLER') {
        updatedSauda['sellerMobile'] = phone;
        if ((updatedSauda['seller'] ?? '').toString().trim().isEmpty) {
          updatedSauda['seller'] = userName;
        }
        updatedSauda['sellerConfirmed'] = true;
      }
      updatedSauda['updatedAt'] = FieldValue.serverTimestamp();

      final batch = _db.batch();

      // 0. Only update parent user document IF it already exists as a genuine registered account with credentials.
      // NEVER create a password-less dummy account for an unregistered party in root 'users' collection!
      try {
        final userDocRef = _db.collection(FirestoreCollections.users).doc(phone);
        final userDocSnap = await userDocRef.get();
        if (userDocSnap.exists) {
          final existingData = userDocSnap.data() ?? {};
          final existingPwd = (existingData['password'] ?? existingData['pin'] ?? '').toString().trim();
          final role = (existingData['role'] ?? existingData['section'] ?? '').toString().toLowerCase();
          if (role == 'broker' || (existingPwd.isNotEmpty && existingPwd != 'N/A')) {
            batch.set(userDocRef, {
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            // It was an unauthenticated stub without credentials, purge it from root 'users'
            batch.delete(userDocRef);
          }
        }
      } catch (_) {}

      // Encrypt sensitive trade details with AES-256 before persisting
      final encryptedRecord = SaudaEncryptionService.encryptSauda(updatedSauda);

      // 1. Save to user's personal records: users/{phone}/records/{saudaId}
      final userRecordRef = _db.collection(FirestoreCollections.users)
          .doc(phone)
          .collection(FirestoreCollections.userRecords)
          .doc(saudaId);
      batch.set(userRecordRef, encryptedRecord, SetOptions(merge: true));

      // 2. Update global sauda document: saudas/{saudaId}
      final globalSaudaRef = _db.collection(FirestoreCollections.saudas).doc(saudaId);
      batch.set(globalSaudaRef, encryptedRecord, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 8));
      debugPrint('🔒 CloudSync: Sauda $saudaId saved with AES-256 encryption to $userRole $phone records');
    } catch (e) {
      debugPrint('CloudSync saveSaudaToUserRecords error: $e');
      rethrow;
    }
  }

  // =============================================================
  // 4. NOTIFICATIONS (brokers/{brokerKey}/notifications & global)
  // =============================================================

  /// Sends a notification into the target user's personal notifications folder, broker sub-collection, and global list.
  static Future<void> sendNotification({
    required String targetMobile,
    required String title,
    required String message,
    String? brokerKey,
  }) async {
    try {
      await ensureAuthSession();
      final String notifId = DateTime.now().millisecondsSinceEpoch.toString();
      final cleanTarget = cleanMobileNumber(targetMobile);
      final target = cleanTarget.isNotEmpty ? cleanTarget : targetMobile.trim();

      final payload = {
        'id': notifId,
        'targetMobile': target,
        'title': title,
        'message': message,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save directly into recipient's personal folder: users/{target}/notifications/{notifId}
      if (target.isNotEmpty) {
        final notifBatch = _db.batch();
        notifBatch.set(
          _db.collection(FirestoreCollections.users).doc(target),
          {
            'mobile': target,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        notifBatch.set(
          _db.collection(FirestoreCollections.users).doc(target).collection(FirestoreCollections.userNotifications).doc(notifId),
          payload,
        );
        await notifBatch.commit().timeout(const Duration(seconds: 8));
        debugPrint('✅ CloudSync: Notification saved under users/$target/notifications/$notifId');
      }
    } catch (e) {
      debugPrint('❌ CloudSync sendNotification error: $e');
    }
  }

  /// Streams notifications for this specific user from their personal folder: users/{mobile}/notifications
  static Stream<List<Map<String, dynamic>>> streamNotifications(
      String brokerKey) {
    final cleanKey = cleanMobileNumber(brokerKey).isNotEmpty
        ? cleanMobileNumber(brokerKey)
        : brokerKey.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(cleanKey)
        .collection(FirestoreCollections.userNotifications)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Clears notifications inside the user's personal notifications folder.
  static Future<void> clearNotifications(String brokerKey) async {
    try {
      final cleanKey = cleanMobileNumber(brokerKey).isNotEmpty
          ? cleanMobileNumber(brokerKey)
          : brokerKey.trim();
      final personalSnap = await _db
          .collection(FirestoreCollections.users)
          .doc(cleanKey)
          .collection(FirestoreCollections.userNotifications)
          .get();

      final batch = SafeBatchRunner(_db);
      for (var doc in personalSnap.docs) {
        await batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('🗑️ CloudSync: Cleared notifications for users/$cleanKey');
    } catch (e) {
      debugPrint('❌ CloudSync clearNotifications error: $e');
    }
  }

  // =============================================================
  // 5. LEGACY & SHARED QUERIES (Preserved for compatibility)
  // =============================================================

  static Stream<List<Map<String, dynamic>>> streamBuyerSaudas(
      String buyerMobile) {
    final cleanMob = cleanMobileNumber(buyerMobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : buyerMobile.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userRecords)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final raw = doc.data();
              final data = SaudaEncryptionService.decryptSauda(raw);
              final existingId = (data['id'] ?? '').toString().trim();
              if (existingId.isEmpty) {
                data['id'] = doc.id;
              }
              data['docId'] = doc.id;
              return data;
            }).toList());
  }

  static Stream<List<Map<String, dynamic>>> streamSellerSaudas(
      String sellerMobile) {
    final cleanMob = cleanMobileNumber(sellerMobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : sellerMobile.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userRecords)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final raw = doc.data();
              final data = SaudaEncryptionService.decryptSauda(raw);
              final existingId = (data['id'] ?? '').toString().trim();
              if (existingId.isEmpty) {
                data['id'] = doc.id;
              }
              data['docId'] = doc.id;
              return data;
            }).toList());
  }

  /// Saves all broker profile fields (PAN, License, Bank, Dalali, Logo, Jins, WhatsApp Template).
  static Future<void> saveBrokerProfile(
    String brokerMobile,
    Map<String, dynamic> profileData,
  ) async {
    try {
      await ensureAuthSession();
      final cleanKey = cleanMobileNumber(brokerMobile).isNotEmpty
          ? cleanMobileNumber(brokerMobile)
          : brokerMobile.trim();
      if (cleanKey.isEmpty) return;

      final firmName = (profileData['firmName'] ?? profileData['name'] ?? '')
          .toString()
          .trim();

      // Save directly to the single personal folder: users/{cleanKey}
      await _db.collection(FirestoreCollections.users).doc(cleanKey).set({
        ...profileData,
        'brokerKey': cleanKey,
        'name': firmName,
        'firmName': firmName,
        'phone': cleanKey,
        'mobile': cleanKey,
        'role': 'broker',
        'section': 'BROKER',
        'isActive': true,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
      debugPrint('✅ CloudSync: Saved broker profile in users/$cleanKey');
    } catch (e) {
      debugPrint('❌ CloudSync saveBrokerProfile error: $e');
    }
  }

  static Future<Map<String, dynamic>?> getBrokerProfile(
      String brokerMobile) async {
    try {
      await ensureAuthSession();
      final cleanKey = cleanMobileNumber(brokerMobile).isNotEmpty
          ? cleanMobileNumber(brokerMobile)
          : brokerMobile.trim();
      if (cleanKey.isEmpty) return null;

      // 1. Read directly from single personal folder users/{cleanKey}
      final userDoc = await _db
          .collection(FirestoreCollections.users)
          .doc(cleanKey)
          .get()
          .timeout(const Duration(seconds: 6));
      if (userDoc.exists && userDoc.data() != null) {
        return userDoc.data();
      }

      // 2. Fallback to legacy brokers/{cleanKey}
      final legacyDoc = await _db
          .collection('brokers')
          .doc(cleanKey)
          .get()
          .timeout(const Duration(seconds: 6));
      return legacyDoc.data();
    } catch (e) {
      debugPrint('CloudSyncService getBrokerProfile error: $e');
      return null;
    }
  }

  /// Updates a global portal service lock switch in app_config/services and service_switches/config
  static Future<void> setServiceSwitch(String serviceKey, bool isEnabled) async {
    try {
      await ensureAuthSession();
      final data = {
        serviceKey: isEnabled,
        'updated_at': FieldValue.serverTimestamp(),
      };
      await _db.collection('app_config').doc('services').set(data, SetOptions(merge: true));
      try {
        await _db.collection('service_switches').doc('config').set(data, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Secondary service_switches sync warning: $e');
      }
      debugPrint('✅ CloudSync: Updated service switch "$serviceKey" to $isEnabled');
    } catch (e) {
      debugPrint('CloudSyncService setServiceSwitch error: $e');
      rethrow;
    }
  }

  /// Batch update multiple service switches at once
  static Future<void> setAllServiceSwitches(Map<String, bool> switches) async {
    try {
      await ensureAuthSession();
      final Map<String, dynamic> data = Map<String, dynamic>.from(switches);
      data['updated_at'] = FieldValue.serverTimestamp();
      await _db.collection('app_config').doc('services').set(data, SetOptions(merge: true));
      try {
        await _db.collection('service_switches').doc('config').set(data, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Secondary service_switches batch sync warning: $e');
      }
      debugPrint('✅ CloudSync: Updated all service switches: $switches');
    } catch (e) {
      debugPrint('CloudSyncService setAllServiceSwitches error: $e');
      rethrow;
    }
  }

  static Stream<Map<String, dynamic>> streamServiceSwitches() async* {
    try {
      await ensureAuthSession();
    } catch (_) {}

    yield* FirebaseFirestore.instance
        .collection('app_config')
        .doc('services')
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (data == null) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    }).handleError((e) {
      debugPrint('streamServiceSwitches error: $e');
      return <String, dynamic>{};
    });
  }

  /// Safely extracts and parses renewal or expiration date from a user document or subscription map.
  static DateTime? parseRenewalDate(dynamic rawData) {
    if (rawData == null) return null;
    dynamic raw;
    if (rawData is Map) {
      final sub = rawData['subscription'] is Map
          ? (rawData['subscription'] as Map)
          : null;
      raw = sub?['renewal_date'] ??
          sub?['valid_until'] ??
          rawData['subscription_renewal_date'] ??
          rawData['subscription_valid_until'] ??
          rawData['subscriptionExpiry'] ??
          rawData['expiryDate'];
    } else {
      raw = rawData;
    }
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  /// Activates a user subscription with an explicit renewal date and saves history receipt.
  static Future<void> activateSubscriptionWithRenewal({
    required String section,
    required String mobile,
    required DateTime renewalDate,
    String plan = '1 Month',
    String note = '',
    String activatedBy = 'ADMIN',
  }) async {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    final renewalIso = renewalDate.toIso8601String();

    final updateData = {
      'is_locked': false,
      'is_blocked': false,
      'subscription_due': false,
      'lock_reason': '',
      'account_status': 'active',
      'subscription_plan': plan,
      'subscription_valid_until': renewalIso,
      'subscription_renewal_date': renewalIso,
      'subscription.is_locked': false,
      'subscription.subscription_due': false,
      'subscription.lock_reason': '',
      'subscription.status': 'active',
      'subscription.plan': plan,
      'subscription.valid_until': renewalIso,
      'subscription.renewal_date': renewalIso,
      'subscription.activated_at': FieldValue.serverTimestamp(),
      'subscription.note': note,
      'subscription.updated_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    // Update single personal folder document ONLY
    await _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .set(updateData, SetOptions(merge: true));

    // Save receipt to subcollection
    try {
      await _db
          .collection(FirestoreCollections.users)
          .doc(phone)
          .collection(FirestoreCollections.userSubscriptions)
          .add({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'plan': plan,
        'renewalDate': renewalIso,
        'validUntil': renewalIso,
        'startDate': DateTime.now().toIso8601String(),
        'status': 'active',
        'note': note,
        'activatedBy': activatedBy,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving subscription receipt: $e');
    }

    // Save in-app notification for the user
    try {
      final dateStr =
          '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}';
      await sendNotification(
        targetMobile: phone,
        title: '🎉 सदस्यता सक्रिय (Subscription Activated)',
        message:
            'आपकी $plan सदस्यता सक्रिय कर दी गई है। नवीनीकरण तारीख (Renewal Date): $dateStr है।',
      );
    } catch (_) {}

    // Delete legacy duplicate section document if it exists
    try {
      final legacyRef = _db
          .collection(FirestoreCollections.users)
          .doc('${section.toUpperCase()}_$phone');
      final snap = await legacyRef.get();
      if (snap.exists) {
        await legacyRef.delete();
      }
    } catch (_) {}
  }

  static Future<void> setLockStatus({
    required String section,
    required String mobile,
    required bool isLocked,
    String reason = 'subscription_due',
  }) async {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();

    final updateData = {
      'is_locked': isLocked,
      'is_blocked': isLocked,
      'subscription_due': isLocked,
      'lock_reason': reason,
      'account_status': isLocked ? 'locked' : 'active',
      'subscription.is_locked': isLocked,
      'subscription.subscription_due': isLocked,
      'subscription.lock_reason': reason,
      'subscription.status': isLocked ? 'locked' : 'active',
      'subscription.updated_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    // Update single personal folder document ONLY
    await _db.collection(FirestoreCollections.users).doc(phone).set(updateData, SetOptions(merge: true));

    // Delete legacy duplicate section document if it exists
    try {
      final legacyRef = _db.collection(FirestoreCollections.users).doc('${section.toUpperCase()}_$phone');
      final snap = await legacyRef.get();
      if (snap.exists) {
        await legacyRef.delete();
      }
    } catch (_) {}
  }

  /// Sets or clears subscription due status for a user account on their single personal folder document.
  static Future<void> setSubscriptionDueStatus({
    required String section,
    required String mobile,
    required bool isDue,
  }) async {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();

    final updateData = {
      'subscription_due': isDue,
      'is_locked': isDue,
      'account_status': isDue ? 'locked' : 'active',
      'subscription.subscription_due': isDue,
      'subscription.is_locked': isDue,
      'subscription.status': isDue ? 'due' : 'active',
      'subscription.updated_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    // Update single personal folder document ONLY
    await _db.collection(FirestoreCollections.users).doc(phone).set(updateData, SetOptions(merge: true));

    // Delete legacy duplicate section document if it exists
    try {
      final legacyRef = _db.collection(FirestoreCollections.users).doc('${section.toUpperCase()}_$phone');
      final snap = await legacyRef.get();
      if (snap.exists) {
        await legacyRef.delete();
      }
    } catch (_) {}
  }

  static Future<void> deleteAccount(String mobile, {String? section}) async {
    await purgeUserAccount(mobile, section: section);
  }

  static Future<void> purgeUserAccount(String mobile, {String? section}) async {
    try {
      await ensureAuthSession();
      final clean = cleanMobileNumber(mobile).isNotEmpty
          ? cleanMobileNumber(mobile)
          : mobile.trim();
      if (clean.isEmpty) return;

      final batch = _db.batch();

      if (section != null && section.isNotEmpty) {
        batch.delete(
            _db.collection(FirestoreCollections.users).doc('${section.toUpperCase()}_$clean'));
      } else {
        const sections = [
          'BROKER',
          'BUYER',
          'SELLER',
          'BILL GENERATOR',
          'DEFAULT'
        ];
        for (final sec in sections) {
          batch.delete(_db.collection(FirestoreCollections.users).doc('${sec}_$clean'));
        }
      }

      // Delete all personal subcollection documents (records, parties, notifications, subscriptions)
      final subcollections = [
        FirestoreCollections.userRecords,
        FirestoreCollections.userParties,
        FirestoreCollections.userNotifications,
        FirestoreCollections.userSubscriptions,
      ];
      for (final sub in subcollections) {
        final snap = await _db
            .collection(FirestoreCollections.users)
            .doc(clean)
            .collection(sub)
            .get();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
      }

      final query =
          await _db.collection(FirestoreCollections.users).where('mobile', isEqualTo: clean).get();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_db.collection(FirestoreCollections.brokers).doc(clean));
      batch.delete(_db.collection(FirestoreCollections.users).doc(clean));
      await batch.commit();
    } catch (e) {
      debugPrint('CloudSyncService purgeUserAccount error: $e');
    }
  }

  static Future<void> deleteUserAccount({
    required String section,
    required String mobile,
  }) async =>
      purgeUserAccount(mobile, section: section);

  // =============================================================
  // 6. USER PERSONAL FOLDER APIs (1 User = 1 Personal Folder)
  // =============================================================

  /// Streams all trade contracts / transactions directly from the user's personal folder:
  /// `users/{mobile}/records`
  static Stream<List<Map<String, dynamic>>> streamUserPersonalRecords(String mobile) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userRecords)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SaudaEncryptionService.decryptSauda(d.data()))
            .toList());
  }

  /// Streams all notifications directly from the user's personal folder:
  /// `users/{mobile}/notifications`
  static Stream<List<Map<String, dynamic>>> streamUserPersonalNotifications(String mobile) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userNotifications)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// Streams all parties directly from the user's personal folder:
  /// `users/{mobile}/parties`
  static Stream<List<Map<String, dynamic>>> streamUserPersonalParties(String mobile, {String? type}) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    Query query = _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userParties);
    if (type != null && type.isNotEmpty) {
      query = query.where('type', isEqualTo: type.trim());
    }
    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) =>
                  {...doc.data() as Map<String, dynamic>, 'id': doc.id})
              .toList(),
        );
  }

  /// Fetches a user's entire personal folder root document: `users/{mobile}`
  static Future<Map<String, dynamic>?> getUserPersonalFolder(String mobile) async {
    try {
      await ensureAuthSession();
      final cleanMob = cleanMobileNumber(mobile);
      final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
      final doc = await _db.collection(FirestoreCollections.users).doc(phone).get();
      return doc.data();
    } catch (e) {
      debugPrint('CloudSync getUserPersonalFolder error: $e');
      return null;
    }
  }

  /// Records a subscription payment receipt inside the user's personal subscriptions subcollection
  /// and updates their personal folder subscription status.
  static Future<void> recordSubscriptionPayment({
    required String mobile,
    required String plan,
    required double amount,
    String paymentMode = 'UPI',
    String? referenceId,
    int durationDays = 30,
    String? section,
  }) async {
    try {
      await ensureAuthSession();
      final cleanMob = cleanMobileNumber(mobile);
      final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
      final String receiptId = 'SUB_${DateTime.now().millisecondsSinceEpoch}';
      final validUntil = DateTime.now().add(Duration(days: durationDays));

      final receiptPayload = {
        'id': receiptId,
        'mobile': phone,
        'plan': plan.toUpperCase(),
        'amount': amount,
        'paymentMode': paymentMode,
        'referenceId': referenceId ?? '',
        'status': 'ACTIVE',
        'durationDays': durationDays,
        'validFrom': FieldValue.serverTimestamp(),
        'validUntil': Timestamp.fromDate(validUntil),
        'createdAt': FieldValue.serverTimestamp(),
      };

      final batch = _db.batch();

      // 1. Personal folder subscription receipt: users/{phone}/subscriptions/{receiptId}
      final receiptRef = _db
          .collection(FirestoreCollections.users)
          .doc(phone)
          .collection(FirestoreCollections.userSubscriptions)
          .doc(receiptId);
      batch.set(receiptRef, receiptPayload);

      // 2. Update user root document subscription map
      final subscriptionUpdate = {
        'subscription': {
          'status': 'active',
          'plan': plan.toUpperCase(),
          'is_locked': false,
          'subscription_due': false,
          'valid_until': Timestamp.fromDate(validUntil),
          'last_receipt_id': receiptId,
          'last_amount': amount,
          'last_payment_mode': paymentMode,
          'updated_at': FieldValue.serverTimestamp(),
        },
        'is_locked': false,
        'subscription_due': false,
        'account_status': 'active',
        'updated_at': FieldValue.serverTimestamp(),
      };

      batch.set(_db.collection(FirestoreCollections.users).doc(phone), subscriptionUpdate, SetOptions(merge: true));

      if (section != null && section.isNotEmpty) {
        batch.delete(_db.collection(FirestoreCollections.users).doc('${section.toUpperCase()}_$phone'));
      }

      await batch.commit();
      debugPrint('💳 CloudSync: Subscription payment recorded for users/$phone/subscriptions/$receiptId');
    } catch (e) {
      debugPrint('❌ CloudSync recordSubscriptionPayment error: $e');
    }
  }

  /// Streams real-time subscription details from the user's personal folder: `users/{mobile}`
  static Stream<Map<String, dynamic>> streamUserPersonalSubscription(String mobile) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    return _db.collection(FirestoreCollections.users).doc(phone).snapshots().map((doc) {
      if (!doc.exists) return <String, dynamic>{};
      final data = doc.data() ?? {};
      final sub = data['subscription'] as Map<String, dynamic>?;
      return sub ?? {
        'status': data['subscription_due'] == true ? 'due' : 'active',
        'plan': data['subscriptionPlan'] ?? 'STANDARD',
        'is_locked': data['is_locked'] ?? false,
        'subscription_due': data['subscription_due'] ?? false,
      };
    });
  }

  /// Streams subscription history receipts from the user's personal folder: `users/{mobile}/subscriptions`
  static Stream<List<Map<String, dynamic>>> streamUserSubscriptionHistory(String mobile) {
    final cleanMob = cleanMobileNumber(mobile);
    final phone = cleanMob.isNotEmpty ? cleanMob : mobile.trim();
    return _db
        .collection(FirestoreCollections.users)
        .doc(phone)
        .collection(FirestoreCollections.userSubscriptions)
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.data()).toList());
  }

  /// One-time sync / migration helper that aggregates existing saudas, parties,
  /// and notifications into the user's personal folder `users/{mobile}/`
  static Future<void> syncUserPersonalFolder(String mobile) async {
    try {
      await ensureAuthSession();
      final cleanMob = cleanMobileNumber(mobile);
      if (cleanMob.isEmpty) return;

      final batch = SafeBatchRunner(_db);
      bool hasChanges = false;

      final brokerSaudas = await _db.collection(FirestoreCollections.brokers).doc(cleanMob).collection(FirestoreCollections.brokerSaudas).get();
      for (final doc in brokerSaudas.docs) {
        await batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanMob).collection(FirestoreCollections.userRecords).doc(doc.id),
          doc.data(),
          SetOptions(merge: true),
        );
        hasChanges = true;
      }

      // 2. Sync broker parties if broker
      final brokerParties = await _db.collection(FirestoreCollections.brokers).doc(cleanMob).collection(FirestoreCollections.parties).get();
      for (final doc in brokerParties.docs) {
        await batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanMob).collection(FirestoreCollections.userParties).doc(doc.id),
          doc.data(),
          SetOptions(merge: true),
        );
        hasChanges = true;
      }

      // 3. Sync notifications
      final notifications = await _db.collection(FirestoreCollections.notifications).where('targetMobile', isEqualTo: cleanMob).get();
      for (final doc in notifications.docs) {
        await batch.set(
          _db.collection(FirestoreCollections.users).doc(cleanMob).collection(FirestoreCollections.userNotifications).doc(doc.id),
          doc.data(),
          SetOptions(merge: true),
        );
        hasChanges = true;
      }

      if (hasChanges) {
        await batch.commit();
        debugPrint('✅ CloudSync: Successfully synced legacy records into personal folder users/$cleanMob');
      }
    } catch (e) {
      debugPrint('CloudSync syncUserPersonalFolder error: $e');
    }
  }

  /// Migrates personal folder subcollections (records, notifications, parties, subscriptions)
  /// when a user changes their mobile phone number.
  static Future<void> _migratePersonalFolderSubCollections({
    required String oldMobile,
    required String newMobile,
    String? newName,
  }) async {
    try {
      final cleanOld = cleanMobileNumber(oldMobile).isNotEmpty ? cleanMobileNumber(oldMobile) : oldMobile.trim();
      final cleanNew = cleanMobileNumber(newMobile).isNotEmpty ? cleanMobileNumber(newMobile) : newMobile.trim();

      final oldUserRef = _db.collection(FirestoreCollections.users).doc(cleanOld);
      final newUserRef = _db.collection(FirestoreCollections.users).doc(cleanNew);

      // A. Records
      final recordsSnap = await oldUserRef.collection(FirestoreCollections.userRecords).get();
      if (recordsSnap.docs.isNotEmpty) {
        final batch = SafeBatchRunner(_db);
        for (var doc in recordsSnap.docs) {
          final recData = SaudaEncryptionService.decryptSauda(doc.data());
          final bClean = cleanMobileNumber(recData['buyerMobile']?.toString());
          final sClean = cleanMobileNumber(recData['sellerMobile']?.toString());
          if (bClean == cleanOld || recData['buyerMobile']?.toString() == oldMobile.trim()) {
            recData['buyerMobile'] = cleanNew;
            if (newName != null && newName.isNotEmpty) recData['buyer'] = newName;
          }
          if (sClean == cleanOld || recData['sellerMobile']?.toString() == oldMobile.trim()) {
            recData['sellerMobile'] = cleanNew;
            if (newName != null && newName.isNotEmpty) recData['seller'] = newName;
          }
          recData['updatedAt'] = FieldValue.serverTimestamp();
          final encryptedRec = SaudaEncryptionService.encryptSauda(recData);

          await batch.set(
            newUserRef.collection(FirestoreCollections.userRecords).doc(doc.id),
            encryptedRec,
            SetOptions(merge: true),
          );
          await batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // B. Notifications
      final notifsSnap = await oldUserRef.collection(FirestoreCollections.userNotifications).get();
      if (notifsSnap.docs.isNotEmpty) {
        final batch = SafeBatchRunner(_db);
        for (var doc in notifsSnap.docs) {
          await batch.set(
            newUserRef.collection(FirestoreCollections.userNotifications).doc(doc.id),
            {...doc.data(), 'targetMobile': newMobile},
            SetOptions(merge: true),
          );
          await batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // C. Parties
      final partiesSnap = await oldUserRef.collection(FirestoreCollections.userParties).get();
      if (partiesSnap.docs.isNotEmpty) {
        final batch = SafeBatchRunner(_db);
        for (var doc in partiesSnap.docs) {
          await batch.set(
            newUserRef.collection(FirestoreCollections.userParties).doc(doc.id),
            doc.data(),
            SetOptions(merge: true),
          );
          await batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // D. Subscriptions
      final subsSnap = await oldUserRef.collection(FirestoreCollections.userSubscriptions).get();
      if (subsSnap.docs.isNotEmpty) {
        final batch = SafeBatchRunner(_db);
        for (var doc in subsSnap.docs) {
          await batch.set(
            newUserRef.collection(FirestoreCollections.userSubscriptions).doc(doc.id),
            {...doc.data(), 'mobile': newMobile},
            SetOptions(merge: true),
          );
          await batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('CloudSync _migratePersonalFolderSubCollections error: $e');
    }
  }

  /// Rearranges and cleans all Firestore user collections into the canonical architecture:
  /// "1 User = 1 Personal Folder": `users/{cleanMobile}` (10-digit clean mobile number).
  ///
  /// Actions performed:
  /// 1. Finds all legacy prefixed documents (e.g. `users/BROKER_9893000000`, `users/BUYER_...`).
  /// 2. Migrates their fields & subcollections into the canonical `users/{cleanMobile}`.
  /// 3. Deletes the legacy prefixed documents.
  /// 4. Ensures parent doc is never a phantom/virtual document in Firebase console.
  /// 5. Consolidates broker profile and firm settings into `users/{cleanMobile}`.
  /// 6. Returns a summary map with statistics.
  static Future<Map<String, int>> rearrangeAndCleanFirestoreCollections() async {
    int totalScanned = 0;
    int prefixedMigrated = 0;
    int phantomFixed = 0;
    int brokersConsolidated = 0;
    int stubsPurged = 0;
    int legacySaudasEncrypted = 0;
    int errorsEncountered = 0;

    try {
      await ensureAuthSession();

      // Step 1: Scan all documents in the 'users' collection
      final usersSnap = await _db.collection(FirestoreCollections.users).get();
      totalScanned = usersSnap.docs.length;

      // Group docs by canonical clean mobile
      final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groupedByClean = {};

      for (final doc in usersSnap.docs) {
        final docId = doc.id;
        final data = doc.data();
        final rawMob = (data['mobile'] ?? data['phone'] ?? '').toString();
        String cleanMob = cleanMobileNumber(rawMob);
        if (cleanMob.isEmpty) {
          cleanMob = cleanMobileNumber(docId.split('_').last);
        }
        if (cleanMob.isEmpty) {
          cleanMob = docId; // fallback if not a phone number
        }

        groupedByClean.putIfAbsent(cleanMob, () => []).add(doc);
      }

      // Process each user group
      for (final entry in groupedByClean.entries) {
        final cleanMob = entry.key;
        final docsList = entry.value;

        // Find canonical doc if exists, or legacy docs
        QueryDocumentSnapshot<Map<String, dynamic>>? canonicalDoc;
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> legacyDocs = [];

        for (final d in docsList) {
          if (d.id == cleanMob) {
            canonicalDoc = d;
          } else {
            legacyDocs.add(d);
          }
        }

        // Merge all legacy data into canonical
        final Map<String, dynamic> mergedData = {};
        if (canonicalDoc != null) {
          mergedData.addAll(canonicalDoc.data());
        }

        for (final leg in legacyDocs) {
          final legData = leg.data();
          legData.forEach((k, v) {
            if (v != null &&
                (!mergedData.containsKey(k) ||
                    mergedData[k] == null ||
                    (mergedData[k] is String && (mergedData[k] as String).isEmpty))) {
              mergedData[k] = v;
            }
          });
        }

        // Check if this document represents a genuine registered user account
        String pwd = (mergedData['password'] ?? mergedData['pin'] ?? '').toString().trim();
        if (pwd.isEmpty || pwd == 'N/A') {
          try {
            final localAcc = AccountService.findExistingAccount(cleanMob);
            if (localAcc != null && localAcc.password.trim().isNotEmpty) {
              pwd = localAcc.password.trim();
              mergedData['password'] = pwd;
            }
          } catch (_) {}
        }
        final role = (mergedData['role'] ?? mergedData['section'] ?? '').toString().toLowerCase();
        final isBroker = role == 'broker' || cleanMob.startsWith('BROKER_');
        final bool isGenuineAccount = (pwd.isNotEmpty && pwd != 'N/A') || isBroker;

        final canonicalRef = _db.collection(FirestoreCollections.users).doc(cleanMob);

        if (!isGenuineAccount) {
          // This is an unauthenticated party contact stub (e.g. PAGAL / 9000000000)
          // It was saved in 'users' root collection without login credentials.
          // Purge canonical doc and legacy stubs from 'users' collection!
          debugPrint('🧹 Purging unauthenticated contact stub from users: $cleanMob (${mergedData['name']})');
          if (canonicalDoc != null) {
            await canonicalRef.delete();
          }
          for (final leg in legacyDocs) {
            try { await leg.reference.delete(); } catch (_) {}
          }
          stubsPurged++;
          continue;
        }

        // Ensure essential fields
        mergedData['mobile'] = cleanMob;
        if ((mergedData['name'] ?? '').toString().trim().isEmpty) {
          mergedData['name'] = 'MANDI USER';
        }
        if ((mergedData['role'] ?? '').toString().trim().isEmpty) {
          mergedData['role'] = mergedData['section'] ?? 'BROKER';
        }
        mergedData['status'] = mergedData['status'] ?? 'active';
        mergedData['cleaned_at'] = FieldValue.serverTimestamp();

        // Write canonical doc
        await canonicalRef.set(mergedData, SetOptions(merge: true));

        // Migrate subcollections from legacy docs to canonical
        for (final leg in legacyDocs) {
          for (final subColl in [
            FirestoreCollections.userRecords,
            FirestoreCollections.userParties,
            FirestoreCollections.userNotifications,
            FirestoreCollections.userSubscriptions,
          ]) {
            try {
              final subSnap = await leg.reference.collection(subColl).get();
              if (subSnap.docs.isNotEmpty) {
                final subBatch = SafeBatchRunner(_db);
                for (final subDoc in subSnap.docs) {
                  final targetSubRef = canonicalRef.collection(subColl).doc(subDoc.id);
                  await subBatch.set(targetSubRef, subDoc.data(), SetOptions(merge: true));
                  await subBatch.delete(subDoc.reference);
                }
                await subBatch.commit();
              }
            } catch (_) {}
          }

          // Delete legacy doc
          try {
            await leg.reference.delete();
            prefixedMigrated++;
          } catch (_) {
            errorsEncountered++;
          }
        }

        phantomFixed++;
      }

      // Step 2: Consolidate 'brokers' collection into 'users'
      try {
        final brokersSnap = await _db.collection('brokers').get();
        for (final bDoc in brokersSnap.docs) {
          final bKey = cleanMobileNumber(bDoc.id).isNotEmpty
              ? cleanMobileNumber(bDoc.id)
              : bDoc.id;
          final bData = bDoc.data();

          // Merge broker profile fields into canonical users/{bKey}
          await _db.collection(FirestoreCollections.users).doc(bKey).set({
            if (bData['firmName'] != null) 'firmName': bData['firmName'],
            if (bData['firmName'] != null) 'brokerFirmName': bData['firmName'],
            if (bData['address'] != null) 'address': bData['address'],
            if (bData['pan'] != null) 'pan': bData['pan'],
            if (bData['gst'] != null) 'gst': bData['gst'],
            if (bData['bankDetails'] != null) 'bankDetails': bData['bankDetails'],
            if (bData['defaultBuyerDalali'] != null)
              'defaultBuyerDalali': bData['defaultBuyerDalali'],
            if (bData['defaultSellerDalali'] != null)
              'defaultSellerDalali': bData['defaultSellerDalali'],
            'section': 'BROKER',
            'role': 'BROKER',
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          brokersConsolidated++;
        }
      } catch (e) {
        debugPrint('Broker consolidation warning: $e');
      }

      // Step 3: Encrypt all legacy plaintext saudas in 'saudas' collection
      try {
        legacySaudasEncrypted += await encryptAllLegacyPlaintextSaudas();
      } catch (e) {
        debugPrint('Legacy saudas encryption error: $e');
      }

      debugPrint(
          '✅ Firestore rearrangement completed: scanned=$totalScanned, migrated=$prefixedMigrated, fixed=$phantomFixed, brokers=$brokersConsolidated, stubsPurged=$stubsPurged, encryptedSaudas=$legacySaudasEncrypted');
    } catch (e) {
      debugPrint('❌ CloudSync.rearrangeAndCleanFirestoreCollections error: $e');
      errorsEncountered++;
    }

    return {
      'scanned': totalScanned,
      'prefixed_migrated': prefixedMigrated,
      'phantom_fixed': phantomFixed,
      'brokers_consolidated': brokersConsolidated,
      'stubs_purged': stubsPurged,
      'legacy_saudas_encrypted': legacySaudasEncrypted,
      'errors': errorsEncountered,
    };
  }

  /// Purges all unauthenticated contact stubs from the root 'users' collection.
  /// When brokers create or edit buyer/seller contacts (parties), they belong in
  /// `users/{brokerKey}/parties/{partyId}`, NOT in the root `users` collection.
  /// Any root doc in 'users' that lacks credentials and is not a broker is deleted.
  static Future<int> purgeUnauthenticatedContactStubs() async {
    int purgedCount = 0;
    try {
      await ensureAuthSession();
      final usersSnap = await _db.collection(FirestoreCollections.users).get();
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final docId = doc.id;
        final rawPassword = (data['password'] ?? data['pin'] ?? '').toString().trim();
        final role = (data['role'] ?? data['section'] ?? '').toString().toLowerCase();
        final isBroker = role == 'broker' || docId.startsWith('BROKER_');

        // Check if account has credentials in local storage before purging
        bool hasLocalCreds = false;
        if (rawPassword.isEmpty || rawPassword == 'N/A') {
          final clean = cleanMobileNumber(docId);
          final localAcc = AccountService.findExistingAccount(clean.isNotEmpty ? clean : docId);
          if (localAcc != null && localAcc.password.trim().isNotEmpty) {
            hasLocalCreds = true;
            // Restore password to doc instead of purging
            await doc.reference.set({'password': localAcc.password.trim()}, SetOptions(merge: true));
          }
        }

        final bool hasValidCredentials = (rawPassword.isNotEmpty && rawPassword != 'N/A') || hasLocalCreds;

        // If not a broker and has no login credentials, it's a contact stub!
        if (!isBroker && !hasValidCredentials) {
          debugPrint('🧹 Purging unauthenticated contact stub from users: ${doc.id} (${data['name']})');
          await doc.reference.delete();
          purgedCount++;
        }
      }
    } catch (e) {
      debugPrint('Error purging unauthenticated contact stubs: $e');
    }
    return purgedCount;
  }

  /// Scans 'saudas' collection and encrypts any legacy plaintext records with AES-256.
  /// In Firebase Console, records will appear as encrypted ciphertext, protecting broker privacy.
  static Future<int> encryptAllLegacyPlaintextSaudas() async {
    int encryptedCount = 0;
    try {
      await ensureAuthSession();
      final saudasSnap = await _db.collection(FirestoreCollections.saudas).get();
      for (final doc in saudasSnap.docs) {
        final data = doc.data();
        if (data['isEncrypted'] != true || data['encryptedPayload'] == null) {
          final encrypted = SaudaEncryptionService.encryptSauda(data);
          // Overwrite with encrypted representation so plaintext fields are erased
          await doc.reference.set(encrypted);
          encryptedCount++;
        }
      }

      // Also scan personal user records (broker and party records)
      final userRecordsSnap = await _db.collectionGroup(FirestoreCollections.userRecords).get();
      for (final doc in userRecordsSnap.docs) {
        final data = doc.data();
        if (data['isEncrypted'] != true || data['encryptedPayload'] == null) {
          final encrypted = SaudaEncryptionService.encryptSauda(data);
          await doc.reference.set(encrypted);
          encryptedCount++;
        }
      }
    } catch (e) {
      debugPrint('Error encrypting legacy saudas: $e');
    }
    return encryptedCount;
  }
}
