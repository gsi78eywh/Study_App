import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/theme/app_theme.dart";
import "../../../core/services/child_safety_service.dart";

/// Dedicated DSWD Child Protection, CWC MAKABATA 1383 Helpline,
/// and Digital Wellness Hub for Students, Parents, and Teachers.
class DswdSafetyModal extends StatelessWidget {
  const DswdSafetyModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DswdSafetyModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final childSafety = ChildSafetyService.instance;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: context.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Modal Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "DSWD Child Safeguarding & Safety Hub",
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        "Council for the Welfare of Children (CWC) • RA 7610 • RA 11650",
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // MAKABATA 1383 Featured Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF047857), Color(0xFF0D9488)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF047857).withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "24/7 DSWD / CWC HELPLINE",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "MAKABATA Helpline 1383",
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Toll-free national hotline providing immediate psychological first-aid, child rights protection, and reporting of online or offline child harms.",
                        style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF047857),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.phone, size: 14),
                            label: const Text("Dial 1383", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: "1383"));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("📞 Helpline 1383 copied to dialer clipboard.")),
                              );
                            },
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 14),
                            label: const Text("Copy Number", style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Clipboard.setData(const ClipboardData(text: "1383"));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Copied 1383 to clipboard.")),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Other Official Helplines
                Text(
                  "Support Helplines for Children & Youth",
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                _buildContactTile(
                  context: context,
                  icon: Icons.shield_rounded,
                  title: "Bantay Bata 163",
                  subtitle: "Nationwide child welfare and rescue service.",
                  contact: "163",
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(height: 8),
                _buildContactTile(
                  context: context,
                  icon: Icons.school_rounded,
                  title: "DepEd Child Protection Unit",
                  subtitle: "School safety, anti-bullying & student learner rights.",
                  contact: "(02) 8637-2306",
                  color: const Color(0xFF8B5CF6),
                ),
                const SizedBox(height: 8),
                _buildContactTile(
                  context: context,
                  icon: Icons.emergency_rounded,
                  title: "Philippine National Emergency",
                  subtitle: "24/7 Police, Medical, & Fire Emergency.",
                  contact: "911",
                  color: const Color(0xFFEF4444),
                ),
                const SizedBox(height: 20),

                // DSWD PES Digital Parenting Guide
                Text(
                  "DSWD Digital Parenting & Wellness Standards",
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                _buildPolicyCard(
                  context: context,
                  icon: Icons.remove_red_eye_rounded,
                  title: "20-20-20 Eye Rest & Screen Breaks",
                  desc: "Every 20 minutes, encourage young learners to rest their eyes for 20 seconds by looking at something 20 feet away and hydrating.",
                  badge: "PES Guideline",
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(height: 8),
                _buildPolicyCard(
                  context: context,
                  icon: Icons.child_care_rounded,
                  title: "Junior Learner Mode (Grades 1–6)",
                  desc: "Simplified vocabulary, friendly icon badges, enlarged touch areas (48dp+), and audio read-aloud support designed for young motor and reading skills.",
                  badge: "Inclusive RA 11650",
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 8),
                _buildPolicyCard(
                  context: context,
                  icon: Icons.sentiment_very_satisfied_rounded,
                  title: "Growth Mindset & Non-Punitive Feedback",
                  desc: "NCCT/DSWD child content standards encourage learning through positive motivation without harsh failure shaming or punitive pressure.",
                  badge: "Child-Friendly",
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 8),
                _buildPolicyCard(
                  context: context,
                  icon: Icons.lock_outline_rounded,
                  title: "Zero Ads & Child Data Privacy",
                  desc: "No third-party trackers, zero data harvesting of minors, and local-first study sets complying with RA 10173 Data Privacy Act.",
                  badge: "Privacy Protected",
                  color: const Color(0xFFEC4899),
                ),
                const SizedBox(height: 24),

                // Quick Toggle Junior Mode inside Modal
                ListenableBuilder(
                  listenable: childSafety,
                  builder: (ctx, _) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.cardBorderColor),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: childSafety.isJuniorMode
                                  ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                  : Colors.grey.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.child_care_rounded,
                              color: childSafety.isJuniorMode ? const Color(0xFF10B981) : context.textSecondary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Junior Learner Mode",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: context.textPrimary,
                                  ),
                                ),
                                Text(
                                  childSafety.isJuniorMode
                                      ? "Active (Grades 1-6 simplified interface)"
                                      : "Standard Mode (Grades 7+ / Advanced)",
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: childSafety.isJuniorMode,
                            activeColor: const Color(0xFF10B981),
                            onChanged: (val) => childSafety.setJuniorMode(val),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String contact,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimary)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: context.textSecondary)),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: color.withValues(alpha: 0.1),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: contact));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Copied $contact to clipboard.")),
              );
            },
            child: Text(contact, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String desc,
    required String badge,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cardBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: context.textPrimary)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(badge, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(desc, style: TextStyle(fontSize: 11.5, color: context.textSecondary, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
