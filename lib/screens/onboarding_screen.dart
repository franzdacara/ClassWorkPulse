import 'package:material_ui/material_ui.dart';

import '../models/student_profile.dart';
import 'profile_fields.dart';

/// First-launch screen that asks who the app is tracking.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onSubmit});

  /// Stores the profile; the app moves on once it completes.
  final Future<void> Function(StudentProfile profile) onSubmit;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  StudentProfile? _profile;
  bool _saving = false;

  Future<void> _submit() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSubmit(profile);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.auto_stories,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Welcome to ClassWorkPulse',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Log daily progress, then turn it into a ready-to-send '
                    'update for parents. Everything runs on this device.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  ProfileFields(
                    onChanged: (profile) => setState(() => _profile = profile),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _profile != null && !_saving ? _submit : null,
                    child: const Text('Get started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
