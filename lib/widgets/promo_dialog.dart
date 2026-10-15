import 'package:flutter/material.dart';
import '../main.dart'; // Uses marketViewDb from secondary Firebase (mandi-market-view)

class PromoDialog {
  /// Checks secondary Firestore (mandi-market-view) and displays the popup dialog if active
  static Future<void> showIfActive(BuildContext context) async {
    try {
      final doc = await marketViewDb
          .collection('market_watch')
          .doc('promo_config')
          .get();

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;
      final bool isActive = data['isActive'] ?? false;
      final String? imageUrl = data['imageUrl'];

      if (isActive &&
          imageUrl != null &&
          imageUrl.isNotEmpty &&
          context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    imageUrl,
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
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 14,
                    child: Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to load promo poster: $e');
    }
  }
}
