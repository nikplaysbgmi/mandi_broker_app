import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/mandi_models.dart';

class MandiBillPrintScreen extends StatefulWidget {
  final MandiPartyModel party;
  final bool isBuyer;
  final List<MandiSaudaModel> deals;
  final String selectedPeriod;
  final BrokerFirmProfileModel brokerProfile;
  final String? initialDuration;

  const MandiBillPrintScreen({
    super.key,
    required this.party,
    required this.isBuyer,
    required this.deals,
    required this.selectedPeriod,
    required this.brokerProfile,
    this.initialDuration,
  });

  @override
  State<MandiBillPrintScreen> createState() => _MandiBillPrintScreenState();
}

class _MandiBillPrintScreenState extends State<MandiBillPrintScreen> {
  bool _isGeneratingPdf = false;
  String _selectedDuration = 'ALL';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialDuration != null && widget.initialDuration!.isNotEmpty) {
      _selectedDuration = widget.initialDuration!;
    }
  }

  List<String> get _availableFinancialYears {
    final Set<String> fys = {};
    for (final d in widget.deals) {
      if (d.financialYear.isNotEmpty) {
        fys.add(d.financialYear);
      }
    }
    final list = fys.toList();
    list.sort((a, b) => b.compareTo(a));
    return list;
  }

  List<MandiSaudaModel> get _filteredDeals {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    switch (_selectedDuration) {
      case 'TODAY':
        return widget.deals.where((d) {
          final dealDate = DateTime(d.date.year, d.date.month, d.date.day);
          return dealDate == today;
        }).toList();

      case 'YESTERDAY':
        return widget.deals.where((d) {
          final dealDate = DateTime(d.date.year, d.date.month, d.date.day);
          return dealDate == yesterday;
        }).toList();

      case '7_DAYS':
        final sevenDaysAgo = today.subtract(const Duration(days: 7));
        return widget.deals.where((d) {
          final dealDate = DateTime(d.date.year, d.date.month, d.date.day);
          return !dealDate.isBefore(sevenDaysAgo) && !dealDate.isAfter(today);
        }).toList();

      case 'THIS_MONTH':
        return widget.deals.where((d) {
          return d.date.year == now.year && d.date.month == now.month;
        }).toList();

      case 'LAST_MONTH':
        final lastMonthYear = now.month == 1 ? now.year - 1 : now.year;
        final lastMonth = now.month == 1 ? 12 : now.month - 1;
        return widget.deals.where((d) {
          return d.date.year == lastMonthYear && d.date.month == lastMonth;
        }).toList();

      case 'CUSTOM':
        if (_customStartDate != null && _customEndDate != null) {
          final start = DateTime(_customStartDate!.year,
              _customStartDate!.month, _customStartDate!.day);
          final end = DateTime(_customEndDate!.year, _customEndDate!.month,
              _customEndDate!.day);
          return widget.deals.where((d) {
            final dealDate = DateTime(d.date.year, d.date.month, d.date.day);
            return !dealDate.isBefore(start) && !dealDate.isAfter(end);
          }).toList();
        }
        return widget.deals;

      default:
        if (_selectedDuration.startsWith('FY ')) {
          return widget.deals
              .where((d) => d.financialYear == _selectedDuration)
              .toList();
        }
        return widget.deals;
    }
  }

  String get _currentDurationLabel {
    final now = DateTime.now();
    switch (_selectedDuration) {
      case 'TODAY':
        return 'TODAY (${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year})';
      case 'YESTERDAY':
        final y = now.subtract(const Duration(days: 1));
        return 'YESTERDAY (${y.day.toString().padLeft(2, '0')}/${y.month.toString().padLeft(2, '0')}/${y.year})';
      case '7_DAYS':
        final start = now.subtract(const Duration(days: 7));
        return 'LAST 7 DAYS (${start.day}/${start.month} - ${now.day}/${now.month}/${now.year})';
      case 'THIS_MONTH':
        return 'THIS MONTH (${_monthNames[now.month]} ${now.year})';
      case 'LAST_MONTH':
        final lm = now.month == 1
            ? DateTime(now.year - 1, 12, 1)
            : DateTime(now.year, now.month - 1, 1);
        return 'LAST MONTH (${_monthNames[lm.month]} ${lm.year})';
      case 'CUSTOM':
        if (_customStartDate != null && _customEndDate != null) {
          final s = _customStartDate!;
          final e = _customEndDate!;
          return '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year} TO ${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
        }
        return 'CUSTOM RANGE';
      default:
        if (_selectedDuration.startsWith('FY ')) {
          return _selectedDuration;
        }
        return widget.selectedPeriod.isNotEmpty
            ? widget.selectedPeriod
            : 'ALL TRANSACTIONS';
    }
  }

  String get _effectivePeriodText {
    if (_selectedDuration == 'ALL') {
      return widget.selectedPeriod.isNotEmpty
          ? widget.selectedPeriod
          : 'ALL TRANSACTIONS';
    }
    if (widget.selectedPeriod.isNotEmpty &&
        widget.selectedPeriod.startsWith('Broker:')) {
      return '${widget.selectedPeriod} • $_currentDurationLabel';
    }
    return _currentDurationLabel;
  }

  final List<String> _monthNames = const [
    '',
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  Uint8List? _safeDecodeLogo(String? rawBase64) {
    if (rawBase64 == null || rawBase64.trim().isEmpty) return null;
    try {
      final clean = rawBase64.contains(',')
          ? rawBase64.split(',').last.trim()
          : rawBase64.trim();
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  Future<void> _generateAndDownloadPdf({
    required List<MandiSaudaModel> sortedDeals,
    required Map<String, List<MandiSaudaModel>> monthlyGroups,
    required int grandTotalBags,
    required double grandTotalDalali,
    required String dateRangeText,
  }) async {
    if (_isGeneratingPdf) return;
    setState(() => _isGeneratingPdf = true);

    try {
      final doc = pw.Document();

      // Supports English, Hindi (Devanagari), and Indian Rupee (₹) symbol
      pw.Font baseFont;
      pw.Font boldFont;
      try {
        baseFont = await PdfGoogleFonts.notoSansDevanagariRegular();
        boldFont = await PdfGoogleFonts.notoSansDevanagariBold();
      } catch (_) {
        baseFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }

      final Uint8List? logoBytes =
          _safeDecodeLogo(widget.brokerProfile.photoBase64);

      final firmTitle = widget.brokerProfile.firmName.isEmpty
          ? 'MANDI BROKER'
          : widget.brokerProfile.firmName;

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context ctx) {
            final List<pw.Widget> elements = [];

            // 1. TOP HEADER BOX
            elements.add(
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.black, width: 1.2),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Broker Details
                    pw.Expanded(
                      flex: 6,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            right: pw.BorderSide(
                                color: PdfColors.black, width: 1.2),
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (logoBytes != null)
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 4),
                                child: pw.Image(
                                  pw.MemoryImage(logoBytes),
                                  height: 42,
                                  width: 80,
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                            pw.Text(
                              firmTitle,
                              style: pw.TextStyle(font: boldFont, fontSize: 13),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text('Address: ${widget.brokerProfile.address}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.Text(
                              'Mobile: ${widget.brokerProfile.mobile} | PAN: ${widget.brokerProfile.panNo}',
                              style:
                                  pw.TextStyle(font: baseFont, fontSize: 9.5),
                            ),
                            pw.Text(
                                'APMC Lic: ${widget.brokerProfile.licenseNo}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.Text('Email: ${widget.brokerProfile.email}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.Divider(thickness: 0.8, color: PdfColors.black),
                            pw.Text(
                              'Bank: ${widget.brokerProfile.bankName} | A/C: ${widget.brokerProfile.accountNo}\nIFSC: ${widget.brokerProfile.ifscCode}',
                              style: pw.TextStyle(font: baseFont, fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Party Details
                    pw.Expanded(
                      flex: 4,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '${widget.isBuyer ? "BUYER" : "SELLER"} INFORMATION',
                              style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 11,
                                decoration: pw.TextDecoration.underline,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text('Name: ${widget.party.name}',
                                style: pw.TextStyle(
                                    font: boldFont, fontSize: 11.5)),
                            pw.Text('Mobile: ${widget.party.mobile}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.Text('Address: ${widget.party.address}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.Text('Role: ${widget.party.type}',
                                style: pw.TextStyle(
                                    font: baseFont, fontSize: 9.5)),
                            pw.SizedBox(height: 4),
                            pw.Text('Period: $_effectivePeriodText',
                                style: pw.TextStyle(
                                    font: boldFont, fontSize: 9.5)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            elements.add(pw.SizedBox(height: 6));

            // 2. TRANSACTION TABLE
            final List<pw.TableRow> rows = [];
            rows.add(
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('Date', boldFont, alignCenter: true),
                  _cell('Opposite Party', boldFont),
                  _cell('Jins', boldFont, alignCenter: true),
                  _cell('Bags', boldFont, alignRight: true),
                  _cell('Rate', boldFont, alignRight: true),
                  _cell('Dalali', boldFont, alignRight: true),
                ],
              ),
            );

            if (sortedDeals.isEmpty) {
              rows.add(
                pw.TableRow(
                  children: [
                    _cell('-', baseFont, alignCenter: true),
                    _cell(
                        'No transactions in selected period ($_currentDurationLabel)',
                        baseFont),
                    _cell('-', baseFont, alignCenter: true),
                    _cell('0', baseFont, alignRight: true),
                    _cell('0', baseFont, alignRight: true),
                    _cell('₹ 0', boldFont, alignRight: true),
                  ],
                ),
              );
            }

            for (var entry in monthlyGroups.entries) {
              for (var d in entry.value) {
                final dalali =
                    widget.isBuyer ? d.totalBuyerDalali : d.totalSellerDalali;
                final dateStr =
                    '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}';
                rows.add(
                  pw.TableRow(
                    children: [
                      _cell(dateStr, baseFont, alignCenter: true),
                      _cell(widget.isBuyer ? d.seller : d.buyer, baseFont),
                      _cell(d.jins, baseFont, alignCenter: true),
                      _cell(d.bags.toString(), baseFont, alignRight: true),
                      _cell(d.rate.toStringAsFixed(0), baseFont,
                          alignRight: true),
                      _cell('₹ ${dalali.toStringAsFixed(0)}', boldFont,
                          alignRight: true),
                    ],
                  ),
                );
              }

              final totalBags =
                  entry.value.fold<int>(0, (acc, e) => acc + e.bags);
              final totalDalali = entry.value
                  .fold<double>(
                      0.0,
                      (acc, e) =>
                          acc +
                          (widget.isBuyer
                              ? e.totalBuyerDalali
                              : e.totalSellerDalali))
                  .toStringAsFixed(0);

              rows.add(
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _cell('${entry.key} TOTAL', boldFont),
                    _cell('', baseFont),
                    _cell('', baseFont),
                    _cell(totalBags.toString(), boldFont, alignRight: true),
                    _cell('', baseFont),
                    _cell('₹ $totalDalali', boldFont, alignRight: true),
                  ],
                ),
              );
            }

            elements.add(
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                columnWidths: const {
                  0: pw.FixedColumnWidth(65),
                  1: pw.FlexColumnWidth(3.0),
                  2: pw.FixedColumnWidth(60),
                  3: pw.FixedColumnWidth(45),
                  4: pw.FixedColumnWidth(50),
                  5: pw.FixedColumnWidth(65),
                },
                children: rows,
              ),
            );

            // 3. GRAND TOTAL FOOTER
            elements.add(
              pw.Table(
                border: const pw.TableBorder(
                  left: pw.BorderSide(color: PdfColors.black, width: 0.8),
                  right: pw.BorderSide(color: PdfColors.black, width: 0.8),
                  bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
                  horizontalInside:
                      pw.BorderSide(color: PdfColors.black, width: 0.8),
                  verticalInside:
                      pw.BorderSide(color: PdfColors.black, width: 0.8),
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(4.0),
                  1: pw.FixedColumnWidth(80),
                  2: pw.FixedColumnWidth(100),
                },
                children: [
                  pw.TableRow(
                    decoration:
                        const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _cell('Date Range Period', boldFont),
                      _cell('Total Bags', boldFont, alignRight: true),
                      _cell('Grand Total Dalali', boldFont, alignRight: true),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      _cell(dateRangeText, boldFont),
                      _cell(grandTotalBags.toString(), boldFont,
                          alignRight: true),
                      _cell(
                          '₹ ${grandTotalDalali.toStringAsFixed(0)}', boldFont,
                          alignRight: true),
                    ],
                  ),
                ],
              ),
            );

            // 4. TERMS & SIGNATURES
            if (widget.brokerProfile.termsAndConditions.isNotEmpty) {
              elements.add(pw.SizedBox(height: 10));
              elements.add(
                pw.Text(
                  'TERMS & CONDITIONS:\n${widget.brokerProfile.termsAndConditions}',
                  style: pw.TextStyle(font: baseFont, fontSize: 8),
                ),
              );
            }

            elements.add(pw.SizedBox(height: 35));
            elements.add(
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Trader / Party Signature',
                      style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  pw.Text('For $firmTitle\n(Authorized Signatory)',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: boldFont, fontSize: 10)),
                ],
              ),
            );

            return elements;
          },
        ),
      );

      await Printing.layoutPdf(
        name: 'Sauda_${widget.party.name.replaceAll(' ', '_')}.pdf',
        onLayout: (PdfPageFormat format) async => doc.save(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF generation error: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Widget _buildDurationSelectorBar({
    required int dealCount,
    required int totalBags,
  }) {
    final availableFYs = _availableFinancialYears;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.calendar_month,
                      size: 18, color: Color(0xFF0F766E)),
                  SizedBox(width: 6),
                  Text(
                    'प्रिंट अवधि चुनें (Select Print Duration):',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.2)),
                ),
                child: Text(
                  '$dealCount सौदे • $totalBags बोरी',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDurationChip(label: 'सभी (All)', value: 'ALL'),
                const SizedBox(width: 6),
                _buildDurationChip(label: 'आज (Today)', value: 'TODAY'),
                const SizedBox(width: 6),
                _buildDurationChip(label: 'कल (Yesterday)', value: 'YESTERDAY'),
                const SizedBox(width: 6),
                _buildDurationChip(label: '7 दिन (7 Days)', value: '7_DAYS'),
                const SizedBox(width: 6),
                _buildDurationChip(
                    label: 'इस माह (This Month)', value: 'THIS_MONTH'),
                const SizedBox(width: 6),
                _buildDurationChip(
                    label: 'पिछला माह (Last Month)', value: 'LAST_MONTH'),
                const SizedBox(width: 6),
                _buildCustomDateChip(),
                ...availableFYs.map((fy) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _buildDurationChip(label: fy, value: fy),
                    )),
              ],
            ),
          ),
          if (_selectedDuration == 'CUSTOM' &&
              _customStartDate != null &&
              _customEndDate != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.date_range, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(
                  'अवधि: ${_customStartDate!.day}/${_customStartDate!.month}/${_customStartDate!.year} से ${_customEndDate!.day}/${_customEndDate!.month}/${_customEndDate!.year}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickCustomDateRange,
                  child: const Text(
                    'तारीख बदलें (Change)',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDurationChip({required String label, required String value}) {
    final isSelected = _selectedDuration == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF0F766E),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 11.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedDuration = value;
          });
        }
      },
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _selectedDuration == 'CUSTOM';
    return ActionChip(
      avatar: Icon(
        Icons.date_range,
        size: 14,
        color: isSelected ? Colors.white : const Color(0xFF0F766E),
      ),
      label: Text(isSelected ? 'कस्टम तारीख (Custom)' : 'कस्टम तारीख...'),
      backgroundColor:
          isSelected ? const Color(0xFF0F766E) : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 11.5,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: _pickCustomDateRange,
    );
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: (_customStartDate != null && _customEndDate != null)
          ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0F766E),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _selectedDuration = 'CUSTOM';
      });
    }
  }

  static pw.Widget _cell(String text, pw.Font font,
      {bool alignRight = false, bool alignCenter = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: alignRight
            ? pw.TextAlign.right
            : (alignCenter ? pw.TextAlign.center : pw.TextAlign.left),
        style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedDeals = List<MandiSaudaModel>.from(_filteredDeals)
      ..sort((a, b) => a.date.compareTo(b.date));

    final Map<String, List<MandiSaudaModel>> monthlyGroups = {};
    for (var d in sortedDeals) {
      final key = '${_monthNames[d.date.month]} ${d.date.year}';
      if (!monthlyGroups.containsKey(key)) monthlyGroups[key] = [];
      monthlyGroups[key]!.add(d);
    }

    final int grandTotalBags =
        sortedDeals.fold<int>(0, (acc, d) => acc + d.bags);
    final double grandTotalDalali = sortedDeals.fold<double>(
      0.0,
      (acc, d) =>
          acc + (widget.isBuyer ? d.totalBuyerDalali : d.totalSellerDalali),
    );
    final String dateRangeText = sortedDeals.isEmpty
        ? 'NO TRANSACTIONS IN $_currentDurationLabel'
        : 'FROM: ${sortedDeals.first.date.day.toString().padLeft(2, '0')}/${sortedDeals.first.date.month.toString().padLeft(2, '0')}/${sortedDeals.first.date.year}  TILL: ${sortedDeals.last.date.day.toString().padLeft(2, '0')}/${sortedDeals.last.date.month.toString().padLeft(2, '0')}/${sortedDeals.last.date.year}';

    final firmTitle = widget.brokerProfile.firmName.isEmpty
        ? 'MANDI BROKER'
        : widget.brokerProfile.firmName;
    final logoBytes = _safeDecodeLogo(widget.brokerProfile.photoBase64);

    return Scaffold(
      backgroundColor: Colors.grey.shade300,
      appBar: AppBar(
        title: const Text('Print Preview (A4 Size)'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _isGeneratingPdf
                  ? null
                  : () => _generateAndDownloadPdf(
                        sortedDeals: sortedDeals,
                        monthlyGroups: monthlyGroups,
                        grandTotalBags: grandTotalBags,
                        grandTotalDalali: grandTotalDalali,
                        dateRangeText: dateRangeText,
                      ),
              icon: _isGeneratingPdf
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0F766E),
                      ),
                    )
                  : const Icon(Icons.picture_as_pdf,
                      size: 18, color: Colors.red),
              label: Text(
                _isGeneratingPdf ? 'WAIT...' : 'PDF',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDurationSelectorBar(
            dealCount: sortedDeals.length,
            totalBags: grandTotalBags,
          ),
          Expanded(
            child: InteractiveViewer(
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.4,
              maxScale: 2.5,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Center(
                    child: Container(
                      width: 760,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 3)),
                        ],
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header Box
                          Container(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.black, width: 1.2),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                          right: BorderSide(
                                              color: Colors.black,
                                              width: 1.2)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (logoBytes != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 6),
                                            child: Image.memory(
                                              logoBytes,
                                              height: 48,
                                              width: 85,
                                              fit: BoxFit.contain,
                                              alignment: Alignment.centerLeft,
                                            ),
                                          ),
                                        Text(
                                          firmTitle,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                            'Address: ${widget.brokerProfile.address}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        Text(
                                          'Mobile: ${widget.brokerProfile.mobile} | PAN: ${widget.brokerProfile.panNo}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Text(
                                            'APMC Lic: ${widget.brokerProfile.licenseNo}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        Text(
                                            'Email: ${widget.brokerProfile.email}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        const Divider(
                                            color: Colors.black,
                                            thickness: 0.8,
                                            height: 10),
                                        Text(
                                          'Bank: ${widget.brokerProfile.bankName} | A/C: ${widget.brokerProfile.accountNo}\nIFSC: ${widget.brokerProfile.ifscCode}',
                                          style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${widget.isBuyer ? "BUYER" : "SELLER"} INFORMATION',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text('Name: ${widget.party.name}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                        Text('Mobile: ${widget.party.mobile}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        Text('Address: ${widget.party.address}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        Text('Role: ${widget.party.type}',
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        const SizedBox(height: 4),
                                        Text('Period: $_effectivePeriodText',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Table
                          Table(
                            border:
                                TableBorder.all(color: Colors.black, width: 1.0),
                            columnWidths: const {
                              0: FixedColumnWidth(100),
                              1: FlexColumnWidth(3.0),
                              2: FixedColumnWidth(100),
                              3: FixedColumnWidth(75),
                              4: FixedColumnWidth(75),
                              5: FixedColumnWidth(95),
                            },
                            children: [
                              TableRow(
                                decoration:
                                    BoxDecoration(color: Colors.grey.shade200),
                                children: const [
                                  _PrintCell('Date',
                                      isHeader: true, alignCenter: true),
                                  _PrintCell('Opposite Party', isHeader: true),
                                  _PrintCell('Jins',
                                      isHeader: true, alignCenter: true),
                                  _PrintCell('Bags',
                                      isHeader: true, alignRight: true),
                                  _PrintCell('Rate',
                                      isHeader: true, alignRight: true),
                                  _PrintCell('Dalali',
                                      isHeader: true, alignRight: true),
                                ],
                              ),
                              if (sortedDeals.isEmpty) ...[
                                TableRow(
                                  children: [
                                    const _PrintCell('-', alignCenter: true),
                                    _PrintCell(
                                      'चुनी गई अवधि ($_currentDurationLabel) में कोई सौदा उपलब्ध नहीं है।',
                                      isBold: true,
                                    ),
                                    const _PrintCell('-', alignCenter: true),
                                    const _PrintCell('0', alignRight: true),
                                    const _PrintCell('0', alignRight: true),
                                    const _PrintCell('₹ 0',
                                        alignRight: true, isBold: true),
                                  ],
                                ),
                              ] else ...[
                                for (var monthEntry in monthlyGroups.entries) ...[
                                  for (var d in monthEntry.value)
                                    TableRow(
                                      children: [
                                        _PrintCell(
                                          '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}',
                                          alignCenter: true,
                                        ),
                                        _PrintCell(widget.isBuyer
                                            ? d.seller
                                            : d.buyer),
                                        _PrintCell(d.jins, alignCenter: true),
                                        _PrintCell(d.bags.toString(),
                                            alignRight: true),
                                        _PrintCell(d.rate.toStringAsFixed(0),
                                            alignRight: true),
                                        _PrintCell(
                                          '₹${(widget.isBuyer ? d.totalBuyerDalali : d.totalSellerDalali).toStringAsFixed(0)}',
                                          alignRight: true,
                                          isBold: true,
                                        ),
                                      ],
                                    ),
                                  TableRow(
                                    decoration: BoxDecoration(
                                        color: Colors.grey.shade100),
                                    children: [
                                      _PrintCell('${monthEntry.key} TOTAL',
                                          isBold: true),
                                      const _PrintCell(''),
                                      const _PrintCell(''),
                                      _PrintCell(
                                        monthEntry.value
                                            .fold<int>(
                                                0, (acc, e) => acc + e.bags)
                                            .toString(),
                                        isBold: true,
                                        alignRight: true,
                                      ),
                                      const _PrintCell(''),
                                      _PrintCell(
                                        '₹${monthEntry.value.fold<double>(0.0, (acc, e) => acc + (widget.isBuyer ? e.totalBuyerDalali : e.totalSellerDalali)).toStringAsFixed(0)}',
                                        isBold: true,
                                        alignRight: true,
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ],
                          ),

                    // Grand Total Table
                    Table(
                      border: const TableBorder(
                        left: BorderSide(color: Colors.black, width: 1.0),
                        right: BorderSide(color: Colors.black, width: 1.0),
                        bottom: BorderSide(color: Colors.black, width: 1.2),
                        horizontalInside:
                            BorderSide(color: Colors.black, width: 1.0),
                        verticalInside:
                            BorderSide(color: Colors.black, width: 1.0),
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(4.0),
                        1: FixedColumnWidth(110),
                        2: FixedColumnWidth(140),
                      },
                      children: [
                        TableRow(
                          decoration:
                              BoxDecoration(color: Colors.grey.shade200),
                          children: const [
                            _PrintCell('Date Range Period', isHeader: true),
                            _PrintCell('Total Bags',
                                isHeader: true, alignRight: true),
                            _PrintCell('Grand Total Dalali',
                                isHeader: true, alignRight: true),
                          ],
                        ),
                        TableRow(
                          children: [
                            _PrintCell(dateRangeText, isBold: true),
                            _PrintCell(grandTotalBags.toString(),
                                isBold: true, alignRight: true),
                            _PrintCell(
                                '₹ ${grandTotalDalali.toStringAsFixed(0)}',
                                isBold: true,
                                alignRight: true),
                          ],
                        ),
                      ],
                    ),

                    if (widget.brokerProfile.termsAndConditions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'TERMS & CONDITIONS:\n${widget.brokerProfile.termsAndConditions}',
                        style: const TextStyle(
                            fontSize: 9.5, color: Colors.black87),
                      ),
                    ],
                    const SizedBox(height: 48),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Trader / Party Signature',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('For $firmTitle\n(Authorized Signatory)',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ],
),
);
}
}

class _PrintCell extends StatelessWidget {
  final String text;
  final bool isHeader;
  final bool isBold;
  final bool alignRight;
  final bool alignCenter;

  const _PrintCell(
    this.text, {
    this.isHeader = false,
    this.isBold = false,
    this.alignRight = false,
    this.alignCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    TextAlign align = TextAlign.left;
    if (alignRight) {
      align = TextAlign.right;
    } else if (alignCenter) {
      align = TextAlign.center;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Text(
        text,
        textAlign: align,
        softWrap: true,
        style: TextStyle(
          fontSize: isHeader ? 11 : 10.5,
          fontWeight:
              (isHeader || isBold) ? FontWeight.bold : FontWeight.normal,
          color: Colors.black,
        ),
      ),
    );
  }
}
