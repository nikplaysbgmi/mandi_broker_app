import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/mandi_models.dart';
import 'screens/main_dashboard_screen.dart';
import 'services/mandi_services.dart';

// =============================================================
// GLOBAL SECONDARY FIREBASE INSTANCES (mandi-market-view)
// =============================================================
late FirebaseFirestore marketViewDb;
late FirebaseStorage marketViewStorage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StorageService.init();
  } catch (e) {
    debugPrint('StorageService initialization failed: $e');
  }

  // 1. Initialize Primary Firebase ([DEFAULT]) for Accounts, Bills, Auth
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    debugPrint('✅ Primary Firebase project initialized.');
  } catch (e) {
    debugPrint('Primary Firebase initialization error: $e');
  }

  // 2. Initialize Secondary Firebase (mandi-market-view)
  try {
    const FirebaseOptions marketOptions = FirebaseOptions(
      apiKey: "AIzaSyAW5OMM6rgbWoHmoPIjQX_Up27QvbYNzbE",
      authDomain: "mandi-market-view.firebaseapp.com",
      projectId: "mandi-market-view",
      storageBucket: "mandi-market-view.firebasestorage.app",
      messagingSenderId: "535917182908",
      appId: "1:535917182908:web:5e90a61f763c30d4eab5b9",
    );

    final FirebaseApp marketApp =
        Firebase.apps.any((app) => app.name == 'marketViewApp')
            ? Firebase.app('marketViewApp')
            : await Firebase.initializeApp(
                name: 'marketViewApp',
                options: marketOptions,
              );

    // Bind Firestore & Cloud Storage to the secondary Firebase project
    marketViewDb = FirebaseFirestore.instanceFor(app: marketApp);
    marketViewStorage = FirebaseStorage.instanceFor(
      app: marketApp,
      bucket: 'mandi-market-view.firebasestorage.app',
    );
    debugPrint(
        '✅ Secondary Firestore & Storage connected to mandi-market-view.');
  } catch (e) {
    debugPrint('Secondary Firebase initialization error: $e');
    try {
      final existingApp = Firebase.app('marketViewApp');
      marketViewDb = FirebaseFirestore.instanceFor(app: existingApp);
      marketViewStorage = FirebaseStorage.instanceFor(
        app: existingApp,
        bucket: 'mandi-market-view.firebasestorage.app',
      );
    } catch (_) {
      marketViewDb = FirebaseFirestore.instance;
      marketViewStorage = FirebaseStorage.instance;
    }
  }

  runApp(const MandiApp());
}

class MandiApp extends StatelessWidget {
  const MandiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'NotoSansDevanagari',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          primary: const Color(0xFF0F766E),
        ),
        useMaterial3: true,
      ),
      home: const MainDashboardScreen(),
    );
  }
}
