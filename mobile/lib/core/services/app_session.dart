import "../network/api_client.dart";
import "child_safety_service.dart";
import "notification_service.dart";
import "session_service.dart";
import "../../features/sync/services/sync_service.dart";

/// Unified Application Session Manager
/// Coordinates multi-service session invalidation, data clearance, and secure account deletion.
class AppSession {
  static void init() {
    SessionService.onClearUserData = SyncService.clearCache;
  }

  static Future<void> signOut({
    required ApiClient api,
    required SessionService session,
  }) async {
    api.clearCaches();
    SyncService.clearCache();
    await session.clearAllUserData();
    await ChildSafetyService.instance.reloadFromPrefs();
    await NotificationService.instance.reloadFromPrefs();
  }

  static Future<bool> deleteAccount({
    required ApiClient api,
    required SessionService session,
  }) async {
    final ok = await api.deleteAccount();
    if (!ok) return false;
    api.clearCaches();
    SyncService.clearCache();
    await session.clearAllUserData();
    await ChildSafetyService.instance.reloadFromPrefs();
    await NotificationService.instance.reloadFromPrefs();
    return true;
  }
}
