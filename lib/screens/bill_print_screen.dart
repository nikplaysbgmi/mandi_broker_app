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

  const MandiBillPrintScreen({
    super.key,
    required this.party,
    required this.isBuyer,
    required this.deals,
    required this.selectedPeriod,
    required this.brokerProfile,
  });

  @override
  State<MandiBillPrintScreen> createState() => _MandiBillPrintScreenState();
}

class _MandiBillPrintScreenState extends State<MandiBillPrintScreen> {
  bool _isGeneratingPdf = false;

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
                            pw.Text('Period: ${widget.selectedPeriod}',
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
    final sortedDeals = List<MandiSaudaModel>.from(widget.deals)
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
        ? 'NO TRANSACTIONS IN PERIOD'
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
      body: InteractiveViewer(
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
                        border: Border.all(color: Colors.black, width: 1.2),
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
                                        color: Colors.black, width: 1.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (logoBytes != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
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
                                      style: const TextStyle(fontSize: 11)),
                                  Text(
                                    'Mobile: ${widget.brokerProfile.mobile} | PAN: ${widget.brokerProfile.panNo}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  Text(
                                      'APMC Lic: ${widget.brokerProfile.licenseNo}',
                                      style: const TextStyle(fontSize: 11)),
                                  Text('Email: ${widget.brokerProfile.email}',
                                      style: const TextStyle(fontSize: 11)),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${widget.isBuyer ? "BUYER" : "SELLER"} INFORMATION',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Name: ${widget.party.name}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  Text('Mobile: ${widget.party.mobile}',
                                      style: const TextStyle(fontSize: 11)),
                                  Text('Address: ${widget.party.address}',
                                      style: const TextStyle(fontSize: 11)),
                                  Text('Role: ${widget.party.type}',
                                      style: const TextStyle(fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text('Period: ${widget.selectedPeriod}',
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
                      border: TableBorder.all(color: Colors.black, width: 1.0),
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
                        for (var monthEntry in monthlyGroups.entries) ...[
                          for (var d in monthEntry.value)
                            TableRow(
                              children: [
                                _PrintCell(
                                  '${d.date.day.toString().padLeft(2, '0')}/${d.date.month.toString().padLeft(2, '0')}/${d.date.year}',
                                  alignCenter: true,
                                ),
                                _PrintCell(widget.isBuyer ? d.seller : d.buyer),
                                _PrintCell(d.jins, alignCenter: true),
                                _PrintCell(d.bags.toString(), alignRight: true),
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
                            decoration:
                                BoxDecoration(color: Colors.grey.shade100),
                            children: [
                              _PrintCell('${monthEntry.key} TOTAL',
                                  isBold: true),
                              const _PrintCell(''),
                              const _PrintCell(''),
                              _PrintCell(
                                monthEntry.value
                                    .fold<int>(0, (acc, e) => acc + e.bags)
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
