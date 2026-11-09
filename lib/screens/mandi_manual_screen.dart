import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MandiManualScreen extends StatefulWidget {
  const MandiManualScreen({super.key});

  @override
  State<MandiManualScreen> createState() => _MandiManualScreenState();
}

class _MandiManualScreenState extends State<MandiManualScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int? _expandedSectionIndex;

  static const String adminSupportPhone = '+919983325558';

  Future<void> _openWhatsAppSupport(String queryTopic) async {
    String cleanPhone = adminSupportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanPhone.length == 10) cleanPhone = '91$cleanPhone';
    final msg = Uri.encodeComponent(
      'नमस्ते Mandi Support, मुझे Mandi Broker App के "$queryTopic" फीचर के संबंध में मार्गदर्शन चाहिए।',
    );
    final url = Uri.parse('https://wa.me/$cleanPhone?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  final List<ManualChapter> _chapters = const [
    ManualChapter(
      id: 'overview',
      title: '1. ऐप परिचय  App Overview)',
      subtitle: '6-इन-1 मंडी टर्मिनल, ऑफलाइन-फर्स्ट व ऑटो क्लाउड सिंक',
      icon: Icons.dashboard_customize_rounded,
      iconColor: Color(0xFF38BDF8),
      points: [
        ManualPoint(
          heading: '6-इन-1 संपूर्ण मंडी समाधान',
          text:
              'यह ऐप दलाल (Broker), Buyer, (Seller, Billing, मार्केट वॉच (NCDEX/Bhav) और सहायता केंद्र को एक जगह जोड़ता है।',
        ),
        ManualPoint(
          heading: 'ऑफलाइन-फर्स्ट आर्किटेक्चर (Offline First)',
          text:
              'मंडी यार्ड में इंटरनेट कमजोर होने पर भी ऐप बिना रुके काम करता है। आपका डेटा डिवाइस के लोकल स्टोरेज में तुरंत सुरक्षित हो जाता है और इंटरनेट मिलते ही फायरबेस क्लाउड से स्वतः सिंक हो जाता है।',
        ),
        ManualPoint(
          heading: '10-अंकों का मोबाइल नंबर आधारित लॉगिन',
          text:
              'किसी जटिल पासवर्ड की आवश्यकता नहीं। केवल अपना 10-अंकों का मोबाइल नंबर दर्ज करें और अपने व्यक्तिगत फोल्डर में सुरक्षित प्रवेश करें।',
        ),
      ],
    ),
    ManualChapter(
      id: 'broker',
      title: '2. Broker Portal',
      subtitle: 'नया सौदा, 4 WhatsApp टेम्पलेट्स,खाता बही',
      icon: Icons.handshake_rounded,
      iconColor: Color(0xFF10B981),
      points: [
        ManualPoint(
          heading: 'नया सौदा दर्ज करना (New Sauda Entry)',
          text:
              'ब्रोकर का नाम, विक्रेता का नाम, जिंस,Bags, वजन (Qtl), भाव प्रति क्विंटल और दलाली दर (प्रति कट्टा या %) दर्ज कर "सौदा सेव करें" पर टैप करें।',
        ),
        ManualPoint(
          heading: '4 प्रकार के WhatsApp सौदा पर्चा टेम्पलेट्स',
          text:
              'सौदा दर्ज होने के बाद आप 4 पेशेवर प्रारूपों में से एक चुन सकते हैं:\n'
              '1. व्यावसायिक (Standard Professional): पूर्ण विवरण, दिनांक, समय, भाव व नियम।\n'
              '2. संक्षिप्त (Compact Quick): तुरंत पुष्टि हेतु 4 लाइनों का छोटा संदेश।\n'
              '3. औपचारिक (Formal Invoice): जीएसटी, पार्टी कोड व डिलीवरी शर्तों सहित।\n'
              '4. सौम्य (Polite Mandi Style): पारंपरिक मंडी भाषा व सम्मानजनक अभिवादन।',
        ),
        ManualPoint(
          heading: 'तुलाई शीट / कांटा पर्ची (Weighment Sheet)',
          text:
              'गाड़ी या ढेर के कट्टों की तुलाई दर्ज करें। कुल वजन (Gross Wt), बारदाना काट (Tare) घटाकर शुद्ध क्विंटल (Net Qtl) स्वतः निकल आता है। इसे WhatsApp पर शेयर कर सकते हैं।',
        ),
        ManualPoint(
          heading: 'Broker Dalali Ledger',
          text:
              'प्रत्येक व्यापारी व किसान का अलग लेजर बनता है। कुल सौदों का टर्नओवर, कुल दलाली, प्राप्त भुगतान और बकाया रकम का हिसाब 1-टैप में WhatsApp स्टेटमेंट के रूप में भेजा जा सकता है।',
        ),
      ],
    ),
    ManualChapter(
      id: 'buyer',
      title: '3.Buyer Portal',
      subtitle: 'खरीद सारांश, सौदे, लेजर व 1-टैप कॉल',
      icon: Icons.shopping_cart_rounded,
      iconColor: Color(0xFF06B6D4),
      points: [
        ManualPoint(
          heading: 'खरीद एनालिटिक्स व सारांश (Purchase Analytics)',
          text:
              'शीर्ष पर कुल खरीदे गए कट्टे, कुल टर्नओवर राशि (Turnover ₹), औसत भाव और कुल दलाली का लाइव सारांश प्रदर्शित होता है।',
        ),
        ManualPoint(
          heading: 'जिंस (Commodity) एवं दिनांक फिल्टर',
          text:
              'सोयाबीन, चना, सरसों, जीरा आदि जिंस चिप्स पर टैप करके तुरंत उस फसल के सभी सौदे देखें। तारीख फिल्टर से आज, इस महीने या किसी भी समयावधि के सौदे देखें।',
        ),
        ManualPoint(
          heading: 'दलाल संपर्क व डायरेक्ट कॉल (1-Tap Call)',
          text:
              'प्रत्येक सौदे में दलाल के नाम के पास दिए गए हरे कॉल बटन पर टैप कर सीधे फोन मिला सकते हैं या WhatsApp पर सौदा पर्चा मंगवा सकते हैं।',
        ),
        ManualPoint(
          heading: 'लंबित सौदे व अप्रूवल (Pending Approval)',
          text:
              '"लंबित सौदे" टैब में वे सौदे दिखाई देते हैं जिनकी डिलीवरी या बिल का सत्यापन अभी बाकी है।',
        ),
      ],
    ),
    ManualChapter(
      id: 'seller',
      title: '4. Seller Portal',
      subtitle: 'बिक्री रिकॉर्ड, भुगतान ट्रैकिंग, ब्रोकर हिसाब ',
      icon: Icons.storefront_rounded,
      iconColor: Color(0xFFF59E0B),
      points: [
        ManualPoint(
          heading: 'बिक्री सारांश (Sales Analytics)',
          text:
              'बिके हुए माल के कुल कट्टे, कुल बिक्री रकम और औसत भाव का सटीक हिसाब तुरंत देखें।',
        ),
        ManualPoint(
          heading: 'सौदा पर्चा सत्यापन (Sauda Slip Verification)',
          text:
              'दलाल द्वारा बनाए गए सौदे का पूरा विवरण (तारीख, भाव, कट्टे, खरीदार) अपनी स्क्रीन पर देखें और रिकॉर्ड के लिए WhatsApp पर सुरक्षित रखें।',
        ),
        ManualPoint(
          heading: 'दलाल खाता मिलान (Ledger Reconciliation)',
          text:
              'दलाल के साथ अपनी दलाली, पल्लेदारी व हम्माली खर्चों का पारदर्शी मिलान करें ताकि भुगतान में कोई असमंजस न रहे।',
        ),
      ],
    ),
    ManualChapter(
      id: 'billing',
      title: '5. Bill Generator',
      subtitle: 'डुअल लैंग्वेज बिल',
      icon: Icons.receipt_long_rounded,
      iconColor: Color(0xFFA855F7),
      points: [
        ManualPoint(
          heading: 'नया बिल  बनाना',
          text:
              'किसान या व्यापारी का नाम (हिंदी व अंग्रेजी), मोबाइल नंबर, गाड़ी नंबर, जिंस का नाम, कट्टे व दर दर्ज करें। ग्रॉस राशि स्वतः जुड़ जाएगी।',
        ),
        ManualPoint(
          heading: 'A4 साइज में रसीद प्रिंट व PDF',
          text:
              'प्रिंट बटन दबाने पर खूबसूरत हिंदी-अंग्रेजी फॉर्मेट में रसीद तैयार होती है। इसे थर्मल प्रिंटर या लेजर प्रिंटर से प्रिंट करें या PDF के रूप में डाउनलोड करें।',
        ),
        ManualPoint(
          heading: 'ईमेल इनवॉइस (Email Invoice)',
          text:
              'यदि खरीदार का ईमेल दर्ज है तो 1-टैप में आधिकारिक डिजिटल इनवॉइस सीधे उनके इनबॉक्स में भेजी जा सकती है।',
        ),
        ManualPoint(
          heading: 'तुलाई व मजदूरी ',
          text:
              'मंडी नियमानुसार बारदाना काट व तुलाई शुल्क का स्वतः हिसाब होकर शुद्ध भुगतान राशि (Net Total) निकलती है।',
        ),
      ],
    ),
    ManualChapter(
      id: 'market_watch',
      title: '6. Live Bhav & Rate Predictions',
      subtitle: 'NCDEX Live Contracts, Local Mandi Rates & AI Analyzer',
      icon: Icons.show_chart_rounded,
      iconColor: Color(0xFFFF5722),
      points: [
        ManualPoint(
          heading: '1: LOCAL (स्थानीय मंडी भाव)',
          text:
              'मार्केट वॉच खोलते ही पहली स्लाइड LOCAL की खुलती है। इसमें आपकी स्थानीय मंडी के दैनिक न्यूनतम व अधिकतम भाव दिखते हैं।',
        ),
        ManualPoint(
          heading: '2: NCDEX (नेशनल कमोडिटी एक्सचेंज)',
          text:
              'सभी कृषि जिंसों के लाइव अनुबंध, वास्तविक एक्सपायरी तारीख, LTP, उतार-चढ़ाव (+/- ₹) और उच्च/निम्न भाव दिखते हैं।',
        ),
        ManualPoint(
          heading: '3: ANALYZER (मंडी विश्लेषक व प्रेडिक्टर)',
          text:
              '11 प्रमुख जिंसों (जीरा, ईसबगोल, ग्वार, धनिया, हल्दी, सरसों, चना, सोयाबीन आदि) का लाइव तकनीकी प्रेडिक्शन।\n'
              '• ट्रेंड बैज: तेज़ी (Bullish 🚀), मंदी (Bearish 🔻) या सीमित दायरा (Sideways ⚖️)।\n'
              '• सपोर्ट S1/S2 व रुकावट R1/R2 लेवल्स।\n'
              '• मार्केट सेंटीमेंट स्कोर (0-100%) व आवक-मांग फंडामेंटल सलाह।',
        ),
      ],
    ),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredChapters = _chapters.where((chap) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final inTitle = chap.title.toLowerCase().contains(q);
      final inSubtitle = chap.subtitle.toLowerCase().contains(q);
      final inPoints = chap.points.any((pt) =>
          pt.heading.toLowerCase().contains(q) ||
          pt.text.toLowerCase().contains(q));
      return inTitle || inSubtitle || inPoints;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1320),
      appBar: AppBar(
        title: const Text('यूज़र मैन्युअल '),
        backgroundColor: const Color(0xFF16253B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: Color(0xFF38BDF8)),
            tooltip: 'WhatsApp Help ',
            onPressed: () => _openWhatsAppSupport('संपूर्ण ऐप सहायता'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Search & Quick Jump Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFF16253B),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText:
                        'मैन्युअल में खोजें (उदा: सौदा, बिल, तुलाई, PIN)...',
                    hintStyle:
                        const TextStyle(color: Colors.white38, fontSize: 12.5),
                    prefixIcon: const Icon(Icons.search,
                        color: Color(0xFF38BDF8), size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF0B1320),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF223249)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF223249)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Overview badges row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBadge(Icons.auto_stories, '7 संपूर्ण अध्याय',
                        const Color(0xFF38BDF8)),
                    _buildBadge(Icons.translate, 'हिंदी + English',
                        const Color(0xFF10B981)),
                    _buildBadge(Icons.wifi_off_rounded, 'ऑफलाइन रेडी',
                        const Color(0xFFF59E0B)),
                  ],
                ),
              ],
            ),
          ),

          // Chapters List
          Expanded(
            child: filteredChapters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off_rounded,
                              size: 48, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text(
                            '"$_searchQuery" से संबंधित कोई विषय नहीं मिला',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'कृपया अन्य शब्द खोजें या नीचे दिए गए बटन से सीधे सहायता लें।',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    itemCount: filteredChapters.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, idx) {
                      final chap = filteredChapters[idx];
                      final bool isExpanded = _expandedSectionIndex == idx;

                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF131D2D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isExpanded
                                ? chap.iconColor.withValues(alpha: 0.6)
                                : const Color(0xFF223249),
                          ),
                        ),
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: isExpanded,
                            onExpansionChanged: (exp) {
                              setState(() {
                                _expandedSectionIndex = exp ? idx : null;
                              });
                            },
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  chap.iconColor.withValues(alpha: 0.15),
                              child: Icon(chap.icon,
                                  color: chap.iconColor, size: 20),
                            ),
                            title: Text(
                              chap.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              chap.subtitle,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11),
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: [
                              const Divider(
                                  color: Color(0xFF223249), height: 1),
                              const SizedBox(height: 12),
                              ...chap.points.map((pt) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0B1320),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.check_circle_rounded,
                                                color: chap.iconColor,
                                                size: 15),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                pt.heading,
                                                style: TextStyle(
                                                  color: chap.iconColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          pt.text,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF25D366),
                                    ),
                                    icon: const Icon(Icons.chat, size: 15),
                                    label: const Text(
                                      'इस विषय पर WhatsApp सहायता लें',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () =>
                                        _openWhatsAppSupport(chap.title),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF131D2D),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SafeArea(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'कोई सवाल बाकी है?',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      'Mandi Support Desk 24x7 उपलब्ध है',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () =>
                    _openWhatsAppSupport('यूज़र मैन्युअल सामान्य पूछताछ'),
                icon: const Icon(Icons.chat, size: 16),
                label: const Text('हेल्पडेस्क',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class ManualChapter {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<ManualPoint> points;

  const ManualChapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.points,
  });
}

class ManualPoint {
  final String heading;
  final String text;

  const ManualPoint({
    required this.heading,
    required this.text,
  });
}
