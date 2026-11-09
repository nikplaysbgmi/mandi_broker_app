import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/email_service.dart';
import '../services/mandi_services.dart';
import '../services/telegram_notification_service.dart';
import 'bill_generator_screen.dart';
import 'broker_portal_screen.dart';
import 'buyer_portal_screen.dart';
import 'contact_services_screen.dart';
import 'market_watch_screen.dart';
import 'seller_portal_screen.dart';
import '../widgets/edit_promo_dialog.dart';
import '../widgets/github_workflow_dialog.dart';
import '../widgets/promo_dialog.dart';
import '../widgets/subscription_renewal_banner.dart';

// =============================================================
// MAIN 6-SECTION DASHBOARD
// =============================================================
class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  Map<String, dynamic> _latestServiceSwitches = {};
  int _failedAdminPinAttempts = 0;
  DateTime? _adminPinLockoutUntil;

  @override
  void initState() {
    super.initState();
    _initializeAuth();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          AppUpdateService.checkForUpdates(context);
        } catch (e) {
          debugPrint('Update check non-fatal error: $e');
        }
        try {
          PromoDialog.showIfActive(context);
        } catch (e) {
          debugPrint('Promo check non-fatal error: $e');
        }
      }
    });
  }

  Future<void> _initializeAuth() async {
    try {
      await CloudSyncService.ensureAuthSession();
      final user = FirebaseAuth.instance.currentUser;
      debugPrint('🔑 Mandi Dashboard Active Auth UID: ${user?.uid}');
    } catch (e) {
      debugPrint('⚠️ Auth session init error: $e');
    }
  }

  void _showLockedNotice(BuildContext context, String sectionTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Notice (सूचना)',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          '$sectionTitle is currently locked or under maintenance by administrator.\n\nयह सेवा वर्तमान में व्यवस्थापक द्वारा बंद (Locked) की गई है। कृपया अन्य चालू सेवाओं का उपयोग करें।',
          style: const TextStyle(color: Colors.black87, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _promptAdminPin(BuildContext context, {bool openPosterDirectly = false}) {
    if (_adminPinLockoutUntil != null &&
        DateTime.now().isBefore(_adminPinLockoutUntil!)) {
      final remainingSec =
          _adminPinLockoutUntil!.difference(DateTime.now()).inSeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '⚠️ सुरक्षा लॉक: बहुत सारे गलत प्रयास। कृपया $remainingSec सेकंड बाद पुनः प्रयास करें।'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final pinController = TextEditingController();
    const String masterPin = "@2740157";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Icon(
              openPosterDirectly
                  ? Icons.campaign_rounded
                  : Icons.admin_panel_settings,
              color: const Color(0xFFFF5722),
            ),
            const SizedBox(width: 8),
            Text(
              openPosterDirectly
                  ? 'पोस्टर सेवा (Master PIN)'
                  : 'Master Admin Access',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.text,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter Master PIN',
            hintStyle: TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Color(0xFF2B2B2B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5722),
            ),
            onPressed: () {
              if (pinController.text.trim() == masterPin) {
                _failedAdminPinAttempts = 0;
                _adminPinLockoutUntil = null;
                Navigator.pop(ctx);
                if (openPosterDirectly) {
                  showDialog(
                    context: context,
                    builder: (context) => const EditPromoDialog(),
                  );
                } else {
                  _showMasterAdminHub(context);
                }
              } else {
                _failedAdminPinAttempts++;
                if (_failedAdminPinAttempts >= 5) {
                  _adminPinLockoutUntil =
                      DateTime.now().add(const Duration(minutes: 5));
                  _failedAdminPinAttempts = 0;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          '🚨 5 गलत प्रयास! सुरक्षा कारणों से Master Admin 5 मिनट के लिए लॉक कर दिया गया है।'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                    ),
                  );
                  return;
                }
                final remaining = 5 - _failedAdminPinAttempts;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Incorrect Master PIN! Access denied. ($remaining प्रयास शेष)'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Enter', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMasterAdminHub(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded,
                color: Color(0xFFFF5722), size: 24),
            SizedBox(width: 8),
            Text(
              'Master Admin Hub',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAdminHubOption(
                icon: Icons.campaign_rounded,
                color: const Color(0xFFFF5722),
                title: '📢 विज्ञापन / पोस्टर सेवा (Post Poster)',
                subtitle: 'डैशबोर्ड व ऐप स्टार्ट पर प्रचार पोस्टर लगाएं',
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => const EditPromoDialog(),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildAdminHubOption(
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF38BDF8),
                title: '👥 यूज़र व पासवर्ड प्रबंधन (Users & Accounts)',
                subtitle: 'सभी यूज़र्स देखें, पासवर्ड बदलें, लॉक/अनलॉक करें',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminUsersListScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildAdminHubOption(
                icon: Icons.tune_rounded,
                color: const Color(0xFF10B981),
                title: '🔒 सेवाएं लॉक / अनलॉक (Services Control)',
                subtitle: 'लाइव भाव, बायर, सेलर, ब्रोकर, बिल सेवाएं चालू/बंद करें',
                onTap: () {
                  Navigator.pop(ctx);
                  AdminUsersListScreen.openServiceSwitchesDialog(context);
                },
              ),
              const SizedBox(height: 10),
              _buildAdminHubOption(
                icon: Icons.play_circle_fill_rounded,
                color: const Color(0xFF38BDF8),
                title: '⚡ GitHub NCDEX Workflow (चलाएं)',
                subtitle: 'NCDEX लाइव भाव तुरंत अपडेट करने हेतु गिटहब एक्शन रन करें',
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (_) => const GitHubWorkflowDialog(),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('बंद करें (CLOSE)',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminHubOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 13, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  void _routeToSection(BuildContext context, String sectionName) {
    final existingUser = AccountService.getSessionUser(sectionName);
    if (existingUser != null) {
      Widget portal;
      if (sectionName == 'BROKER') {
        portal = const BrokerSectionPortal();
      } else if (sectionName == 'BUYER') {
        portal = BuyerSectionPortal(user: existingUser);
      } else if (sectionName == 'SELLER') {
        portal = SellerSectionPortal(user: existingUser);
      } else {
        final isUnlocked =
            StorageService.get('session_BILL_GENERATOR_UNLOCKED') == 'true';
        portal = isUnlocked
            ? BillGeneratorSectionPortal(username: existingUser.name)
            : BillGeneratorMaintenanceScreen(username: existingUser.name);
      }
      Navigator.push(context, MaterialPageRoute(builder: (context) => portal));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SectionLoginGate(sectionName: sectionName),
      ),
    );
  }

  Future<void> _confirmRemoveDeviceAccount(
    BuildContext context,
    StateSetter setDialogState,
    UserAccount account,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.no_accounts_outlined, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Remove from Device',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Remove ${account.name} (${account.section} • ${account.mobile}) from this device\'s quick login list?\n\nThis will NOT delete your cloud account.',
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final all = AccountService.getAllAccounts();
      all.removeWhere(
        (a) =>
            a.mobile.trim() == account.mobile.trim() &&
            a.section.trim().toUpperCase() ==
                account.section.trim().toUpperCase(),
      );
      AccountService.saveAccounts(all);

      final activeSec = account.section.toUpperCase();
      if (StorageService.get('session_${activeSec}_mobile') == account.mobile) {
        StorageService.remove('session_$activeSec');
        StorageService.remove('session_${activeSec}_name');
        StorageService.remove('session_${activeSec}_mobile');
        StorageService.remove('session_${activeSec}_email');
        StorageService.remove('session_${activeSec}_address');
      }

      try {
        TelegramNotificationService.notifyAccountDeleted(
          name: account.name,
          mobile: account.mobile,
          section: account.section,
          deletedBy: 'USER (Self Remove)',
          reason: 'User removed profile from device quick login list',
        );
      } catch (tgErr) {
        debugPrint('Telegram notification failed: $tgErr');
      }

      setDialogState(() {});
      if (mounted) setState(() {});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${account.name} from this device.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _openMainMenuProfileDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allAccounts = AccountService.getAllAccounts();
          final brokerUser = AccountService.getSessionUser('BROKER');
          final buyerUser = AccountService.getSessionUser('BUYER');
          final sellerUser = AccountService.getSessionUser('SELLER');
          final billUser = AccountService.getSessionUser('BILL GENERATOR');

          final activeUser = brokerUser ?? buyerUser ?? sellerUser ?? billUser;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.account_circle, color: Color(0xFF14B8A6), size: 28),
                SizedBox(width: 10),
                Text(
                  'User Profile & Accounts',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (activeUser != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF14B8A6),
                                child: Text(
                                  activeUser.name.isNotEmpty
                                      ? activeUser.name[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeUser.name,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      activeUser.section.toUpperCase(),
                                      style: const TextStyle(
                                        color: Color(0xFF0F766E),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Text(
                            'Mobile: ${activeUser.mobile}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Email: ${activeUser.email.isNotEmpty ? activeUser.email : "Not Provided"}',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12.5,
                            ),
                          ),
                          if (activeUser.address.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Address: ${activeUser.address}',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                          // Live Subscription Details Card in Profile Dialog
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .doc(CloudSyncService.cleanMobileNumber(
                                    activeUser.mobile))
                                .snapshots(),
                            builder: (context, subSnap) {
                              if (!subSnap.hasData ||
                                  subSnap.data == null ||
                                  !subSnap.data!.exists) {
                                return const SizedBox.shrink();
                              }
                              final subData = subSnap.data!.data()
                                      as Map<String, dynamic>? ??
                                  {};
                              final renewalDate =
                                  CloudSyncService.parseRenewalDate(subData);
                              final daysLeft = renewalDate
                                  ?.difference(DateTime.now())
                                  .inDays;
                              final plan = (subData['subscription_plan'] ??
                                      (subData['subscription'] is Map
                                          ? subData['subscription']['plan']
                                          : null) ??
                                      'Active Plan')
                                  .toString();
                              final isLocked = subData['is_locked'] == true ||
                                  subData['subscription_due'] == true ||
                                  (daysLeft != null && daysLeft < 0);

                              final dateStr = renewalDate != null
                                  ? '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}'
                                  : 'Not set';

                              return Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isLocked
                                      ? Colors.red.shade50
                                      : (daysLeft != null && daysLeft <= 7)
                                          ? Colors.amber.shade50
                                          : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isLocked
                                        ? Colors.red.shade300
                                        : (daysLeft != null && daysLeft <= 7)
                                            ? Colors.amber.shade300
                                            : Colors.teal.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isLocked
                                              ? Icons.lock_outline
                                              : (daysLeft != null &&
                                                      daysLeft <= 7)
                                                  ? Icons
                                                      .notification_important_rounded
                                                  : Icons.verified_user_rounded,
                                          size: 16,
                                          color: isLocked
                                              ? Colors.red.shade800
                                              : (daysLeft != null &&
                                                      daysLeft <= 7)
                                                  ? Colors.amber.shade900
                                                  : Colors.teal.shade800,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Subscription Status',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isLocked
                                                ? Colors.red.shade900
                                                : (daysLeft != null &&
                                                        daysLeft <= 7)
                                                    ? Colors.amber.shade900
                                                    : Colors.teal.shade900,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isLocked
                                                ? Colors.red
                                                : Colors.teal.shade700,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            isLocked ? 'SUBSCRIPTION DUE' : 'ACTIVE',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Plan: $plan',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87),
                                    ),
                                    if (renewalDate != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Renewal: $dateStr (${daysLeft != null ? (daysLeft < 0 ? "Expired ${-daysLeft} days ago" : (daysLeft == 0 ? "Today" : "$daysLeft days left")) : ""})',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: (daysLeft != null &&
                                                  daysLeft <= 7)
                                              ? Colors.red.shade800
                                              : Colors.black87,
                                          fontWeight: (daysLeft != null &&
                                                  daysLeft <= 7)
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        for (final sec in [
                          'BROKER',
                          'BUYER',
                          'SELLER',
                          'BILL GENERATOR'
                        ]) {
                          StorageService.remove('session_$sec');
                          StorageService.remove('session_${sec}_name');
                          StorageService.remove('session_${sec}_mobile');
                          StorageService.remove('session_${sec}_email');
                          StorageService.remove('session_${sec}_address');
                        }
                        StorageService.remove(
                            'session_BILL_GENERATOR_UNLOCKED');
                        setDialogState(() {});
                        if (mounted) setState(() {});
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Logged out of active session successfully.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.logout, size: 16),
                      label: const Text('LOGOUT ACTIVE SESSION'),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.person_outline,
                              size: 36, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'No Active User Logged In',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap any of the portal cards to sign in to your account.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (allAccounts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saved Device Accounts:',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${allAccounts.length} saved',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black45),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...allAccounts.map((acc) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Navigator.pop(ctx);
                              final sec = acc.section.toUpperCase();
                              bool isAllowed = true;
                              if (sec == 'BUYER') {
                                isAllowed =
                                    _latestServiceSwitches['buyer_portal'] ==
                                        true;
                              } else if (sec == 'SELLER') {
                                isAllowed =
                                    _latestServiceSwitches['seller_portal'] ==
                                        true;
                              } else if (sec == 'BROKER') {
                                isAllowed =
                                    _latestServiceSwitches['broker_portal'] !=
                                        false;
                              } else if (sec == 'BILL GENERATOR') {
                                isAllowed =
                                    _latestServiceSwitches['bill_generator'] !=
                                        false;
                              }
                              if (!isAllowed) {
                                _showLockedNotice(context, '$sec Portal');
                                return;
                              }
                              _routeToSection(context, sec);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          acc.name,
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${acc.section} • ${acc.mobile}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                      color: Colors.redAccent,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    tooltip: 'Remove from device',
                                    onPressed: () =>
                                        _confirmRemoveDeviceAccount(
                                      context,
                                      setDialogState,
                                      acc,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [Color(0xFF16253B), Color(0xFF0B1320)],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<dynamic>(
            stream: CloudSyncService.streamServiceSwitches(),
            builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
              // Default Buyer & Seller to false (LOCKED) so they cannot be bypassed offline or on iOS init
              bool enableMarketView = true;
              bool enableBuyerPortal = false;
              bool enableSellerPortal = false;
              bool enableBrokerPortal = true;
              bool enableBillGenerator = true;

              if (snapshot.hasData && snapshot.data != null) {
                try {
                  final dynamic raw = snapshot.data;
                  Map<dynamic, dynamic>? dataMap;

                  if (raw is Map) {
                    dataMap = raw;
                  } else if (raw is DocumentSnapshot && raw.data() is Map) {
                    dataMap = raw.data() as Map<dynamic, dynamic>;
                  }

                  if (dataMap != null && dataMap.isNotEmpty) {
                    _latestServiceSwitches = Map<String, dynamic>.from(dataMap);
                    bool parseSwitch(dynamic val, bool defaultValue) {
                      if (val == null) return defaultValue;
                      if (val is bool) return val;
                      if (val is String) {
                        return val.trim().toLowerCase() == 'true';
                      }
                      if (val is num) return val != 0;
                      return defaultValue;
                    }

                    enableMarketView =
                        parseSwitch(dataMap['market_view'], true);
                    enableBuyerPortal =
                        parseSwitch(dataMap['buyer_portal'], false);
                    enableSellerPortal =
                        parseSwitch(dataMap['seller_portal'], false);
                    enableBrokerPortal =
                        parseSwitch(dataMap['broker_portal'], true);
                    enableBillGenerator =
                        parseSwitch(dataMap['bill_generator'], true);
                  }
                } catch (e) {
                  debugPrint('Switch parse error: $e');
                }
              }

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => _promptAdminPin(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      size: 13,
                                      color: Color(0xFF10B981),
                                    ),
                                    SizedBox(width: 5),
                                    Text(
                                      'Nik_jodhpur• 2026',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFF14B8A6)
                                    .withValues(alpha: 0.15),
                                foregroundColor: const Color(0xFF14B8A6),
                              ),
                              icon: const Icon(Icons.account_circle_outlined,
                                  size: 22),
                              tooltip: 'User Profile & Settings',
                              onPressed: _openMainMenuProfileDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          kAppName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          kAppNameHindi,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Subscription Renewal Reminder Banner (approaching within 7 days)
                        const SubscriptionRenewalBanner(),

                        // Realtime Advertisement & Notice Banner
                        const DashboardPromoBanner(),

                        // 1. LIVE BHAV
                        _buildSectionCard(
                          context: context,
                          title: 'LIVE BHAV',
                          hindiTitle: 'दैनिक मंडी भाव एवं आवक',
                          description: enableMarketView
                              ? 'Live rates, arrival volumes & commodity lists'
                              : 'Temporarily under maintenance',
                          icon: Icons.show_chart_rounded,
                          accentColor: enableMarketView
                              ? const Color(0xFF10B981)
                              : Colors.grey,
                          badgeText:
                              enableMarketView ? 'PUBLIC ACCESS' : 'LOCKED 🔒',
                          isPublic: enableMarketView,
                          onTap: () {
                            if (enableMarketView) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MarketWatchScreen(),
                                ),
                              );
                            } else {
                              _showLockedNotice(context, 'Live Bhav');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 2. BUYER
                        _buildSectionCard(
                          context: context,
                          title: 'BUYER',
                          hindiTitle: 'खरीदार खरीद खाता व बही',
                          description: enableBuyerPortal
                              ? 'Buyer purchase records'
                              : 'Buyer portal temporarily closed for maintenance',
                          icon: Icons.storefront_rounded,
                          accentColor: enableBuyerPortal
                              ? const Color(0xFF38BDF8)
                              : Colors.grey,
                          badgeText:
                              enableBuyerPortal ? 'SECURE LOGIN' : 'LOCKED 🔒',
                          isPublic: false,
                          onTap: () {
                            if (enableBuyerPortal) {
                              _routeToSection(context, 'BUYER');
                            } else {
                              _showLockedNotice(context, 'Buyer Portal');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 3. SELLER
                        _buildSectionCard(
                          context: context,
                          title: 'SELLER',
                          hindiTitle: 'विक्रेता / किसान खाता',
                          description: enableSellerPortal
                              ? 'Seller sales records'
                              : 'Seller portal temporarily closed for maintenance',
                          icon: Icons.agriculture_rounded,
                          accentColor: enableSellerPortal
                              ? const Color(0xFFF59E0B)
                              : Colors.grey,
                          badgeText:
                              enableSellerPortal ? 'SECURE LOGIN' : 'LOCKED 🔒',
                          isPublic: false,
                          onTap: () {
                            if (enableSellerPortal) {
                              _routeToSection(context, 'SELLER');
                            } else {
                              _showLockedNotice(context, 'Seller Portal');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 4. BROKER
                        _buildSectionCard(
                          context: context,
                          title: 'BROKER',
                          hindiTitle: 'ब्रोकर बही व टेम्पलेट',
                          description: enableBrokerPortal
                              ? 'Deal entry, custom templates & settlement '
                              : 'Broker portal temporarily closed for maintenance',
                          icon: Icons.handshake_rounded,
                          accentColor: enableBrokerPortal
                              ? const Color(0xFF14B8A6)
                              : Colors.grey,
                          badgeText: enableBrokerPortal
                              ? 'BROKER SYSTEM'
                              : 'LOCKED 🔒',
                          isPublic: false,
                          isHighlighted: enableBrokerPortal,
                          onTap: () {
                            if (enableBrokerPortal) {
                              _routeToSection(context, 'BROKER');
                            } else {
                              _showLockedNotice(context, 'Broker Portal');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 5. BILL GENERATOR
                        _buildSectionCard(
                          context: context,
                          title: 'BILL GENERATOR',
                          hindiTitle: 'बिल जनरेटर',
                          description: enableBillGenerator
                              ? 'Farmer mandi slips, weight tally & statement print'
                              : 'Bill generator temporarily closed for maintenance',
                          icon: Icons.receipt_long_rounded,
                          accentColor: enableBillGenerator
                              ? const Color(0xFFA855F7)
                              : Colors.grey,
                          badgeText:
                              enableBillGenerator ? 'SECURE DESK' : 'LOCKED 🔒',
                          isPublic: false,
                          onTap: () {
                            if (enableBillGenerator) {
                              _routeToSection(context, 'BILL GENERATOR');
                            } else {
                              _showLockedNotice(context, 'Bill Generator');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 6. CONTACT US & SERVICES
                        _buildSectionCard(
                          context: context,
                          title: 'CONTACT US & SERVICES',
                          hindiTitle:
                              'सहायता, सब्सक्रिप्शन, विज्ञापन व पासवर्ड रीसेट',
                          description:
                              'Promotion banner, WhatsApp password reset, subscription & live help',
                          icon: Icons.support_agent_rounded,
                          accentColor: const Color(0xFF06B6D4),
                          badgeText: 'SUPPORT HUB',
                          isPublic: true,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ContactServicesScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Developer- Nik_jodhpur • Mob: 9983325558 • Responsible For Nothing • Only For Educational Purpose • Thanks for support ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required String hindiTitle,
    required String description,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required bool isPublic,
    required VoidCallback onTap,
    bool isHighlighted = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: accentColor.withValues(alpha: 0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? accentColor.withValues(alpha: 0.08)
                : const Color(0xFF131D2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? accentColor.withValues(alpha: 0.5)
                  : const Color(0xFF223249),
              width: isHighlighted ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPublic
                                ? const Color(0xFF10B981)
                                    .withValues(alpha: 0.15)
                                : const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isPublic
                                  ? const Color(0xFF10B981)
                                      .withValues(alpha: 0.4)
                                  : const Color(0xFF475569),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: isPublic
                                  ? const Color(0xFF10B981)
                                  : Colors.grey.shade300,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hindiTitle,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================
// ADMIN USERS, PASSWORDS & SUBSCRIPTION DASHBOARD
// =============================================================
class AdminUsersListScreen extends StatefulWidget {
  const AdminUsersListScreen({super.key});

  static void openServiceSwitchesDialog(BuildContext context) =>
      _AdminUsersListScreenState._openServiceSwitchesDialog(context);

  @override
  State<AdminUsersListScreen> createState() => _AdminUsersListScreenState();
}

class _AdminUsersListScreenState extends State<AdminUsersListScreen> {
  String _searchFilter = '';
  bool _isAuthReady = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    try {
      await CloudSyncService.ensureAuthSession();
      // Silently purge any unauthenticated party contact stubs from users root collection
      CloudSyncService.purgeUnauthenticatedContactStubs();
    } catch (e) {
      debugPrint('Admin screen auth session check error: $e');
    } finally {
      if (mounted) {
        setState(() => _isAuthReady = true);
      }
    }
  }

  Widget _buildPlanChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF10B981)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF10B981)
                : const Color(0xFF334155),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _openSubscriptionActivationDialog({
    required String section,
    required String mobile,
    required String userName,
    DateTime? existingRenewalDate,
    bool isAlreadyActive = false,
  }) {
    int selectedDays = 30;
    String selectedPlan = '1 Month (30 Days)';
    DateTime renewalDate = existingRenewalDate != null &&
            existingRenewalDate.isAfter(DateTime.now())
        ? existingRenewalDate.add(const Duration(days: 30))
        : DateTime.now().add(const Duration(days: 30));
    final noteController =
        TextEditingController(text: 'Monthly Plan Subscription');
    bool sendWhatsApp = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final daysLeft = renewalDate.difference(DateTime.now()).inDays;
            final dateStr =
                '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}';

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isAlreadyActive
                          ? Icons.edit_calendar_rounded
                          : Icons.verified_user_rounded,
                      color: const Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAlreadyActive
                              ? 'नवीनीकरण तारीख बढ़ाएं'
                              : 'सदस्यता चालू करें (Turn ON)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$userName ($mobile)',
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'अवधि चुनें (Select Renewal Plan):',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPlanChip(
                          label: '1 महीना (30 दिन)',
                          isSelected: selectedDays == 30,
                          onTap: () {
                            setDialogState(() {
                              selectedDays = 30;
                              selectedPlan = '1 Month (30 Days)';
                              renewalDate = DateTime.now()
                                  .add(const Duration(days: 30));
                            });
                          },
                        ),
                        _buildPlanChip(
                          label: '3 महीने (90 दिन)',
                          isSelected: selectedDays == 90,
                          onTap: () {
                            setDialogState(() {
                              selectedDays = 90;
                              selectedPlan = '3 Months (90 Days)';
                              renewalDate = DateTime.now()
                                  .add(const Duration(days: 90));
                            });
                          },
                        ),
                        _buildPlanChip(
                          label: '6 महीने (180 दिन)',
                          isSelected: selectedDays == 180,
                          onTap: () {
                            setDialogState(() {
                              selectedDays = 180;
                              selectedPlan = '6 Months (180 Days)';
                              renewalDate = DateTime.now()
                                  .add(const Duration(days: 180));
                            });
                          },
                        ),
                        _buildPlanChip(
                          label: '1 वर्ष (365 दिन)',
                          isSelected: selectedDays == 365,
                          onTap: () {
                            setDialogState(() {
                              selectedDays = 365;
                              selectedPlan = '1 Year (365 Days)';
                              renewalDate = DateTime.now()
                                  .add(const Duration(days: 365));
                            });
                          },
                        ),
                        _buildPlanChip(
                          label: '📅 कस्टम तारीख',
                          isSelected: selectedDays == 0,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogCtx,
                              initialDate: renewalDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 1825)),
                            );
                            if (!dialogCtx.mounted) return;
                            if (picked != null) {
                              setDialogState(() {
                                selectedDays = 0;
                                selectedPlan = 'Custom Plan';
                                renewalDate = picked;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Display Current Calculated Renewal Date
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16253B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'नई नवीनीकरण तारीख (Renewal Date):',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$dateStr (${daysLeft > 0 ? '$daysLeft दिन शेष' : 'आज'})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.date_range,
                                color: Color(0xFF38BDF8), size: 20),
                            tooltip: 'कैलेंडर से चुनें',
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: dialogCtx,
                                initialDate: renewalDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 1825)),
                              );
                              if (!dialogCtx.mounted) return;
                              if (picked != null) {
                                setDialogState(() {
                                  selectedDays = 0;
                                  selectedPlan = 'Custom Date';
                                  renewalDate = picked;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Notes / Amount Field
                    TextField(
                      controller: noteController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'प्लान विवरण / नोट (वैकल्पिक)',
                        labelStyle: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF16253B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // WhatsApp confirmation checkbox
                    InkWell(
                      onTap: () {
                        setDialogState(() => sendWhatsApp = !sendWhatsApp);
                      },
                      child: Row(
                        children: [
                          Checkbox(
                            value: sendWhatsApp,
                            activeColor: const Color(0xFF25D366),
                            onChanged: (val) {
                              setDialogState(() => sendWhatsApp = val ?? true);
                            },
                          ),
                          const Expanded(
                            child: Text(
                              '📲 यूज़र को WhatsApp पर तुरंत रसीद व नवीनीकरण सूचना भेजें',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द करें (Cancel)',
                      style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(
                    isAlreadyActive
                        ? 'तारीख अपडेट करें'
                        : 'चालू करें (Turn ON)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _activateUserWithRenewal(
                      section: section,
                      mobile: mobile,
                      userName: userName,
                      renewalDate: renewalDate,
                      plan: selectedPlan,
                      note: noteController.text.trim(),
                      sendWhatsApp: sendWhatsApp,
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _activateUserWithRenewal({
    required String section,
    required String mobile,
    required String userName,
    required DateTime renewalDate,
    required String plan,
    required String note,
    required bool sendWhatsApp,
  }) async {
    try {
      await CloudSyncService.activateSubscriptionWithRenewal(
        section: section,
        mobile: mobile,
        renewalDate: renewalDate,
        plan: plan,
        note: note,
        activatedBy: 'ADMIN',
      );

      final dateStr =
          '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ $userName की सदस्यता सक्रिय हो गई (नवीनीकरण: $dateStr)'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      if (sendWhatsApp) {
        final cleanMob = CloudSyncService.cleanMobileNumber(mobile);
        if (cleanMob.isNotEmpty) {
          final message = '''नमस्ते $userName जी! 🙏
Mandi Trade Portal पर आपकी सदस्यता सक्रिय (ACTIVATED) कर दी गई है।

📋 सदस्यता विवरण:
• खाता आईडी: $cleanMob
• सेवा पोर्टल: $section
• प्लान: $plan
• नवीनीकरण तारीख (Renewal Date): $dateStr

मंडी के लाइव भाव, सौदे एवं खाता सेवाओं का लाभ उठाने के लिए ऐप खोलें।
किसी भी सहायता हेतु संपर्क करें: 9983325558

धन्यवाद!
Mandi Trade Portal Support''';

          final uri = Uri.parse(
              'https://wa.me/91$cleanMob?text=${Uri.encodeComponent(message)}');
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('त्रुटि: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendWhatsAppRenewalReminder({
    required String mobile,
    required String userName,
    required String section,
    required DateTime? renewalDate,
  }) async {
    final cleanMob = CloudSyncService.cleanMobileNumber(mobile);
    if (cleanMob.isEmpty) return;

    final String dateStr = renewalDate != null
        ? '${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year}'
        : 'शीघ्र देय (Due Soon)';
    final String daysRemainingText = renewalDate != null
        ? '${renewalDate.difference(DateTime.now()).inDays} दिन शेष'
        : 'कृपया संपर्क करें';

    final message = '''नमस्ते $userName जी! 🙏
यह Mandi Trade Portal से आपकी सदस्यता नवीनीकरण (Renewal Reminder) की सूचना है।

📋 खाता विवरण:
• यूज़र आईडी: $cleanMob
• पोर्टल: $section
• नवीनीकरण तारीख (Renewal Date): $dateStr ($daysRemainingText)

मंडी के लाइव भाव, सौदे एवं खाता सेवाएं बिना रुकावट चालू रखने के लिए कृपया समय पर अपनी सदस्यता का नवीनीकरण कराएं।

भुगतान / सहायता हेतु संपर्क करें: 9983325558
धन्यवाद!
Mandi Trade Portal Support''';

    final uri = Uri.parse(
        'https://wa.me/91$cleanMob?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp खोलने में असमर्थ')),
      );
    }
  }

  Future<void> _toggleUserLock({
    required String section,
    required String mobile,
    required bool currentLockedState,
    String userName = '',
  }) async {
    if (!currentLockedState) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Confirm Lock / Due',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Text(
            'क्या आप $userName ($mobile) का खाता ब्लॉक/सब्सक्रिप्शन ओवरड्यू करना चाहते हैं?',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lock Account',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      if (!mounted) return;
    }

    try {
      await CloudSyncService.setLockStatus(
        section: section,
        mobile: mobile,
        isLocked: !currentLockedState,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentLockedState
                ? 'Account locked (Subscription overdue).'
                : 'Account unlocked (Access active).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating account: $e')),
      );
    }
  }

  Future<void> _confirmDeleteUser({
    required String section,
    required String mobile,
    required String userName,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete $userName ($mobile) from $section?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CloudSyncService.purgeUserAccount(mobile, section: section);

        TelegramNotificationService.notifyAccountDeleted(
          name: userName,
          mobile: mobile,
          section: section,
          deletedBy: 'ADMIN (Master PIN Panel)',
          reason: 'Manual deletion by administrator',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Account $userName deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')),
          );
        }
      }
    }
  }

  void _showRearrangeCollectionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
          ),
          title: const Row(
            children: [
              Icon(Icons.auto_fix_high_rounded, color: Color(0xFF38BDF8)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'डेटा व्यवस्थित करें (Rearrange & Clean)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'यह टूल फायरबेस कलेक्शन्स को "1 User = 1 Personal Folder" आर्किटेक्चर में पूरी तरह व्यवस्थित करेगा:\n\n'
            '1. सभी पुराने डुप्लीकेट डॉक्युमेंट्स (BROKER_... आदि) को सिंगल पर्सनल फोल्डर (users/{mobile}) में मर्ज करेगा।\n'
            '2. ब्रोकर के बिना पासवर्ड वाले पार्टी संपर्कों (PAGAL जैसे स्टब्स) को users रूट से हटाएगा।\n'
            '3. सभी पुराने सौदों को AES-256 एन्क्रिप्शन से फायरबेस में सुरक्षित/गोपनीय करेगा।\n'
            '4. सब-कलेक्शन्स (records, parties, subscriptions) को सही फोल्डर में सुरक्षित माइग्रेट करेगा।\n'
            '5. फैंटम (इटैलिक) डॉक्युमेंट्स को ठीक करेगा।\n\n'
            'क्या आप डेटा क्लीनअप और रीअरेंज शुरू करना चाहते हैं?',
            style:
                TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('START CLEANUP (शुरू करें)'),
              onPressed: () async {
                Navigator.pop(ctx);
                _runRearrangeCollections();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _runRearrangeCollections() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: Color(0xFF16253B),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF38BDF8)),
                SizedBox(width: 16),
                Text(
                  'डेटाबेस व्यवस्थित किया जा रहा है...\nRearranging Firestore Collections...',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final res =
          await CloudSyncService.rearrangeAndCleanFirestoreCollections();
      if (mounted) {
        Navigator.pop(context); // Close progress dialog

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'सफलतापूर्वक व्यवस्थित (Completed)',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              'फायरबेस कलेक्शन्स सफलतापूर्वक व्यवस्थित हो गए हैं:\n\n'
              '• कुल स्कैन किए गए यूज़र्स: ${res['scanned'] ?? 0}\n'
              '• डुप्लीकेट/पुराने प्रीफ़िक्स हटाए गए: ${res['prefixed_migrated'] ?? 0}\n'
              '• अनधिकृत पार्टी स्टब्स (Password: N/A) हटाए गए: ${res['stubs_purged'] ?? 0}\n'
              '• पुराने सौदे AES-256 से एन्क्रिप्ट/गोपनीय किए गए: ${res['legacy_saudas_encrypted'] ?? 0}\n'
              '• वैध फोल्डर्स फिक्स किए गए: ${res['phantom_fixed'] ?? 0}\n'
              '• कंसोलिडेट किए गए ब्रोकर प्रोफाइल्स: ${res['brokers_consolidated'] ?? 0}\n\n'
              'अब प्रत्येक वास्तविक यूज़र का केवल एक सिंगल पर्सनल फ़ोल्डर (users/{mobile}) है और सभी सौदे सुरक्षित हैं।',
              style: const TextStyle(
                  color: Color(0xFFCBD5E1), fontSize: 13, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Cleanup failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static void _openServiceSwitchesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1.2),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PORTAL SERVICES CONTROL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                          Text(
                            'सेवाएं लॉक / अनलॉक नियंत्रण',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.pop(ctx),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Batch Actions: Unlock All / Lock All
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.lock_open_rounded, size: 14),
                        label: const Text(
                          'Unlock All (सभी चालू)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          await CloudSyncService.setAllServiceSwitches({
                            'market_view': true,
                            'buyer_portal': true,
                            'seller_portal': true,
                            'broker_portal': true,
                            'bill_generator': true,
                          });
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('All services unlocked successfully!'),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.lock_outline_rounded, size: 14),
                        label: const Text(
                          'Lock All (सभी बंद)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          await CloudSyncService.setAllServiceSwitches({
                            'market_view': false,
                            'buyer_portal': false,
                            'seller_portal': false,
                            'broker_portal': false,
                            'bill_generator': false,
                          });
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'All services locked for maintenance.'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Color(0xFF334155), height: 1),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: StreamBuilder<dynamic>(
                      stream: CloudSyncService.streamServiceSwitches(),
                      builder: (context, snapshot) {
                        Map<String, dynamic> dataMap = {};
                        if (snapshot.hasData && snapshot.data != null) {
                          final dynamic raw = snapshot.data;
                          if (raw is Map) {
                            dataMap = Map<String, dynamic>.from(raw);
                          } else if (raw is DocumentSnapshot &&
                              raw.data() is Map) {
                            dataMap =
                                Map<String, dynamic>.from(raw.data() as Map);
                          }
                        }

                        bool parseSwitch(String key, bool defaultValue) {
                          final val = dataMap[key];
                          if (val == null) return defaultValue;
                          if (val is bool) return val;
                          if (val is String) {
                            return val.trim().toLowerCase() == 'true';
                          }
                          if (val is num) return val != 0;
                          return defaultValue;
                        }

                        final serviceList = [
                          {
                            'key': 'market_view',
                            'title': 'Live Bhav',
                            'hindiTitle': 'दैनिक मंडी भाव एवं आवक',
                            'desc':
                                'Local Mandi, NCDEX live ticker & Analyzer',
                            'icon': Icons.show_chart_rounded,
                            'color': const Color(0xFF10B981),
                            'default': true,
                          },
                          {
                            'key': 'show_analyzer',
                            'title': 'Show Analyzer Tab',
                            'hindiTitle': 'कमोडिटी एनालाइज़र टैब (दिखाएं / छिपाएं)',
                            'desc':
                                'Live Bhav में Analyzer टैब को छुपाएं या दिखाएं',
                            'icon': Icons.visibility_rounded,
                            'color': const Color(0xFFA855F7),
                            'default': true,
                          },
                          {
                            'key': 'buyer_portal',
                            'title': 'Buyer Portal',
                            'hindiTitle': 'खरीदार खाता एवं ब्रोकर सूची',
                            'desc':
                                'Buyer login, purchase records & private khata',
                            'icon': Icons.storefront_rounded,
                            'color': const Color(0xFF38BDF8),
                            'default': false,
                          },
                          {
                            'key': 'seller_portal',
                            'title': 'Seller Portal',
                            'hindiTitle': 'विक्रेता / किसान खाता',
                            'desc':
                                'Farmer portal, sauda slips & sales settlement',
                            'icon': Icons.agriculture_rounded,
                            'color': const Color(0xFFF59E0B),
                            'default': false,
                          },
                          {
                            'key': 'broker_portal',
                            'title': 'Broker Portal',
                            'hindiTitle': 'ब्रोकर बही व टेम्पलेट',
                            'desc':
                                'Broker deals entry, 4 WhatsApp templates & ledger',
                            'icon': Icons.handshake_rounded,
                            'color': const Color(0xFF14B8A6),
                            'default': true,
                          },
                          {
                            'key': 'bill_generator',
                            'title': 'Bill Generator',
                            'hindiTitle': 'बिल जनरेटर',
                            'desc':
                                'Farmer weight slips, statement print & PDF slips',
                            'icon': Icons.receipt_long_rounded,
                            'color': const Color(0xFFA855F7),
                            'default': true,
                          },
                        ];

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: serviceList.map((svc) {
                            final key = svc['key'] as String;
                            final isEnabled =
                                parseSwitch(key, svc['default'] as bool);
                            final color = svc['color'] as Color;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16253B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isEnabled
                                      ? color.withValues(alpha: 0.45)
                                      : Colors.redAccent
                                          .withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      svc['icon'] as IconData,
                                      color: color,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              svc['title'] as String,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: isEnabled
                                                    ? const Color(0xFF10B981)
                                                        .withValues(alpha: 0.2)
                                                    : Colors.redAccent
                                                        .withValues(alpha: 0.2),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isEnabled
                                                      ? const Color(0xFF10B981)
                                                      : Colors.redAccent,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                isEnabled
                                                    ? 'ACTIVE / UNLOCKED'
                                                    : 'LOCKED',
                                                style: TextStyle(
                                                  color: isEnabled
                                                      ? const Color(0xFF10B981)
                                                      : Colors.redAccent,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          svc['hindiTitle'] as String,
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          svc['desc'] as String,
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: 10,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isEnabled,
                                    activeThumbColor: const Color(0xFF10B981),
                                    activeTrackColor: const Color(0xFF10B981)
                                        .withValues(alpha: 0.4),
                                    inactiveThumbColor: Colors.redAccent,
                                    inactiveTrackColor:
                                        Colors.redAccent.withValues(alpha: 0.3),
                                    onChanged: (newVal) async {
                                      try {
                                        await CloudSyncService.setServiceSwitch(
                                          key,
                                          newVal,
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${svc['title']} ${newVal ? "UNLOCKED (Active)" : "LOCKED (Closed)"}.',
                                              ),
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      } catch (err) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Error updating switch: $err'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '💡 Changes sync instantly across all user devices through Firestore.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MASTER ADMIN ACCESS',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              'Users, Passwords & Service Controls',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline_rounded,
                color: Color(0xFF38BDF8)),
            tooltip: 'Run GitHub NCDEX Workflow',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const GitHubWorkflowDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: Color(0xFFFF5722)),
            tooltip: 'पोस्टर व विज्ञापन लगाएं (Post Poster)',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const EditPromoDialog(),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor:
                    const Color(0xFF10B981).withValues(alpha: 0.15),
                foregroundColor: const Color(0xFF10B981),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text(
                'Lock / Unlock Services',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openServiceSwitchesDialog(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // PROMINENT ADVERTISEMENT & POSTER SERVICE CARD
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16253B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF5722).withValues(alpha: 0.5),
                width: 1.4,
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
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5722).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.campaign_rounded,
                      color: Color(0xFFFF5722), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADVERTISEMENT & POSTER SERVICE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'विज्ञापन पोस्टर सेवा (डैशबोर्ड व ऐप स्टार्ट पर दिखाएं)',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5722),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.post_add_rounded, size: 16),
                  label: const Text(
                    'Post / Edit',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const EditPromoDialog(),
                    );
                  },
                ),
              ],
            ),
          ),

          // PROMINENT GITHUB WORKFLOW RUNNER CARD
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16253B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.45),
                width: 1.4,
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
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.play_circle_fill_rounded,
                      color: Color(0xFF38BDF8), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GITHUB NCDEX WORKFLOW',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'NCDEX स्क्रैपर वर्कफ़्लो ट्रिगर करें व लाइव स्टेटस देखें',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 16),
                  label: const Text(
                    'Run Workflow',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const GitHubWorkflowDialog(),
                    );
                  },
                ),
              ],
            ),
          ),

          // PROMINENT LOCK / UNLOCK SERVICES CONTROL CARD
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16253B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                width: 1.4,
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
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOCK / UNLOCK SERVICES',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'पोर्टल सेवाएं चालू / बंद करें (लाइव भाव, बायर, सेलर, ब्रोकर, बिल)',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.lock_open_rounded, size: 15),
                  label: const Text(
                    'Switches',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _openServiceSwitchesDialog(context),
                ),
              ],
            ),
          ),

          // REARRANGE & CLEAN FIRESTORE COLLECTIONS CARD
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF16253B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_fix_high_rounded,
                      color: Color(0xFF38BDF8), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REARRANGE & CLEAN COLLECTIONS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '1 User = 1 Folder (डुप्लीकेट व फैंटम डॉक्युमेंट्स हटाएं)',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.cleaning_services_rounded, size: 14),
                  label: const Text(
                    'Clean & Fix',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _showRearrangeCollectionsDialog(context),
                ),
              ],
            ),
          ),

          // HIDE / UNHIDE ANALYZER CARD
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF16253B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFA855F7).withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: StreamBuilder<dynamic>(
              stream: CloudSyncService.streamServiceSwitches(),
              builder: (context, switchSnap) {
                bool showAnalyzer = true;
                if (switchSnap.hasData && switchSnap.data != null) {
                  final dynamic raw = switchSnap.data;
                  if (raw is Map && raw['show_analyzer'] != null) {
                    final v = raw['show_analyzer'];
                    showAnalyzer =
                        v is bool ? v : (v.toString().toLowerCase() == 'true');
                  }
                }

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: showAnalyzer
                            ? const Color(0xFF10B981).withValues(alpha: 0.18)
                            : Colors.redAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        showAnalyzer
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: showAnalyzer
                            ? const Color(0xFF10B981)
                            : Colors.redAccent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'COMMODITY ANALYZER (एनालाइज़र)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            showAnalyzer
                                ? 'स्थिति: दिख रहा है (Live Bhav में एक्टिव)'
                                : 'स्थिति: छिपा हुआ है (Live Bhav में छुपा है)',
                            style: TextStyle(
                              color: showAnalyzer
                                  ? const Color(0xFF10B981)
                                  : Colors.redAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: showAnalyzer
                            ? Colors.red.shade800
                            : const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        showAnalyzer
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 14,
                      ),
                      label: Text(
                        showAnalyzer
                            ? 'Hide Analyzer (छिपाएं)'
                            : 'Unhide Analyzer (दिखाएं)',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final newStatus = !showAnalyzer;
                        await CloudSyncService.setServiceSwitch(
                            'show_analyzer', newStatus);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                newStatus
                                    ? '👁️ एनालाइज़र अब Live Bhav में दिखेगा (Unhidden)!'
                                    : '🙈 एनालाइज़र Live Bhav से छिपा दिया गया है (Hidden)!',
                              ),
                              backgroundColor: newStatus
                                  ? const Color(0xFF10B981)
                                  : Colors.orangeAccent,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by Mobile, Name, or Section...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF16253B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) =>
                  setState(() => _searchFilter = val.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: !_isAuthReady
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF5722)),
                  )
                : StreamBuilder<dynamic>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (BuildContext context,
                        AsyncSnapshot<dynamic> snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFFFF5722)),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Error loading users: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        );
                      }

                      final List<dynamic> rawDocs =
                          (snapshot.data?.docs as List<dynamic>?) ?? [];

                      // Deduplicate users list by clean 10-digit mobile number & filter out contact stubs
                      final Map<String, dynamic> uniqueByMobile = {};
                      for (final doc in rawDocs) {
                        final data = (doc.data() as Map?) ?? {};
                        final docId = doc.id?.toString() ?? '';
                        final rawMob =
                            (data['mobile'] ?? data['phone'] ?? '').toString();
                        String cleanMob = CloudSyncService.cleanMobileNumber(
                            rawMob.isNotEmpty ? rawMob : docId);
                        if (cleanMob.isEmpty) {
                          cleanMob = CloudSyncService.cleanMobileNumber(
                              docId.split('_').last);
                        }
                        final key = cleanMob.isNotEmpty ? cleanMob : docId;

                        // Check credentials
                        final pwd = (data['password'] ?? data['pin'] ?? '').toString().trim();
                        final role = (data['role'] ?? data['section'] ?? '').toString().toLowerCase();
                        final isBroker = role == 'broker' || docId.startsWith('BROKER_');
                        final hasCreds = pwd.isNotEmpty && pwd != 'N/A';

                        // Ignore broker contact stubs without login credentials
                        if (!isBroker && !hasCreds) {
                          continue;
                        }

                        if (!uniqueByMobile.containsKey(key)) {
                          uniqueByMobile[key] = doc;
                        } else if (!docId.contains('_')) {
                          uniqueByMobile[key] =
                              doc; // Prefer canonical personal folder
                        }
                      }
                      final List<dynamic> docs = uniqueByMobile.values.toList();

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No registered users in "users" collection.\nRegister an account to see it here.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white54, height: 1.5),
                          ),
                        );
                      }

                      final filtered = docs.where((dynamic d) {
                        final dynamic rawData = d.data();
                        if (rawData is! Map) return false;
                        final name = (rawData['name'] ??
                                rawData['userName'] ??
                                rawData['firmName'] ??
                                '')
                            .toString()
                            .toLowerCase();
                        final mobile =
                            (rawData['mobile'] ?? rawData['phone'] ?? d.id)
                                .toString()
                                .toLowerCase();
                        final section =
                            (rawData['section'] ?? '').toString().toLowerCase();

                        if (_searchFilter.isEmpty) return true;
                        return name.contains(_searchFilter) ||
                            mobile.contains(_searchFilter) ||
                            section.contains(_searchFilter);
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'No matching users found for this search.',
                            style: TextStyle(color: Colors.white38),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final dynamic doc = filtered[index];
                          final Map<dynamic, dynamic> data =
                              (doc.data() as Map?) ?? {};
                          final String docId = doc.id?.toString() ?? '';

                          final String name = (data['name'] ??
                                  data['userName'] ??
                                  data['firmName'] ??
                                  'Unnamed')
                              .toString();
                          final String mobile =
                              (data['mobile'] ?? data['phone'] ?? '')
                                      .toString()
                                      .isNotEmpty
                                  ? (data['mobile'] ?? data['phone']).toString()
                                  : docId.split('_').last;
                          final String password =
                              (data['password'] ?? data['pin'] ?? 'N/A')
                                  .toString();
                          final String section = (data['section'] ??
                                  (docId.contains('_')
                                      ? docId.split('_').first
                                      : 'GENERAL'))
                              .toString()
                              .toUpperCase();
                          final String email = (data['email'] ?? '').toString();
                          final bool isLocked = data['is_locked'] == true ||
                              data['is_blocked'] == true ||
                              data['subscription_due'] == true ||
                              data['account_status'] == 'locked' ||
                              data['account_status'] == 'suspended';

                          final DateTime? renewalDate =
                              CloudSyncService.parseRenewalDate(data);
                          final int? daysLeft =
                              renewalDate?.difference(DateTime.now()).inDays;
                          final String planName = (data['subscription_plan'] ??
                                  (data['subscription'] is Map
                                      ? data['subscription']['plan']
                                      : null) ??
                                  data['subscriptionPlan'] ??
                                  '1 Month')
                              .toString();

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131D2D),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isLocked
                                    ? Colors.red.shade900
                                    : const Color(0xFF223249),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isLocked
                                            ? Colors.red.withValues(alpha: 0.15)
                                            : Colors.green
                                                .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isLocked
                                              ? Colors.redAccent
                                              : Colors.greenAccent,
                                        ),
                                      ),
                                      child: Text(
                                        isLocked
                                            ? 'SUBSCRIPTION DUE'
                                            : 'ACTIVE SUBSCRIPTION',
                                        style: TextStyle(
                                          color: isLocked
                                              ? Colors.redAccent
                                              : Colors.greenAccent,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                    color: Color(0xFF223249), height: 16),
                                Row(
                                  children: [
                                    const Icon(Icons.badge_outlined,
                                        size: 14, color: Colors.white54),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Portal: $section',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 13),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.phone_android,
                                        size: 14, color: Colors.white54),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ID: $mobile',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.vpn_key_rounded,
                                          size: 15, color: Color(0xFFFF5722)),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Password / PIN: ',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12.5),
                                      ),
                                      SelectableText(
                                        password,
                                        style: const TextStyle(
                                          color: Color(0xFFFFCC80),
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Email: $email',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11.5),
                                  ),
                                ],
                                // SUBSCRIPTION RENEWAL STATUS BOX
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: renewalDate == null
                                          ? const Color(0xFF334155)
                                          : (daysLeft != null && daysLeft < 0)
                                              ? Colors.redAccent
                                                  .withValues(alpha: 0.6)
                                              : (daysLeft != null &&
                                                      daysLeft <= 7)
                                                  ? Colors.amber
                                                      .withValues(alpha: 0.7)
                                                  : const Color(0xFF10B981)
                                                      .withValues(alpha: 0.5),
                                      width: 1.1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_repeat_rounded,
                                        size: 16,
                                        color: renewalDate == null
                                            ? Colors.white54
                                            : (daysLeft != null && daysLeft < 0)
                                                ? Colors.redAccent
                                                : (daysLeft != null &&
                                                        daysLeft <= 7)
                                                    ? Colors.amber
                                                    : const Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              renewalDate != null
                                                  ? 'Renewal: ${renewalDate.day.toString().padLeft(2, '0')}-${renewalDate.month.toString().padLeft(2, '0')}-${renewalDate.year} ($planName)'
                                                  : 'Renewal: No Date Set ($planName)',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              renewalDate == null
                                                  ? 'Tap "Extend Date" to set renewal'
                                                  : (daysLeft != null &&
                                                          daysLeft < 0)
                                                      ? '⚠️ Subscription overdue by ${-daysLeft} days!'
                                                      : (daysLeft != null &&
                                                              daysLeft <= 7)
                                                          ? '🔔 Reminder: Only $daysLeft days left!'
                                                          : 'Active Subscription ($daysLeft days left)',
                                              style: TextStyle(
                                                color: renewalDate == null
                                                    ? Colors.white38
                                                    : (daysLeft != null &&
                                                            daysLeft < 0)
                                                        ? Colors.redAccent
                                                        : (daysLeft != null &&
                                                                daysLeft <= 7)
                                                            ? Colors.amber
                                                            : const Color(
                                                                0xFF94A3B8),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor:
                                              const Color(0xFF38BDF8),
                                        ),
                                        icon: const Icon(
                                            Icons.edit_calendar_rounded,
                                            size: 14),
                                        label: const Text('Extend Date',
                                            style: TextStyle(fontSize: 11)),
                                        onPressed: () =>
                                            _openSubscriptionActivationDialog(
                                          section: section,
                                          mobile: mobile,
                                          userName: name,
                                          existingRenewalDate: renewalDate,
                                          isAlreadyActive: !isLocked,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF25D366),
                                        side: const BorderSide(
                                            color: Color(0xFF25D366),
                                            width: 1.1),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        visualDensity: VisualDensity.compact,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(
                                          Icons.chat_bubble_outline_rounded,
                                          size: 14),
                                      label: const Text(
                                        'WhatsApp Reminder',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      onPressed: () =>
                                          _sendWhatsAppRenewalReminder(
                                        mobile: mobile,
                                        userName: name,
                                        section: section,
                                        renewalDate: renewalDate,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        if (isLocked) {
                                          _openSubscriptionActivationDialog(
                                            section: section,
                                            mobile: mobile,
                                            userName: name,
                                            existingRenewalDate: renewalDate,
                                            isAlreadyActive: false,
                                          );
                                        } else {
                                          _toggleUserLock(
                                            section: section,
                                            mobile: mobile,
                                            currentLockedState: isLocked,
                                            userName: name,
                                          );
                                        }
                                      },
                                      icon: Icon(
                                        isLocked
                                            ? Icons.lock_open_rounded
                                            : Icons.lock_outline_rounded,
                                        size: 16,
                                        color: isLocked
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                      label: Text(
                                        isLocked
                                            ? 'Turn ON (Activate)'
                                            : 'Block / Overdue',
                                        style: TextStyle(
                                          color: isLocked
                                              ? Colors.greenAccent
                                              : Colors.orangeAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Colors.redAccent),
                                      tooltip: 'Delete Account',
                                      onPressed: () => _confirmDeleteUser(
                                        section: section,
                                        mobile: mobile,
                                        userName: name,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// BILL GENERATOR MAINTENANCE SCREEN (7-TAP SECRET BYPASS)
// =============================================================
class BillGeneratorMaintenanceScreen extends StatefulWidget {
  final String username;

  const BillGeneratorMaintenanceScreen({super.key, required this.username});

  @override
  State<BillGeneratorMaintenanceScreen> createState() =>
      _BillGeneratorMaintenanceScreenState();
}

class _BillGeneratorMaintenanceScreenState
    extends State<BillGeneratorMaintenanceScreen> {
  int _secretTapCount = 0;

  void _showHiddenAccessDialog() {
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFA855F7)),
            SizedBox(width: 10),
            Text(
              'Admin Bypass Access',
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the administrator bypass key to access the Bill Generator:',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: keyController,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Master Security Key',
                labelStyle: TextStyle(color: Colors.black54),
                prefixIcon:
                    Icon(Icons.shield_outlined, color: Color(0xFFA855F7)),
                border: OutlineInputBorder(),
                isDense: true,
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
              backgroundColor: const Color(0xFFA855F7),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final entered = keyController.text.trim();
              if (entered == '2850') {
                Navigator.pop(ctx);
                StorageService.save('session_BILL_GENERATOR_UNLOCKED', 'true');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BillGeneratorSectionPortal(
                      username: widget.username,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Invalid Master Key!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('BYPASS & ENTER'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: const Text('BILL GENERATOR'),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              StorageService.remove('session_BILL GENERATOR');
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainDashboardScreen(),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    _secretTapCount++;
                    if (_secretTapCount >= 7) {
                      _secretTapCount = 0;
                      _showHiddenAccessDialog();
                    }
                  },
                  child: CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.orange.withValues(alpha: 0.15),
                    child: const Icon(
                      Icons.build_circle_outlined,
                      size: 44,
                      color: Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'SYSTEM UNDER MAINTENANCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'User: ${widget.username}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    'This service is permanently closed, so please use other service.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.brown,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('BACK TO DASHBOARD'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// LOGIN GATE WITH REAL-TIME CLOUD CREDENTIAL VALIDATION
// =============================================================
class SectionLoginGate extends StatefulWidget {
  final String sectionName;

  const SectionLoginGate({super.key, required this.sectionName});

  @override
  State<SectionLoginGate> createState() => _SectionLoginGateState();
}

class _SectionLoginGateState extends State<SectionLoginGate> {
  final _mobileController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscurePin = true;
  bool _isLoading = false;

  static const String adminSupportPhone = '+919983325558';

  @override
  void initState() {
    super.initState();
    final savedMobile =
        StorageService.get('session_${widget.sectionName}_mobile') ??
            StorageService.get('session_${widget.sectionName}');
    if (savedMobile != null && savedMobile.toString().isNotEmpty) {
      _mobileController.text = savedMobile.toString();
    }
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _requestPasswordResetViaWhatsApp() async {
    final cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final enteredMobile = _mobileController.text.trim();

    final message = enteredMobile.isNotEmpty
        ? 'नमस्ते Mandi Support Team, मैं (${widget.sectionName}) पोर्टल का उपयोगकर्ता हूँ। मेरा पंजीकृत मोबाइल नंबर $enteredMobile है। कृपया मेरा पासवर्ड / PIN रीसेट करने में सहायता करें।'
        : 'नमस्ते Mandi Support Team, मैं (${widget.sectionName}) पोर्टल का उपयोगकर्ता हूँ। कृपया मेरा पासवर्ड / PIN रीसेट करने में सहायता करें।';

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

  void _initiateLogin() async {
    final identifier = _mobileController.text.trim();
    final pin = _pinController.text.trim();

    if (identifier.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your Mobile Number and Password'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dynamic rawCloudData =
          await CloudSyncService.getAccountByIdentifier(identifier)
              .timeout(const Duration(seconds: 6), onTimeout: () => null);

      if (!mounted) return;

      if (rawCloudData == null || rawCloudData is! Map) {
        final accounts = AccountService.getAllAccounts();
        accounts.removeWhere(
          (a) =>
              a.mobile.trim() == identifier ||
              a.email.trim().toLowerCase() == identifier.toLowerCase(),
        );
        AccountService.saveAccounts(accounts);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account not found! If you changed your mobile or Gmail, please log in with your updated details.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final Map<String, dynamic> cloudData =
          Map<String, dynamic>.from(rawCloudData);

      final bool isLocked = cloudData['is_locked'] == true ||
          cloudData['is_blocked'] == true ||
          cloudData['account_status'] == 'locked' ||
          cloudData['account_status'] == 'suspended';

      if (isLocked) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payment_rounded, color: Colors.amber, size: 28),
                SizedBox(width: 10),
                Text(
                  'Subscription Due',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your portal subscription has expired or is currently overdue.',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Please renew your plan or contact the mandi admin office to reactivate your access.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final UserAccount liveUser = UserAccount.fromJson(cloudData);
      final accounts = AccountService.getAllAccounts();
      accounts.removeWhere(
        (a) => a.mobile == liveUser.mobile && a.section == liveUser.section,
      );
      accounts.add(liveUser);
      AccountService.saveAccounts(accounts);

      if (liveUser.section.toUpperCase() != widget.sectionName.toUpperCase()) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Access Denied',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'This account is registered under "${liveUser.section}". Please log in through the ${liveUser.section} portal.',
              style: const TextStyle(color: Colors.black87),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      if (liveUser.password.trim() != pin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect Password / PIN!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final emailToUse = liveUser.email.trim();
      if (emailToUse.isEmpty || !emailToUse.contains('@')) {
        // Direct login permitted for accounts created without an email (e.g. party created by broker)
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('लॉगिन सफल! (सुझाव: 2-Step OTP सुरक्षा हेतु प्रोफाइल में ईमेल अवश्य जोड़ें)'),
              backgroundColor: Color(0xFF0F766E),
              duration: Duration(seconds: 4),
            ),
          );
          _completeSuccessfulLogin(liveUser);
        }
        return;
      }

      final loginOtp = (100000 + Random().nextInt(900000)).toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sending security OTP to $emailToUse...'),
          backgroundColor: const Color(0xFF0F766E),
          duration: const Duration(seconds: 3),
        ),
      );

      bool sent = false;
      try {
        sent = await EmailService.sendOtpEmail(
          recipientEmail: emailToUse,
          recipientName: liveUser.name,
          otp: loginOtp,
          purpose: 'Login',
        ).timeout(const Duration(seconds: 15), onTimeout: () {
          debugPrint('❌ Email delivery timed out after 15 seconds.');
          return false;
        });
      } catch (e) {
        debugPrint('❌ EmailService threw an unhandled exception: $e');
        sent = false;
      }

      if (!mounted) return;

      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to deliver OTP to $emailToUse.\nPlease check phone internet, Private DNS, or EmailJS monthly quota.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      setState(() => _isLoading = false);
      _showLoginOtpDialog(liveUser, loginOtp);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _completeSuccessfulLogin(UserAccount account) {
    StorageService.save(
      'session_${widget.sectionName}',
      account.mobile,
    );
    StorageService.save(
      'session_${widget.sectionName}_name',
      account.name,
    );
    StorageService.save(
      'session_${widget.sectionName}_mobile',
      account.mobile,
    );
    StorageService.save(
      'session_${widget.sectionName}_email',
      account.email,
    );
    StorageService.save(
      'session_${widget.sectionName}_address',
      account.address,
    );

    final allAccounts = AccountService.getAllAccounts();
    final index = allAccounts.indexWhere(
      (a) =>
          a.mobile == account.mobile &&
          a.section == widget.sectionName,
    );
    if (index >= 0) {
      allAccounts[index] = account;
    } else {
      allAccounts.add(account);
    }
    AccountService.saveAccounts(allAccounts);

    Widget targetPortal;
    if (widget.sectionName == 'BROKER') {
      targetPortal = const BrokerSectionPortal();
    } else if (widget.sectionName == 'BUYER') {
      targetPortal = BuyerSectionPortal(user: account);
    } else if (widget.sectionName == 'SELLER') {
      targetPortal = SellerSectionPortal(user: account);
    } else {
      final isUnlocked =
          StorageService.get('session_BILL_GENERATOR_UNLOCKED') ==
              'true';
      targetPortal = isUnlocked
          ? BillGeneratorSectionPortal(username: account.name)
          : BillGeneratorMaintenanceScreen(username: account.name);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => targetPortal),
    );
  }

  void _showLoginOtpDialog(UserAccount account, String expectedOtp) {
    final otpCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.mark_email_read, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text(
              'Enter Email OTP',
              style: TextStyle(color: Colors.black87),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the 6-digit code sent to ${account.email}:',
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-Digit OTP',
                labelStyle: TextStyle(color: Colors.black54),
                prefixIcon: Icon(Icons.pin, color: Color(0xFF0F766E)),
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
              final enteredOtp = otpCtrl.text.trim();
              if (enteredOtp != expectedOtp) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid OTP! Please check your email inbox.',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);
              _completeSuccessfulLogin(account);
            },
            child: const Text('VERIFY & ENTER'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuyer = widget.sectionName.toUpperCase().contains('BUYER');
    final isSeller = widget.sectionName.toUpperCase().contains('SELLER');
    final brandColor = isBuyer
        ? const Color(0xFF0284C7)
        : isSeller
            ? const Color(0xFFD97706)
            : const Color(0xFF0F766E);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('${widget.sectionName} PORTAL LOGIN'),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
      ),
      body: Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(
            primary: brandColor,
            onSurface: const Color(0xFF0F172A),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor:
                        const Color(0xFF0F766E).withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.shield_outlined,
                      size: 36,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${widget.sectionName} SIGN IN',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: '10-Digit Mobile Number',
                      labelStyle: const TextStyle(color: Colors.black54),
                      prefixIcon: const Icon(
                        Icons.phone_android,
                        color: Color(0xFF0F766E),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF0F766E),
                          width: 2,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinController,
                    obscureText: _obscurePin,
                    keyboardType: TextInputType.visiblePassword,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Security PIN / Password',
                      labelStyle: const TextStyle(color: Colors.black54),
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        color: Color(0xFF0F766E),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade400),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF0F766E),
                          width: 2,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility_off : Icons.visibility,
                          color: Colors.black54,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePin = !_obscurePin),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _requestPasswordResetViaWhatsApp,
                      icon: const Icon(Icons.chat,
                          size: 14, color: Color(0xFF25D366)),
                      label: const Text(
                        'पासवर्ड भूल गए? (WhatsApp रीसेट)',
                        style: TextStyle(
                          color: Color(0xFF25D366),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isLoading ? null : _initiateLogin,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.login),
                    label:
                        Text(_isLoading ? 'LOGGING IN...' : 'LOGIN TO PORTAL'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.black12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFF0F766E)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CreateAccountScreen(
                            sectionName: widget.sectionName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.person_add_outlined,
                      color: Color(0xFF0F766E),
                    ),
                    label: const Text(
                      'CREATE NEW ACCOUNT',
                      style: TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// MODERN PROGRESSIVE ONBOARDING: EMAIL -> OTP -> CREATE PASSWORD
// =============================================================
class CreateAccountScreen extends StatefulWidget {
  final String sectionName;

  const CreateAccountScreen({super.key, required this.sectionName});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  int _currentStep = 1;

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String _generatedOtp = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Gmail address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await CloudSyncService.ensureAuthSession();

      final existing = await CloudSyncService.getAccountByIdentifier(email)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);

      if (!mounted) return;

      if (existing != null) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Email already registered under "${existing['section']}"!',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _generatedOtp = (100000 + Random().nextInt(900000)).toString();

      final sent = await EmailService.sendOtpEmail(
        recipientEmail: email,
        recipientName: 'New Member',
        otp: _generatedOtp,
        purpose: 'Account Registration',
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (sent) {
        setState(() => _currentStep = 2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OTP sent to $email'),
            backgroundColor: const Color(0xFF0F766E),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to deliver email. Check internet connection or EmailJS keys.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleVerifyOtp() {
    if (_otpCtrl.text.trim() == _generatedOtp) {
      setState(() => _currentStep = 3);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid OTP! Please check your email inbox.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleCompleteRegistration() async {
    final name = _nameCtrl.text.trim().toUpperCase();
    final mobile = _mobileCtrl.text.trim();
    final address = _addressCtrl.text.trim().toUpperCase();
    final password = _passwordCtrl.text.trim();
    final confirmPassword = _confirmPasswordCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();

    if (name.isEmpty ||
        mobile.length != 10 ||
        address.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all fields correctly (Mobile must be 10 digits)',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await CloudSyncService.ensureAuthSession();

      final bool mobileExists =
          await CloudSyncService.isMobileRegistered(mobile);
      if (mobileExists) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mobile $mobile is already registered in the Mandi Network! Please login with your password.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      final newAccount = UserAccount(
        name: name,
        mobile: mobile,
        email: email,
        address: address,
        password: password,
        section: widget.sectionName,
      );

      final accounts = AccountService.getAllAccounts();
      accounts.removeWhere(
        (a) => a.mobile == mobile && a.section == widget.sectionName,
      );
      accounts.add(newAccount);
      AccountService.saveAccounts(accounts);

      try {
        await CloudSyncService.saveAccount(newAccount.toJson())
            .timeout(const Duration(seconds: 8));

        if (widget.sectionName == 'BROKER') {
          await CloudSyncService.initializeBrokerAccount(
            brokerKey: mobile,
            brokerName: name,
            phone: mobile,
            email: email,
            address: address,
          );

          final brokerProfile = BrokerFirmProfileModel(
            firmName: name,
            mobile: mobile,
            email: email,
            address: address,
          );
          await CloudSyncService.saveBrokerProfile(
            mobile,
            brokerProfile.toJson(),
          ).timeout(const Duration(seconds: 8));
        }
      } catch (cloudErr) {
        debugPrint('❌ CloudSync Write Error: $cloudErr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Cloud sync warning: $cloudErr'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      StorageService.save('session_${widget.sectionName}', mobile);
      StorageService.save('session_${widget.sectionName}_name', name);
      StorageService.save('session_${widget.sectionName}_mobile', mobile);
      StorageService.save('session_${widget.sectionName}_email', email);
      StorageService.save('session_${widget.sectionName}_address', address);

      try {
        TelegramNotificationService.notifyNewRegistration(
          name: name,
          mobile: mobile,
          section: widget.sectionName,
          email: email,
          address: address,
        );
      } catch (tgErr) {
        debugPrint('Telegram notification failed: $tgErr');
      }

      if (!mounted) return;

      Widget targetPortal;
      if (widget.sectionName == 'BROKER') {
        targetPortal = const BrokerSectionPortal();
      } else if (widget.sectionName == 'BUYER') {
        targetPortal = BuyerSectionPortal(user: newAccount);
      } else if (widget.sectionName == 'SELLER') {
        targetPortal = SellerSectionPortal(user: newAccount);
      } else {
        targetPortal =
            BillGeneratorMaintenanceScreen(username: newAccount.name);
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => targetPortal),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStepIndicator(int step, String label) {
    final isDone = _currentStep > step;
    final isCurrent = _currentStep == step;

    return Column(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: isDone || isCurrent
              ? const Color(0xFF0F766E)
              : Colors.grey.shade300,
          child: isDone
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : Text(
                  '$step',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? Colors.white : Colors.grey.shade700,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCurrent ? const Color(0xFF0F766E) : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider(bool active) {
    return Container(
      width: 32,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      color: active ? const Color(0xFF0F766E) : Colors.grey.shade300,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuyer = widget.sectionName.toUpperCase().contains('BUYER');
    final isSeller = widget.sectionName.toUpperCase().contains('SELLER');
    final brandColor = isBuyer
        ? const Color(0xFF0284C7)
        : isSeller
            ? const Color(0xFFD97706)
            : const Color(0xFF0F766E);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('REGISTER ${widget.sectionName}'),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
      ),
      body: Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(
            primary: brandColor,
            onSurface: const Color(0xFF0F172A),
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStepIndicator(1, 'Email'),
                      _buildStepDivider(_currentStep >= 2),
                      _buildStepIndicator(2, 'Verify'),
                      _buildStepDivider(_currentStep >= 3),
                      _buildStepIndicator(3, 'Password'),
                    ],
                  ),
                  const Divider(height: 28, color: Colors.black12),
                  if (_currentStep == 1) ...[
                    const Text(
                      'Step 1: Verify Email Address',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'We will send a 6-digit confirmation OTP to your Gmail.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Gmail Address',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: Color(0xFF0F766E),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isLoading ? null : _handleSendOtp,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.send),
                      label: Text(
                        _isLoading ? 'SENDING OTP...' : 'SEND VERIFICATION OTP',
                      ),
                    ),
                  ],
                  if (_currentStep == 2) ...[
                    const Text(
                      'Step 2: Enter Verification Code',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the 6-digit OTP sent to ${_emailCtrl.text.trim()}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: '6-Digit OTP',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(Icons.pin, color: Color(0xFF0F766E)),
                        border: OutlineInputBorder(),
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading ? null : _handleSendOtp,
                        child: const Text(
                          'Resend OTP',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _handleVerifyOtp,
                      child: const Text('VERIFY OTP'),
                    ),
                  ],
                  if (_currentStep == 3) ...[
                    const Text(
                      'Step 3: Setup Profile & Password',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Email verified! Provide details and choose your password.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Full Name / Firm Name',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: Color(0xFF0F766E),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: '10-Digit Mobile Number (Login ID)',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.phone_android,
                          color: Color(0xFF0F766E),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      inputFormatters: [UpperCaseTextFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Mandi / Office Address',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.location_on_outlined,
                          color: Color(0xFF0F766E),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Create Password',
                        labelStyle: const TextStyle(color: Colors.black54),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: Color(0xFF0F766E),
                        ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.black54,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _confirmPasswordCtrl,
                      obscureText: _obscurePassword,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        labelStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(
                          Icons.lock_reset,
                          color: Color(0xFF0F766E),
                        ),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed:
                          _isLoading ? null : _handleCompleteRegistration,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isLoading
                            ? 'CREATING ACCOUNT...'
                            : 'REGISTER & COMPLETE',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
