/// Centralized registry of all Firestore collections, subcollections,
/// and document keys used across Mandi Trade Portal and Mandi Market View.
/// 
/// Supports the "1 User = 1 Personal Folder" multi-tenant architecture.
class FirestoreCollections {
  FirestoreCollections._();

  // ===========================================================================
  // 1. PRIMARY FIREBASE: mandi-trade-portal (USER PERSONAL FOLDER)
  // ===========================================================================

  /// Root user directory. Each document represents ONE personal user folder:
  /// `users/{userKey}` where userKey is cleanMobile or `${SECTION}_${MOBILE}`.
  /// 
  /// The personal folder encapsulates:
  /// - Profile details (name, mobile, email, address, section)
  /// - Subscription state (status, is_locked, subscription_due, plan, expiry)
  /// - Settings (bank details, dalali commission rules)
  static const String users = 'users';

  /// Legacy / direct mobile account records (`accounts/{mobile}`).
  static const String accounts = 'accounts';

  /// Broker personal folders (`brokers/{brokerKey}`).
  static const String brokers = 'brokers';

  /// Dedicated broker profile documents (`broker_profiles/{cleanMobile}`).
  static const String brokerProfiles = 'broker_profiles';

  /// Global network saudas ledger (`saudas/{saudaId}`).
  /// Cross-party index for instant lookup by buyerMobile and sellerMobile.
  static const String saudas = 'saudas';

  /// Global broadcast and targeted user notifications (`notifications/{notifId}`).
  static const String notifications = 'notifications';

  /// System configurations, service switches, and version controls.
  static const String appConfig = 'app_config';

  /// Modular feature toggles and switches (e.g., doc: 'config').
  static const String serviceSwitches = 'service_switches';

  // ===========================================================================
  // 2. PERSONAL FOLDER SUBCOLLECTIONS (under users/{userId}/ or brokers/{id}/)
  // ===========================================================================

  /// User's personal records / transactions / trade contracts:
  /// `users/{userId}/records/{recordId}`
  static const String userRecords = 'records';

  /// Alias for personal trade transactions:
  /// `users/{userId}/transactions/{txId}`
  static const String userTransactions = 'transactions';

  /// User's personal in-app notifications and alerts:
  /// `users/{userId}/notifications/{notifId}`
  static const String userNotifications = 'notifications';

  /// User's personal parties / contacts / clients:
  /// `users/{userId}/parties/{partyId}`
  static const String userParties = 'parties';

  /// User's personal subscription history and payment receipts:
  /// `users/{userId}/subscriptions/{subId}`
  static const String userSubscriptions = 'subscriptions';

  // Legacy subcollections under brokers/{brokerId}/
  static const String parties = 'parties';
  static const String brokerSaudas = 'saudas';
  static const String brokerNotifications = 'notifications';

  // ===========================================================================
  // 3. PERSONAL FOLDER PATH BUILDERS (1 User = 1 Folder)
  // ===========================================================================

  /// Path to user's personal root folder: `users/{userId}`
  static String userFolderPath(String userId) => '$users/$userId';

  /// Path to user's personal trade records: `users/{userId}/records`
  static String userRecordsPath(String userId) => '$users/$userId/$userRecords';

  /// Path to user's personal transactions: `users/{userId}/transactions`
  static String userTransactionsPath(String userId) => '$users/$userId/$userTransactions';

  /// Path to user's personal notifications: `users/{userId}/notifications`
  static String userNotificationsPath(String userId) => '$users/$userId/$userNotifications';

  /// Path to user's personal parties: `users/{userId}/parties`
  static String userPartiesPath(String userId) => '$users/$userId/$userParties';

  /// Path to user's personal subscription receipts: `users/{userId}/subscriptions`
  static String userSubscriptionsPath(String userId) => '$users/$userId/$userSubscriptions';

  // ===========================================================================
  // 4. SECONDARY FIREBASE: mandi-market-view
  // ===========================================================================

  /// Live commodity prices, analyzer predictions, and promotional configs.
  static const String marketWatch = 'market_watch';

  /// Real-time active user heartbeats: `live_presence/{sessionId}`.
  /// Ephemeral presence documents for the live viewers counter.
  static const String livePresence = 'live_presence';

  // ===========================================================================
  // 5. CANONICAL DOCUMENT IDENTIFIERS
  // ===========================================================================

  // Under `market_watch`:
  static const String docLiveSummary = 'live_summary';
  static const String docMcxSummary = 'mcx_summary';
  static const String docLocalMandiSummary = 'local_mandi_summary';
  static const String docRatePredictions = 'rate_predictions';
  static const String docPromoConfig = 'promo_config';
  static const String docLiveUsers = 'live_users';

  // Under `app_config`:
  static const String docServices = 'services';
  static const String docAppUpdate = 'app_update';

  // Under `service_switches`:
  static const String docServiceConfig = 'config';
}
