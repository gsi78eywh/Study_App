import "package:flutter/material.dart";

import "../../../core/network/api_client.dart";
import "../../../core/services/session_service.dart";
import "../../../core/theme/app_theme.dart";
import "../../courses/screens/dashboard_screen.dart";

/// A short, local first-run guide. It does not wait on the network, so a new
/// learner can always reach the app even while the API is warming up.
class OnboardingScreen extends StatefulWidget {
  final ApiClient apiClient;
  final SessionService sessionService;

  const OnboardingScreen({
    super.key,
    required this.apiClient,
    required this.sessionService,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _steps = [
    (Icons.dashboard_outlined, "Your learning space", "Create a course to keep notes, flashcards, and practice sets together."),
    (Icons.document_scanner_outlined, "Add your materials", "Use AI Studio to paste notes, upload a file, or scan pages into a study set."),
    (Icons.bolt_outlined, "Practice with focus", "Review flashcards, take a quiz, then use the tutor when you need an explanation."),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.sessionService.completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => DashboardScreen(apiClient: widget.apiClient, sessionService: widget.sessionService)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text("Skip")),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: .10), shape: BoxShape.circle),
                          child: Icon(step.$1, size: 64, color: AppColors.primaryDark),
                        ),
                        const SizedBox(height: 36),
                        Text(step.$2, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                        const SizedBox(height: 14),
                        Text(step.$3, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.textSecondary, height: 1.5)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == _page ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: index == _page ? AppColors.primaryDark : AppColors.lightCardBorder, borderRadius: BorderRadius.circular(8)),
              )),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLast ? _finish : () => _pageController.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                  child: Text(isLast ? "Get started" : "Continue"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
