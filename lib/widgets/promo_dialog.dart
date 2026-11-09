import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart'; // Uses marketViewDb

/// URL normalizer: converts 10-digit mobile number into WhatsApp link or prefixes https://
String normalizePromoUrl(String raw) {
  raw = raw.trim();
  if (raw.isEmpty) return '';
  if (RegExp(r'^\d{10}$').hasMatch(raw)) {
    return 'https://wa.me/91$raw';
  }
  if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
    return 'https://$raw';
  }
  return raw;
}

Future<void> launchPromoUrl(BuildContext context, String rawUrl) async {
  final cleanUrl = normalizePromoUrl(rawUrl);
  if (cleanUrl.isEmpty) return;
  try {
    final uri = Uri.parse(cleanUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $cleanUrl')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening link: $e')),
      );
    }
  }
}

class PromoDialog {
  /// Checks secondary Firestore (mandi-market-view) with primary fallback
  /// and displays the popup dialog if active
  static Future<void> showIfActive(BuildContext context) async {
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

      if (doc == null || !doc.exists) return;
      dynamic rawData;
      try {
        rawData = doc.data();
      } catch (_) {}
      if (rawData == null || rawData is! Map) return;

      final bool isActive = rawData['isActive'] == true;
      final bool showOnStartup = rawData['showPopupOnStartup'] != false;
      final String? imageUrl = rawData['imageUrl']?.toString().trim();
      final String? title = rawData['title']?.toString().trim();
      final String? redirectUrl = rawData['redirectUrl']?.toString().trim();
      final int hideDelaySeconds =
          int.tryParse(rawData['hideDelaySeconds']?.toString() ?? '5') ?? 5;

      if (isActive &&
          showOnStartup &&
          imageUrl != null &&
          imageUrl.isNotEmpty &&
          context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _PromoDialogWidget(
            imageUrl: imageUrl,
            title: title,
            redirectUrl: redirectUrl,
            hideDelaySeconds: hideDelaySeconds > 0 ? hideDelaySeconds : 5,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to load promo poster: $e');
    }
  }
}

class _PromoDialogWidget extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final String? redirectUrl;
  final int hideDelaySeconds;

  const _PromoDialogWidget({
    required this.imageUrl,
    this.title,
    this.redirectUrl,
    required this.hideDelaySeconds,
  });

  @override
  State<_PromoDialogWidget> createState() => _PromoDialogWidgetState();
}

class _PromoDialogWidgetState extends State<_PromoDialogWidget> {
  late int _remainingSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.hideDelaySeconds;
    _startCountdown();
  }

  void _startCountdown() {
    if (_remainingSeconds <= 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 1) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canDismiss = _remainingSeconds <= 0;
    final bool hasRedirect =
        widget.redirectUrl != null && widget.redirectUrl!.trim().isNotEmpty;

    return PopScope(
      canPop: canDismiss,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFF5722).withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar with Title and Close Button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF334155), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5722).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              const Color(0xFFFF5722).withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign_rounded,
                              size: 13, color: Color(0xFFFF5722)),
                          SizedBox(width: 4),
                          Text(
                            'सूचना / विज्ञापन',
                            style: TextStyle(
                              color: Color(0xFFFF5722),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title?.isNotEmpty == true
                            ? widget.title!
                            : 'Mandi Special Notice',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Close button with countdown
                    canDismiss
                        ? InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF5722),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.close,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'बंद करें',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white30,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    value: widget.hideDelaySeconds > 0
                                        ? (widget.hideDelaySeconds -
                                                _remainingSeconds +
                                                1) /
                                            widget.hideDelaySeconds
                                        : 1.0,
                                    strokeWidth: 2,
                                    color: const Color(0xFFFF5722),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${_remainingSeconds}s',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ],
                ),
              ),

              // Poster Image
              GestureDetector(
                onTap: () {
                  if (hasRedirect) {
                    launchPromoUrl(context, widget.redirectUrl!);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PromoImageViewerScreen(
                          imageUrl: widget.imageUrl,
                          title: widget.title,
                          redirectUrl: widget.redirectUrl,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 440),
                  color: Colors.black,
                  child: Image.network(
                    widget.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 250,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          color: Color(0xFFFF5722),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: Colors.white38, size: 40),
                          SizedBox(height: 8),
                          Text(
                            'पोस्टर लोड करने में समस्या हुई',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Action Button (if redirectUrl provided)
              if (hasRedirect)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: const Color(0xFF1E293B),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () =>
                        launchPromoUrl(context, widget.redirectUrl!),
                    icon: const Icon(Icons.touch_app_rounded, size: 18),
                    label: const Text(
                      '👉 यहाँ क्लिक करें / संपर्क करें (Open Link)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full screen zoomable image viewer for the poster
class PromoImageViewerScreen extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final String? redirectUrl;

  const PromoImageViewerScreen({
    super.key,
    required this.imageUrl,
    this.title,
    this.redirectUrl,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasRedirect =
        redirectUrl != null && redirectUrl!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          title?.isNotEmpty == true ? title! : 'पोस्टर विवरण (Poster)',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (hasRedirect)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF10B981),
              ),
              onPressed: () => launchPromoUrl(context, redirectUrl!),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text(
                'Open Link',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, prog) {
              if (prog == null) return child;
              return const CircularProgressIndicator(color: Color(0xFFFF5722));
            },
          ),
        ),
      ),
    );
  }
}

/// Realtime Banner widget rendered on the Main Dashboard
class DashboardPromoBanner extends StatefulWidget {
  const DashboardPromoBanner({super.key});

  @override
  State<DashboardPromoBanner> createState() => _DashboardPromoBannerState();
}

class _DashboardPromoBannerState extends State<DashboardPromoBanner> {
  bool _dismissedThisSession = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: marketViewDb
          .collection('market_watch')
          .doc('promo_config')
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic>? data;
        if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
          try {
            data = snapshot.data!.data() as Map<String, dynamic>?;
          } catch (_) {}
        }

        // If secondary DB snapshot is null or inactive, fallback to primary Firestore
        if (data == null || data['isActive'] != true) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('market_watch')
                .doc('promo_config')
                .snapshots(),
            builder: (context, primarySnap) {
              Map<String, dynamic>? pData;
              if (primarySnap.hasData &&
                  primarySnap.data != null &&
                  primarySnap.data!.exists) {
                try {
                  pData = primarySnap.data!.data() as Map<String, dynamic>?;
                } catch (_) {}
              }
              return _buildBannerContent(context, pData);
            },
          );
        }

        return _buildBannerContent(context, data);
      },
    );
  }

  Widget _buildBannerContent(
      BuildContext context, Map<String, dynamic>? promoData) {
    if (promoData == null) return const SizedBox.shrink();

    final bool isActive = promoData['isActive'] == true;
    final bool showOnDashboard = promoData['showDashboardBanner'] != false;
    final String? imageUrl = promoData['imageUrl']?.toString().trim();
    final String? title = promoData['title']?.toString().trim();
    final String? redirectUrl = promoData['redirectUrl']?.toString().trim();

    if (!isActive || !showOnDashboard || imageUrl == null || imageUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool hasRedirect = redirectUrl != null && redirectUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF131F33),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF5722).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5722).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Title Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF1A2A44),
              border: Border(
                bottom: BorderSide(color: Color(0xFF223859), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5722).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFF5722).withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign_rounded,
                          size: 13, color: Color(0xFFFF5722)),
                      SizedBox(width: 4),
                      Text(
                        'विज्ञापन / सूचना',
                        style: TextStyle(
                          color: Color(0xFFFF5722),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title?.isNotEmpty == true
                        ? title!
                        : 'विशेष सूचना एवं विज्ञापन',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Tap to view full hint
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PromoImageViewerScreen(
                          imageUrl: imageUrl,
                          title: title,
                          redirectUrl: redirectUrl,
                        ),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.fullscreen_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ),
                const SizedBox(width: 4),
                // Session dismiss button
                InkWell(
                  onTap: () {
                    setState(() => _dismissedThisSession = true);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close, color: Colors.white38, size: 16),
                  ),
                ),
              ],
            ),
          ),

          // Poster Image Area
          GestureDetector(
            onTap: () {
              if (hasRedirect) {
                launchPromoUrl(context, redirectUrl);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PromoImageViewerScreen(
                      imageUrl: imageUrl,
                      title: title,
                      redirectUrl: redirectUrl,
                    ),
                  ),
                );
              }
            },
            child: Container(
              constraints: const BoxConstraints(maxHeight: 220),
              color: Colors.black,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Image.network(
                    imageUrl,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 160,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFF5722),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      alignment: Alignment.center,
                      child: const Text(
                        'पोस्टर लोड नहीं हो सका',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded,
                            size: 11, color: Colors.white70),
                        SizedBox(width: 3),
                        Text(
                          'पूरा देखने हेतु टैप करें',
                          style: TextStyle(color: Colors.white70, fontSize: 9.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Button if redirectUrl provided
          if (hasRedirect)
            InkWell(
              onTap: () => launchPromoUrl(context, redirectUrl),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F766E),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded,
                        color: Colors.white, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'यहाँ क्लिक करें / संपर्क करें (Click Here to Connect)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
