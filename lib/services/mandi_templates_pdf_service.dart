import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class MandiTemplatesPdfService {
  MandiTemplatesPdfService._();

  static Future<pw.Font> _loadFont({bool bold = false}) async {
    try {
      return bold
          ? await PdfGoogleFonts.notoSansDevanagariBold()
          : await PdfGoogleFonts.notoSansDevanagariRegular();
    } catch (_) {
      return bold ? pw.Font.helveticaBold() : pw.Font.helvetica();
    }
  }

  // =============================================================
  // 1. BLANK SAUDA SLIP TEMPLATE (सौदा पर्चा प्रारूप)
  // =============================================================
  static Future<Uint8List> generateSaudaSlipTemplate(
      PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await _loadFont(bold: false);
    final fontBold = await _loadFont(bold: true);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                pw.Center(
                  child: pw.Text(
                    'सौदा पर्चा / अनुबंध पत्र (SAUDA SLIP)',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'MANDI BROKER TRADE CONFIRMATION NOTE',
                    style: pw.TextStyle(font: font, fontSize: 8),
                  ),
                ),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 4),

                // Slip Meta
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('पर्चा सं. (Slip No): ___________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('दिनांक (Date): ____/____/202___',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('समय (Time): _________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('दलाल (Broker): _____________________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('मोबाइल (Mob): __________________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Party Details Box
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700, width: 0.8),
                    color: PdfColors.grey100,
                  ),
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              'क्रेता / व्यापारी (Buyer): _______________________',
                              style: pw.TextStyle(font: fontBold, fontSize: 10),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              'फोन / GST: _______________________',
                              style: pw.TextStyle(font: font, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              'विक्रेता / किसान (Seller): ______________________',
                              style: pw.TextStyle(font: fontBold, fontSize: 10),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              'फोन / मंडी: _______________________',
                              style: pw.TextStyle(font: font, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                // Trade Particulars Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        _buildCell('जिंस (Commodity)', font: fontBold, isHeader: true),
                        _buildCell('कट्टे (Bags)', font: fontBold, isHeader: true),
                        _buildCell('अनुमानित वजन (Qtl)', font: fontBold, isHeader: true),
                        _buildCell('भाव (Rate ₹)', font: fontBold, isHeader: true),
                        _buildCell('दलाली (Dalali)', font: fontBold, isHeader: true),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        _buildCell(' \n \n ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        _buildCell(' \n \n ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                        _buildCell(' ', font: font),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Terms
                pw.Text(
                  'नियम व शर्तें (Terms & Conditions):',
                  style: pw.TextStyle(font: fontBold, fontSize: 9),
                ),
                pw.Text('1. माल की डिलीवरी शर्त: __________________________________________________',
                    style: pw.TextStyle(font: font, fontSize: 8.5)),
                pw.Text('2. भुगतान अवधि (Payment Due): _______ दिन के भीतर।',
                    style: pw.TextStyle(font: font, fontSize: 8.5)),
                pw.Text('3. तुलाई व काट मंडी के नियमानुसार मान्य होगी।',
                    style: pw.TextStyle(font: font, fontSize: 8.5)),

                pw.Spacer(),

                // Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      children: [
                        pw.Container(width: 80, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 3),
                        pw.Text('हस्ताक्षर क्रेता (Buyer)',
                            style: pw.TextStyle(font: font, fontSize: 8.5)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(width: 80, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 3),
                        pw.Text('हस्ताक्षर विक्रेता (Seller)',
                            style: pw.TextStyle(font: font, fontSize: 8.5)),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(width: 80, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 3),
                        pw.Text('हस्ताक्षर दलाल (Broker)',
                            style: pw.TextStyle(font: font, fontSize: 8.5)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // =============================================================
  // 2. BLANK TULAI SHEET TEMPLATE (तुलाई शीट / तोल पत्रक)
  // =============================================================
  static Future<Uint8List> generateTulaiSheetTemplate(
      PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await _loadFont(bold: false);
    final fontBold = await _loadFont(bold: true);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    'मंडी तुलाई पर्ची / कांटा तोल पत्रक (TULAI SHEET)',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'BAG-WISE WEIGHMENT SCALE RECORD SHEET',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 6),

                // Meta Info
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('दिनांक (Date): ____/____/202___',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('कांटा / पर्ची सं.: _____________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('वाहन / गाड़ी सं.: _____________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('जिंस (Commodity): ________________',
                        style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    pw.Text('किसान / विक्रेता: _________________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('व्यापारी / क्रेता: _________________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 12),

                // 50-Bag Weighing Grid (10 rows x 5 columns)
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: List.generate(5, (col) {
                        final start = col * 10 + 1;
                        final end = start + 9;
                        return _buildCell('कट्टा ($start - $end)',
                            font: fontBold, isHeader: true, fontSize: 9);
                      }),
                    ),
                    ...List.generate(10, (row) {
                      return pw.TableRow(
                        children: List.generate(5, (col) {
                          final idx = col * 10 + row + 1;
                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 7),
                            child: pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('$idx.',
                                    style: pw.TextStyle(
                                        font: font,
                                        fontSize: 8.5,
                                        color: PdfColors.grey700)),
                                pw.Text('        Kg',
                                    style: pw.TextStyle(
                                        font: font, fontSize: 8.5)),
                              ],
                            ),
                          );
                        }),
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 14),

                // Calculation Summary Table
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                    color: PdfColors.grey100,
                  ),
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('कुल कट्टे (Total Bags): ________',
                              style: pw.TextStyle(font: fontBold, fontSize: 10.5)),
                          pw.Text('सकल वजन (Gross Wt): __________ Kg',
                              style: pw.TextStyle(font: fontBold, fontSize: 10.5)),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('बारदाना काट (Tare/Bag): _____ ग्राम',
                              style: pw.TextStyle(font: font, fontSize: 10)),
                          pw.Text('कुल काट (Total Tare): __________ Kg',
                              style: pw.TextStyle(font: font, fontSize: 10)),
                        ],
                      ),
                      pw.Divider(thickness: 0.8, color: PdfColors.grey500),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('शुद्ध वजन (Net Weight): ______________ क्विंटल (Qtl)',
                              style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 12,
                                  color: PdfColors.blue900)),
                          pw.Text('तोलिया (Weigher): ____________',
                              style: pw.TextStyle(font: font, fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),

                pw.Spacer(),

                // Signatures
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('कांटा ऑपरेटर हस्ताक्षर: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('क्रेता प्रतिनिधि: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('दलाल हस्ताक्षर: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // =============================================================
  // 3. BLANK DALALI LEDGER TEMPLATE (दलाली खाता बही)
  // =============================================================
  static Future<Uint8List> generateDalaliLedgerTemplate(
      PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await _loadFont(bold: false);
    final fontBold = await _loadFont(bold: true);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    'दलाली खाता बही / स्टेटमेंट (DALALI LEDGER STATEMENT)',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'BROKER COMMISSION & TRANSACTION LEDGER',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 6),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ब्रोकर / फर्म: _________________________',
                        style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    pw.Text('पार्टी का नाम: _________________________',
                        style: pw.TextStyle(font: fontBold, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('मोबाइल: __________________________',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                    pw.Text('अवधि (Period): ____/____/____ से ____/____/____',
                        style: pw.TextStyle(font: font, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Ledger Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        _buildCell('दिनांक (Date)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('सौदा नं (Sauda)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('जिंस (Crop)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('कट्टे (Bags)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('भाव (Rate ₹)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('कुल रकम (Turnover)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('दलाली दर', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('दलाली (₹)', font: fontBold, isHeader: true, fontSize: 8.5),
                        _buildCell('जमा / बाकी', font: fontBold, isHeader: true, fontSize: 8.5),
                      ],
                    ),
                    ...List.generate(12, (index) {
                      return pw.TableRow(
                        children: [
                          _buildCell(' \n ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                          _buildCell(' ', font: font, fontSize: 8),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 10),

                // Total Summary
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Text('कुल कट्टे: ________',
                          style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.Text('कुल टर्नओवर: ₹____________',
                          style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.Text('कुल दलाली: ₹____________',
                          style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 10.5,
                              color: PdfColors.green900)),
                    ],
                  ),
                ),

                pw.Spacer(),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('जांचकर्ता हस्ताक्षर: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('पार्टी हस्ताक्षर: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('दलाल सील व हस्ताक्षर: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // =============================================================
  // 4. BLANK MANDI INVOICE TEMPLATE (कच्चा / पक्का मंडी बिल)
  // =============================================================
  static Future<Uint8List> generateMandiInvoiceTemplate(
      PdfPageFormat format) async {
    final pdf = pw.Document();
    final font = await _loadFont(bold: false);
    final fontBold = await _loadFont(bold: true);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
            ),
            padding: const pw.EdgeInsets.all(14),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Center(
                  child: pw.Text(
                    'मंडी बिल / इनवॉइस (MANDI TRADE INVOICE)',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Center(
                  child: pw.Text(
                    'CASH MEMO & GRAIN TRADING BILL',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
                pw.Divider(thickness: 1.2, color: PdfColors.black),
                pw.SizedBox(height: 6),

                // Firm & Bill details
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('फर्म / विक्रेता: _________________________',
                            style: pw.TextStyle(font: fontBold, fontSize: 10.5)),
                        pw.SizedBox(height: 3),
                        pw.Text('मंडी यार्ड / पता: _______________________',
                            style: pw.TextStyle(font: font, fontSize: 9.5)),
                        pw.SizedBox(height: 3),
                        pw.Text('GSTIN / PAN: __________________________',
                            style: pw.TextStyle(font: font, fontSize: 9.5)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('बिल सं. (Invoice No): ___________',
                            style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        pw.SizedBox(height: 3),
                        pw.Text('दिनांक (Date): ____/____/202___',
                            style: pw.TextStyle(font: font, fontSize: 9.5)),
                        pw.SizedBox(height: 3),
                        pw.Text('दलाल (Broker): __________________',
                            style: pw.TextStyle(font: font, fontSize: 9.5)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Buyer Box
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey600, width: 0.6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('क्रेता का नाम (M/s): _______________________________________',
                          style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.Text('मोबाइल: _________________',
                          style: pw.TextStyle(font: font, fontSize: 10)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                // Items Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        _buildCell('क्र. (No)', font: fontBold, isHeader: true, fontSize: 9),
                        _buildCell('जिंस का विवरण (Item Name)', font: fontBold, isHeader: true, fontSize: 9),
                        _buildCell('कट्टे (Bags)', font: fontBold, isHeader: true, fontSize: 9),
                        _buildCell('वजन (Weight Qtl)', font: fontBold, isHeader: true, fontSize: 9),
                        _buildCell('दर (Rate ₹)', font: fontBold, isHeader: true, fontSize: 9),
                        _buildCell('सकल राशि (Gross ₹)', font: fontBold, isHeader: true, fontSize: 9),
                      ],
                    ),
                    ...List.generate(6, (i) {
                      return pw.TableRow(
                        children: [
                          _buildCell('${i + 1}', font: font, fontSize: 8.5),
                          _buildCell(' \n ', font: font, fontSize: 8.5),
                          _buildCell(' ', font: font, fontSize: 8.5),
                          _buildCell(' ', font: font, fontSize: 8.5),
                          _buildCell(' ', font: font, fontSize: 8.5),
                          _buildCell(' ', font: font, fontSize: 8.5),
                        ],
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Expenses / Deduction breakdown
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('रकम शब्दों में (Amount in words):',
                              style: pw.TextStyle(font: fontBold, fontSize: 9)),
                          pw.SizedBox(height: 2),
                          pw.Text('________________________________________________________',
                              style: pw.TextStyle(font: font, fontSize: 8.5)),
                          pw.SizedBox(height: 6),
                          pw.Text('बैंक विवरण (Bank Details):',
                              style: pw.TextStyle(font: fontBold, fontSize: 9)),
                          pw.Text('खाता सं.: ___________________  IFSC: ___________________',
                              style: pw.TextStyle(font: font, fontSize: 8.5)),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
                        children: [
                          _buildTotalRow('सकल राशि (Gross):', '₹ ____________', font),
                          _buildTotalRow('दलाली (Brokerage):', '₹ ____________', font),
                          _buildTotalRow('तुलाई / हम्माली:', '₹ ____________', font),
                          _buildTotalRow('बारदाना / अन्य खर्च:', '₹ ____________', font),
                          _buildTotalRow('शुद्ध राशि (NET TOTAL):', '₹ ____________', fontBold, isHighlight: true),
                        ],
                      ),
                    ),
                  ],
                ),

                pw.Spacer(),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('नोट: माल की जांच कर प्राप्त किया।',
                        style: pw.TextStyle(font: font, fontSize: 8.5)),
                    pw.Text('हस्ताक्षर क्रेता / प्राप्तकर्ता: _______________',
                        style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text('प्राधिकृत हस्ताक्षर (Authorised): _______________',
                        style: pw.TextStyle(font: fontBold, fontSize: 9)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildCell(
    String text, {
    required pw.Font font,
    bool isHeader = false,
    double fontSize = 9,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: isHeader ? pw.Alignment.center : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          font: font,
          fontSize: fontSize,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.TableRow _buildTotalRow(
    String label,
    String value,
    pw.Font font, {
    bool isHighlight = false,
  }) {
    return pw.TableRow(
      decoration: isHighlight
          ? const pw.BoxDecoration(color: PdfColors.grey300)
          : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(font: font, fontSize: 8.5)),
        ),
      ],
    );
  }
}

