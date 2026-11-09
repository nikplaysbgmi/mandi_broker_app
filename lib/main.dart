import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/mandi_models.dart';
import 'screens/main_dashboard_screen.dart';
import 'services/mandi_services.dart';
import 'services/market_watch_service.dart';
import 'widgets/offline_banner_wrapper.dart';

// =============================================================
// SAFE GLOBAL FIREBASE INSTANCES (Delegates to MarketWatchService)
// =============================================================
FirebaseFirestore get marketViewDb => MarketWatchService.currentDb;
FirebaseStorage get marketViewStorage => MarketWatchService.currentStorage;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Visible Error Boundary (Prevents silent blank screens)
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint('Flutter Error: ${details.exceptionAsString()}');
      final message = details.exceptionAsString().toLowerCase();
      // Harmless layout overflows should NEVER break the screen or display red error boxes
      if (message.contains('overflowed by') || message.contains('renderflex')) {
        return const SizedBox.shrink();
      }
      return Material(
        color: const Color(0xFF0B1320),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16253B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded,
                          color: Color(0xFF14B8A6), size: 36),
                      SizedBox(height: 10),
                      Text(
                        'Temporary Render Notice',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'A view component is refreshing. Please navigate back or retry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    };

    // 2. Safe Local Storage Init (Catches iOS WebKit localStorage blocks)
    try {
      await StorageService.init();
    } catch (e) {
      debugPrint('StorageService init caught: $e');
    }

    // 3. Initialize Primary Firebase safely without accessing Firebase.apps (WebKit iOS safe)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Primary Firebase initialized.');
    } catch (e) {
      debugPrint('Primary Firebase init caught: $e');
    }

    // 4. Initialize Secondary Firebase in the background (Non-blocking for iOS)
    _initSecondaryFirebase();

    // 5. Mount App immediately so iOS Safari never black-screens
    runApp(const MandiApp());
  }, (error, stack) {
    debugPrint('Uncaught Top-Level Web Error: $error');
  });
}

/// Asynchronously connects to secondary Firebase project (mandi-market-view)
void _initSecondaryFirebase() {
  MarketWatchService.getDatabase().catchError((e) {
    debugPrint('Secondary Firebase background init: $e');
    return MarketWatchService.currentDb;
  });
}

class MandiApp extends StatelessWidget {
  const MandiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        canvasColor: const Color(0xFFF1F5F9),
        cardColor: Colors.white,
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        fontFamilyFallback: const [
          '-apple-system',
          'BlinkMacSystemFont',
          'Segoe UI',
          'Roboto',
          'Noto Sans Devanagari',
          'sans-serif',
        ],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
          primary: const Color(0xFF0F766E),
          surface: Colors.white,
          onSurface: const Color(0xFF0F172A),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return StrictInternetLockWrapper(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MainDashboardScreen(),
    );
  }
}
