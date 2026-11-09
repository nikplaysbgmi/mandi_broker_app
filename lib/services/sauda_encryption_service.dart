import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// High-Security AES-256 Encryption Service for Mandi Sauda Records.
/// Encrypts all sensitive trading data (Buyer, Seller, Mobile Numbers, Rate, Bags, Jins, Dalali)
/// before persisting to Firebase Cloud Firestore.
/// In Firebase Console, records appear as unreadable encrypted ciphertext.
class SaudaEncryptionService {
  // 256-bit AES Master Key
  static final enc.Key _masterKey =
      enc.Key.fromUtf8('MandiBrokerTradeSecurityKey2026!');

  // Fallback 128-bit Initialization Vector for legacy documents
  static final enc.IV _fixedIV = enc.IV.fromUtf8('MandiTradeIV2026');

  static final enc.Encrypter _encrypter =
      enc.Encrypter(enc.AES(_masterKey, mode: enc.AESMode.cbc));

  /// Root keys preserved in plaintext strictly for document ID lookup, timeline sorting, and FY filtering.
  /// All other fields (parties, phones, quantities, prices, commissions) are completely encrypted.
  static const Set<String> _preservedRootKeys = {
    'id',
    'date',
    'financialYear',
    'brokerKey',
    'createdAt',
    'updatedAt',
    'isEncrypted',
  };

  /// Encrypts sensitive fields in a sauda map into an encryptedPayload string
  /// with a cryptographically secure, randomized Initialization Vector (IV).
  static Map<String, dynamic> encryptSauda(Map<String, dynamic> raw) {
    try {
      final sensitive = <String, dynamic>{};
      final preserved = <String, dynamic>{};

      raw.forEach((key, value) {
        if (_preservedRootKeys.contains(key)) {
          preserved[key] = value;
        } else {
          // Convert DateTime to ISO string for JSON serialization
          if (value is DateTime) {
            sensitive[key] = value.toIso8601String();
          } else {
            sensitive[key] = value;
          }
        }
      });

      final jsonStr = jsonEncode(sensitive);
      // Generate a fresh, cryptographically secure 16-byte IV for every document
      final dynamicIV = enc.IV.fromSecureRandom(16);
      final encrypted = _encrypter.encrypt(jsonStr, iv: dynamicIV);

      return {
        ...preserved,
        'isEncrypted': true,
        'encryptedPayload': '${dynamicIV.base64}:${encrypted.base64}',
      };
    } catch (e) {
      debugPrint('SaudaEncryptionService encrypt error: $e');
      return raw;
    }
  }

  /// Decrypts a sauda document from Firestore back into its complete plain format.
  /// Handles both modern dynamic IV payloads and legacy fixed-IV documents seamlessly.
  static Map<String, dynamic> decryptSauda(Map<String, dynamic> docData) {
    try {
      if (docData['isEncrypted'] != true ||
          docData['encryptedPayload'] == null) {
        // Plaintext / unencrypted document
        return Map<String, dynamic>.from(docData);
      }

      final cipherText = docData['encryptedPayload'].toString();
      String decryptedJson;

      if (cipherText.contains(':')) {
        // Modern payload: "IV_BASE64:CIPHERTEXT_BASE64"
        final parts = cipherText.split(':');
        final iv = enc.IV.fromBase64(parts[0]);
        final actualCipher = parts.sublist(1).join(':');
        decryptedJson = _encrypter.decrypt64(actualCipher, iv: iv);
      } else {
        // Legacy document with fixed IV
        decryptedJson = _encrypter.decrypt64(cipherText, iv: _fixedIV);
      }

      final Map<String, dynamic> sensitive = jsonDecode(decryptedJson);

      final result = Map<String, dynamic>.from(docData);
      result.remove('encryptedPayload');
      result.addAll(sensitive);
      return result;
    } catch (e) {
      debugPrint('SaudaEncryptionService decrypt error: $e');
      return Map<String, dynamic>.from(docData);
    }
  }

  /// Checks if a document map is encrypted.
  static bool isEncrypted(Map<String, dynamic> docData) {
    return docData['isEncrypted'] == true &&
        docData['encryptedPayload'] != null;
  }
}
