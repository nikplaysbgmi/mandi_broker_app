import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TelegramNotificationService {
  // Replace with the token received from @BotFather
  static const String botToken = String.fromEnvironment('TELEGRAM_BOT_TOKEN',
      defaultValue: '8739454011:AAE47NWX6iU0_V42W3xMWO41fUp5W0KZghg');

  // Replace with your personal Chat ID received from @userinfobot
  static const String adminChatId = String.fromEnvironment(
      'TELEGRAM_ADMIN_CHAT_ID',
      defaultValue: '6226394875');

  /// HTML entity escaper to prevent Telegram 400 Bad Request parsing errors
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Sends instant registration alert to Telegram
  static Future<void> notifyNewRegistration({
    required String name,
    required String mobile,
    required String section,
    String? email,
    String? address,
  }) async {
    try {
      final String messageText = '''🚨 <b>NEW USER REGISTERED</b>

👤 <b>Name:</b> ${_escapeHtml(name)}
📱 <b>Mobile:</b> <code>$mobile</code>
🏷️ <b>Section:</b> ${_escapeHtml(section)}
📧 <b>Email:</b> ${_escapeHtml(email ?? 'N/A')}
📍 <b>Address:</b> ${_escapeHtml(address ?? 'N/A')}
⏰ <b>Time:</b> ${DateTime.now().toLocal().toString().split('.')[0]}''';

      final uri =
          Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': adminChatId,
              'text': messageText,
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('✅ Telegram registration alert sent successfully.');
      } else {
        debugPrint(
            '⚠️ Telegram API error status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Telegram notification exception: $e');
    }
  }

  /// Sends instant user profile / details update alert to Telegram
  static Future<void> notifyProfileUpdated({
    required String section,
    required String oldMobile,
    required String newMobile,
    String? oldName,
    required String newName,
    String? oldEmail,
    required String newEmail,
    String? address,
    String? updatedBy,
  }) async {
    try {
      final cleanOldMob = oldMobile.trim();
      final cleanNewMob = newMobile.trim();
      final cleanOldName = (oldName ?? '').trim();
      final cleanNewName = newName.trim();
      final cleanOldEmail = (oldEmail ?? '').trim().toLowerCase();
      final cleanNewEmail = newEmail.trim().toLowerCase();

      final bool mobileChanged = cleanOldMob.isNotEmpty &&
          cleanNewMob.isNotEmpty &&
          cleanOldMob != cleanNewMob;
      final bool nameChanged = cleanOldName.isNotEmpty &&
          cleanNewName.isNotEmpty &&
          cleanOldName.toLowerCase() != cleanNewName.toLowerCase();
      final bool emailChanged = cleanOldEmail.isNotEmpty &&
          cleanNewEmail.isNotEmpty &&
          cleanOldEmail != cleanNewEmail;

      final List<String> changeSummary = [];
      if (nameChanged) changeSummary.add('👤 Name');
      if (mobileChanged) changeSummary.add('📱 Mobile');
      if (emailChanged) changeSummary.add('📧 Gmail/Email');

      final buffer = StringBuffer();
      buffer.writeln('✏️ <b>USER DETAILS UPDATED</b>');
      if (changeSummary.isNotEmpty) {
        buffer.writeln('🔔 <b>Updated:</b> ${changeSummary.join(', ')}');
      }
      buffer.writeln('');
      buffer.writeln('🏷️ <b>Section:</b> ${_escapeHtml(section)}');

      // Name
      if (nameChanged) {
        buffer.writeln(
            '👤 <b>Name:</b> ${_escapeHtml(cleanOldName)} ➔ <b>${_escapeHtml(cleanNewName)}</b> ⚠️');
      } else {
        buffer.writeln('👤 <b>Name:</b> ${_escapeHtml(cleanNewName)}');
      }

      // Mobile
      if (mobileChanged) {
        buffer.writeln(
            '📱 <b>Mobile:</b> <code>$cleanOldMob</code> ➔ <code>$cleanNewMob</code> ⚠️');
      } else {
        buffer.writeln('📱 <b>Mobile:</b> <code>$cleanNewMob</code>');
      }

      // Gmail / Email
      if (emailChanged) {
        buffer.writeln(
            '📧 <b>Gmail / Email:</b> ${_escapeHtml(cleanOldEmail)} ➔ <b>${_escapeHtml(cleanNewEmail)}</b> ⚠️');
      } else if (cleanNewEmail.isNotEmpty) {
        buffer.writeln('📧 <b>Gmail / Email:</b> ${_escapeHtml(cleanNewEmail)}');
      } else {
        buffer.writeln('📧 <b>Gmail / Email:</b> N/A');
      }

      if (address != null && address.trim().isNotEmpty) {
        buffer.writeln('📍 <b>Address:</b> ${_escapeHtml(address.trim())}');
      }

      if (updatedBy != null && updatedBy.trim().isNotEmpty) {
        buffer.writeln('🛠️ <b>Action By:</b> ${_escapeHtml(updatedBy.trim())}');
      }

      buffer.writeln(
          '⏰ <b>Time:</b> ${DateTime.now().toLocal().toString().split('.')[0]}');

      final uri =
          Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': adminChatId,
              'text': buffer.toString(),
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('✅ Telegram profile update alert sent successfully.');
      } else {
        debugPrint(
            '⚠️ Telegram API error status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Telegram profile update alert exception: $e');
    }
  }

  /// Sends instant account deletion alert to Telegram
  static Future<void> notifyAccountDeleted({
    required String name,
    required String mobile,
    required String section,
    String? reason,
    String? deletedBy,
  }) async {
    try {
      final String messageText = '''🗑️ <b>ACCOUNT DELETED</b>

👤 <b>Name:</b> ${_escapeHtml(name)}
📱 <b>Mobile:</b> <code>$mobile</code>
🏷️ <b>Section:</b> ${_escapeHtml(section)}
🛠️ <b>Action By:</b> ${_escapeHtml(deletedBy ?? 'USER')}
📝 <b>Reason:</b> ${_escapeHtml(reason ?? 'Account closed')}
⏰ <b>Time:</b> ${DateTime.now().toLocal().toString().split('.')[0]}''';

      final uri =
          Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': adminChatId,
              'text': messageText,
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('✅ Telegram deletion alert sent successfully.');
      } else {
        debugPrint(
            '⚠️ Telegram API error status: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Telegram deletion alert exception: $e');
    }
  }

  /// Sends instant promotion/poster ad request alert to Telegram
  static Future<bool> notifyPromotionRequest({
    required String firmName,
    required String contact,
    String? details,
  }) async {
    try {
      final String messageText = '''📢 <b>NEW PROMOTION / POSTER REQUEST</b>

🏢 <b>Firm Name:</b> ${_escapeHtml(firmName)}
📱 <b>Mobile / WhatsApp:</b> <code>$contact</code>
📝 <b>Details:</b> ${_escapeHtml(details != null && details.trim().isNotEmpty ? details.trim() : 'N/A')}
⏰ <b>Time:</b> ${DateTime.now().toLocal().toString().split('.')[0]}''';

      final uri =
          Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': adminChatId,
              'text': messageText,
              'parse_mode': 'HTML',
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('✅ Telegram promotion alert sent successfully.');
        return true;
      } else {
        debugPrint(
            '⚠️ Telegram API error status: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Telegram promotion alert exception: $e');
      return false;
    }
  }
}
