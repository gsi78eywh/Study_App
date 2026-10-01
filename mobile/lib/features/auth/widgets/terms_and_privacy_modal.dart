import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "../../../core/theme/app_theme.dart";

class TermsAndPrivacyModal {
  static void showTerms(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.gavel_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Terms of Service",
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ctx.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSection(
                  ctx,
                  title: "1. Academic Integrity & Responsible Use",
                  body:
                      "StudyApp is an educational aid engineered to accelerate active recall, spaced repetition, and collegiate mastery. Users agree not to utilize StudyApp for cheating during proctored examinations or unauthorized assessments.",
                ),
                _buildSection(
                  ctx,
                  title: "2. AI Synthesis & Content Generation",
                  body:
                      "AI-assisted practice questions, flashcards, and Socratic tutoring are synthesized from user-uploaded course modules. The AI is designed to augment study routines, but students should verify primary sources for official academic coursework.",
                ),
                _buildSection(
                  ctx,
                  title: "3. DSWD Child Protection & Safe Learning Guardrails",
                  body:
                      "In compliance with Philippine child protection standards (Republic Act 7610 and DSWD MAKABATA 1383 Helpline), StudyApp strictly prohibits harassment, bullying, explicit content, or exploitation. All learning spaces are safe and monitored for learner well-being.",
                ),
                _buildSection(
                  ctx,
                  title: "4. Student Data Ownership",
                  body:
                      "All student notes, uploaded documents, notebook drafts, and generated flashcards remain 100% your intellectual property. We do not sell or monetize student materials.",
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("I Understand & Agree"),
          ),
        ],
      ),
    );
  }

  static void showPrivacy(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Privacy Policy",
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ctx.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSection(
                  ctx,
                  title: "1. No Third-Party Ad Tracking or Data Brokering",
                  body:
                      "StudyApp has zero third-party advertising trackers, cookies, or behavioral trackers. Your study habits, grades, and mistakes are private to your personal learning profile.",
                ),
                _buildSection(
                  ctx,
                  title: "2. Local Storage & Secure Token Auth",
                  body:
                      "Session tokens and user configurations are stored in your device's private app preferences. Authentication uses industry-standard salted BCrypt hashing and signed JWT authentication.",
                ),
                _buildSection(
                  ctx,
                  title: "3. AI Confidentiality & Privacy",
                  body:
                      "Your uploaded notes and exam materials sent for AI synthesis are processed in memory and never used to train global public AI models. You retain complete control over your academic data.",
                ),
                _buildSection(
                  ctx,
                  title: "4. DSWD Child Welfare Compliance",
                  body:
                      "StudyApp maintains a strict zero-tolerance policy against inappropriate content or exploitation. Contact MAKABATA Helpline at 1383 for child protection assistance.",
                ),
                _buildSection(
                  ctx,
                  title: "5. Account Deletion & Right to Be Forgotten",
                  body:
                      "Students can request complete account and data erasure anytime via Settings or by contacting academic support.",
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Got It"),
          ),
        ],
      ),
    );
  }

  static Widget _buildSection(BuildContext ctx, {required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: ctx.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.45,
              color: ctx.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
