import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/email_service.dart';
import '../services/mandi_services.dart';
import 'bill_generator_screen.dart';
import 'broker_portal_screen.dart';
import 'buyer_portal_screen.dart';
import 'contact_services_screen.dart';
import 'market_watch_screen.dart';
import 'seller_portal_screen.dart';

// =============================================================
// MAIN 6-SECTION DASHBOARD
// =============================================================
class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAuth();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.checkForUpdates(context);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Notice',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: const Text(
          'This service is permanently closed, so please use other service.',
          style: TextStyle(fontSize: 13),
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

  void _openMainMenuProfileDialog() {
    final allAccounts = AccountService.getAllAccounts();
    final brokerUser = AccountService.getSessionUser('BROKER');
    final buyerUser = AccountService.getSessionUser('BUYER');
    final sellerUser = AccountService.getSessionUser('SELLER');
    final billUser = AccountService.getSessionUser('BILL GENERATOR');

    final activeUser = brokerUser ?? buyerUser ?? sellerUser ?? billUser;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.account_circle, color: Color(0xFF14B8A6), size: 28),
            SizedBox(width: 10),
            Text(
              'User Profile & Accounts',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
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
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Email: ${activeUser.email.isNotEmpty ? activeUser.email : "Not Provided"}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      if (activeUser.address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Address: ${activeUser.address}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ],
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
                    StorageService.remove('session_BILL_GENERATOR_UNLOCKED');
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Logged out of active session successfully.'),
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
                      Icon(Icons.person_outline, size: 36, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No Active User Logged In',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Tap any of the portal cards to sign in to your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
              if (allAccounts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Saved Device Accounts:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                ...allAccounts.map((acc) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Navigator.pop(ctx);
                        _routeToSection(context, acc.section.toUpperCase());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${acc.section} • ${acc.mobile}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 16, color: Colors.grey),
                          ],
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
          child: StreamBuilder<Map<String, dynamic>>(
            stream: CloudSyncService.streamServiceSwitches(),
            builder: (context, snapshot) {
              final config = snapshot.data ?? const {};

              final bool enableMarketView = config['market_view'] ?? true;
              final bool enableBuyerPortal = config['buyer_portal'] ?? true;
              final bool enableSellerPortal = config['seller_portal'] ?? true;

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
                            Container(
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
                                    'APMC • E-MANDI NETWORK',
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
                        const SizedBox(height: 24),

                        // 1. MARKET VIEW
                        _buildSectionCard(
                          context: context,
                          title: 'MARKET VIEW',
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
                              _showLockedNotice(context, 'Market View');
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // 2. BUYER
                        _buildSectionCard(
                          context: context,
                          title: 'BUYER',
                          hindiTitle: 'खरीदार खाता एवं ब्रोकर सूची',
                          description: enableBuyerPortal
                              ? 'Browse brokers, confirm purchases & view khata'
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
                              ? 'Browse brokers, confirm sales & view khata'
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

                        // 4. BROKER (ALWAYS ACTIVE)
                        _buildSectionCard(
                          context: context,
                          title: 'BROKER',
                          hindiTitle: 'ब्रोकर बही व टेम्पलेट',
                          description:
                              'Deal entry, custom templates & settlement (ACTIVE)',
                          icon: Icons.handshake_rounded,
                          accentColor: const Color(0xFF14B8A6),
                          badgeText: 'BROKER SYSTEM',
                          isPublic: false,
                          isHighlighted: true,
                          onTap: () => _routeToSection(context, 'BROKER'),
                        ),
                        const SizedBox(height: 12),

                        // 5. BILL GENERATOR
                        _buildSectionCard(
                          context: context,
                          title: 'BILL GENERATOR',
                          hindiTitle: 'बिल एवं पर्चा जनरेटर',
                          description:
                              'Farmer mandi slips, weight tally & statement print',
                          icon: Icons.receipt_long_rounded,
                          accentColor: const Color(0xFFA855F7),
                          badgeText: 'SECURE DESK',
                          isPublic: false,
                          onTap: () =>
                              _routeToSection(context, 'BILL GENERATOR'),
                        ),
                        const SizedBox(height: 12),

                        // 6. CONTACT US & SERVICES
                        _buildSectionCard(
                          context: context,
                          title: 'CONTACT US & SERVICES',
                          hindiTitle:
                              'सहायता, सब्सक्रिप्शन, विज्ञापन व WhatsApp रीसेट',
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
                          'Broker Directory Table • Visible Broker Info • Custom WhatsApp Templates',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFA855F7)),
            SizedBox(width: 10),
            Text(
              'Admin Bypass Access',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Master Security Key',
                prefixIcon: Icon(Icons.shield_outlined),
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

  static const String adminSupportPhone = '+919876543210';

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
      final cloudData =
          await CloudSyncService.getAccountByIdentifier(identifier)
              .timeout(const Duration(seconds: 6), onTimeout: () => null);

      if (!mounted) return;

      if (cloudData == null) {
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

      final bool isLocked = cloudData['is_locked'] == true ||
          cloudData['is_blocked'] == true ||
          cloudData['account_status'] == 'locked' ||
          cloudData['account_status'] == 'suspended';

      if (isLocked) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payment_rounded, color: Colors.amber, size: 28),
                SizedBox(width: 10),
                Text(
                  'Subscription Due',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your portal subscription has expired or is currently overdue.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
            title: const Text(
              'Access Denied',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'This account is registered under "${liveUser.section}". Please log in through the ${liveUser.section} portal.',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Invalid or missing email ($emailToUse) for this account.'),
            backgroundColor: Colors.red,
          ),
        );
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

  void _showLoginOtpDialog(UserAccount account, String expectedOtp) {
    final otpCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mark_email_read, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('Enter Email OTP'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the 6-digit code sent to ${account.email}:'),
            const SizedBox(height: 16),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '6-Digit OTP',
                prefixIcon: Icon(Icons.pin),
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
            },
            child: const Text('VERIFY & ENTER'),
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
        title: Text('${widget.sectionName} PORTAL LOGIN'),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 18,
                  offset: Offset(0, 6),
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
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: '10-Digit Mobile Number',
                    prefixIcon: Icon(Icons.phone_android),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pinController,
                  obscureText: _obscurePin,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    labelText: 'Security PIN / Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePin ? Icons.visibility_off : Icons.visibility,
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
                  label: Text(_isLoading ? 'LOGGING IN...' : 'LOGIN TO PORTAL'),
                ),
                const SizedBox(height: 16),
                const Divider(),
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
        setState(() => _isLoading = false);
        if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: Text('REGISTER ${widget.sectionName}'),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.all(Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 18,
                  offset: Offset(0, 6),
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
                const Divider(height: 28),
                if (_currentStep == 1) ...[
                  const Text(
                    'Step 1: Verify Email Address',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                    decoration: const InputDecoration(
                      labelText: 'Gmail Address',
                      prefixIcon: Icon(Icons.email_outlined),
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
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the 6-digit OTP sent to ${_emailCtrl.text.trim()}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '6-Digit OTP',
                      prefixIcon: Icon(Icons.pin),
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
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
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
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Full Name / Firm Name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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
                      labelText: '10-Digit Mobile Number (Login ID)',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _addressCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [UpperCaseTextFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Mandi / Office Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Create Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
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
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: Icon(Icons.lock_reset),
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
                    onPressed: _isLoading ? null : _handleCompleteRegistration,
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
    );
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
}
