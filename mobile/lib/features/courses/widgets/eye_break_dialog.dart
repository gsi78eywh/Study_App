import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/child_safety_service.dart';

/// DSWD / CWC Compliant Digital Wellness Eye-Break Dialog.
/// Implements the 20-20-20 rule (Look 20 feet away for 20 seconds every 20-30 mins)
/// recommended for pediatric ocular health and digital safety.
class EyeBreakDialog extends StatefulWidget {
  const EyeBreakDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const EyeBreakDialog(),
    );
  }

  @override
  State<EyeBreakDialog> createState() => _EyeBreakDialogState();
}

class _EyeBreakDialogState extends State<EyeBreakDialog> {
  int _countdownSeconds = 20;
  Timer? _timer;
  bool _timerActive = false;
  bool _timerCompleted = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTwentySecondRest() {
    setState(() {
      _countdownSeconds = 20;
      _timerActive = true;
      _timerCompleted = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdownSeconds <= 1) {
        t.cancel();
        setState(() {
          _countdownSeconds = 0;
          _timerActive = false;
          _timerCompleted = true;
        });
      } else {
        setState(() {
          _countdownSeconds--;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isJunior = ChildSafetyService.instance.isJuniorMode;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon & Shield
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.green.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🌿', style: TextStyle(fontSize: 34)),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                isJunior
                    ? '🌟 Super Learner Eye Rest!'
                    : '🌿 Healthy Eye Break (DSWD PES Rule)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.teal.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Text(
                'Your brain and eyes worked hard! Rest your vision using the 20-20-20 pediatric health rule.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // 20-20-20 Checklist Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.teal.shade200.withOpacity(0.8)),
                ),
                child: Column(
                  children: [
                    _buildChecklistRow('👀', 'Look away at a green tree or far wall (~20 ft)'),
                    const SizedBox(height: 10),
                    _buildChecklistRow('💧', 'Blink gently and take a cool drink of water'),
                    const SizedBox(height: 10),
                    _buildChecklistRow('🙆', 'Roll your shoulders & stretch your posture'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Interactive 20s rest timer widget
              if (_timerActive)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.green, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Resting Eyes: $_countdownSeconds seconds left',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                )
              else if (_timerCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.teal, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Great job! Eyes are energized & ready! ✨',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _startTwentySecondRest,
                    icon: const Icon(Icons.play_circle_outline, color: Colors.teal),
                    label: const Text(
                      'Start 20-Second Eye Relaxation Timer',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.teal, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ChildSafetyService.instance.resetEyeBreakTimer();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Remind in 10m'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ChildSafetyService.instance.resetEyeBreakTimer();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'I\'m Refreshed! 🚀',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistRow(String icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E4038),
            ),
          ),
        ),
      ],
    );
  }
}
