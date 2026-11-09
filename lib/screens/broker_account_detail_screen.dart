import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mandi_models.dart';
import '../services/cloud_sync_service.dart';
import '../services/mandi_services.dart';
import 'bill_print_screen.dart';

/// Full-screen Broker Account Detail View for Buyers and Sellers.
/// Allows searching through all saudas with this broker, viewing bank details,
/// editing deal details, deleting deals, and sharing/printing statements.
class BrokerAccountDetailScreen extends StatefulWidget {
  final String brokerFirmName;
  final String brokerMobile;
  final List<MandiSaudaModel> initialDeals;
  final UserAccount currentUser;
  final bool isBuyer;
  final Function(MandiSaudaModel updated)? onSaudaEdited;
  final Function(String saudaId)? onSaudaDeleted;

  const BrokerAccountDetailScreen({
    super.key,
    required this.brokerFirmName,
    required this.brokerMobile,
    required this.initialDeals,
    required this.currentUser,
    required this.isBuyer,
    this.onSaudaEdited,
    this.onSaudaDeleted,
  });

  @override
  State<BrokerAccountDetailScreen> createState() =>
      _BrokerAccountDetailScreenState();
}

class _BrokerAccountDetailScreenState extends State<BrokerAccountDetailScreen> {
  late List<MandiSaudaModel> _deals;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedFinancialYear = 'ALL';
  String? _selectedCrop;
  bool _showBankDetails = false;

  @override
  void initState() {
    super.initState();
    _deals = List<MandiSaudaModel>.from(widget.initialDeals)
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<String> get _availableFinancialYears {
    final Set<String> fySet = {};
    for (final d in _deals) {
      if (d.financialYear.isNotEmpty) {
        fySet.add(d.financialYear);
      }
    }
    final list = fySet.toList();
    list.sort((a, b) => b.compareTo(a));
    return list;
  }

  Set<String> get _availableCrops {
    final Set<String> crops = {};
    for (final d in _deals) {
      if (d.jins.trim().isNotEmpty) {
        crops.add(d.jins.trim().toUpperCase());
      }
    }
    return crops;
  }

  List<MandiSaudaModel> get _filteredDeals {
    return _deals.where((d) {
      // 1. FY filter
      if (_selectedFinancialYear != 'ALL' &&
          d.financialYear != _selectedFinancialYear) {
        return false;
      }
      // 2. Crop filter
      if (_selectedCrop != null &&
          d.jins.trim().toUpperCase() != _selectedCrop) {
        return false;
      }
      // 3. Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchCrop = d.jins.toLowerCase().contains(q);
        final matchId = d.id.toLowerCase().contains(q);
        final matchRate = d.rate.toString().contains(q);
        final matchBags = d.bags.toString().contains(q);
        final matchDate =
            '${d.date.day}/${d.date.month}/${d.date.year}'.contains(q);
        final matchSeller = d.seller.toLowerCase().contains(q) ||
            d.sellerMobile.contains(q);
        final matchBuyer = d.buyer.toLowerCase().contains(q) ||
            d.buyerMobile.contains(q);

        if (!matchCrop &&
            !matchId &&
            !matchRate &&
            !matchBags &&
            !matchDate &&
            !matchSeller &&
            !matchBuyer) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _handleDeleteDeal(MandiSaudaModel sauda) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red, size: 26),
            SizedBox(width: 8),
            Text('सौदा हटाएं (Delete Sauda)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'क्या आप वाकई इस सौदे को अपनी बही से हटाना चाहते हैं?',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🌾 जिंस: ${sauda.jins} - ${sauda.bags} बोरी @ ₹${sauda.rate.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'सौदा ID: #${sauda.id} | कुल: ₹${(sauda.bags * sauda.rate).toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें (CANCEL)',
                style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('हटाएं (DELETE)',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await CloudSyncService.deleteSaudaFromUserFolder(
        userMobile: widget.currentUser.mobile,
        saudaId: sauda.id,
      );

      setState(() {
        _deals.removeWhere((s) => s.id == sauda.id);
      });

      widget.onSaudaDeleted?.call(sauda.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('✅ सौदा बही से सफलतापूर्वक हटा दिया गया!'),
              ],
            ),
            backgroundColor: Color(0xFF0F766E),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ सौदा हटाने में त्रुटि: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleEditDeal(MandiSaudaModel sauda) {
    showEditPartySaudaDialog(
      context: context,
      sauda: sauda,
      isBuyer: widget.isBuyer,
      currentUser: widget.currentUser,
      onSaudaEdited: (updated) {
        setState(() {
          final idx = _deals.indexWhere((s) => s.id == updated.id);
          if (idx != -1) {
            _deals[idx] = updated;
          } else {
            _deals.insert(0, updated);
          }
        });
        widget.onSaudaEdited?.call(updated);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDeals;
    final totalBags = filtered.fold<int>(0, (acc, d) => acc + d.bags);
    final totalAmount =
        filtered.fold<double>(0.0, (acc, d) => acc + (d.bags * d.rate));
    final totalDalali = filtered.fold<double>(
      0.0,
      (acc, d) =>
          acc + (widget.isBuyer ? d.totalBuyerDalali : d.totalSellerDalali),
    );

    final brokerProfile = BrokerFirmProfileModel(
      firmName: widget.brokerFirmName,
      mobile: widget.brokerMobile,
      address: widget.brokerMobile,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.brokerFirmName.isNotEmpty
                  ? widget.brokerFirmName
                  : 'ब्रोकर खाता',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.isBuyer
                  ? 'क्रेता बही खाता (Buyer Khata)'
                  : 'विक्रेता बही खाता (Seller Khata)',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF38BDF8),
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'प्रिंट खाता (Print Statement)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MandiBillPrintScreen(
                    party: MandiPartyModel(
                      name: widget.currentUser.name,
                      mobile: widget.currentUser.mobile,
                      address: widget.currentUser.address,
                      type: widget.isBuyer ? 'Buyer' : 'Seller',
                    ),
                    isBuyer: widget.isBuyer,
                    deals: _deals,
                    selectedPeriod: _selectedFinancialYear == 'ALL'
                        ? 'Broker: ${widget.brokerFirmName}'
                        : 'Broker: ${widget.brokerFirmName} ($_selectedFinancialYear)',
                    brokerProfile: brokerProfile,
                    initialDuration: _selectedFinancialYear != 'ALL'
                        ? _selectedFinancialYear
                        : 'ALL',
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Color(0xFF0F766E)),
            tooltip: 'व्हाट्सएप खाता शेयर करें',
            onPressed: () async {
              await WhatsAppService.shareBrokerKhataStatement(
                brokerFirmName: widget.brokerFirmName,
                brokerMobile: widget.brokerMobile,
                partyName: widget.currentUser.name,
                partyMobile: widget.currentUser.mobile,
                isBuyer: widget.isBuyer,
                deals: filtered,
                recipientMobile: widget.brokerMobile,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Broker Profile & Bank Details Card
                _buildBrokerHeaderCard(),
                const SizedBox(height: 12),

                // 2. Financial Trading Summary Bar
                _buildTradingSummaryBar(
                  dealCount: filtered.length,
                  totalBags: totalBags,
                  totalAmount: totalAmount,
                  totalDalali: totalDalali,
                ),
                const SizedBox(height: 12),

                // 3. Search & Filter Bar
                _buildSearchAndFilterCard(),
                const SizedBox(height: 12),

                // 4. Deals List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'सौदे की सूची (${filtered.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty ||
                        _selectedCrop != null ||
                        _selectedFinancialYear != 'ALL')
                      TextButton.icon(
                        icon: const Icon(Icons.clear_all, size: 16),
                        label: const Text('फ़िल्टर हटाएं (Reset)',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          setState(() {
                            _searchCtrl.clear();
                            _searchQuery = '';
                            _selectedFinancialYear = 'ALL';
                            _selectedCrop = null;
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // 5. Deals ListView
                if (filtered.isEmpty)
                  _buildEmptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildDealCard(filtered[index]);
                    },
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 1. Broker Profile & Bank Details Card
  Widget _buildBrokerHeaderCard() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: CloudSyncService.getBrokerProfile(widget.brokerMobile),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? {};
        final firmName = profile['firmName']?.toString().isNotEmpty == true
            ? profile['firmName'].toString()
            : (widget.brokerFirmName.isNotEmpty
                ? widget.brokerFirmName
                : 'Mandi Broker');
        final phone = profile['mobile']?.toString().isNotEmpty == true
            ? profile['mobile'].toString()
            : widget.brokerMobile;
        final address = (profile['address'] ?? 'मुख्य मंडी प्रांगण').toString();

        final bank = (profile['bankDetails'] as Map?) ?? {};
        final bankName = (bank['bankName'] ?? '').toString();
        final accNo = (bank['accountNumber'] ?? bank['accountNo'] ?? '')
            .toString();
        final ifsc = (bank['ifsc'] ?? '').toString();
        final branch = (bank['branch'] ?? '').toString();
        final pan = (profile['pan'] ?? '').toString();
        final gst = (profile['gst'] ?? '').toString();

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          const Color(0xFF0F766E).withValues(alpha: 0.12),
                      child: const Icon(Icons.business_rounded,
                          color: Color(0xFF0F766E), size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            firmName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '📞 $phone ${address.isNotEmpty ? "• 📍 $address" : ""}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Call & WhatsApp Direct Buttons
                    if (phone.isNotEmpty) ...[
                      IconButton(
                        icon: const Icon(Icons.call,
                            color: Color(0xFF0F766E), size: 22),
                        tooltip: 'कॉल करें',
                        onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chat,
                            color: Color(0xFF25D366), size: 22),
                        tooltip: 'व्हाट्सएप चैट',
                        onPressed: () =>
                            launchUrl(Uri.parse('https://wa.me/91$phone')),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Toggle Bank Details Button
                InkWell(
                  onTap: () =>
                      setState(() => _showBankDetails = !_showBankDetails),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.account_balance,
                                size: 15, color: Color(0xFF0F766E)),
                            SizedBox(width: 6),
                            Text(
                              'ब्रोकर बैंक व कर विवरण (Bank & Tax Info)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _showBankDetails
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: const Color(0xFF0F766E),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_showBankDetails) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBankRow('बैंक का नाम (Bank):',
                            bankName.isNotEmpty ? bankName : 'उपलब्ध नहीं'),
                        _buildBankRow('खाता संख्या (A/C No):',
                            accNo.isNotEmpty ? accNo : 'उपलब्ध नहीं'),
                        _buildBankRow('IFSC कोड:',
                            ifsc.isNotEmpty ? ifsc : 'उपलब्ध नहीं'),
                        _buildBankRow('शाखा (Branch):',
                            branch.isNotEmpty ? branch : 'उपलब्ध नहीं'),
                        if (pan.isNotEmpty) _buildBankRow('PAN नंबर:', pan),
                        if (gst.isNotEmpty) _buildBankRow('GSTIN:', gst),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBankRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  // 2. Financial Trading Summary Bar
  Widget _buildTradingSummaryBar({
    required int dealCount,
    required int totalBags,
    required double totalAmount,
    required double totalDalali,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSummaryItem('कुल सौदे', '$dealCount', Icons.receipt_long),
          Container(width: 1, height: 32, color: Colors.white24),
          _buildSummaryItem('कुल बोरी', '$totalBags', Icons.inventory_2),
          Container(width: 1, height: 32, color: Colors.white24),
          _buildSummaryItem(
            widget.isBuyer ? 'कुल खरीद' : 'कुल बिक्री',
            '₹${totalAmount.toStringAsFixed(0)}',
            Icons.currency_rupee,
            valueColor: const Color(0xFF38BDF8),
          ),
          Container(width: 1, height: 32, color: Colors.white24),
          _buildSummaryItem(
            'देय दलाली',
            '₹${totalDalali.toStringAsFixed(0)}',
            Icons.handshake,
            valueColor: const Color(0xFF4ADE80),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.white,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // 3. Search & Filter Bar
  Widget _buildSearchAndFilterCard() {
    final availableFYs = _availableFinancialYears;
    final crops = _availableCrops;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live Search Input
            TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'सौदा खोजें (जिंस, तारीख, सौदा ID, पार्टी, भाव)...',
                hintStyle: const TextStyle(fontSize: 12.5),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),

            // Financial Year (वित्त वर्ष) Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 13, color: Color(0xFF0284C7)),
                        SizedBox(width: 4),
                        Text(
                          'वित्त वर्ष (FY):',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('सभी वर्ष (All)'),
                    selected: _selectedFinancialYear == 'ALL',
                    selectedColor: const Color(0xFF0284C7),
                    backgroundColor: Colors.grey.shade100,
                    labelStyle: TextStyle(
                      color: _selectedFinancialYear == 'ALL'
                          ? Colors.white
                          : Colors.black87,
                      fontWeight: _selectedFinancialYear == 'ALL'
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 11,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedFinancialYear = 'ALL');
                      }
                    },
                  ),
                  ...availableFYs.map((fy) {
                    final isSelected = _selectedFinancialYear == fy;
                    final count =
                        _deals.where((d) => d.financialYear == fy).length;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        label: Text('$fy ($count)'),
                        selected: isSelected,
                        selectedColor: const Color(0xFF0284C7),
                        backgroundColor: Colors.grey.shade100,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedFinancialYear = fy);
                          }
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Commodity (जिंस) Chips (without amount as per user preference)
            if (crops.length > 1) ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('सभी जिंस (All)'),
                      selected: _selectedCrop == null,
                      selectedColor: const Color(0xFF0F766E),
                      backgroundColor: Colors.grey.shade100,
                      labelStyle: TextStyle(
                        color:
                            _selectedCrop == null ? Colors.white : Colors.black87,
                        fontWeight: _selectedCrop == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 11,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: (val) {
                        if (val) setState(() => _selectedCrop = null);
                      },
                    ),
                    ...crops.map((crop) {
                      final isSelected = _selectedCrop == crop;
                      final cropBags = _deals
                          .where((d) => d.jins.trim().toUpperCase() == crop)
                          .fold<int>(0, (acc, d) => acc + d.bags);
                      return Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: FilterChip(
                          label: Text('$crop: $cropBags बोरी'),
                          selected: isSelected,
                          selectedColor: const Color(0xFF0F766E),
                          backgroundColor: Colors.grey.shade100,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 11,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          onSelected: (val) {
                            setState(() {
                              _selectedCrop = val ? crop : null;
                            });
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 4. Deal Card with Direct Edit & Delete Actions
  Widget _buildDealCard(MandiSaudaModel s) {
    final dateStr =
        '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}/${s.date.year}';
    final totalAmount = (s.bags * s.rate);
    final dalaliAmount =
        widget.isBuyer ? s.totalBuyerDalali : s.totalSellerDalali;
    final dalaliPerBag =
        widget.isBuyer ? s.buyerDalaliPerBag : s.sellerDalaliPerBag;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.teal.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Crop, Date, FY badge, and Sauda ID
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.jins,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        s.financialYear,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'ID: #${s.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 2: Bags @ Rate & Total Value
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${s.bags} बोरी  @  ₹${s.rate.toStringAsFixed(0)} / क्विंटल',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '₹${totalAmount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Row 3: Counterparty Info Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isBuyer
                          ? '🚜 विक्रेता: ${s.seller.isNotEmpty ? s.seller : "Seller"} ${s.sellerMobile.isNotEmpty ? "(${s.sellerMobile})" : ""}'
                          : '🛒 क्रेता: ${s.buyer.isNotEmpty ? s.buyer : "Buyer"} ${s.buyerMobile.isNotEmpty ? "(${s.buyerMobile})" : ""}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Row 4: Dalali Note
            Text(
              'देय दलाली: ₹${dalaliAmount.toStringAsFixed(0)} (₹${dalaliPerBag.toStringAsFixed(0)}/बोरी)',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 18),

            // Action Buttons: Edit, Delete, WhatsApp Slip
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                // 1. Edit Sauda Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _handleEditDeal(s),
                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                  label: const Text(
                    'संपादित करें (Edit)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),

                // 2. Delete Sauda Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _handleDeleteDeal(s),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text(
                    'हटाएं (Delete)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 30),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'कोई सौदा नहीं मिला (No Deals Found)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _searchQuery.isNotEmpty
                  ? '"$_searchQuery" से मिलता कोई सौदा इस खाते में नहीं है'
                  : 'इस वित्तीय वर्ष अथवा ब्रोकर खाते में कोई सौदा दर्ज नहीं है',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone reusable dialog for Buyers & Sellers to edit any Sauda.
/// Updates the sauda across both personal Firestore folder and local storage.
void showEditPartySaudaDialog({
  required BuildContext context,
  required MandiSaudaModel sauda,
  required bool isBuyer,
  required UserAccount currentUser,
  required Function(MandiSaudaModel updated) onSaudaEdited,
}) {
  final jinsCtrl = TextEditingController(text: sauda.jins);
  final bagsCtrl = TextEditingController(text: sauda.bags.toString());
  final rateCtrl = TextEditingController(text: sauda.rate.toString());
  final dalaliCtrl = TextEditingController(
    text: isBuyer
        ? sauda.buyerDalaliPerBag.toString()
        : sauda.sellerDalaliPerBag.toString(),
  );

  DateTime selectedDate = sauda.date;
  final now = DateTime.now();
  bool isSaving = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: Color(0xFF0F766E), size: 26),
            const SizedBox(width: 8),
            Text(
              'सौदा संपादित करें (Edit Sauda #${sauda.id})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Date Row with Date Picker Button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Color(0xFF0F766E)),
                        const SizedBox(width: 8),
                        Text(
                          'दिनांक: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFF0F766E),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              selectedDate.isAfter(now) ? now : selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: now,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: const Text('बदलें (Change)'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Jins / Commodity Input
              TextField(
                controller: jinsCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'जिंस / Commodity *',
                  hintText: 'उदा. SOYABEAN, WHEAT',
                  prefixIcon: Icon(Icons.grass),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),

              // Bags & Rate
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bagsCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'बोरी (Bags) *',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: rateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'भाव (₹/क्विंटल) *',
                        prefixIcon: Icon(Icons.currency_rupee),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Dalali Per Bag
              TextField(
                controller: dalaliCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: isBuyer
                      ? 'क्रेता दलाली (₹/बोरी)'
                      : 'विक्रेता दलाली (₹/बोरी)',
                  prefixIcon: const Icon(Icons.handshake_outlined),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(ctx),
            child: const Text('रद्द करें (CANCEL)'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
            ),
            onPressed: isSaving
                ? null
                : () async {
                    final int bags = int.tryParse(bagsCtrl.text.trim()) ?? 0;
                    final double rate =
                        double.tryParse(rateCtrl.text.trim()) ?? 0.0;
                    final String jins = jinsCtrl.text.trim().toUpperCase();

                    if (jins.isEmpty || bags <= 0 || rate <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('कृपया जिंस, बोरी और भाव सही भरें'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final double dalali =
                        double.tryParse(dalaliCtrl.text.trim()) ?? 0.0;

                    setDialogState(() => isSaving = true);

                    final updated = sauda.copyWith(
                      date: selectedDate,
                      financialYear:
                          MandiSaudaModel.computeFinancialYear(selectedDate),
                      jins: jins,
                      bags: bags,
                      rate: rate,
                      buyer: sauda.buyer,
                      buyerMobile: sauda.buyerMobile,
                      seller: sauda.seller,
                      sellerMobile: sauda.sellerMobile,
                      buyerDalaliPerBag:
                          isBuyer ? dalali : sauda.buyerDalaliPerBag,
                      sellerDalaliPerBag:
                          !isBuyer ? dalali : sauda.sellerDalaliPerBag,
                    );

                    try {
                      await CloudSyncService.saveSaudaToUserRecords(
                        userMobile: currentUser.mobile,
                        userName: currentUser.name,
                        userRole: isBuyer ? 'BUYER' : 'SELLER',
                        saudaData: updated.toJson(),
                      );

                      onSaudaEdited(updated);

                      if (context.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.check_circle,
                                    color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text('✅ सौदा सफलतापूर्वक अपडेट कर दिया गया!'),
                              ],
                            ),
                            backgroundColor: Color(0xFF0F766E),
                          ),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ अपडेट करने में समस्या: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('सहेजें (SAVE)'),
          ),
        ],
      ),
    ),
  );
}
