import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/hero_form_scaffold.dart';

/// The one thing the app needs before it can show anyone their numbers.
///
/// Reached on a local-only build, and on a signed-in account that arrived
/// without a name — a driver who signed up on this device has already given
/// one, and skips straight past this.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final ValueChanged<String> onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return HeroFormScaffold(
      eyebrow: 'YOUR PROFIT, MADE CLEAR',
      headline: 'Drive smarter.\nKeep more.',
      subcopy:
          'Turn each completed session into a clear view of what you earned, '
          'what it cost, and what you actually kept.',
      aside: const ProfitPreview(),
      card: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set up your dashboard',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Space.gapXs,
            Text(
              'Start with your first name.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            Space.gapXl,
            TextFormField(
              key: const ValueKey('onboarding-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.givenName],
              // The name is greeted on every Today screen. A pasted paragraph
              // would break that line rather than personalise it.
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              decoration: const InputDecoration(
                labelText: 'First name',
                hintText: 'Ahmed',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name to continue'
                  : null,
              onFieldSubmitted: (_) => _continue(),
            ),
            Space.gapMd,
            FilledButton(
              key: const ValueKey('onboarding-continue'),
              onPressed: _continue,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue'),
                  SizedBox(width: Space.sm),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
            Space.gapLg,
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Text(
                    'Private and stored on this device',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _continue() {
    if (_formKey.currentState!.validate()) {
      widget.onComplete(_name.text.trim());
    }
  }
}
