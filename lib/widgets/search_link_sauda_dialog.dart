import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/mandi_services.dart';

/// Interactive Dialog for Buyers and Sellers to search any Custom Sauda ID
/// created by a broker and save/link it directly into their personal records.
void showSearchAndLinkSaudaDialog({
  required BuildContext context,
  required UserAccount currentUser,
  required String userRole, // 'BUYER' or 'SELLER'
  VoidCallback? onSaudaLinked,
}) {
  final isBuyer = userRole.toUpperCase() == 'BUYER';
  final themeColor = isBuyer ? const Color(0xFF0284C7) : const Color(0xFFD97706);
  final roleHindi = isBuyer ? 'खरीदार (BUYER)' : 'विक्रेता / किसान (SELLER)';

  final idController = TextEditingController();
  bool isSearching = false;
  bool isSaving = false;
  Map<String, dynamic>? foundSauda;
  String? searchError;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> executeSearch() async {
          final query = idController.text.trim();
          if (query.isEmpty) {
            setDialogState(() {
              searchError = 'कृपया सौदा नंबर (Sauda ID) दर्ज करें।';
              foundSauda = null;
            });
            return;
          }

          setDialogState(() {
            isSearching = true;
            searchError = null;
            foundSauda = null;
          });

          try {
            final res = await CloudSyncService.findSaudaById(query);
            if (res != null && res.isNotEmpty) {
              final isExpired = MandiSaudaModel.checkCodeExpired(
                saudaDateRaw: res['date'],
                createdAtRaw: res['createdAt'],
              );

              if (isExpired) {
                final dateStr = (res['date'] ?? '').toString().split('T').first;
                setDialogState(() {
                  searchError =
                      '⚠️ यह सौदा कोड (#$query) 1 माह से अधिक पुराना होने के कारण अमान्य (Expired) हो चुका है।\n(सौदा दिनांक: $dateStr • सौदा कोड केवल 1 माह के लिए मान्य रहता है)\nकृपया अपने रिकॉर्ड में जोड़ने हेतु ब्रोकर से संपर्क करें।';
                  foundSauda = null;
                  isSearching = false;
                });
                return;
              }

              setDialogState(() {
                foundSauda = res;
                isSearching = false;
              });
            } else {
              setDialogState(() {
                searchError =
                    'सौदा कोड "$query" नहीं मिला। कृपया ब्रोकर द्वारा दिया गया 6-अंकीय कोड (3 अक्षर + 3 अंक, उदा. ABC123) जांचें।';
                isSearching = false;
              });
            }
          } catch (e) {
            setDialogState(() {
              searchError = 'सौदा खोजने में त्रुटि: $e';
              isSearching = false;
            });
          }
        }

        Future<void> saveToRecords() async {
          if (foundSauda == null) return;

          final isExpired = MandiSaudaModel.checkCodeExpired(
            saudaDateRaw: foundSauda!['date'],
            createdAtRaw: foundSauda!['createdAt'],
          );
          if (isExpired) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ यह सौदा कोड 1 माह से अधिक पुराना होने के कारण अमान्य हो चुका है।'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          setDialogState(() => isSaving = true);

          try {
            await CloudSyncService.saveSaudaToUserRecords(
              userMobile: currentUser.mobile,
              userName: currentUser.name,
              userRole: userRole,
              saudaData: foundSauda!,
            );

            // Also update local storage cache
            try {
              final model = MandiSaudaModel.fromJson(foundSauda!);
              final key = isBuyer
                  ? 'buyer_records_${currentUser.mobile}'
                  : 'seller_records_${currentUser.mobile}';
              if (isBuyer) {
                model.buyerConfirmed = true;
                model.buyerMobile = currentUser.mobile;
              } else {
                model.sellerConfirmed = true;
                model.sellerMobile = currentUser.mobile;
              }
              final raw = StorageService.get(key);
              List<MandiSaudaModel> list = [];
              if (raw != null && raw.isNotEmpty) {
                try {
                  list = (jsonDecode(raw) as List)
                      .map((e) => MandiSaudaModel.fromJson(e))
                      .toList();
                } catch (_) {}
              }
              list.removeWhere((s) => s.id == model.id);
              list.insert(0, model);
              StorageService.save(
                  key, jsonEncode(list.map((s) => s.toJson()).toList()));
            } catch (_) {}

            onSaudaLinked?.call();

            if (ctx.mounted) {
              Navigator.pop(ctx);
            }

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✅ सौदा #${foundSauda!['id']} आपके रिकॉर्ड में सफलतापूर्वक जोड़ दिया गया!',
                  ),
                  backgroundColor: const Color(0xFF10B981),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } catch (err) {
            setDialogState(() => isSaving = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('रिकॉर्ड सेव करने में त्रुटि: $err')),
              );
            }
          }
        }

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.receipt_long_rounded,
                            color: themeColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LINK SAUDA BY CODE (सौदा कोड से जोड़ें)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: themeColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '6-अंकीय कोड से खोजें व $roleHindi बही में जोड़ें (सौदा कोड 1 माह तक मान्य)',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black45),
                        onPressed: () => Navigator.pop(ctx),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Search input row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: idController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.8,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter Sauda Code (उदा. ABC123 - 3 अक्षर व 3 अंक)',
                            hintStyle: const TextStyle(
                                color: Colors.black38,
                                fontSize: 12.5,
                                fontWeight: FontWeight.normal),
                            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.content_paste_rounded,
                                      size: 18),
                                  tooltip: 'Paste ID',
                                  onPressed: () async {
                                    final data = await Clipboard.getData(
                                        Clipboard.kTextPlain);
                                    if (data?.text != null &&
                                        data!.text!.trim().isNotEmpty) {
                                      idController.text = data.text!.trim();
                                      setDialogState(() {});
                                    }
                                  },
                                ),
                                if (idController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      idController.clear();
                                      setDialogState(() {
                                        foundSauda = null;
                                        searchError = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: themeColor, width: 1.8),
                            ),
                          ),
                          onSubmitted: (_) => executeSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isSearching ? null : executeSearch,
                        child: isSearching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Search Error Message
                  if (searchError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              searchError!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Found Sauda Details Card
                  if (foundSauda != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF86EFAC)),
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
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'SAUDA #${foundSauda!['id']}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F766E)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFF0F766E)
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      'वैध (${MandiSaudaModel.daysRemainingForCode(saudaDateRaw: foundSauda!['date'], createdAtRaw: foundSauda!['createdAt'])} दिन शेष)',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F766E),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'दिनांक: ${(foundSauda!['date'] ?? '').toString().split('T').first}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.black54),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('जिंस / फसल (Commodity):',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                    Text(
                                      '${foundSauda!['jins'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('बोरी / वजन (Quantity):',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                    Text(
                                      '${foundSauda!['bags'] ?? 0} बोरी',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('सौदा भाव (Rate):',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                    Text(
                                      '₹${foundSauda!['rate'] ?? 0} / क्विंटल',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F766E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('कुल रकम (Turnover):',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54)),
                                    Text(
                                      '₹${((num.tryParse(foundSauda!['bags']?.toString() ?? '0') ?? 0) * (num.tryParse(foundSauda!['rate']?.toString() ?? '0') ?? 0)).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.handshake_rounded,
                                  size: 15, color: Color(0xFF0F766E)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'ब्रोकर: ${foundSauda!['brokerFirmName'] ?? 'Broker'} (${foundSauda!['brokerMobile'] ?? ''})',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.swap_horiz_rounded,
                                  size: 15, color: Colors.black54),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isBuyer
                                      ? 'विक्रेता (Seller): ${foundSauda!['seller'] ?? 'N/A'}'
                                      : 'खरीदार (Buyer): ${foundSauda!['buyer'] ?? 'N/A'}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Save / Link Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.save_alt_rounded, size: 18),
                      label: Text(
                        isSaving
                            ? 'Saving to records...'
                            : 'SAVE TO MY RECORDS (अपने रिकॉर्ड में जोड़ें)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      onPressed: isSaving ? null : saveToRecords,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

