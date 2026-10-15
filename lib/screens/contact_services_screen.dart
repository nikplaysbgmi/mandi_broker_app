import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/email_service.dart';

// =============================================================
// MODULE: CONTACT US & SERVICES HUB (WHATSAPP RESET ENABLED)
// =============================================================
class ContactServicesScreen extends StatelessWidget {
  const ContactServicesScreen({super.key});

  static const String adminSupportPhone = '+919983325558';
  static const String adminSupportEmail = 'teamknclabs@gmail.com';

  Future<void> _openWhatsApp(BuildContext context, String message) async {
    String cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) {
      cleanPhone = '91$cleanPhone';
    }

    final url = Uri.parse(
        'https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}');
    final canLaunch = await canLaunchUrl(url);
    if (!context.mounted) return;

    if (canLaunch) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('WhatsApp cannot be launched on this device')),
      );
    }
  }

  Future<void> _makePhoneCall(BuildContext context) async {
    final url = Uri.parse('tel:$adminSupportPhone');
    final canLaunch = await canLaunchUrl(url);
    if (!context.mounted) return;

    if (canLaunch) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not initiate phone call')),
      );
    }
  }

  // 1. PROMOTION / POSTER REQUEST MODAL
  void _openPromotionDialog(BuildContext context) {
    final firmNameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16253B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.campaign,
                            color: Colors.deepOrange, size: 26),
                        SizedBox(width: 8),
                        Text(
                          'प्रमोशन / विज्ञापन अनुरोध',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'मार्केट टर्मिनल में अपनी फर्म या ब्रोकरेज का पोस्टर लगाने हेतु विवरण भरें:',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: firmNameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'फर्म / व्यापारी का नाम (Firm Name)',
                    labelStyle: TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Color(0xFF0B1320),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: contactCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '10-अंकों का मोबाइल / WhatsApp नंबर',
                    labelStyle: TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Color(0xFF0B1320),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'विज्ञापन विवरण (बैनर संदेश, जिंस आदि)',
                    labelStyle: TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: Color(0xFF0B1320),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final firm = firmNameCtrl.text.trim();
                          final contact = contactCtrl.text.trim();
                          final details = detailsCtrl.text.trim();

                          if (firm.isEmpty || contact.length < 10) {
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'कृपया फर्म का नाम और 10-अंकों का मोबाइल नंबर भरें'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setModalState(() => isSubmitting = true);

                          final content = '''
<h3>नया प्रमोशन अनुरोध (New Banner Ad Request)</h3>
<p><b>Firm Name:</b> $firm</p>
<p><b>Contact:</b> $contact</p>
<p><b>Details:</b> $details</p>
<p>Sent from Mandi Broker App</p>
''';

                          final bool sent = await EmailService.sendBillEmail(
                            recipientEmail: adminSupportEmail,
                            recipientName: 'Mandi Admin',
                            subject: 'नया प्रमोशन अनुरोध: $firm',
                            htmlContent: content,
                          );

                          if (!modalContext.mounted) return;
                          Navigator.pop(ctx);

                          if (!context.mounted) return;
                          if (sent) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'विज्ञापन अनुरोध भेज दिया गया है! हमारी टीम शीघ्र संपर्क करेगी।',
                                ),
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                          } else {
                            // Fallback to WhatsApp if email fails
                            _openWhatsApp(
                              context,
                              'नमस्ते Mandi Admin, नया प्रमोशन अनुरोध:\nफर्म: $firm\nमोबाइल: $contact\nविवरण: $details',
                            );
                          }
                        },
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                  label: Text(
                    isSubmitting ? 'भेजा जा रहा है...' : 'अनुरोध सबमिट करें',
                    style: const TextStyle(
                      color: Colors.white,
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

  // 2. SUBSCRIPTION MODAL
  void _openSubscriptionDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16253B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.workspace_premium,
                    color: Color(0xFFFFD700), size: 28),
                SizedBox(width: 10),
                Text(
                  'सब्सक्रिप्शन एवं प्लान (Subscription)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1320),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'मंडी प्रो प्लान (Mandi Pro)',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Chip(
                        label: Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: Color(0xFF0F766E),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• लाइव NCDEX एवं MCX रियल-टाइम कोट्स',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  Text(
                    '• असीमित बिल जनरेटर, पर्चा व तुलाई शीट',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                  Text(
                    '• Brevo ईमेल इनवॉइस एवं सुरक्षित क्लाउड बैकअप',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _openWhatsApp(
                  context,
                  'नमस्ते, मुझे Mandi Broker App की सब्सक्रिप्शन रिन्यू / अपग्रेड करवानी है।',
                );
              },
              icon: const Icon(Icons.chat),
              label: const Text(
                'सब्सक्रिप्शन रिन्यू करें (WhatsApp)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: const Text('CONTACT US & SERVICES'),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131D2D),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF223249)),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF06B6D4),
                    child: Icon(Icons.support_agent_rounded,
                        color: Colors.white, size: 28),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'मंडी सहायता केंद्र',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'विज्ञापन, WhatsApp पासवर्ड रीसेट, प्लान रिन्यूअल व डायरेक्ट सपोर्ट',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Service 1: Promotion Request
            _buildServiceTile(
              context: context,
              icon: Icons.campaign_rounded,
              iconColor: Colors.deepOrange,
              title: 'प्रमोशन / विज्ञापन अनुरोध (Promotion Request)',
              subtitle:
                  'मार्केट टर्मिनल में अपनी दुकान या फर्म का पोस्टर लगवाएं',
              onTap: () => _openPromotionDialog(context),
            ),
            const SizedBox(height: 10),

            // Service 2: Reset Password via WhatsApp
            _buildServiceTile(
              context: context,
              icon: Icons.lock_reset_rounded,
              iconColor: const Color(0xFF25D366),
              title: 'पासवर्ड / PIN रीसेट अनुरोध (WhatsApp Reset)',
              subtitle:
                  'पासवर्ड भूल गए हैं या बदलना है? WhatsApp पर एडमिन से रीसेट करवाएं',
              onTap: () => _openWhatsApp(
                context,
                'नमस्ते Mandi Support Team, मुझे अपने खाते का पासवर्ड / PIN रीसेट करवाना है। कृपया सहायता करें।',
              ),
            ),
            const SizedBox(height: 10),

            // Service 3: Subscription Status
            _buildServiceTile(
              context: context,
              icon: Icons.workspace_premium_rounded,
              iconColor: const Color(0xFFFFD700),
              title: 'सब्सक्रिप्शन एवं प्लान (Subscription Status)',
              subtitle: 'सक्रिय प्लान की जांच करें व WhatsApp पर रिन्यू करवाएं',
              onTap: () => _openSubscriptionDialog(context),
            ),
            const SizedBox(height: 16),

            const Divider(color: Color(0xFF223249)),
            const SizedBox(height: 10),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _openWhatsApp(
                context,
                'नमस्ते Mandi Support Team, मुझे सहायता की आवश्यकता है।',
              ),
              icon: const Icon(Icons.chat),
              label: const Text(
                'WHATSAPP सहायता डेस्क',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 10),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF38BDF8),
                side: const BorderSide(color: Color(0xFF38BDF8), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _makePhoneCall(context),
              icon: const Icon(Icons.call),
              label: const Text(
                'कॉल करें (CALL SUPPORT DESK)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF131D2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF223249)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: iconColor.withValues(alpha: 0.15),
                child: Icon(icon, color: iconColor, size: 22),
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
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
