import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/cloud_sync_service.dart';
import '../services/mandi_services.dart';

/// Real-time banner displayed on the user's dashboard showing their active
/// subscription details, days remaining, and proactive renewal reminders.
/// Built as a resilient StatefulWidget with persistent local caching to prevent
/// any blinking, flickering, or unexpected disappearance during network syncs.
class SubscriptionRenewalBanner extends StatefulWidget {
  const SubscriptionRenewalBanner({super.key});

  @override
  State<SubscriptionRenewalBanner> createState() =>
      _SubscriptionRenewalBannerState();
}

class _SubscriptionRenewalBannerState extends State<SubscriptionRenewalBanner> {
  static const String adminPhone = '9983325558';
  String? _activeMobile;
  Stream<DocumentSnapshot>? _userStream;
  Map<String, dynamic>? _lastValidData;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  void _loadInitialData() {
    _activeMobile = _findActiveUserMobile();

    // 1. Immediately restore locally cached subscription data to ensure ZERO blink on startup!
    final cachedJson = StorageService.get('cached_subscription_banner_data');
    if (cachedJson != null && cachedJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map) {
          _lastValidData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    // 2. Initialize the Firestore real-time stream
    if (_activeMobile != null && _activeMobile!.isNotEmpty) {
      _userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_activeMobile)
          .snapshots();
    }
  }

  @override
  void didUpdateWidget(covariant SubscriptionRenewalBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentMob = _findActiveUserMobile();
    if (currentMob != _activeMobile) {
      _activeMobile = currentMob;
      if (_activeMobile != null && _activeMobile!.isNotEmpty) {
        _userStream = FirebaseFirestore.instance
            .collection('users')
            .doc(_activeMobile)
            .snapshots();
      }
    }
  }

  String? _findActiveUserMobile() {
    for (final key in [
      'session_BROKER_mobile',
      'session_BUYER_mobile',
      'session_SELLER_mobile',
      'session_BILL GENERATOR_mobile',
      'session_active_mobile',
      'last_logged_in_mobile',
      'session_BROKER',
      'session_BUYER',
      'session_SELLER',
      'session_BILL GENERATOR',
    ]) {
      final val = StorageService.get(key);
      if (val != null && val.toString().trim().isNotEmpty) {
        final clean = CloudSyncService.cleanMobileNumber(val.toString());
        if (clean.length == 10) return clean;
      }
    }

    final all = AccountService.getAllAccounts();
    if (all.isNotEmpty) {
      for (final acc in all) {
        final clean = CloudSyncService.cleanMobileNumber(acc.mobile);
        if (clean.length == 10) return clean;
      }
    }

    // Device-level fallback from previous successful subscription sync
    final cachedMob = StorageService.get('cached_subscription_mobile');
    if (cachedMob != null && cachedMob.trim().isNotEmpty) {
      final clean = CloudSyncService.cleanMobileNumber(cachedMob.trim());
      if (clean.length == 10) return clean;
    }

    return null;
  }

  void _updateCache(Map<String, dynamic> data, String mobile) {
    _lastValidData = data;
    try {
      if (mobile.isNotEmpty) {
        StorageService.save('cached_subscription_mobile', mobile);
      }
      StorageService.save(
        'cached_subscription_banner_data',
        jsonEncode({
          'name': data['name'] ?? data['userName'] ?? data['firmName'],
          'subscription_plan': data['subscription_plan'] ??
              (data['subscription'] is Map
                  ? data['subscription']['plan']
                  : null) ??
              data['subscriptionPlan'],
          'subscription_renewal_date': data['subscription_renewal_date'] ??
              (data['subscription'] is Map
                  ? data['subscription']['renewal_date']
                  : null),
          'subscription_valid_until': data['subscription_valid_until'] ??
              (data['subscription'] is Map
                  ? data['subscription']['valid_until']
                  : null),
          'is_locked': data['is_locked'],
          'is_blocked': data['is_blocked'],
          'subscription_due': data['subscription_due'],
          'account_status': data['account_status'],
        }),
      );
    } catch (_) {}
  }

  Future<void> _openWhatsAppRenewal(
      String userName, String mobile, String dateText,
      {bool isExpired = false}) async {
    final statusText = isExpired
        ? 'Subscription is Due / Expired'
        : 'Renewal Date: $dateText';

    final message = '''Hello Mandi Admin! 🙏
I am a Mandi Trade Portal user.

📋 Account Details:
• Name: $userName
• Mobile / ID: $mobile
• Status: $statusText

Please assist me in renewing my subscription.
Thank you!''';

    final uri = Uri.parse(
        'https://wa.me/91$adminPhone?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mob = _activeMobile ?? _findActiveUserMobile();

    if (mob == null || mob.isEmpty) {
      if (_lastValidData != null) {
        return _buildBannerFromData(_lastValidData!, '');
      }
      return const SizedBox.shrink();
    }

    _userStream ??= FirebaseFirestore.instance
        .collection('users')
        .doc(mob)
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        Map<String, dynamic>? data;

        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          final raw = snapshot.data!.data();
          if (raw is Map<String, dynamic>) {
            data = raw;
            _updateCache(raw, mob);
          } else if (raw is Map) {
            data = Map<String, dynamic>.from(raw);
            _updateCache(data, mob);
          }
        }

        // When stream is connecting, reconnecting, or snapshot is temporarily absent,
        // NEVER collapse or hide! Keep displaying the verified cached data!
        data ??= _lastValidData;

        if (data == null || data.isEmpty) {
          return const SizedBox.shrink();
        }

        return _buildBannerFromData(data, mob);
      },
    );
  }

  Widget _buildBannerFromData(Map<String, dynamic> data, String mobile) {
    final renewalDate = CloudSyncService.parseRenewalDate(data);
    final isLocked = data['is_locked'] == true ||
        data['is_blocked'] == true ||
        data['subscription_due'] == true ||
        data['account_status'] == 'locked' ||
        data['account_status'] == 'suspended';

    final userName =
        (data['name'] ?? data['userName'] ?? data['firmName'] ?? 'User')
            .toString();
    final planName = (data['subscription_plan'] ??
            (data['subscription'] is Map
                ? data['subscription']['plan']
                : null) ??
            data['subscriptionPlan'] ??
            'Active Subscription')
        .toString();

    if (renewalDate == null && !isLocked) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final daysLeft = renewalDate?.difference(now).inDays;
    final dateText = renewalDate != null
        ? '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}'
        : 'De-activated';

    // =========================================================
    // CASE 1: ACTIVE SUBSCRIPTION (> 7 Days Left)
    // Show prominent green Active Membership Card in account!
    // =========================================================
    if (daysLeft != null && daysLeft > 7 && !isLocked) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF0F2922)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.7),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF10B981),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'ACTIVE SUBSCRIPTION',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(0xFF10B981),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          planName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Renewal Date: $dateText ($daysLeft days remaining) • Services active',
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF25D366),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
              label: const Text('Receipt', style: TextStyle(fontSize: 11)),
              onPressed: () => _openWhatsAppRenewal(
                userName,
                mobile,
                dateText,
                isExpired: false,
              ),
            ),
          ],
        ),
      );
    }

    // =========================================================
    // CASE 2: EXPIRING SOON OR EXPIRED (<= 7 Days Left or Locked)
    // Show prominent warning reminder banner!
    // =========================================================
    final bool isExpired = (daysLeft != null && daysLeft < 0) || isLocked;
    final bgColor =
        isExpired ? const Color(0xFF450A0A) : const Color(0xFF451A03);
    final borderColor = isExpired ? Colors.redAccent : Colors.amber;
    final iconColor = isExpired ? Colors.redAccent : Colors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.7), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExpired
                      ? Icons.error_outline_rounded
                      : Icons.notification_important_rounded,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExpired
                          ? 'Subscription Due'
                          : (daysLeft == 0
                              ? 'Subscription Renewal Reminder (Due Today)'
                              : 'Subscription Renewal Reminder ($daysLeft day${daysLeft == 1 ? "" : "s"} left)'),
                      style: TextStyle(
                        color: isExpired ? Colors.redAccent : Colors.amber,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isExpired
                          ? 'Dear $userName, your ($planName) subscription is due as of $dateText${daysLeft != null && daysLeft < 0 ? " (${-daysLeft} days ago)" : ""}. Please renew to keep your services active.'
                          : 'Dear $userName, your ($planName) subscription expires on $dateText (${daysLeft == 0 ? "Today" : "$daysLeft days left"}). Please renew to ensure uninterrupted service.',
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                label: Text(
                  isExpired
                      ? 'Renew Now (WhatsApp)'
                      : 'Renew with Admin (WhatsApp)',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openWhatsAppRenewal(
                  userName,
                  mobile,
                  dateText,
                  isExpired: isExpired,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
