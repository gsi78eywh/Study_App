import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/services/notification_service.dart";
import "../../../core/theme/app_theme.dart";

class NotificationSheet extends StatelessWidget {
  const NotificationSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const NotificationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return ListenableBuilder(
      listenable: NotificationService.instance,
      builder: (context, _) {
        final ns = NotificationService.instance;

        return Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag Handle
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              // Sheet Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF6366F1), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                "Notifications & Reminders",
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.textPrimary,
                                ),
                              ),
                              if (ns.unreadCount > 0) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${ns.unreadCount}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            "Daily study schedule and active recall alerts",
                            style: TextStyle(fontSize: 12, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (ns.unreadCount > 0)
                      TextButton(
                        onPressed: () => ns.markAllAsRead(),
                        child: const Text("Mark All Read", style: TextStyle(fontSize: 12)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  children: [
                    // Daily Study Reminder Configuration Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF1E1B4B), const Color(0xFF311042)]
                              : [const Color(0xFFEEF2FF), const Color(0xFFFAF5FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text("⏰", style: TextStyle(fontSize: 18)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Daily Study Reminder",
                                    style: GoogleFonts.outfit(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Switch.adaptive(
                                value: ns.dailyReminderEnabled,
                                activeTrackColor: const Color(0xFF6366F1),
                                onChanged: (val) => ns.setDailyReminderEnabled(val),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Notifies you when your daily 25-minute smart review sequence is ready.",
                            style: TextStyle(fontSize: 12, color: context.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              InkWell(
                                onTap: ns.dailyReminderEnabled
                                    ? () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay(
                                            hour: ns.reminderHour,
                                            minute: ns.reminderMinute,
                                          ),
                                        );
                                        if (picked != null) {
                                          await ns.setReminderTime(picked.hour, picked.minute);
                                        }
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: context.surfaceColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: ns.dailyReminderEnabled
                                          ? const Color(0xFF6366F1)
                                          : context.cardBorderColor,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                        color: ns.dailyReminderEnabled
                                            ? const Color(0xFF6366F1)
                                            : context.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        ns.reminderTimeFormatted,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: ns.dailyReminderEnabled
                                              ? context.textPrimary
                                              : context.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: () => ns.triggerTestReminder(context),
                                icon: const Icon(Icons.send_rounded, size: 14),
                                label: const Text("Test Alert Now", style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Additional Notification Toggles
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.secondaryBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text("🔥", style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Study Streak Protection",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
                                  ),
                                ],
                              ),
                              Switch.adaptive(
                                value: ns.streakAlertsEnabled,
                                activeTrackColor: const Color(0xFFF97316),
                                onChanged: (val) => ns.setStreakAlertsEnabled(val),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Text("🧠", style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Mistake Bank Retrieval Drills",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
                                  ),
                                ],
                              ),
                              Switch.adaptive(
                                value: ns.mistakeAlertsEnabled,
                                activeTrackColor: const Color(0xFFEC4899),
                                onChanged: (val) => ns.setMistakeAlertsEnabled(val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Recent Notifications Section Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "RECENT NOTIFICATIONS",
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: context.textSecondary,
                          ),
                        ),
                        Text(
                          "${ns.notifications.length} alerts",
                          style: TextStyle(fontSize: 11, color: context.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Notification Cards
                    ...ns.notifications.map((notif) {
                      return InkWell(
                        onTap: () => ns.markAsRead(notif.id),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: notif.isRead
                                ? context.surfaceColor
                                : notif.color.withValues(alpha: isDark ? 0.12 : 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: notif.isRead
                                  ? context.cardBorderColor
                                  : notif.color.withValues(alpha: 0.35),
                              width: notif.isRead ? 1 : 1.4,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: notif.color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(notif.icon, size: 16, color: notif.color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notif.title,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.bold,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (!notif.isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: notif.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notif.message,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.textSecondary,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
