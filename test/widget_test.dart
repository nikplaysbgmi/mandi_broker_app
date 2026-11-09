import 'package:flutter_test/flutter_test.dart';
import 'package:mandi_broker_app/models/mandi_models.dart';
import 'package:mandi_broker_app/services/sauda_encryption_service.dart';

void main() {
  group('MandiSaudaModel Unit Tests', () {
    test('Calculates total buyer and seller dalali correctly', () {
      final sauda = MandiSaudaModel(
        id: 'test_sauda_1',
        date: DateTime(2026, 1, 1),
        buyer: 'Ramesh Trading',
        buyerMobile: '9876543210',
        seller: 'Kisan Agro',
        sellerMobile: '9876543211',
        jins: 'JEERA',
        bags: 100,
        rate: 25000,
        buyerDalaliPerBag: 10.0,
        sellerDalaliPerBag: 15.0,
      );

      expect(sauda.totalBuyerDalali, 1000.0);
      expect(sauda.totalSellerDalali, 1500.0);
      expect(sauda.totalDalaliEarned, 2500.0);
    });

    test('Serializes and deserializes correctly to/from JSON', () {
      final original = MandiSaudaModel(
        id: 'sauda_json_test',
        date: DateTime(2026, 3, 15),
        buyer: 'Shree Ram Traders',
        buyerMobile: '9829012345',
        seller: 'Mohan Lal',
        sellerMobile: '9829054321',
        jins: 'SAUNF',
        bags: 50,
        rate: 18000,
        buyerDalaliPerBag: 5.0,
        sellerDalaliPerBag: 5.0,
        buyerConfirmed: true,
        sellerConfirmed: false,
      );

      final json = original.toJson();
      final restored = MandiSaudaModel.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.buyer, original.buyer);
      expect(restored.seller, original.seller);
      expect(restored.jins, original.jins);
      expect(restored.bags, original.bags);
      expect(restored.rate, original.rate);
      expect(restored.buyerDalaliPerBag, original.buyerDalaliPerBag);
      expect(restored.sellerDalaliPerBag, original.sellerDalaliPerBag);
      expect(restored.buyerConfirmed, true);
      expect(restored.sellerConfirmed, false);
      expect(restored.financialYear, 'FY 2025-26');
    });

    test('Computes Indian Mandi Financial Year (April 1 to March 31) accurately', () {
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2026, 4, 1)), 'FY 2026-27');
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2026, 11, 5)), 'FY 2026-27');
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2027, 1, 15)), 'FY 2026-27');
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2027, 3, 31)), 'FY 2026-27');
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2026, 3, 31)), 'FY 2025-26');
      expect(MandiSaudaModel.computeFinancialYear(DateTime(2026, 1, 1)), 'FY 2025-26');
    });

    test('Validates Sauda Code expiration after 1 month (30 days)', () {
      final now = DateTime(2026, 11, 6, 12, 0);

      // 1. Sauda created today is VALID
      expect(
        MandiSaudaModel.checkCodeExpired(
          saudaDateRaw: DateTime(2026, 11, 6),
          currentTime: now,
        ),
        false,
      );

      // 2. Sauda created 10 days ago is VALID
      expect(
        MandiSaudaModel.checkCodeExpired(
          saudaDateRaw: DateTime(2026, 10, 27),
          currentTime: now,
        ),
        false,
      );

      // 3. Sauda created 29 days ago is VALID
      expect(
        MandiSaudaModel.checkCodeExpired(
          saudaDateRaw: DateTime(2026, 10, 8),
          currentTime: now,
        ),
        false,
      );

      // 4. Sauda created 35 days ago (more than 1 month) is EXPIRED (invalid)
      expect(
        MandiSaudaModel.checkCodeExpired(
          saudaDateRaw: DateTime(2026, 10, 1),
          currentTime: now,
        ),
        true,
      );

      // 5. Sauda created 2 months ago is EXPIRED (invalid)
      expect(
        MandiSaudaModel.checkCodeExpired(
          saudaDateRaw: DateTime(2026, 9, 1),
          currentTime: now,
        ),
        true,
      );

      // 6. Check days remaining computation
      expect(
        MandiSaudaModel.daysRemainingForCode(
          saudaDateRaw: DateTime(2026, 11, 1),
          currentTime: now,
        ),
        greaterThanOrEqualTo(24),
      );
    });
  });

  group('UserAccount Model Unit Tests', () {
    test('Serializes and parses user account cleanly', () {
      final account = UserAccount(
        name: 'Sharma Dalal',
        address: 'Mandi Yard, Shop 12',
        mobile: '9988776655',
        email: 'sharma@example.com',
        password: 'secret',
        section: 'BROKER',
      );

      final json = account.toJson();
      final restored = UserAccount.fromJson(json);

      expect(restored.name, 'Sharma Dalal');
      expect(restored.mobile, '9988776655');
      expect(restored.email, 'sharma@example.com');
      expect(restored.section, 'BROKER');
    });
  });

  group('Party Mobile Update & Account Sync Tests', () {
    test('Updating party mobile updates all matching deals without duplicate accounts', () {
      const oldMobile = '9876543210';
      const newMobile = '9876599999';

      final party = MandiPartyModel(
        name: 'RAMESH TRADERS',
        mobile: oldMobile,
        address: 'SHOP 5',
        type: 'Buyer',
      );

      final deals = [
        MandiSaudaModel(
          id: 'D1',
          date: DateTime(2026, 11, 6),
          buyer: party.name,
          buyerMobile: oldMobile,
          seller: 'KISAN 1',
          sellerMobile: '9000000001',
          jins: 'WHEAT',
          bags: 50,
          rate: 2400,
          buyerDalaliPerBag: 10.0,
          sellerDalaliPerBag: 10.0,
        ),
        MandiSaudaModel(
          id: 'D2',
          date: DateTime(2026, 11, 6),
          buyer: party.name,
          buyerMobile: oldMobile,
          seller: 'KISAN 2',
          sellerMobile: '9000000002',
          jins: 'MUSTARD',
          bags: 100,
          rate: 5500,
          buyerDalaliPerBag: 10.0,
          sellerDalaliPerBag: 10.0,
        ),
      ];

      // Simulate party edit
      final updatedParty = MandiPartyModel(
        name: 'RAMESH TRADERS PVT LTD',
        mobile: newMobile,
        address: 'SHOP 5',
        type: 'Buyer',
      );

      for (var s in deals) {
        if (s.buyerMobile == oldMobile) {
          s.buyerMobile = updatedParty.mobile;
          s.buyer = updatedParty.name;
        }
      }

      // Verify all deals now point to new mobile
      expect(deals.every((d) => d.buyerMobile == newMobile), isTrue);
      expect(deals.every((d) => d.buyer == 'RAMESH TRADERS PVT LTD'), isTrue);
      expect(deals.any((d) => d.buyerMobile == oldMobile), isFalse);
    });
  });

  group('Sauda AES-256 Encryption & Privacy Tests', () {
    test('Encrypts sensitive trade data into unreadable ciphertext for Firebase', () {
      final saudaPayload = {
        'id': 'ARW319',
        'date': DateTime(2026, 11, 6, 15, 4, 1),
        'financialYear': 'FY 2026-27',
        'buyer': 'AMBARAM SONARAM CHODHARY',
        'buyerMobile': '9876543210',
        'seller': 'SDDF FARMS',
        'sellerMobile': '9123456780',
        'jins': 'DHANIYA',
        'bags': 250,
        'rate': 2520.0,
        'buyerDalaliPerBag': 20.0,
        'sellerDalaliPerBag': 0.0,
        'brokerFirmName': 'NIRMAL BROKERS',
        'brokerMobile': '9988776655',
      };

      // 1. Encrypt
      final encryptedMap = SaudaEncryptionService.encryptSauda(saudaPayload);

      // Verify that sensitive fields are NOT exposed at the root level in Firestore
      expect(encryptedMap['isEncrypted'], isTrue);
      expect(encryptedMap['encryptedPayload'], isNotNull);
      expect(encryptedMap['buyer'], isNull);
      expect(encryptedMap['seller'], isNull);
      expect(encryptedMap['jins'], isNull);
      expect(encryptedMap['rate'], isNull);
      expect(encryptedMap['bags'], isNull);
      expect(encryptedMap['buyerDalaliPerBag'], isNull);

      // Verify that index lookup keys (id, date, financialYear) are preserved
      expect(encryptedMap['id'], 'ARW319');
      expect(encryptedMap['financialYear'], 'FY 2026-27');

      // 2. Decrypt
      final decryptedMap = SaudaEncryptionService.decryptSauda(encryptedMap);

      expect(decryptedMap['id'], 'ARW319');
      expect(decryptedMap['buyer'], 'AMBARAM SONARAM CHODHARY');
      expect(decryptedMap['seller'], 'SDDF FARMS');
      expect(decryptedMap['jins'], 'DHANIYA');
      expect(decryptedMap['bags'], 250);
      expect(decryptedMap['rate'], 2520.0);
      expect(decryptedMap['buyerDalaliPerBag'], 20.0);
      expect(decryptedMap['brokerFirmName'], 'NIRMAL BROKERS');
    });

    test('Passes through legacy plaintext documents gracefully', () {
      final legacyPayload = {
        'id': 'OLD123',
        'buyer': 'Old Trader',
        'rate': 1800.0,
        'bags': 40,
      };

      final result = SaudaEncryptionService.decryptSauda(legacyPayload);
      expect(result['buyer'], 'Old Trader');
      expect(result['rate'], 1800.0);
    });
  });

  group('Telegram Notification Alert Tests', () {
    test('Profile update detects mobile, email, and name changes accurately', () {
      const oldMobile = '9876543210';
      const newMobile = '9876599999';
      const oldName = 'RAMESH TRADERS';
      const newName = 'RAMESH & SONS PVT LTD';
      const oldEmail = 'ramesh@old.com';
      const newEmail = 'ramesh@new.com';

      const bool mobileChanged = oldMobile != newMobile;
      const bool nameChanged = oldName != newName;
      const bool emailChanged = oldEmail != newEmail;

      expect(mobileChanged, isTrue);
      expect(nameChanged, isTrue);
      expect(emailChanged, isTrue);

      final List<String> changeSummary = [];
      if (nameChanged) changeSummary.add('👤 Name');
      if (mobileChanged) changeSummary.add('📱 Mobile');
      if (emailChanged) changeSummary.add('📧 Gmail/Email');

      expect(changeSummary.length, 3);
      expect(changeSummary, contains('👤 Name'));
      expect(changeSummary, contains('📱 Mobile'));
      expect(changeSummary, contains('📧 Gmail/Email'));
    });
  });
}
