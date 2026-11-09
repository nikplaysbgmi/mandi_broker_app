import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';

/// Shows an intuitive dialog for Buyers and Sellers to directly add/record
/// any trade into their own personal books without needing any Sauda Code
/// and without triggering any WhatsApp share prompt.
void showManualAddSaudaDialog({
  required BuildContext context,
  required UserAccount currentUser,
  required String userRole, // 'BUYER' or 'SELLER'
  List<MandiSaudaModel>? existingDeals,
  VoidCallback? onSaudaAdded,
}) {
  final isBuyer = userRole.toUpperCase() == 'BUYER';
  final themeColor =
      isBuyer ? const Color(0xFF0284C7) : const Color(0xFFD97706);

  // Extract unique past party names & broker names for autocomplete
  final Set<String> pastParties = {};
  final Set<String> pastBrokers = {};
  if (existingDeals != null) {
    for (final d in existingDeals) {
      if (isBuyer) {
        if (d.seller.trim().isNotEmpty) pastParties.add(d.seller.trim());
      } else {
        if (d.buyer.trim().isNotEmpty) pastParties.add(d.buyer.trim());
      }
      if (d.brokerFirmName.trim().isNotEmpty &&
          !d.brokerFirmName.contains('Direct')) {
        pastBrokers.add(d.brokerFirmName.trim());
      }
    }
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ManualAddSaudaDialogWidget(
      currentUser: currentUser,
      isBuyer: isBuyer,
      themeColor: themeColor,
      pastParties: pastParties.toList(),
      pastBrokers: pastBrokers.toList(),
      onSaudaAdded: onSaudaAdded,
    ),
  );
}

class _ManualAddSaudaDialogWidget extends StatefulWidget {
  final UserAccount currentUser;
  final bool isBuyer;
  final Color themeColor;
  final List<String> pastParties;
  final List<String> pastBrokers;
  final VoidCallback? onSaudaAdded;

  const _ManualAddSaudaDialogWidget({
    required this.currentUser,
    required this.isBuyer,
    required this.themeColor,
    required this.pastParties,
    required this.pastBrokers,
    this.onSaudaAdded,
  });

  @override
  State<_ManualAddSaudaDialogWidget> createState() =>
      _ManualAddSaudaDialogWidgetState();
}

class _ManualAddSaudaDialogWidgetState
    extends State<_ManualAddSaudaDialogWidget> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  final _partyNameCtrl = TextEditingController();
  final _partyMobileCtrl = TextEditingController();
  final _brokerNameCtrl = TextEditingController();
  final _brokerMobileCtrl = TextEditingController();
  final _jinsCtrl = TextEditingController();
  final _bagsCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _dalaliRateCtrl = TextEditingController(text: '0');

  bool _isSaving = false;
  String? _errorMessage;

  static const List<String> _popularCommodities = [
    'चना (Chana)',
    'सोयाबीन (Soyabean)',
    'गेहूँ (Wheat)',
    'सरसों (Mustard)',
    'मक्का (Maize)',
    'मूंग (Moong)',
    'उड़द (Urad)',
    'तुवर / अरहर (Tur)',
    'धनिया (Coriander)',
    'लहसुन (Garlic)',
    'प्याज (Onion)',
    'मेथी (Fenugreek)',
  ];

  @override
  void dispose() {
    _partyNameCtrl.dispose();
    _partyMobileCtrl.dispose();
    _brokerNameCtrl.dispose();
    _brokerMobileCtrl.dispose();
    _jinsCtrl.dispose();
    _bagsCtrl.dispose();
    _rateCtrl.dispose();
    _dalaliRateCtrl.dispose();
    super.dispose();
  }

  double get _totalAmount {
    final bags = int.tryParse(_bagsCtrl.text.trim()) ?? 0;
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    return bags * rate;
  }

  double get _totalDalali {
    final bags = int.tryParse(_bagsCtrl.text.trim()) ?? 0;
    final dRate = double.tryParse(_dalaliRateCtrl.text.trim()) ?? 0.0;
    return bags * dRate;
  }

  Future<void> _handleSave() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final partyName = _partyNameCtrl.text.trim().toUpperCase();
    final jins = _jinsCtrl.text.trim().toUpperCase();
    final bags = int.tryParse(_bagsCtrl.text.trim()) ?? 0;
    final rate = double.tryParse(_rateCtrl.text.trim()) ?? 0.0;
    final dalali = double.tryParse(_dalaliRateCtrl.text.trim()) ?? 0.0;
    final partyMob = _partyMobileCtrl.text.trim();
    final brokerName = _brokerNameCtrl.text.trim().toUpperCase();
    final brokerMob = _brokerMobileCtrl.text.trim();

    if (partyName.isEmpty) {
      setState(() => _errorMessage = widget.isBuyer
          ? 'कृपया विक्रेता/पार्टी का नाम दर्ज करें'
          : 'कृपया खरीदार/पार्टी का नाम दर्ज करें');
      return;
    }

    if (jins.isEmpty) {
      setState(() => _errorMessage = 'कृपया जिंस (फसल) का नाम दर्ज करें');
      return;
    }

    if (bags <= 0) {
      setState(() => _errorMessage = 'कृपया मान्य बोरी संख्या (> 0) दर्ज करें');
      return;
    }

    if (rate <= 0) {
      setState(() => _errorMessage = 'कृपया मान्य भाव (> 0) दर्ज करें');
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Auto-generate clean unique ID (no manual code required from user)
      final autoId =
          'REC${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}${Random().nextInt(900) + 100}';

      final sauda = MandiSaudaModel(
        id: autoId,
        date: _selectedDate,
        buyer: widget.isBuyer ? widget.currentUser.name : partyName,
        buyerMobile: widget.isBuyer ? widget.currentUser.mobile : partyMob,
        seller: widget.isBuyer ? partyName : widget.currentUser.name,
        sellerMobile: widget.isBuyer ? partyMob : widget.currentUser.mobile,
        jins: jins,
        bags: bags,
        rate: rate,
        buyerDalaliPerBag: widget.isBuyer ? dalali : 0.0,
        sellerDalaliPerBag: widget.isBuyer ? 0.0 : dalali,
        buyerConfirmed: true,
        sellerConfirmed: true,
        brokerFirmName:
            brokerName.isNotEmpty ? brokerName : 'Direct (सीधा सौदा)',
        brokerMobile: brokerMob,
      );

      await CloudSyncService.saveSaudaToUserRecords(
        userMobile: widget.currentUser.mobile,
        userName: widget.currentUser.name,
        userRole: widget.isBuyer ? 'BUYER' : 'SELLER',
        saudaData: sauda.toJson(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isBuyer
                        ? '✅ सौदा बही में सफलतापूर्वक दर्ज हो गया!'
                        : '✅ सौदा बही में सफलतापूर्वक दर्ज हो गया!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0F766E),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSaudaAdded?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'सौदा सुरक्षित करने में त्रुटि: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.themeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.isBuyer
                              ? Icons.shopping_bag_outlined
                              : Icons.sell_outlined,
                          color: widget.themeColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isBuyer
                                  ? 'बही में नया सौदा दर्ज करें (Add Purchase)'
                                  : 'बही में नया सौदा दर्ज करें (Add Sale)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.themeColor,
                              ),
                            ),
                            const Text(
                              'सीधा या आढ़त का सौदा तुरंत अपनी बही में जोड़ें',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.black54),
                        tooltip: 'बंद करें (Close)',
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 2. Date Selector Bar
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_month,
                                size: 18, color: widget.themeColor),
                            const SizedBox(width: 8),
                            Text(
                              'दिनांक: ${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year} (${MandiSaudaModel.computeFinancialYear(_selectedDate)})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ],
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: now,
                            );
                            if (picked != null) {
                              setState(() => _selectedDate = picked);
                            }
                          },
                          child: Text(
                            'तारीख बदलें',
                            style: TextStyle(
                              color: widget.themeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Party Name Field (Autocomplete from past parties)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Autocomplete<String>(
                        optionsBuilder: (TextEditingValue val) {
                          final q = val.text.trim().toUpperCase();
                          if (q.isEmpty) return const Iterable<String>.empty();
                          return widget.pastParties
                              .where((p) => p.toUpperCase().contains(q));
                        },
                        onSelected: (selection) =>
                            _partyNameCtrl.text = selection,
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          // Link controller if user types
                          controller.addListener(() {
                            _partyNameCtrl.text = controller.text;
                          });
                          return TextFormField(
                            controller: controller,
                            focusNode: focusNode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: widget.isBuyer
                                  ? 'Seller Name *'
                                  : 'Buyer Name*',
                              hintText: widget.isBuyer ? '' : '',
                              prefixIcon: Icon(
                                widget.isBuyer
                                    ? Icons.person_outline
                                    : Icons.store_outlined,
                                color: widget.themeColor,
                              ),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'नाम दर्ज करना अनिवार्य है';
                              }
                              return null;
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 10),

                  // 4. Party Mobile (Optional)
                  TextFormField(
                    controller: _partyMobileCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText:
                          'पार्टी मोबाइल नंबर (Mobile Number - Optional)',
                      hintText: 'मोबाइल नंबर',
                      prefixIcon:
                          Icon(Icons.phone_outlined, color: Colors.grey),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 5. Broker Name & Mobile (Optional)
                  Row(
                    children: [
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (TextEditingValue val) {
                            final q = val.text.trim().toUpperCase();
                            if (q.isEmpty) {
                              return const Iterable<String>.empty();
                            }
                            return widget.pastBrokers
                                .where((b) => b.toUpperCase().contains(q));
                          },
                          onSelected: (selection) =>
                              _brokerNameCtrl.text = selection,
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            controller.addListener(() {
                              _brokerNameCtrl.text = controller.text;
                            });
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'दलाल / ब्रोकर फर्म (Broker)',
                                hintText: 'खाली छोड़ें यदि सीधा सौदा है',
                                prefixIcon: Icon(Icons.handshake_outlined,
                                    color: Colors.grey),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 12),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _brokerMobileCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'ब्रोकर मोबाइल (Optional)',
                            hintText: '10 अंक',
                            prefixIcon: Icon(Icons.phone_android,
                                color: Colors.grey, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 6. Commodity / Jins Field
                  TextFormField(
                    controller: _jinsCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'जिंस (Commodity / Jins) *',
                      hintText: 'उदा. चना, सोयाबीन, गेहूँ, सरसों',
                      prefixIcon:
                          Icon(Icons.grass_outlined, color: widget.themeColor),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'जिंस का नाम अनिवार्य है';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),

                  // Quick Commodity Suggestion Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _popularCommodities.map((cropWithEn) {
                        final pureName = cropWithEn.split(' ').first;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(
                              pureName,
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: Colors.grey.shade100,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: () {
                              setState(() {
                                _jinsCtrl.text = pureName;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 7. Bags, Rate & Dalali Row
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _bagsCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'बोरी संख्या *',
                            hintText: '',
                            prefixIcon: Icon(Icons.inventory_2_outlined,
                                color: Colors.black54, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                          ),
                          validator: (val) {
                            final b = int.tryParse(val ?? '') ?? 0;
                            if (b <= 0) return 'बोरी > 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: TextFormField(
                          controller: _rateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'भाव (₹/बोरी) *',
                            hintText: '',
                            prefixIcon: Icon(Icons.currency_rupee,
                                color: Colors.black54, size: 18),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                          ),
                          validator: (val) {
                            final r = double.tryParse(val ?? '') ?? 0.0;
                            if (r <= 0) return 'भाव > 0';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _dalaliRateCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'दलाली ₹/बोरी',
                            hintText: '0',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 8. Live Calculation Summary Card
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: widget.themeColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'कुल माल मूल्य',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.black54),
                            ),
                            Text(
                              '₹${_totalAmount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: widget.themeColor,
                              ),
                            ),
                          ],
                        ),
                        Container(
                            height: 28, width: 1, color: Colors.grey.shade300),
                        Column(
                          children: [
                            const Text(
                              'कुल दलाली',
                              style: TextStyle(
                                  fontSize: 10.5, color: Colors.black54),
                            ),
                            Text(
                              '₹${_totalDalali.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Container(
                            height: 28, width: 1, color: Colors.grey.shade300),
                        Column(
                          children: [
                            Text(
                              widget.isBuyer ? 'कुल लागत' : 'निवल प्राप्य',
                              style: const TextStyle(
                                  fontSize: 10.5, color: Colors.black54),
                            ),
                            Text(
                              '₹${(widget.isBuyer ? (_totalAmount + _totalDalali) : (_totalAmount - _totalDalali)).toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 9. Action Buttons: Cancel and Save to Book (No Sauda Code, No WhatsApp prompt)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('रद्द करें (Cancel)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.themeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _isSaving ? null : _handleSave,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline,
                                  size: 20),
                          label: Text(
                            _isSaving
                                ? 'सुरक्षित हो रहा है...'
                                : 'बही में सौदा दर्ज करें (Save Deal)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
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
