import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../../auth/application/auth_gateway.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({
    super.key,
    this.accountEmail,
    this.onDeleteAccount,
  });

  final String? accountEmail;

  /// Permanently destroys the account. Null in a local-only build, where there
  /// is no account and nothing on a server to remove.
  final Future<void> Function()? onDeleteAccount;

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  var _deleting = false;

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
          if (widget.accountEmail != null) ...[
            _PrivacyCard(
              icon: Icons.cloud_done_outlined,
              title: 'Account sync',
              body:
                  'Your sessions, goals and preferences sync to the account signed in as ${widget.accountEmail}.',
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
          // Last on the screen, and the only destructive thing on it. Both
          // stores require an account created in an app to be removable from
          // that app, so this is not optional.
          if (widget.onDeleteAccount != null) ...[
            const SizedBox(height: Space.md),
            _PrivacyCard(
              icon: Icons.delete_forever_outlined,
              title: 'Delete your account',
              body:
                  'Permanently removes your account and every session, expense '
                  'and setting stored under it, on this device and on the '
                  'server. This cannot be undone.',
              action: OutlinedButton.icon(
                key: const ValueKey('privacy-delete-account'),
                onPressed: _deleting ? null : _confirmDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever_outlined, size: 18),
                label: Text(_deleting ? 'Deleting…' : 'Delete account'),
              ),
            ),
          ],
          const SizedBox(height: Space.bottomNavClearance),
        ],
      ),
    ),
  );

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await widget.onDeleteAccount!();
      if (!mounted) return;
      // The app has already swapped its home to the sign-in screen underneath
      // this route. Popping is what reveals it — without this the driver would
      // be left staring at the privacy page of an account that no longer
      // exists.
      Navigator.of(context).pop();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// Asks for the word DELETE before destroying an account.
///
/// A plain confirm button is the pattern used for deleting one session, which
/// is recoverable by re-entering it. This is not: it takes the account, every
/// shift, every expense and the ability to sign in, with no undo anywhere in
/// the system. Typing makes the action deliberate rather than a mis-tap.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _phrase = 'DELETE';

  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _controller.text.trim().toUpperCase() == _phrase;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'This permanently removes your account and every session, expense '
            'and setting under it. This cannot be undone.',
          ),
          const SizedBox(height: Space.lg),
          TextField(
            key: const ValueKey('delete-account-confirm-field'),
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type $_phrase to confirm',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete-account'),
          // Inert until the word is typed, so the destructive button cannot be
          // reached by tapping twice in the same place.
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
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
