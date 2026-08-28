import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key, this.accountEmail});

  final String? accountEmail;

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: 'Privacy & security',
    body: PageFrame(
      maxWidth: 680,
      child: ListView(
        children: [
          _PrivacyCard(
            icon: Icons.shield_outlined,
            title: 'Your data stays yours',
            body:
                'Driver Wealth stores a working copy on this device so session tracking and edits keep working offline.',
          ),
          const SizedBox(height: Space.md),
          if (accountEmail != null) ...[
            _PrivacyCard(
              icon: Icons.cloud_done_outlined,
            title: 'Account sync',
              body:
                  'Your sessions, goals and preferences sync to the account signed in as $accountEmail.',
            ),
            const SizedBox(height: Space.md),
          ],
          _PrivacyCard(
            icon: Icons.location_on_outlined,
            title: 'Location access',
            body:
                'Location is used to add up distance while a driving session is active. Manage the permission in your device settings.',
            action: OutlinedButton.icon(
              key: const ValueKey('privacy-open-device-settings'),
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open device settings'),
            ),
          ),
          const SizedBox(height: Space.bottomNavClearance),
        ],
      ),
    ),
  );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(Space.lg),
    elevation: Elevation.flat,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoftIcon(icon),
        const SizedBox(height: Space.md),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) ...[const SizedBox(height: Space.lg), action!],
      ],
    ),
  );
}
