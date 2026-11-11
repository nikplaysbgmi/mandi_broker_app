import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// =============================================================
// SAFE MAP/LIST EXTRACTION HELPERS FOR iOS SAFARI WEBKIT
// =============================================================
Map<String, dynamic> _safeExtractDocMap(dynamic snapshotData) {
  if (snapshotData == null) return <String, dynamic>{};
  try {
    dynamic rawMap;
    if (snapshotData is DocumentSnapshot) {
      rawMap = snapshotData.data();
    } else if (snapshotData is Map) {
      rawMap = snapshotData;
    }
    if (rawMap is Map) {
      final Map<String, dynamic> result = <String, dynamic>{};
      rawMap.forEach((key, value) {
        if (key != null) {
          result[key.toString()] = value;
        }
      });
      return result;
    }
  } catch (_) {}
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _safeExtractList(dynamic rawList) {
  if (rawList is! Iterable) return <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> cleanList = <Map<String, dynamic>>[];
  for (final dynamic element in rawList) {
    if (element is Map) {
      final Map<String, dynamic> itemMap = <String, dynamic>{};
      element.forEach((k, v) {
        if (k != null) itemMap[k.toString()] = v;
      });
      cleanList.add(itemMap);
    }
  }
  return cleanList;
}

// =============================================================
// TAB: ANALYZER & COMMODITY RATE PREDICTOR
// =============================================================
class AnalyzerWatchList extends StatefulWidget {
  final FirebaseFirestore db;
  const AnalyzerWatchList({super.key, required this.db});

  @override
  State<AnalyzerWatchList> createState() => _AnalyzerWatchListState();
}

class _AnalyzerWatchListState extends State<AnalyzerWatchList> {
  int _selectedCommodityIdx = 0;

  // Custom calculator state
  final TextEditingController _calcPriceCtrl = TextEditingController();
  int _calcHorizon = 0; // 0: Daily, 1: Weekly, 2: Monthly
  Map<String, dynamic>? _calculatedResult;

  static const List<Map<String, dynamic>> _defaultPredictions = [
    {
      'name': 'जीरा (Jeera)',
      'code': 'JEERA',
      'icon': '🌾',
      'patterns': ['JEERA', 'JEERAUNJHA', 'जीरा'],
      'bhav': 25800.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 25200.0,
      'targetMax': 27400.0,
      'support1': 25300.0,
      'support2': 24800.0,
      'res1': 26600.0,
      'res2': 27500.0,
      'confidence': 84,
      'arrival': 'मंडियों में आवक सामान्य से कम',
      'demand': 'निर्यात व घरेलू मसाला मांग मजबूत',
      'advice':
          'गिरावट पर खरीदारी की रणनीति। ₹25,000 के स्टॉपलॉस के साथ ₹26,600 - ₹27,400 के स्तर संभव।',
    },
    {
      'name': 'ईसबगोल (Isabgol)',
      'code': 'ISABGOL',
      'icon': '💊',
      'patterns': ['ISABGOL', 'PSYLLIUM', 'ईसबगोल', 'इसबगोल'],
      'bhav': 13200.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 12800.0,
      'targetMax': 14200.0,
      'support1': 12900.0,
      'support2': 12500.0,
      'res1': 13800.0,
      'res2': 14500.0,
      'confidence': 80,
      'arrival': 'सीमित दैनिक आवक, किसान होल्डिंग पर',
      'demand': 'फार्मा व एक्सपोर्ट कंपनियों से अच्छी लिवाली',
      'advice':
          'मजबूत फंडामेंटल्स। ₹12,900 के सपोर्ट के साथ धीरे-धीरे एक्युमुलेट करें।',
    },
    {
      'name': 'ग्वार गम (Guar Gum)',
      'code': 'GUARGUM',
      'icon': '📦',
      'patterns': ['GUARGUM', 'GUARGUM5', 'ग्वार गम', 'ग्वारगम'],
      'bhav': 10650.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 10400.0,
      'targetMax': 11400.0,
      'support1': 10350.0,
      'support2': 10100.0,
      'res1': 11000.0,
      'res2': 11600.0,
      'confidence': 82,
      'arrival': 'मंडियों में नई आवक धीमी',
      'demand': 'क्रूड ऑयल स्थिरता व क्रशिंग मांग से सपोर्ट',
      'advice':
          '₹10,350 के ऊपर बने रहने पर तेज उछाल संभव। टारगेट ₹11,000 - ₹11,400।',
    },
    {
      'name': 'ग्वार सीड (Guar Seed)',
      'code': 'GUARSEED',
      'icon': '🌰',
      'patterns': ['GUARSEED', 'GUARSEED10', 'ग्वार सीड', 'ग्वारसीड'],
      'bhav': 5350.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 5200.0,
      'targetMax': 5750.0,
      'support1': 5250.0,
      'support2': 5100.0,
      'res1': 5550.0,
      'res2': 5800.0,
      'confidence': 79,
      'arrival': 'औसत आवक, मिलर्स की नियमित खरीद',
      'demand': 'गम मिलों की सक्रिय मांग',
      'advice':
          'निचले स्तरों पर सपोर्ट मजबूत। ₹5,250 के पास खरीदारी का अच्छा अवसर।',
    },
    {
      'name': 'धनिया (Dhaniya)',
      'code': 'DHANIYA',
      'icon': '🌿',
      'patterns': ['DHANIYA', 'CORIANDER', 'धनिया'],
      'bhav': 7450.0,
      'trend': 'सीमित दायरा (Sideways)',
      'targetMin': 7200.0,
      'targetMax': 7900.0,
      'support1': 7250.0,
      'support2': 7000.0,
      'res1': 7700.0,
      'res2': 8100.0,
      'confidence': 72,
      'arrival': 'हाजिर में संतुलित सप्लाई',
      'demand': 'मसाला निर्माताओं की सीमित खरीद',
      'advice':
          'दायरे में कारोबार। ₹7,250 के पास खरीद और ₹7,750 के आसपास मुनाफा बांधें।',
    },
    {
      'name': 'हल्दी (Turmeric)',
      'code': 'TURMERIC',
      'icon': '🟨',
      'patterns': ['TURMERIC', 'TMCFGRNZM', 'हल्दी'],
      'bhav': 13900.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 13500.0,
      'targetMax': 15200.0,
      'support1': 13400.0,
      'support2': 12900.0,
      'res1': 14500.0,
      'res2': 15500.0,
      'confidence': 86,
      'arrival': 'सप्लाई टाइट, पुराना स्टॉक कम',
      'demand': 'निर्यात व घरेलू त्योहारी मांग मजबूत',
      'advice': 'मध्यम अवधि में बड़ा उछाल संभव। लंबी पोजीशन बनाए रखने की सलाह।',
    },
    {
      'name': 'सरसों / रायड़ा (Mustard)',
      'code': 'MUSTARD',
      'icon': '🟡',
      'patterns': ['MUSTARD', 'SARSON', 'सरसों', 'रायड़ा', 'रायडा'],
      'bhav': 5850.0,
      'trend': 'सीमित दायरा (Sideways)',
      'targetMin': 5700.0,
      'targetMax': 6150.0,
      'support1': 5720.0,
      'support2': 5600.0,
      'res1': 6000.0,
      'res2': 6200.0,
      'confidence': 75,
      'arrival': 'दैनिक आवक में स्थिरता',
      'demand': 'त्योहारी तेल मांग, क्रशिंग मार्जिन सीमित',
      'advice': '₹5,720 के स्टॉपलॉस के साथ ₹6,000 के टारगेट हेतु ट्रेड करें।',
    },
    {
      'name': 'चना (Chana)',
      'code': 'CHANA',
      'icon': '🥣',
      'patterns': ['CHANA', 'GRAM', 'चना'],
      'bhav': 6900.0,
      'trend': 'सीमित दायरा (Sideways)',
      'targetMin': 6750.0,
      'targetMax': 7250.0,
      'support1': 6750.0,
      'support2': 6600.0,
      'res1': 7100.0,
      'res2': 7350.0,
      'confidence': 74,
      'arrival': 'हाजिर में संतुलित सप्लाई',
      'demand': 'दाल मिलों की जरूरत अनुसार खरीद',
      'advice':
          'दायरे में कारोबार। ₹6,750 से ₹7,150 के बीच रेंज-ट्रेडिंग की सलाह।',
    },
    {
      'name': 'सोयाबीन (Soybean)',
      'code': 'SOYABEAN',
      'icon': '🫘',
      'patterns': ['SOYBEAN', 'SOYABEAN', 'SOYA', 'सोयाबीन'],
      'bhav': 4450.0,
      'trend': 'मंदी / दबाव (Bearish)',
      'targetMin': 4250.0,
      'targetMax': 4650.0,
      'support1': 4300.0,
      'support2': 4150.0,
      'res1': 4600.0,
      'res2': 4750.0,
      'confidence': 70,
      'arrival': 'नई फसल की आवक का दबाव',
      'demand': 'वैश्विक सोया तेल व डीओसी में सुस्ती',
      'advice': 'उछाल पर मुनाफा बांधें, नई बड़ी खरीद में जल्दबाजी न करें।',
    },
    {
      'name': 'मूंग (Moong)',
      'code': 'MOONG',
      'icon': '🟢',
      'patterns': ['MOONG', 'MUNG', 'मूंग'],
      'bhav': 7800.0,
      'trend': 'तेज़ी (Bullish)',
      'targetMin': 7500.0,
      'targetMax': 8400.0,
      'support1': 7600.0,
      'support2': 7400.0,
      'res1': 8100.0,
      'res2': 8500.0,
      'confidence': 78,
      'arrival': 'बढ़िया क्वालिटी की आवक सीमित',
      'demand': 'सरकारी खरीद व दाल मिल मांग',
      'advice': 'बढ़िया क्वालिटी माल में तेजी बनी रहेगी। होल्ड रखने की सलाह।',
    },
    {
      'name': 'कपास (Cotton)',
      'code': 'COTTON',
      'icon': '☁️',
      'patterns': ['COTTON', 'COKUDL', 'KAPAS', 'कपास'],
      'bhav': 7150.0,
      'trend': 'सीमित दायरा (Sideways)',
      'targetMin': 6900.0,
      'targetMax': 7500.0,
      'support1': 6950.0,
      'support2': 6800.0,
      'res1': 7350.0,
      'res2': 7600.0,
      'confidence': 71,
      'arrival': 'नई कपास की नियमित आवक',
      'demand': 'स्पिनिंग मिलों की सीमित लिवाली',
      'advice': '₹6,950 के नीचे जाने पर दबाव, ₹7,350 के ऊपर फ्रेश तेजी।',
    },
  ];

  @override
  void dispose() {
    _calcPriceCtrl.dispose();
    super.dispose();
  }

  void _runCalculator(double currentBhav) {
    final double inputPrice =
        double.tryParse(_calcPriceCtrl.text.trim()) ?? currentBhav;
    if (inputPrice <= 0) return;

    double targetPct = 0.04; // Daily
    double stopLossPct = 0.02;

    if (_calcHorizon == 1) {
      targetPct = 0.07; // Weekly
      stopLossPct = 0.035;
    } else if (_calcHorizon == 2) {
      targetPct = 0.12; // Monthly
      stopLossPct = 0.06;
    }

    final double targetPrice = inputPrice * (1 + targetPct);
    final double stopLoss = inputPrice * (1 - stopLossPct);
    final double profitPerQtl = targetPrice - inputPrice;
    final double profitPerBag = profitPerQtl * 0.5; // standard 50kg bag

    setState(() {
      _calculatedResult = {
        'inputPrice': inputPrice,
        'targetPrice': targetPrice,
        'stopLoss': stopLoss,
        'profitPerQtl': profitPerQtl,
        'profitPerBag': profitPerBag,
        'targetPct': (targetPct * 100).toStringAsFixed(1),
        'stopLossPct': (stopLossPct * 100).toStringAsFixed(1),
      };
    });
  }

  static DateTime? _parseContractExpiry(String expiryStr) {
    if (expiryStr.isEmpty) return null;
    final clean = expiryStr.trim().toUpperCase();
    const monthMap = {
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12
    };
    final regExp = RegExp(
      r'(?:(\d{1,2})[\s\-_]+)?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[a-z]*(?:[\s\-_]+(\d{2,4}))?',
    );
    final match = regExp.firstMatch(clean);
    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '') ?? 20;
      final month = monthMap[match.group(2) ?? ''] ?? 1;
      int year = int.tryParse(match.group(3) ?? '') ?? DateTime.now().year;
      if (year < 100) year += 2000;
      return DateTime(year, month, day, 23, 59, 59);
    }
    return null;
  }

  static bool _isContractExpired(String expiryStr) {
    final exp = _parseContractExpiry(expiryStr);
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  /// Real-Time Live Market Bhav & Dynamic Prediction Matcher
  List<Map<String, dynamic>> _mergeLivePredictions({
    required dynamic liveSnapData,
    required dynamic predSnapData,
    required dynamic localSnapData,
  }) {
    final Map<String, dynamic> liveDoc = _safeExtractDocMap(liveSnapData);
    final List<Map<String, dynamic>> liveRates = _safeExtractList(
      liveDoc['commodities'] ?? liveDoc['rates'],
    );

    final Map<String, dynamic> predDoc = _safeExtractDocMap(predSnapData);
    final List<Map<String, dynamic>> adminRates = _safeExtractList(
      predDoc['rates'],
    );

    final Map<String, dynamic> localDoc = _safeExtractDocMap(localSnapData);
    final List<Map<String, dynamic>> localRates = _safeExtractList(
      localDoc['rates'],
    );

    final List<Map<String, dynamic>> mergedList = [];

    for (final def in _defaultPredictions) {
      final List<String> patterns = (def['patterns'] as List<dynamic>?)
              ?.map((p) => p.toString().toUpperCase())
              .toList() ??
          [def['code'].toString().toUpperCase()];

      // 1. Try matching with active (non-expired) NCDEX Live Feed
      Map<String, dynamic>? liveMatch;
      for (final rate in liveRates) {
        final String exp =
            (rate['expiry'] ?? rate['contract'] ?? '').toString();
        // Automatically skip contracts that stopped on the 20th
        if (_isContractExpired(exp)) continue;

        final String sym =
            (rate['symbol'] ?? rate['name'] ?? rate['commodity'] ?? '')
                .toString()
                .toUpperCase();
        for (final p in patterns) {
          if (sym.contains(p)) {
            liveMatch = rate;
            break;
          }
        }
        if (liveMatch != null) break;
      }

      // 2. Try matching with Local Mandi Feed
      Map<String, dynamic>? localMatch;
      if (liveMatch == null) {
        for (final rate in localRates) {
          final String name =
              (rate['name'] ?? rate['crop'] ?? '').toString().toUpperCase();
          for (final p in patterns) {
            if (name.contains(p)) {
              localMatch = rate;
              break;
            }
          }
          if (localMatch != null) break;
        }
      }

      // 3. Admin Custom Override
      final adminMatch = adminRates.firstWhere(
        (e) =>
            (e['name'] ?? '').toString().trim().toLowerCase() ==
            def['name'].toString().trim().toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      double currentBhav = (def['bhav'] as num).toDouble();
      double liveChange = 0.0;
      bool isLiveSync = false;
      String liveSource = 'पूर्वानुमान (Forecast)';
      String liveExpiry = '';

      if (liveMatch != null) {
        final String rawLtp =
            (liveMatch['lastPrice'] ?? liveMatch['ltp'] ?? '0')
                .toString()
                .replaceAll(',', '')
                .trim();
        final double ltp = double.tryParse(rawLtp) ?? 0.0;

        final String rawChange = (liveMatch['change'] ?? '0')
            .toString()
            .replaceAll(',', '')
            .replaceAll('+', '')
            .trim();
        final double change = double.tryParse(rawChange) ?? 0.0;

        if (ltp > 0) {
          currentBhav = ltp;
          liveChange = change;
          isLiveSync = true;
          liveSource = 'NCDEX LIVE';
          liveExpiry = (liveMatch['expiry'] ?? liveMatch['contract'] ?? 'NEAR')
              .toString()
              .trim();
        }
      } else if (localMatch != null) {
        final double minRate = double.tryParse(
                (localMatch['min'] ?? '0').toString().replaceAll(',', '')) ??
            0.0;
        final double maxRate = double.tryParse(
                (localMatch['max'] ?? '0').toString().replaceAll(',', '')) ??
            0.0;
        final double avg = maxRate > 0
            ? (minRate > 0 ? (minRate + maxRate) / 2 : maxRate)
            : 0.0;
        if (avg > 0) {
          currentBhav = avg;
          isLiveSync = true;
          liveSource = 'स्थानीय मंडी (Mandi Live)';
        }
      } else if (adminMatch.isNotEmpty && adminMatch['bhav'] != null) {
        final double ab = double.tryParse(adminMatch['bhav'].toString()) ?? 0.0;
        if (ab > 0) currentBhav = ab;
      }

      // Dynamic real-time calculation of targets and sentiment relative to live LTP
      final double changePct =
          currentBhav > 0 ? (liveChange / currentBhav) * 100 : 0.0;

      String trend = def['trend'].toString();
      Color trendColor = const Color(0xFF10B981);
      double targetMin = (def['targetMin'] as num).toDouble();
      double targetMax = (def['targetMax'] as num).toDouble();
      double s1 = (def['support1'] as num).toDouble();
      double s2 = (def['support2'] as num).toDouble();
      double r1 = (def['res1'] as num).toDouble();
      double r2 = (def['res2'] as num).toDouble();
      int confidence = (def['confidence'] as num).toInt();

      if (isLiveSync && liveChange != 0.0) {
        if (liveChange > 0 || changePct >= 0.2) {
          trend = 'तेज़ी (Bullish) 🚀';
          trendColor = const Color(0xFF10B981);
          final double boost = (changePct * 0.01).clamp(0.0, 0.035);
          targetMin = currentBhav * 0.985;
          targetMax = currentBhav * (1.045 + boost);
          s1 = currentBhav * 0.982;
          s2 = currentBhav * 0.965;
          r1 = currentBhav * 1.030;
          r2 = currentBhav * 1.058;
          confidence = (80 + changePct * 3.5).clamp(70.0, 95.0).toInt();
        } else if (liveChange < 0 || changePct <= -0.2) {
          trend = 'मंदी / दबाव (Bearish) 🔻';
          trendColor = const Color(0xFFEF4444);
          final double drop = (changePct.abs() * 0.01).clamp(0.0, 0.035);
          targetMin = currentBhav * (0.950 - drop);
          targetMax = currentBhav * 1.015;
          s1 = currentBhav * 0.965;
          s2 = currentBhav * 0.945;
          r1 = currentBhav * 1.015;
          r2 = currentBhav * 1.035;
          confidence = (75 + changePct.abs() * 3.0).clamp(65.0, 90.0).toInt();
        } else {
          trend = 'सीमित दायरा (Sideways) ⚖️';
          trendColor = const Color(0xFFF59E0B);
          targetMin = currentBhav * 0.975;
          targetMax = currentBhav * 1.025;
          s1 = currentBhav * 0.980;
          s2 = currentBhav * 0.960;
          r1 = currentBhav * 1.020;
          r2 = currentBhav * 1.040;
          confidence = 74;
        }
      } else if (adminMatch.isNotEmpty) {
        if (adminMatch['trend'] != null) trend = adminMatch['trend'].toString();
        if (adminMatch['targetMin'] != null) {
          targetMin =
              double.tryParse(adminMatch['targetMin'].toString()) ?? targetMin;
        }
        if (adminMatch['targetMax'] != null) {
          targetMax =
              double.tryParse(adminMatch['targetMax'].toString()) ?? targetMax;
        }
        if (adminMatch['support1'] != null) {
          s1 = double.tryParse(adminMatch['support1'].toString()) ?? s1;
        }
        if (adminMatch['res1'] != null) {
          r1 = double.tryParse(adminMatch['res1'].toString()) ?? r1;
        }
        if (adminMatch['confidence'] != null) {
          confidence =
              int.tryParse(adminMatch['confidence'].toString()) ?? confidence;
        }
        final bool isB = trend.contains('तेज़ी') || trend.contains('Bullish');
        final bool isM = trend.contains('मंदी') || trend.contains('Bearish');
        trendColor = isB
            ? const Color(0xFF10B981)
            : (isM ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
      }

      final String arrival =
          (adminMatch['arrival'] ?? def['arrival']).toString();
      final String demand = (adminMatch['demand'] ?? def['demand']).toString();

      String advice = (adminMatch['advice'] ?? '').toString().trim();
      if (advice.isEmpty) {
        if (isLiveSync) {
          if (liveChange > 0 || changePct >= 0.2) {
            advice =
                'गिरावट पर खरीदारी की रणनीति। ₹${s2.round()} के स्टॉपलॉस के साथ ₹${r1.round()} - ₹${r2.round()} के स्तर संभव।';
          } else if (liveChange < 0 || changePct <= -0.2) {
            advice =
                'उछाल पर सतर्कता / मुनाफा वसूली की रणनीति। ₹${r2.round()} के स्टॉपलॉस के साथ ₹${s2.round()} - ₹${s1.round()} के स्तर संभव।';
          } else {
            advice =
                'दायरे में व्यापार की रणनीति। ₹${s1.round()} के सपोर्ट के पास खरीदारी और ₹${r1.round()} पर मुनाफा वसूली की सलाह।';
          }
        } else {
          advice = def['advice'].toString();
        }
      }

      mergedList.add({
        'name': def['name'],
        'code': def['code'],
        'icon': def['icon'],
        'bhav': currentBhav,
        'liveChange': liveChange,
        'changePct': changePct,
        'isLiveSync': isLiveSync,
        'liveSource': liveSource,
        'liveExpiry': liveExpiry,
        'trend': trend,
        'trendColor': trendColor,
        'targetMin': targetMin,
        'targetMax': targetMax,
        'support1': s1,
        'support2': s2,
        'res1': r1,
        'res2': r2,
        'confidence': confidence,
        'arrival': arrival,
        'demand': demand,
        'advice': advice,
      });
    }

    return mergedList;
  }

  Widget _buildHorizonChip(String label, int value) {
    final bool isSelected = _calcHorizon == value;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _calcHorizon = value;
            if (_calculatedResult != null) {
              final double p = _calculatedResult!['inputPrice'];
              _runCalculator(p);
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                isSelected ? const Color(0xFF0F766E) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF14B8A6) : Colors.white12,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream:
          widget.db.collection('market_watch').doc('live_summary').snapshots(),
          builder: (context, liveSnap) {
            return StreamBuilder<dynamic>(
              stream: widget.db
                  .collection('market_watch')
                  .doc('rate_predictions')
                  .snapshots(),
              builder: (context, predSnap) {
                return StreamBuilder<dynamic>(
                  stream: widget.db
                      .collection('market_watch')
                      .doc('local_mandi_summary')
                      .snapshots(),
                  builder: (context, localSnap) {
                    final List<Map<String, dynamic>> predictions =
                        _mergeLivePredictions(
                      liveSnapData: liveSnap.data,
                      predSnapData: predSnap.data,
                      localSnapData: localSnap.data,
                    );

                    if (_selectedCommodityIdx >= predictions.length) {
                      _selectedCommodityIdx = 0;
                    }

                    final Map<String, dynamic> current =
                        predictions[_selectedCommodityIdx];

                    final double currentBhav = (current['bhav'] as num).toDouble();
                    final double liveChange =
                        (current['liveChange'] as num).toDouble();
                    final double changePct =
                        (current['changePct'] as num).toDouble();
                    final bool isLiveSync = current['isLiveSync'] == true;
                    final String liveSource =
                        (current['liveSource'] ?? '').toString();
                    final String liveExpiry =
                        (current['liveExpiry'] ?? '').toString();

                    final String trend =
                        (current['trend'] ?? 'तेज़ी (Bullish)').toString();
                    final Color trendColor = current['trendColor'] as Color;

                    final double targetMin =
                        (current['targetMin'] as num).toDouble();
                    final double targetMax =
                        (current['targetMax'] as num).toDouble();
                    final double s1 = (current['support1'] as num).toDouble();
                    final double s2 = (current['support2'] as num).toDouble();
                    final double r1 = (current['res1'] as num).toDouble();
                    final double r2 = (current['res2'] as num).toDouble();
                    final int confidence = (current['confidence'] as num).toInt();

                    final bool isPositive = liveChange >= 0;
                    final Color changeColor = liveChange == 0
                        ? Colors.white70
                        : (isPositive
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444));

                    return ListView(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      children: [
                        // Top Real-Time Live Sync Status Banner with Lock Button
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isLiveSync
                                  ? const Color(0xFF00E676).withValues(alpha: 0.4)
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isLiveSync
                                      ? const Color(0xFF00E676)
                                          .withValues(alpha: 0.15)
                                      : const Color(0xFF38BDF8)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isLiveSync
                                      ? Icons.sensors_rounded
                                      : Icons.psychology_rounded,
                                  color: isLiveSync
                                      ? const Color(0xFF00E676)
                                      : const Color(0xFF38BDF8),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          isLiveSync
                                              ? '🔴 LIVE AUTO-SYNC (रियल-टाइम अपडेट)'
                                              : 'AI मंडी कमोडिटी प्रेडिक्टर (Predictor)',
                                          style: TextStyle(
                                            color: isLiveSync
                                                ? const Color(0xFF00E676)
                                                : Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isLiveSync
                                          ? 'लाइव भाव के साथ अनुमानित लक्ष्य व स्टॉपलॉस स्वतः अपडेट हो रहे हैं'
                                          : 'तकनीकी चार्ट, आवक व फंडामेंटल रुझान अनुसार संभावित आगामी भाव',
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 12),

                    // Horizontal Commodity Filter Chips
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: predictions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = predictions[index];
                          final bool isSelected =
                              index == _selectedCommodityIdx;
                          final String name = (item['name'] ?? '').toString();
                          final String icon = (item['icon'] ?? '🌾').toString();
                          final bool hasLive = item['isLiveSync'] == true;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedCommodityIdx = index;
                                final double b =
                                    (item['bhav'] as num).toDouble();
                                _calcPriceCtrl.text = b.toStringAsFixed(0);
                                _calculatedResult = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFF5722)
                                    : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFFF5722)
                                      : (hasLive
                                          ? const Color(0xFF00E676)
                                              .withValues(alpha: 0.3)
                                          : Colors.white24),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(icon,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 6),
                                  Text(
                                    name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (hasLive) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF00E676),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 1. Featured Commodity Prediction Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161F2E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: trendColor.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    (current['icon'] ?? '🌾').toString(),
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    (current['name'] ?? '').toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: trendColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: trendColor),
                                ),
                                child: Text(
                                  trend,
                                  style: TextStyle(
                                    color: trendColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Current Live Bhav & Target Range
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1320),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isLiveSync
                                          ? const Color(0xFF00E676)
                                              .withValues(alpha: 0.3)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            isLiveSync
                                                ? '🔴 लाइव हाजिर भाव'
                                                : 'मौजूदा भाव',
                                            style: TextStyle(
                                              color: isLiveSync
                                                  ? const Color(0xFF00E676)
                                                  : Colors.white54,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isLiveSync &&
                                              liveExpiry.isNotEmpty)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF262626),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                liveExpiry,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₹${currentBhav.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Text(
                                            'प्रति क्विंटल ',
                                            style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 10),
                                          ),
                                          if (isLiveSync && liveChange != 0.0)
                                            Text(
                                              isPositive
                                                  ? '(+₹${liveChange.toStringAsFixed(0)} / +${changePct.toStringAsFixed(1)}%)'
                                                  : '(-₹${liveChange.abs().toStringAsFixed(0)} / ${changePct.toStringAsFixed(1)}%)',
                                              style: TextStyle(
                                                color: changeColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1320),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            trendColor.withValues(alpha: 0.4)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '🎯 अनुमानित आगामी दायरा',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₹${targetMin.toStringAsFixed(0)} - ₹${targetMax.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: trendColor,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'सटीकता भरोसा: $confidence%',
                                        style: const TextStyle(
                                            color: Color(0xFF38BDF8),
                                            fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Sentiment Meter
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'मार्केट सेंटीमेंट (धारणा स्कोर)',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 11.5),
                                  ),
                                  Text(
                                    '$confidence% तेज़ी का रुख',
                                    style: TextStyle(
                                      color: trendColor,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: confidence / 100.0,
                                  backgroundColor: Colors.white12,
                                  color: trendColor,
                                  minHeight: 7,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Support & Resistance Box
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E1624),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'सपोर्ट लेवल्स (Support / तल):',
                                      style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11.5),
                                    ),
                                    Text(
                                      'S1: ₹${s1.toStringAsFixed(0)}  |  S2: ₹${s2.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                    color: Colors.white12, height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'रुकावट लेवल्स (Resistance):',
                                      style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 11.5),
                                    ),
                                    Text(
                                      'R1: ₹${r1.toStringAsFixed(0)}  |  R2: ₹${r2.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Color(0xFFF59E0B),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Mandi Fundamentals
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'स्रोत: $liveSource  •  आवक: ${current['arrival'] ?? 'सामान्य'}  •  मांग: ${current['demand'] ?? 'संतुलित'}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Strategy Advice Box
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF0F766E)
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lightbulb_rounded,
                                    color: Color(0xFF14B8A6), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    (current['advice'] ?? '').toString(),
                                    style: const TextStyle(
                                      color: Color(0xFF99F6E4),
                                      fontSize: 11.5,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Custom Commodity Calculator
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151D2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calculate_rounded,
                                  color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                '${current['name']} लाभ व स्टॉपलॉस कैलकुलेटर',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _calcPriceCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText:
                                        'भाव: ₹${currentBhav.toStringAsFixed(0)}',
                                    hintStyle:
                                        const TextStyle(color: Colors.white38),
                                    filled: true,
                                    fillColor: const Color(0xFF0B1320),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Colors.white24),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Colors.white24),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => _runCalculator(currentBhav),
                                child: const Text(
                                  'गणना करें',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Time Horizon Selector
                          Row(
                            children: [
                              _buildHorizonChip('दैनिक (Daily)', 0),
                              const SizedBox(width: 6),
                              _buildHorizonChip('साप्ताहिक (Weekly)', 1),
                              const SizedBox(width: 6),
                              _buildHorizonChip('मासिक (Monthly)', 2),
                            ],
                          ),

                          if (_calculatedResult != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B1320),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF0F766E)
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        '🎯 संभावित बिक्री लक्ष्य:',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                      Text(
                                        '₹${(_calculatedResult!['targetPrice'] as num).toDouble().toStringAsFixed(0)} (+${_calculatedResult!['targetPct']}%)',
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        '🛡️ सुरक्षित स्टॉपलॉस / तल:',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                      Text(
                                        '₹${(_calculatedResult!['stopLoss'] as num).toDouble().toStringAsFixed(0)} (-${_calculatedResult!['stopLossPct']}%)',
                                        style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                      color: Colors.white12, height: 14),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        '💰 प्रति कट्टा संभावित लाभ (50kg):',
                                        style: TextStyle(
                                            color: Color(0xFF38BDF8),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '+₹${(_calculatedResult!['profitPerBag'] as num).toDouble().toStringAsFixed(0)} / कट्टा',
                                        style: const TextStyle(
                                          color: Color(0xFF00E676),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. All Commodities Quick Overview List
                    const Row(
                      children: [
                        Icon(Icons.list_alt_rounded,
                            color: Color(0xFF38BDF8), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'सभी प्रमुख जिंसों का त्वरित पूर्वानुमान (Overview)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: predictions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = predictions[index];
                        final String name = (item['name'] ?? '').toString();
                        final String icon = (item['icon'] ?? '🌾').toString();
                        final double bhav = (item['bhav'] as num).toDouble();
                        final String tr = (item['trend'] ?? '').toString();
                        final double tMax =
                            (item['targetMax'] as num).toDouble();
                        final bool isBull = tr.contains('तेज़ी');
                        final bool isBear = tr.contains('मंदी');
                        final bool hasLive = item['isLiveSync'] == true;

                        final Color c = isBull
                            ? const Color(0xFF10B981)
                            : (isBear
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFF59E0B));

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedCommodityIdx = index;
                              _calcPriceCtrl.text = bhav.toStringAsFixed(0);
                              _calculatedResult = null;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131D2D),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: index == _selectedCommodityIdx
                                    ? const Color(0xFFFF5722)
                                    : (hasLive
                                        ? const Color(0xFF00E676)
                                            .withValues(alpha: 0.25)
                                        : Colors.white12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(icon,
                                        style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 8),
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (hasLive) ...[
                                      const SizedBox(width: 5),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF00E676)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          'LIVE',
                                          style: TextStyle(
                                            color: Color(0xFF00E676),
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹${bhav.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'लक्ष्य: ₹${tMax.toStringAsFixed(0)}',
                                          style: TextStyle(
                                              color: c,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: c.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isBull
                                            ? 'तेज़ी'
                                            : (isBear ? 'मंदी' : 'दायरा'),
                                        style: TextStyle(
                                          color: c,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// =============================================================
// ADMIN DIALOG: RATE PREDICTIONS (ANALYZER)
// =============================================================
class EditRatePredictionsDialog extends StatefulWidget {
  final FirebaseFirestore db;
  const EditRatePredictionsDialog({super.key, required this.db});

  @override
  State<EditRatePredictionsDialog> createState() =>
      _EditRatePredictionsDialogState();
}

class _EditRatePredictionsDialogState extends State<EditRatePredictionsDialog> {
  final List<String> commodityNames = [
    'जीरा (Jeera)',
    'ईसबगोल (Isabgol)',
    'ग्वार गम (Guar Gum)',
    'ग्वार सीड (Guar Seed)',
    'धनिया (Dhaniya)',
    'हल्दी (Turmeric)',
    'सरसों / रायड़ा (Mustard)',
    'चना (Chana)',
    'सोयाबीन (Soybean)',
    'मूंग (Moong)',
    'कपास (Cotton)',
  ];

  late String selectedName;
  final TextEditingController bhavCtrl = TextEditingController();
  final TextEditingController targetMinCtrl = TextEditingController();
  final TextEditingController targetMaxCtrl = TextEditingController();
  final TextEditingController support1Ctrl = TextEditingController();
  final TextEditingController res1Ctrl = TextEditingController();
  final TextEditingController confidenceCtrl = TextEditingController();
  final TextEditingController adviceCtrl = TextEditingController();
  String selectedTrend = 'तेज़ी (Bullish)';

  bool isSaving = false;
  Map<String, Map<String, dynamic>> rateMap = {};

  @override
  void initState() {
    super.initState();
    selectedName = commodityNames[0];
    _loadExistingPredictions();
  }

  @override
  void dispose() {
    bhavCtrl.dispose();
    targetMinCtrl.dispose();
    targetMaxCtrl.dispose();
    support1Ctrl.dispose();
    res1Ctrl.dispose();
    confidenceCtrl.dispose();
    adviceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingPredictions() async {
    try {
      final doc = await widget.db
          .collection('market_watch')
          .doc('rate_predictions')
          .get();
      if (!mounted) return;
      final map = _safeExtractDocMap(doc);
      final rates = _safeExtractList(map['rates']);
      for (var r in rates) {
        final name = (r['name'] ?? '').toString();
        if (name.isNotEmpty) {
          rateMap[name] = r;
        }
      }
      _populateFieldsFor(selectedName);
    } catch (_) {
      _populateFieldsFor(selectedName);
    }
  }

  void _populateFieldsFor(String name) {
    final existing = rateMap[name] ?? {};
    bhavCtrl.text = (existing['bhav'] ?? '25000').toString();
    selectedTrend = (existing['trend'] ?? 'तेज़ी (Bullish)').toString();
    targetMinCtrl.text = (existing['targetMin'] ?? '24500').toString();
    targetMaxCtrl.text = (existing['targetMax'] ?? '27000').toString();
    support1Ctrl.text = (existing['support1'] ?? '24800').toString();
    res1Ctrl.text = (existing['res1'] ?? '26500').toString();
    confidenceCtrl.text = (existing['confidence'] ?? '82').toString();
    adviceCtrl.text =
        (existing['advice'] ?? 'गिरावट पर खरीदारी की सलाह।').toString();
    setState(() {});
  }

  void _cacheCurrentFields() {
    rateMap[selectedName] = {
      'name': selectedName,
      'bhav': double.tryParse(bhavCtrl.text.trim()) ?? 0,
      'trend': selectedTrend,
      'targetMin': double.tryParse(targetMinCtrl.text.trim()) ?? 0,
      'targetMax': double.tryParse(targetMaxCtrl.text.trim()) ?? 0,
      'support1': double.tryParse(support1Ctrl.text.trim()) ?? 0,
      'res1': double.tryParse(res1Ctrl.text.trim()) ?? 0,
      'confidence': int.tryParse(confidenceCtrl.text.trim()) ?? 80,
      'advice': adviceCtrl.text.trim(),
    };
  }

  Future<void> _saveAll() async {
    _cacheCurrentFields();
    setState(() => isSaving = true);

    final List<Map<String, dynamic>> rateList = [];
    for (var name in commodityNames) {
      if (rateMap.containsKey(name)) {
        rateList.add(rateMap[name]!);
      } else {
        rateList.add({
          'name': name,
          'bhav': 20000,
          'trend': 'तेज़ी (Bullish)',
          'targetMin': 19000,
          'targetMax': 22000,
          'confidence': 80,
          'advice': 'बाजार में स्थिरता की उम्मीद।',
        });
      }
    }

    try {
      await widget.db.collection('market_watch').doc('rate_predictions').set({
        'rates': rateList,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => isSaving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('पूर्वानुमान सफलतापूर्वक अपडेट हो गए!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('एरर: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Row(
        children: [
          Icon(Icons.auto_graph_rounded, color: Color(0xFF38BDF8), size: 22),
          SizedBox(width: 8),
          Text(
            'भाव प्रिडिक्टर अपडेट करें',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Commodity Selector Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B2B2B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedName,
                    dropdownColor: const Color(0xFF2B2B2B),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    isExpanded: true,
                    items: commodityNames.map((name) {
                      return DropdownMenuItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (newVal) {
                      if (newVal != null) {
                        _cacheCurrentFields();
                        setState(() {
                          selectedName = newVal;
                          _populateFieldsFor(newVal);
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Current Bhav & Trend
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bhavCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'मौजूदा भाव (₹)',
                        labelStyle:
                            TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2B2B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedTrend,
                          dropdownColor: const Color(0xFF2B2B2B),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'तेज़ी (Bullish)',
                              child: Text('तेज़ी (Bullish)',
                                  style: TextStyle(color: Color(0xFF10B981))),
                            ),
                            DropdownMenuItem(
                              value: 'मंदी (Bearish)',
                              child: Text('मंदी (Bearish)',
                                  style: TextStyle(color: Color(0xFFEF4444))),
                            ),
                            DropdownMenuItem(
                              value: 'सीमित दायरा (Sideways)',
                              child: Text('सीमित दायरा',
                                  style: TextStyle(color: Color(0xFFF59E0B))),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => selectedTrend = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Target Min & Max
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: targetMinCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'टारगेट निचला (Min ₹)',
                        labelStyle:
                            TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: targetMaxCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'टारगेट ऊपरी (Max ₹)',
                        labelStyle:
                            TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Support 1 & Res 1
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: support1Ctrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'सपोर्ट लेवल S1 (₹)',
                        labelStyle:
                            TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: res1Ctrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'रुकावट लेवल R1 (₹)',
                        labelStyle:
                            TextStyle(color: Colors.white60, fontSize: 12),
                        filled: true,
                        fillColor: Color(0xFF2B2B2B),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Confidence Score
              TextField(
                controller: confidenceCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'भरोसा / सेंटीमेंट स्कोर (0-100%)',
                  labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF2B2B2B),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              // Advice Note
              TextField(
                controller: adviceCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'मंडी विश्लेषक सलाह (Advisory Note)',
                  labelStyle: TextStyle(color: Colors.white60, fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF2B2B2B),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('रद्द करें', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: isSaving ? null : _saveAll,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
          ),
          child: isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('सेव करें (Save)',
                  style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

