import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/mandi_services.dart';
import '../services/mandi_templates_pdf_service.dart';

class MandiDownloadsScreen extends StatefulWidget {
  const MandiDownloadsScreen({super.key});

  @override
  State<MandiDownloadsScreen> createState() => _MandiDownloadsScreenState();
}

class _MandiDownloadsScreenState extends State<MandiDownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingApk = false;
  String _latestVersion = AppUpdateService.currentVersion;
  String? _apkDownloadUrl;
  String _releaseNotes = 'New stable build with enhanced speed and features.';

  static const String adminSupportPhone = '+919983325558';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchVersionInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchVersionInfo() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version_control')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _latestVersion =
                (data['latest_version'] ?? _latestVersion).toString();
            _apkDownloadUrl = (data['download_url'] ?? '').toString().trim();
            _releaseNotes = (data['release_notes'] ?? _releaseNotes).toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _downloadApk() async {
    setState(() => _isLoadingApk = true);
    try {
      String targetUrl = _apkDownloadUrl ?? '';
      if (targetUrl.isEmpty) {
        // Fallback default release download URL
        targetUrl =
            'https://github.com/nikplaysbgmi/mandi_broker_app/releases/latest';
      }

      final uri = Uri.parse(targetUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('डाउनलोड लिंक खोलने में समस्या आई')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('डाउनलोड एरर: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingApk = false);
    }
  }

  Future<void> _openWhatsAppCustomForm() async {
    String cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) cleanPhone = '91$cleanPhone';
    final msg = Uri.encodeComponent(
      'नमस्ते Mandi Support Team, मुझे अपनी मंडी फर्म के लिए कस्टमाइज्ड प्रिंटिंग फॉर्म (सौदा / बिल फॉर्मेट) बनवाना है।',
    );
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _previewAndPrintPdf({
    required String title,
    required Future<dynamic> Function(PdfPageFormat) builder,
    required String filename,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFF0B1320),
          appBar: AppBar(
            title: Text(title, style: const TextStyle(fontSize: 16)),
            backgroundColor: const Color(0xFF16253B),
            foregroundColor: Colors.white,
          ),
          body: PdfPreview(
            build: (format) async => await builder(format),
            canChangeOrientation: false,
            canChangePageFormat: false,
            initialPageFormat: PdfPageFormat.a4,
            pdfFileName: filename,
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPdfDirect({
    required Future<dynamic> Function(PdfPageFormat) builder,
    required String filename,
  }) async {
    try {
      final bytes = await builder(PdfPageFormat.a4);
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('डाउनलोड एरर: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: const Text('DOWNLOADS'),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF10B981),
          indicatorWeight: 3.5,
          labelColor: const Color(0xFF10B981),
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          tabs: const [
            Tab(
                icon: Icon(Icons.install_mobile_rounded, size: 20),
                text: 'ऐप डाउनलोड (App APK)'),
            Tab(
                icon: Icon(Icons.picture_as_pdf_rounded, size: 20),
                text: 'मंडी फॉर्म्स (PDF Forms)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAppDownloadsTab(),
          _buildFormsTab(),
        ],
      ),
    );
  }

  // =============================================================
  // TAB 1: APP & PWA DOWNLOADS
  // =============================================================
  Widget _buildAppDownloadsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Android APK Download Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF16253B), Color(0xFF0F1E33)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.android_rounded,
                            color: Color(0xFF10B981), size: 30),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mandi Broker Android APK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v$_latestVersion (LATEST)',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Upto: ~ 70 MB',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _releaseNotes,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoadingApk ? null : _downloadApk,
                icon: _isLoadingApk
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.download_rounded, size: 20),
                label: Text(
                  _isLoadingApk
                      ? 'डाउनलोड शुरू हो रहा है...'
                      : 'एंड्रॉयड APK डाउनलोड करें',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                  ),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text(
                    'Check For Updates',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onPressed: () => AppUpdateService.checkForUpdates(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. Progressive Web App (PWA) / Add to Home Screen
        const Text(
          'होम स्क्रीन पर सीधे ऐप जोड़ें (Install Without Download)',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        const Text(
          'बिना किसी फाइल को डाउनलोड किए, आप इसे तुरंत अपनी होम स्क्रीन पर ऐप की तरह चला सकते हैं:',
          style: TextStyle(color: Colors.white54, fontSize: 11.5),
        ),
        const SizedBox(height: 12),

        _buildInstallStepTile(
          icon: Icons.phone_android_rounded,
          iconColor: const Color(0xFF10B981),
          title: 'Android फोन (Google Chrome)',
          subtitle:
              'ब्राउज़र में ऊपर दाईं ओर तीन बिंदु (⋮) दबाएं ➔ "Add to Home screen" या "Install App" चुनें।',
        ),
        const SizedBox(height: 10),

        _buildInstallStepTile(
          icon: Icons.apple_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: 'iPhone / iPad (Safari Browser)',
          subtitle:
              'सफारी में नीचे दिए गए शेयर बटन (⎋) को दबाएं ➔ नीचे स्क्रॉल कर "Add to Home Screen" (+) चुनें।',
        ),
        const SizedBox(height: 10),

        _buildInstallStepTile(
          icon: Icons.laptop_chromebook_rounded,
          iconColor: const Color(0xFFA855F7),
          title: 'कंप्यूटर / लैपटॉप (PC Windows & Mac)',
          subtitle:
              'Chrome या Edge ब्राउज़र में वेबसाइट URL के दाईं ओर दिए गए "Install App" (⊕) बटन पर क्लिक करें।',
        ),
      ],
    );
  }

  Widget _buildInstallStepTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF223249)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor, size: 18),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================================
  // TAB 2: PRINTABLE BLANK MANDI PDF FORMS
  // =============================================================
  Widget _buildFormsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF131D2D),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF223249)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFF38BDF8), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ये खाली (Blank) आधिकारिक मंडी प्रारूप हैं। आप इन्हें सीधे A4/A5 पेपर पर प्रिंट कर सकते हैं या PDF डाउनलोड करके अपनी मंडी दुकान में प्रयोग कर सकते हैं।',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 11.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 1. Sauda Slip Blank
        _buildPdfFormCard(
          title: '1. सौदा प्रारूप (Sauda Confirmation Slip)',
          subtitle:
              'A4 साइज • क्रेता-विक्रेता विवरण, भाव, कट्टे, दलाली व डिलीवरी शर्तें',
          icon: Icons.receipt_rounded,
          iconColor: const Color(0xFF10B981),
          onPreview: () => _previewAndPrintPdf(
            title: 'सौदा प्रारूप प्रिव्यू',
            builder: MandiTemplatesPdfService.generateSaudaSlipTemplate,
            filename: 'Mandi_Sauda_Slip_Blank.pdf',
          ),
          onDownload: () => _downloadPdfDirect(
            builder: MandiTemplatesPdfService.generateSaudaSlipTemplate,
            filename: 'Mandi_Sauda_Slip_Blank.pdf',
          ),
        ),
        const SizedBox(height: 12),

        // 2. Tulai Sheet Blank
        _buildPdfFormCard(
          title: '2. मंडी तुलाई शीट / तोल पत्रक (Tulai Sheet)',
          subtitle:
              'A4 साइज • 50-कट्टों का वजन ग्रिड, बारदाना काट व शुद्ध क्विंटल योग',
          icon: Icons.scale_rounded,
          iconColor: const Color(0xFF38BDF8),
          onPreview: () => _previewAndPrintPdf(
            title: 'तुलाई शीट प्रारूप प्रिव्यू',
            builder: MandiTemplatesPdfService.generateTulaiSheetTemplate,
            filename: 'Mandi_Tulai_Sheet_Blank.pdf',
          ),
          onDownload: () => _downloadPdfDirect(
            builder: MandiTemplatesPdfService.generateTulaiSheetTemplate,
            filename: 'Mandi_Tulai_Sheet_Blank.pdf',
          ),
        ),
        const SizedBox(height: 12),

        // 3. Dalali Ledger Blank
        _buildPdfFormCard(
          title: '3. दलाली खाता बही (Dalali Ledger)',
          subtitle:
              'A4 साइज • पार्टी-वार सौदा क्रमांक, टर्नओवर, दलाली दर व बाकी हिसाब',
          icon: Icons.menu_book_rounded,
          iconColor: const Color(0xFFFFD700),
          onPreview: () => _previewAndPrintPdf(
            title: 'दलाली खाता बही प्रिव्यू',
            builder: MandiTemplatesPdfService.generateDalaliLedgerTemplate,
            filename: 'Mandi_Dalali_Ledger_Blank.pdf',
          ),
          onDownload: () => _downloadPdfDirect(
            builder: MandiTemplatesPdfService.generateDalaliLedgerTemplate,
            filename: 'Mandi_Dalali_Ledger_Blank.pdf',
          ),
        ),
        const SizedBox(height: 12),

        // 4. Mandi Invoice Blank
        _buildPdfFormCard(
          title: '4. मंडी बिल / कैश मेमो (Mandi Trade Invoice)',
          subtitle:
              'A4 साइज • संपूर्ण बिल प्रारूप, जिंस विवरण, वजन, दर व खर्चे तालिका',
          icon: Icons.request_quote_rounded,
          iconColor: const Color(0xFFA855F7),
          onPreview: () => _previewAndPrintPdf(
            title: 'मंडी बिल प्रारूप प्रिव्यू',
            builder: MandiTemplatesPdfService.generateMandiInvoiceTemplate,
            filename: 'Mandi_Invoice_Bill_Blank.pdf',
          ),
          onDownload: () => _downloadPdfDirect(
            builder: MandiTemplatesPdfService.generateMandiInvoiceTemplate,
            filename: 'Mandi_Invoice_Bill_Blank.pdf',
          ),
        ),
        const SizedBox(height: 16),

        // Custom Template Order Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF16253B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF223249)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.palette_rounded,
                      color: Colors.deepOrange, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'अपनी फर्म के नाम का विशेष प्रिंट प्रारूप बनवाएं',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'यदि आप अपनी फर्म के नाम, लोगो, मंडी लाइसेंस व फोन नंबर के साथ कस्टम प्रिंटिंग प्रारूप बनवाना चाहते हैं, तो हमारी टीम से संपर्क करें:',
                style: TextStyle(
                    color: Colors.white60, fontSize: 11.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF25D366),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: const Size(double.infinity, 40),
                ),
                onPressed: _openWhatsAppCustomForm,
                icon: const Icon(Icons.chat, size: 16),
                label: const Text(
                  'कस्टम प्रारूप अनुरोध (WhatsApp)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPdfFormCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onPreview,
    required VoidCallback onDownload,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF223249)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: iconColor.withValues(alpha: 0.15),
                child: Icon(icon, color: iconColor, size: 20),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                  onPressed: onPreview,
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('प्रिव्यू व प्रिंट',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                  ),
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('PDF शेयर / सेव',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
