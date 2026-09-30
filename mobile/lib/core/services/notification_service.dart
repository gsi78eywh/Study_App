import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class AppNotificationItem {
  final String id;
  final String title;
  final String message;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String category;
  bool isRead;

  AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.icon,
    required this.color,
    required this.category,
    this.isRead = false,
  });
}

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const _keyDailyReminder = "pref_daily_reminder_enabled";
  static const _keyReminderHour = "pref_reminder_hour";
  static const _keyReminderMinute = "pref_reminder_minute";
  static const _keyStreakAlerts = "pref_streak_alerts_enabled";
  static const _keyMistakeAlerts = "pref_mistake_alerts_enabled";

  bool _dailyReminderEnabled = true;
  int _reminderHour = 19; // 7:00 PM default
  int _reminderMinute = 0;
  bool _streakAlertsEnabled = true;
  bool _mistakeAlertsEnabled = true;

  final List<AppNotificationItem> _notifications = [];

  bool get dailyReminderEnabled => _dailyReminderEnabled;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
  bool get streakAlertsEnabled => _streakAlertsEnabled;
  bool get mistakeAlertsEnabled => _mistakeAlertsEnabled;

  List<AppNotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  String get reminderTimeFormatted {
    final period = _reminderHour >= 12 ? "PM" : "AM";
    final hour12 = _reminderHour % 12 == 0 ? 12 : _reminderHour % 12;
    final minuteStr = _reminderMinute.toString().padLeft(2, "0");
    return "$hour12:$minuteStr $period";
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyReminderEnabled = prefs.getBool(_keyDailyReminder) ?? true;
    _reminderHour = prefs.getInt(_keyReminderHour) ?? 19;
    _reminderMinute = prefs.getInt(_keyReminderMinute) ?? 0;
    _streakAlertsEnabled = prefs.getBool(_keyStreakAlerts) ?? true;
    _mistakeAlertsEnabled = prefs.getBool(_keyMistakeAlerts) ?? true;

    if (_notifications.isEmpty) {
      _seedDefaultNotifications();
    }
    notifyListeners();
  }

  void _seedDefaultNotifications() {
    _notifications.addAll([
      AppNotificationItem(
        id: "notif-daily-1",
        title: "⏰ Daily Study Session Ready",
        message: "Your personalized 25-minute study plan is generated. Review your top priority course today!",
        timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
        icon: Icons.bolt_rounded,
        color: const Color(0xFF6366F1),
        category: "study_reminder",
        isRead: true,
      ),
      AppNotificationItem(
        id: "notif-streak-1",
        title: "🔥 Keep Your Study Streak Alive",
        message: "Complete 1 quick drill or 3 flashcards today to extend your streak counter!",
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFFF97316),
        category: "streak_alert",
        isRead: true,
      ),
      AppNotificationItem(
        id: "notif-mistake-1",
        title: "🧠 Mistake Bank Spaced Retrieval",
        message: "Review flagged mistake concepts to consolidate retention before upcoming exams.",
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        icon: Icons.psychology_alt_rounded,
        color: const Color(0xFFEC4899),
        category: "mistake_review",
        isRead: true,
      ),
      AppNotificationItem(
        id: "notif-wellness-1",
        title: "🌿 Eye Wellness & 20-20-20 Rest",
        message: "Every 20 minutes of digital reading, rest your eyes on an object 20 feet away for 20 seconds.",
        timestamp: DateTime.now().subtract(const Duration(hours: 8)),
        icon: Icons.remove_red_eye_outlined,
        color: const Color(0xFF10B981),
        category: "wellness",
        isRead: true,
      ),
    ]);
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    _dailyReminderEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailyReminder, enabled);
  }

  Future<void> setReminderTime(int hour, int minute) async {
    _reminderHour = hour;
    _reminderMinute = minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderHour, hour);
    await prefs.setInt(_keyReminderMinute, minute);
  }

  Future<void> setStreakAlertsEnabled(bool enabled) async {
    _streakAlertsEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStreakAlerts, enabled);
  }

  Future<void> setMistakeAlertsEnabled(bool enabled) async {
    _mistakeAlertsEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMistakeAlerts, enabled);
  }

  void addNotification({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    required String category,
  }) {
    final item = AppNotificationItem(
      id: "notif-${DateTime.now().millisecondsSinceEpoch}",
      title: title,
      message: message,
      timestamp: DateTime.now(),
      icon: icon,
      color: color,
      category: category,
      isRead: false,
    );
    _notifications.insert(0, item);
    notifyListeners();
  }

  void markAllAsRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void markAsRead(String id) {
    final notif = _notifications.firstWhere((n) => n.id == id, orElse: () => _notifications.first);
    notif.isRead = true;
    notifyListeners();
  }

  void triggerTestReminder(BuildContext context) {
    addNotification(
      title: "🔔 Test Daily Study Reminder",
      message: "Time for your 25-minute smart study session! Keep your learning streak alive.",
      icon: Icons.notifications_active_rounded,
      color: const Color(0xFF6366F1),
      category: "study_reminder",
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "⏰ Study Reminder: Time for your daily active recall review!",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF6366F1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
