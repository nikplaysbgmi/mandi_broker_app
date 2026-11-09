import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../main.dart'; // Uses marketViewDb

class EditPromoDialog extends StatefulWidget {
  const EditPromoDialog({super.key});

  @override
  State<EditPromoDialog> createState() => _EditPromoDialogState();
}

class _EditPromoDialogState extends State<EditPromoDialog> {
  final _urlCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _redirectUrlCtrl = TextEditingController();
  final _hideDelayCtrl = TextEditingController(text: '5');

  bool _isActive = true;
  bool _showPopupOnStartup = true;
  bool _showDashboardBanner = true;
  bool _isSaving = false;
  bool _isUploading = false;
  bool _isLoading = true;

  // ImgBB API key for free permanent cloud hosting
  static const String _imgBbApiKey = "e7eaf830df6f232fa61240e72675076f";

  @override
  void initState() {
    super.initState();
    _loadPromoData();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    _redirectUrlCtrl.dispose();
    _hideDelayCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPromoData() async {
    try {
      DocumentSnapshot? doc;
      try {
        doc = await marketViewDb
            .collection('market_watch')
            .doc('promo_config')
            .get();
      } catch (_) {}

      if (doc == null || !doc.exists || doc.data() == null) {
        try {
          doc = await FirebaseFirestore.instance
              .collection('market_watch')
              .doc('promo_config')
              .get();
        } catch (_) {}
      }

      if (doc != null && doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        _urlCtrl.text = data['imageUrl']?.toString() ?? '';
        _titleCtrl.text = data['title']?.toString() ?? '';
        _redirectUrlCtrl.text = data['redirectUrl']?.toString() ?? '';
        final int delay =
            int.tryParse(data['hideDelaySeconds']?.toString() ?? '5') ?? 5;
        _hideDelayCtrl.text = delay.toString();

        setState(() {
          _isActive = data['isActive'] ?? true;
          _showPopupOnStartup = data['showPopupOnStartup'] ?? true;
          _showDashboardBanner = data['showDashboardBanner'] ?? true;
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Error loading promo settings: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // Uploads directly to ImgBB and receives permanent image link
  Future<void> _pickAndUploadToImgBB() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file == null) return;
    if (!mounted) return;

    setState(() => _isUploading = true);

    try {
      final Uint8List bytes = await file.readAsBytes();
      final String base64Image = base64Encode(bytes);

      final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$_imgBbApiKey');
      final response = await http.post(
        uri,
        body: {
          'image': base64Image,
          'name': 'mandi_promo_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final String uploadedUrl =
            data['data']['display_url'] ?? data['data']['url'];
        if (!mounted) return;
        setState(() {
          _urlCtrl.text = uploadedUrl;
          _isActive = true;
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ पोस्टर सफलतापूर्वक अपलोड हो गया (Uploaded to Cloud)!'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      } else {
        throw Exception(data['error']?['message'] ?? 'Upload failed');
      }
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ImgBB Upload Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _savePromo() async {
    setState(() => _isSaving = true);
    try {
      final int delay = int.tryParse(_hideDelayCtrl.text.trim()) ?? 5;
      final String rawUrl = _urlCtrl.text.trim();
      final String rawTitle = _titleCtrl.text.trim();
      final String rawRedirect = _redirectUrlCtrl.text.trim();

      final promoPayload = {
        'imageUrl': rawUrl,
        'title': rawTitle,
        'redirectUrl': rawRedirect,
        'isActive': _isActive,
        'showPopupOnStartup': _showPopupOnStartup,
        'showDashboardBanner': _showDashboardBanner,
        'hideDelaySeconds': delay > 0 ? delay : 5,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 1. Save to marketViewDb
      try {
        await marketViewDb
            .collection('market_watch')
            .doc('promo_config')
            .set(promoPayload, SetOptions(merge: true));
      } catch (e) {
        debugPrint('marketViewDb promo save warning: $e');
      }

      // 2. Dual-save to primary FirebaseFirestore for resilient fallback
      try {
        await FirebaseFirestore.instance
            .collection('market_watch')
            .doc('promo_config')
            .set(promoPayload, SetOptions(merge: true));
      } catch (e) {
        debugPrint('primaryDb promo save warning: $e');
      }

      try {
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('promo_banner')
            .set(promoPayload, SetOptions(merge: true));
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isActive
                ? '📢 पोस्टर लाइव हो गया है! (Poster Published Successfully)'
                : 'पोस्टर सेटिंग्स सेव कर ली गई हैं।',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving promo: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _clearPoster() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('पोस्टर हटाएं (Remove Poster)',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'क्या आप वर्तमान पोस्टर को पूरी तरह हटाना चाहते हैं?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('हटाएं', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _urlCtrl.clear();
      _titleCtrl.clear();
      _redirectUrlCtrl.clear();
      _isActive = false;
    });
    await _savePromo();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(18),
        child: _isLoading
            ? const Center(
                heightFactor: 4,
                child: CircularProgressIndicator(color: Color(0xFFFF5722)),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5722)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.campaign_rounded,
                            color: Color(0xFFFF5722),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'विज्ञापन / पोस्टर सेवा',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Post Poster / Ad on Main Dashboard & Startup',
                                style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white60),
                          onPressed: () => Navigator.pop(context),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Color(0xFF334155), height: 1),
                    const SizedBox(height: 14),

                    // Gallery Upload Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(
                            color: Color(0xFF0284C7), width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isUploading ? null : _pickAndUploadToImgBB,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF38BDF8),
                              ),
                            )
                          : const Icon(Icons.add_photo_alternate_rounded,
                              size: 20),
                      label: Text(
                        _isUploading
                            ? 'क्लाउड पर अपलोड हो रहा है...'
                            : 'गैलरी से पोस्टर चुनें व अपलोड करें (Upload Image)',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Direct Image URL Field
                    TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'पोस्टर इमेज लिंक (Poster Image URL)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'https://i.ibb.co/... या ऊपर बटन से अपलोड करें',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.link,
                            color: Color(0xFF38BDF8), size: 18),
                        suffixIcon: _urlCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 16, color: Colors.white54),
                                onPressed: () {
                                  _urlCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF334155)),
                        ),
                        isDense: true,
                      ),
                    ),

                    // Live Image Preview if URL is present
                    if (_urlCtrl.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF10B981), width: 1.2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Center(
                              child: Image.network(
                                _urlCtrl.text.trim(),
                                fit: BoxFit.contain,
                                loadingBuilder: (_, child, prog) {
                                  if (prog == null) return child;
                                  return const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF10B981),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.broken_image,
                                          color: Colors.redAccent, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'अमान्य इमेज लिंक (Invalid Image URL)',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.all(6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '✓ Preview',
                                style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Optional Title / Headline
                    TextField(
                      controller: _titleCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'पोस्टर शीर्षक / हैडलाइन (वैकल्पिक)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'उदा. 📢 विशेष सूचना या मंडी सेवा ऑफर',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.title,
                            color: Color(0xFFF59E0B), size: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF334155)),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Optional Redirect / WhatsApp URL
                    TextField(
                      controller: _redirectUrlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'क्लिक करने पर खुलने वाला लिंक या व्हाट्सएप नंबर',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: 'उदा. 9876543210 या https://wa.me/... या वेबसाइट',
                        hintStyle: const TextStyle(color: Colors.white38),
                        helperText:
                            '10 अंकों का मोबाइल नंबर डालने पर स्वतः व्हाट्सएप चैट खुलेगी',
                        helperStyle:
                            const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        prefixIcon: const Icon(Icons.touch_app_rounded,
                            color: Color(0xFF10B981), size: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF334155)),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Close Delay Countdown
                    TextField(
                      controller: _hideDelayCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'पॉपअप क्लोज बटन टाइमर (सेकंड में)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        hintText: '5',
                        hintStyle: const TextStyle(color: Colors.white38),
                        helperText:
                            'यूज़र इतने सेकंड बाद ही पोस्टर बंद कर पाएंगे (डिफ़ॉल्ट 5 सेकंड)',
                        helperStyle:
                            const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        prefixIcon: const Icon(Icons.timer_outlined,
                            color: Colors.orangeAccent, size: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF334155)),
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Toggle Controls
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16253B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '📢 विज्ञापन चालू रखें (Active / Live)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              _isActive
                                  ? 'पोस्टर सभी यूज़र्स को दिखाई दे रहा है'
                                  : 'पोस्टर बंद (छिपा हुआ) है',
                              style: TextStyle(
                                  color: _isActive
                                      ? const Color(0xFF10B981)
                                      : Colors.redAccent,
                                  fontSize: 11),
                            ),
                            value: _isActive,
                            activeThumbColor: const Color(0xFF10B981),
                            onChanged: (val) =>
                                setState(() => _isActive = val),
                          ),
                          const Divider(
                              color: Color(0xFF334155), height: 1),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '📱 ऐप खुलते ही पॉपअप दिखाएं (Startup Popup)',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12.5),
                            ),
                            value: _showPopupOnStartup,
                            activeThumbColor: const Color(0xFF38BDF8),
                            onChanged: (val) =>
                                setState(() => _showPopupOnStartup = val),
                          ),
                          const Divider(
                              color: Color(0xFF334155), height: 1),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '🏠 मुख्य डैशबोर्ड पर बैनर दिखाएं (Dashboard Banner)',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12.5),
                            ),
                            value: _showDashboardBanner,
                            activeThumbColor: const Color(0xFFF59E0B),
                            onChanged: (val) =>
                                setState(() => _showDashboardBanner = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons
                    Row(
                      children: [
                        if (_urlCtrl.text.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                            ),
                            onPressed: _clearPoster,
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('हटाएं',
                                style: TextStyle(fontSize: 12)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('रद्द करें',
                              style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _savePromo,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF5722),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_rounded,
                                  size: 16),
                          label: Text(
                            _isSaving ? 'सेव हो रहा है...' : 'प्रकाशित करें (Save)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
