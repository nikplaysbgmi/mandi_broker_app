import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Centralized Manager for the Secondary Firebase project (mandi-market-view).
/// Resolves race conditions, duplicate-app initialization crashes, and WebKit/Safari timeouts.
/// Fully WebKit / iOS Safari safe: avoids calls to `Firebase.apps` which throw on iOS Safari before init.
class MarketWatchService {
  static FirebaseApp? _marketApp;
  static FirebaseFirestore? _marketDb;
  static FirebaseStorage? _marketStorage;
  static Completer<FirebaseFirestore>? _initCompleter;

  static const FirebaseOptions marketOptions = FirebaseOptions(
    apiKey: "AIzaSyAW5OMM6rgbWoHmoPIjQX_Up27QvbYNzbE",
    authDomain: "mandi-market-view.firebaseapp.com",
    projectId: "mandi-market-view",
    storageBucket: "mandi-market-view.firebasestorage.app",
    messagingSenderId: "535917182908",
    appId: "1:535917182908:web:5e90a61f763c30d4eab5b9",
  );

  /// Synchronous getter with safe fallback to primary Firestore.
  static FirebaseFirestore get currentDb {
    if (_marketDb != null) return _marketDb!;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return FirebaseFirestore.instance;
    }
  }

  /// Synchronous getter with safe fallback to primary FirebaseStorage.
  static FirebaseStorage get currentStorage {
    if (_marketStorage != null) return _marketStorage!;
    try {
      return FirebaseStorage.instance;
    } catch (_) {
      return FirebaseStorage.instance;
    }
  }

  /// Thread-safe asynchronous connection to mandi-market-view.
  /// Prevents concurrent Firebase.initializeApp calls and duplicate-app exceptions.
  static Future<FirebaseFirestore> getDatabase() async {
    if (_marketDb != null) return _marketDb!;
    if (_initCompleter != null) return _initCompleter!.future;

    final completer = Completer<FirebaseFirestore>();
    _initCompleter = completer;

    try {
      FirebaseApp? marketApp = _marketApp;
      if (marketApp == null) {
        try {
          marketApp = await Firebase.initializeApp(
            name: 'marketViewApp',
            options: marketOptions,
          );
        } catch (e) {
          // If already initialized, retrieve by name safely
          try {
            marketApp = Firebase.app('marketViewApp');
          } catch (_) {}
        }
      }

      if (marketApp != null) {
        _marketApp = marketApp;
        _marketStorage = FirebaseStorage.instanceFor(
          app: marketApp,
          bucket: 'mandi-market-view.firebasestorage.app',
        );
        _marketDb = FirebaseFirestore.instanceFor(app: marketApp);
        completer.complete(_marketDb!);
        debugPrint('✅ Secondary Firebase (mandi-market-view) successfully connected.');
        return _marketDb!;
      }
    } catch (e) {
      debugPrint('Secondary Firebase initialization failed ($e). Falling back to primary.');
    }

    try {
      final fallback = FirebaseFirestore.instance;
      _marketDb = fallback;
      completer.complete(fallback);
      return fallback;
    } catch (e) {
      debugPrint('Primary Firebase fallback also failed: $e');
      _initCompleter = null; // allow retry
      rethrow;
    }
  }
}
