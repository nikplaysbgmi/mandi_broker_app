import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class CloudSyncService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    final docId = '${section.trim().toUpperCase()}_${mobile.trim()}';
    return _db.collection('users').doc(docId).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data() ?? {};
      return data['is_locked'] == true ||
          data['is_blocked'] == true ||
          data['subscription_due'] == true ||
          data['account_status'] == 'locked' ||
          data['account_status'] == 'suspended';
    });
  }

  /// Checks if a user's subscription is overdue or administrative lock is active.
  /// Returns true if locked, or true if network unreachable.
  static Future<bool> isUserSubscriptionLocked(String identifier) async {
    try {
      final accountDoc = await getAccountByIdentifier(identifier);
      if (accountDoc == null) return false;
      return accountDoc['is_locked'] == true ||
          accountDoc['subscription_due'] == true ||
          accountDoc['is_blocked'] == true ||
          accountDoc['account_status'] == 'locked' ||
          accountDoc['account_status'] == 'suspended';
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
      final clean = mobile.trim();
      if (clean.isEmpty) return false;

      // 1. Direct check across known section document IDs in the users collection
      const sections = [
        'BROKER',
        'BUYER',
        'SELLER',
        'BILL GENERATOR',
        'DEFAULT'
      ];
      for (final section in sections) {
        final docId = '${section}_$clean';
        final doc = await _db.collection('users').doc(docId).get();
        if (doc.exists) return true;
      }

      // 2. Query check across users collection
      final userQuery = await _db
          .collection('users')
          .where('mobile', isEqualTo: clean)
          .limit(1)
          .get();
      if (userQuery.docs.isNotEmpty) return true;

      // 3. Verify broker root directory
      final brokerDoc = await _db.collection('brokers').doc(clean).get();
      if (brokerDoc.exists) return true;

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
  static Future<void> saveAccount(Map<String, dynamic> accountData) async {
    try {
      await ensureAuthSession();

      final String mobile = (accountData['mobile'] ?? '').toString().trim();
      final String email =
          (accountData['email'] ?? '').toString().trim().toLowerCase();
      final String password = (accountData['password'] ?? '').toString().trim();
      final String section =
          (accountData['section'] ?? 'DEFAULT').toString().trim().toUpperCase();
      if (mobile.isEmpty) return;

      final String docId = '${section}_$mobile';
      final docRef = _db.collection('users').doc(docId);
      final existingSnap = await docRef.get();

      final Map<String, dynamic> payload = {
        'name': (accountData['name'] ?? '').toString().trim(),
        'mobile': mobile,
        'email': email,
        'address': (accountData['address'] ?? '').toString().trim(),
        'password': password,
        'section': section,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // Preserve existing lock/subscription flags if document already exists
      if (!existingSnap.exists) {
        payload['is_locked'] = false;
        payload['subscription_due'] = false;
        payload['lock_reason'] = 'subscription_due';
        payload['account_status'] = 'active';
        payload['is_blocked'] = false;
        payload['created_at'] = FieldValue.serverTimestamp();
      }

      await docRef
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));

      // Also sync password to any other matching documents in 'users' with the same mobile
      if (password.isNotEmpty) {
        final mobileQuery = await _db
            .collection('users')
            .where('mobile', isEqualTo: mobile)
            .get();
        for (final doc in mobileQuery.docs) {
          if (doc.id != docId) {
            await doc.reference.update({
              'password': password,
              'updated_at': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // If registered as a broker, also initialize/update root broker folder
      if (section == 'BROKER') {
        await initializeBrokerAccount(
          brokerKey: mobile,
          brokerName: (accountData['name'] ?? '').toString(),
          phone: mobile,
          email: email,
          address: (accountData['address'] ?? '').toString(),
        );
        if (password.isNotEmpty) {
          await _db.collection('brokers').doc(mobile).set({
            'password': password,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      debugPrint(
          '✅ CloudSync: Registered user account saved under users/$docId');
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
      if (clean.isEmpty) return null;

      // 1. If section is specified and identifier is a mobile number, check direct doc ID first
      if (section != null &&
          section.trim().isNotEmpty &&
          !clean.contains('@')) {
        final directDoc = await _db
            .collection('users')
            .doc('${section.trim().toUpperCase()}_$clean')
            .get()
            .timeout(const Duration(seconds: 6));
        if (directDoc.exists && directDoc.data() != null) {
          return directDoc.data();
        }
      }

      // 2. Query by mobile
      final queryByMobile = await _db
          .collection('users')
          .where('mobile', isEqualTo: clean)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 6));

      if (queryByMobile.docs.isNotEmpty) {
        return queryByMobile.docs.first.data();
      }

      // 3. Query by email
      final queryByEmail = await _db
          .collection('users')
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
  }) async {
    try {
      await ensureAuthSession();

      final cleanOldMob = oldMobile.trim();
      final cleanNewMob = newMobile.trim();
      final cleanNewEmail = newEmail.trim().toLowerCase();
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

      // 2. Read existing user document
      final oldDocSnapshot = await _db.collection('users').doc(oldDocId).get();
      final oldData = oldDocSnapshot.data() ?? {};

      final batch = _db.batch();

      if (cleanNewMob != cleanOldMob) {
        // Create new user document & delete old
        final newDocRef = _db.collection('users').doc(newDocId);
        batch.set(
          newDocRef,
          {
            ...oldData,
            'name': newName.trim(),
            'mobile': cleanNewMob,
            'email': cleanNewEmail,
            'address': address.trim(),
            'section': cleanSection,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        final oldDocRef = _db.collection('users').doc(oldDocId);
        batch.delete(oldDocRef);

        // Migrate broker profile
        if (cleanSection == 'BROKER') {
          final oldBrokerRef = _db.collection('brokers').doc(cleanOldMob);
          final newBrokerRef = _db.collection('brokers').doc(cleanNewMob);
          final brokerSnap = await oldBrokerRef.get();

          if (brokerSnap.exists) {
            batch.set(
              newBrokerRef,
              {
                ...brokerSnap.data()!,
                'brokerKey': cleanNewMob,
                'name': newName.trim(),
                'firmName': newName.trim(),
                'phone': cleanNewMob,
                'mobile': cleanNewMob,
                'email': cleanNewEmail,
                'address': address.trim(),
                'updated_at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
            batch.delete(oldBrokerRef);
          }
        }

        await batch.commit().timeout(const Duration(seconds: 10));

        // 3. TRANSFER SUB-COLLECTIONS & GLOBAL TRANSACTIONS
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
        final docRef = _db.collection('users').doc(oldDocId);
        batch.set(
          docRef,
          {
            'name': newName.trim(),
            'email': cleanNewEmail,
            'address': address.trim(),
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (cleanSection == 'BROKER') {
          final brokerRef = _db.collection('brokers').doc(cleanOldMob);
          batch.set(
            brokerRef,
            {
              'name': newName.trim(),
              'firmName': newName.trim(),
              'email': cleanNewEmail,
              'address': address.trim(),
              'updated_at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit().timeout(const Duration(seconds: 10));
      }

      debugPrint('✅ CloudSync: Profile & data migrated cleanly to $newDocId');
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
        final partyBatch = _db.batch();
        for (var doc in partiesSnap.docs) {
          final data = doc.data();
          partyBatch.set(
            newBrokerRef.collection('parties').doc(doc.id),
            {...data, 'brokerKey': newBrokerKey},
            SetOptions(merge: true),
          );
          partyBatch.delete(doc.reference);
        }
        await partyBatch.commit();
      }

      // B. Migrate Saudas sub-collection & update global saudas
      final saudasSnap = await oldBrokerRef.collection('saudas').get();
      if (saudasSnap.docs.isNotEmpty) {
        final saudaBatch = _db.batch();
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
          saudaBatch.set(
            newBrokerRef.collection('saudas').doc(doc.id),
            updatedData,
            SetOptions(merge: true),
          );
          saudaBatch.delete(doc.reference);

          // 2. Update copy in global saudas
          saudaBatch.set(
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
        final globalBatch = _db.batch();
        for (var doc in globalSaudasSnap.docs) {
          globalBatch.update(doc.reference, {
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
        final notifBatch = _db.batch();
        for (var doc in notifsSnap.docs) {
          notifBatch.set(
            newBrokerRef.collection('notifications').doc(doc.id),
            doc.data(),
            SetOptions(merge: true),
          );
          notifBatch.delete(doc.reference);
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
      final saudaBatch = _db.batch();
      bool hasUpdates = false;

      if (section == 'BUYER') {
        final query = await _db
            .collection('saudas')
            .where('buyerMobile', isEqualTo: oldMobile)
            .get();
        for (var doc in query.docs) {
          saudaBatch.update(doc.reference, {
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
          saudaBatch.update(doc.reference, {
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

  /// Saves a buyer or seller privately inside the broker's own sub-collection.
  static Future<void> saveBrokerParty({
    required String brokerKey,
    required Map<String, dynamic> partyData,
  }) async {
    try {
      await ensureAuthSession();
      final cleanBroker = brokerKey.trim();
      final String partyMobile = (partyData['mobile'] ?? '').toString().trim();
      final String docId = partyMobile.isNotEmpty
          ? partyMobile
          : DateTime.now().millisecondsSinceEpoch.toString();

      await _db
          .collection('brokers')
          .doc(cleanBroker)
          .collection('parties')
          .doc(docId)
          .set({
        ...partyData,
        'brokerKey': cleanBroker,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));

      debugPrint(
          '✅ CloudSync: Saved private party under brokers/$cleanBroker/parties/$docId');
    } catch (e) {
      debugPrint('❌ CloudSync saveBrokerParty error: $e');
    }
  }

  /// Streams only the parties (buyers & sellers) belonging to this specific broker.
  static Stream<List<Map<String, dynamic>>> streamBrokerParties(
    String brokerKey, {
    String? type,
  }) {
    Query query =
        _db.collection('brokers').doc(brokerKey.trim()).collection('parties');

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

  /// Deletes a party from the broker's private directory.
  static Future<void> deleteBrokerParty(
      String brokerKey, String partyDocOrMobile) async {
    try {
      await ensureAuthSession();
      await _db
          .collection('brokers')
          .doc(brokerKey.trim())
          .collection('parties')
          .doc(partyDocOrMobile.trim())
          .delete()
          .timeout(const Duration(seconds: 6));
      debugPrint(
          '🗑️ CloudSync: Deleted party $partyDocOrMobile from brokers/$brokerKey');
    } catch (e) {
      debugPrint('❌ CloudSync deleteBrokerParty error: $e');
    }
  }

  // =============================================================
  // 3. ISOLATED BROKER SAUDAS (brokers/{brokerKey}/saudas)
  // =============================================================

  /// Saves a sauda into the broker's private sub-collection and updates public registry for buyers/sellers.
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
              .toString();

      final batch = _db.batch();

      // 1. Private to the broker folder: brokers/{brokerKey}/saudas/{saudaId}
      final brokerSaudaRef =
          _db.collection('brokers').doc(key).collection('saudas').doc(saudaId);

      batch.set(
        brokerSaudaRef,
        {
          ...saudaData,
          'brokerKey': key,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // 2. Global registry copy (so Buyers and Sellers can view their saudas in their portals)
      final globalSaudaRef = _db.collection('saudas').doc(saudaId);
      batch.set(
        globalSaudaRef,
        {
          ...saudaData,
          'brokerKey': key,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 8));
      debugPrint(
          '✅ CloudSync: Sauda stored under brokers/$key/saudas/$saudaId');
    } catch (e) {
      debugPrint('❌ CloudSync bookSauda error: $e');
    }
  }

  /// Streams saudas belonging strictly to this broker's sub-collection.
  static Stream<List<Map<String, dynamic>>> streamBrokerSaudas(
      String brokerKey) {
    return _db
        .collection('brokers')
        .doc(brokerKey.trim())
        .collection('saudas')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Updates a sauda both in the broker's folder and the shared ledger.
  static Future<void> updateSauda(
    String saudaId,
    Map<String, dynamic> saudaData, {
    String? brokerKey,
  }) async {
    try {
      await ensureAuthSession();
      final key = getActiveBrokerKey(
          brokerKey ?? saudaData['brokerMobile']?.toString());
      final batch = _db.batch();

      final brokerRef = _db
          .collection('brokers')
          .doc(key)
          .collection('saudas')
          .doc(saudaId.trim());
      final globalRef = _db.collection('saudas').doc(saudaId.trim());

      batch.set(
          brokerRef,
          {...saudaData, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
      batch.set(
          globalRef,
          {...saudaData, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('❌ CloudSync updateSauda error: $e');
    }
  }

  /// Deletes a sauda from the broker's folder and the shared ledger.
  static Future<void> deleteSauda(String saudaId, {String? brokerKey}) async {
    try {
      await ensureAuthSession();
      final key = getActiveBrokerKey(brokerKey);
      final batch = _db.batch();

      batch.delete(_db
          .collection('brokers')
          .doc(key)
          .collection('saudas')
          .doc(saudaId.trim()));
      batch.delete(_db.collection('saudas').doc(saudaId.trim()));

      await batch.commit().timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('❌ CloudSync deleteSauda error: $e');
    }
  }

  // =============================================================
  // 4. NOTIFICATIONS (brokers/{brokerKey}/notifications & global)
  // =============================================================

  /// Sends a notification into both the broker's sub-collection and global notifications collection.
  static Future<void> sendNotification({
    required String targetMobile,
    required String title,
    required String message,
    String? brokerKey,
  }) async {
    try {
      await ensureAuthSession();
      final String notifId = DateTime.now().millisecondsSinceEpoch.toString();
      final key = getActiveBrokerKey(brokerKey ?? targetMobile);
      final cleanTarget = targetMobile.trim();

      final payload = {
        'id': notifId,
        'targetMobile': cleanTarget,
        'title': title,
        'message': message,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      };

      final batch = _db.batch();
      batch.set(
        _db
            .collection('brokers')
            .doc(key)
            .collection('notifications')
            .doc(notifId),
        payload,
      );
      batch.set(
        _db.collection('notifications').doc(notifId),
        payload,
      );

      await batch.commit().timeout(const Duration(seconds: 8));

      debugPrint(
          '✅ CloudSync: Notification saved under brokers/$key/notifications/$notifId');
    } catch (e) {
      debugPrint('❌ CloudSync sendNotification error: $e');
    }
  }

  /// Streams notifications for this specific broker.
  static Stream<List<Map<String, dynamic>>> streamNotifications(
      String brokerKey) {
    return _db
        .collection('brokers')
        .doc(brokerKey.trim())
        .collection('notifications')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Clears notifications inside the broker's folder and global target list.
  static Future<void> clearNotifications(String brokerKey) async {
    try {
      final cleanKey = brokerKey.trim();
      final snapshot = await _db
          .collection('brokers')
          .doc(cleanKey)
          .collection('notifications')
          .get();

      final globalSnap = await _db
          .collection('notifications')
          .where('targetMobile', isEqualTo: cleanKey)
          .get();

      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      for (var doc in globalSnap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ CloudSync clearNotifications error: $e');
    }
  }

  // =============================================================
  // 5. LEGACY & SHARED QUERIES (Preserved for compatibility)
  // =============================================================

  static Stream<List<Map<String, dynamic>>> streamBuyerSaudas(
      String buyerMobile) {
    return _db
        .collection('saudas')
        .where('buyerMobile', isEqualTo: buyerMobile.trim())
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  static Stream<List<Map<String, dynamic>>> streamSellerSaudas(
      String sellerMobile) {
    return _db
        .collection('saudas')
        .where('sellerMobile', isEqualTo: sellerMobile.trim())
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Saves all broker profile fields (PAN, License, Bank, Dalali, Logo, Jins, WhatsApp Template).
  static Future<void> saveBrokerProfile(
    String brokerMobile,
    Map<String, dynamic> profileData,
  ) async {
    try {
      await ensureAuthSession();
      final cleanKey = brokerMobile.trim();
      if (cleanKey.isEmpty) return;

      final firmName = (profileData['firmName'] ?? profileData['name'] ?? '')
          .toString()
          .trim();

      await _db.collection('brokers').doc(cleanKey).set({
        ...profileData,
        'brokerKey': cleanKey,
        'name': firmName,
        'firmName': firmName,
        'phone': cleanKey,
        'mobile': cleanKey,
        'role': 'broker',
        'isActive': true,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('❌ CloudSync saveBrokerProfile error: $e');
    }
  }

  static Future<Map<String, dynamic>?> getBrokerProfile(
      String brokerMobile) async {
    try {
      await ensureAuthSession();
      final doc = await _db
          .collection('brokers')
          .doc(brokerMobile.trim())
          .get()
          .timeout(const Duration(seconds: 6));
      return doc.data();
    } catch (e) {
      debugPrint('CloudSyncService getBrokerProfile error: $e');
      return null;
    }
  }

  static Stream<Map<String, dynamic>> streamServiceSwitches() {
    return _db
        .collection('app_config')
        .doc('services')
        .snapshots()
        .map((doc) => doc.data() ?? {});
  }

  static Future<void> setLockStatus({
    required String section,
    required String mobile,
    required bool isLocked,
    String reason = 'subscription_due',
  }) async {
    final docId = '${section.toUpperCase()}_${mobile.trim()}';
    await _db.collection('users').doc(docId).update({
      'is_locked': isLocked,
      'is_blocked': isLocked,
      'subscription_due': isLocked,
      'lock_reason': reason,
      'account_status': isLocked ? 'locked' : 'active',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Sets or clears subscription due status for a user account.
  static Future<void> setSubscriptionDueStatus({
    required String section,
    required String mobile,
    required bool isDue,
  }) async {
    final docId = '${section.toUpperCase()}_${mobile.trim()}';
    await _db.collection('users').doc(docId).update({
      'subscription_due': isDue,
      'is_locked': isDue,
      'account_status': isDue ? 'locked' : 'active',
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteAccount(String mobile, {String? section}) async {
    await purgeUserAccount(mobile, section: section);
  }

  static Future<void> purgeUserAccount(String mobile, {String? section}) async {
    try {
      await ensureAuthSession();
      final clean = mobile.trim();
      if (clean.isEmpty) return;

      final batch = _db.batch();

      if (section != null && section.isNotEmpty) {
        batch.delete(
            _db.collection('users').doc('${section.toUpperCase()}_$clean'));
      } else {
        const sections = [
          'BROKER',
          'BUYER',
          'SELLER',
          'BILL GENERATOR',
          'DEFAULT'
        ];
        for (final sec in sections) {
          batch.delete(_db.collection('users').doc('${sec}_$clean'));
        }
      }

      final query =
          await _db.collection('users').where('mobile', isEqualTo: clean).get();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }

      batch.delete(_db.collection('brokers').doc(clean));
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
}
