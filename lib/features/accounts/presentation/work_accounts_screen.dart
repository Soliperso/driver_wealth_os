import 'package:flutter/material.dart';

import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../application/earnings_connection_gateway.dart';
import '../application/earnings_repository.dart';
import '../domain/work_platform.dart';
import 'platform_logo.dart';

class WorkAccountsScreen extends StatefulWidget {
  const WorkAccountsScreen({
    super.key,
    required this.connectionGateway,
    this.syncStatus,
    this.onRefreshEarnings,
  });

  final EarningsConnectionGateway connectionGateway;
  final SyncStatus? syncStatus;
  final Future<void> Function()? onRefreshEarnings;

  @override
  State<WorkAccountsScreen> createState() => _WorkAccountsScreenState();
}

class _WorkAccountsScreenState extends State<WorkAccountsScreen> {
  WorkPlatform? _busyPlatform;
  final Set<WorkPlatform> _connectedPlatforms = {};

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: 'Work accounts',
    body: PageFrame(
      maxWidth: 720,
      child: ListView(
        children: [
          const _ConnectionIntro(),
          if (widget.syncStatus != null) ...[
            const SizedBox(height: 16),
            _SyncStatusCard(
              status: widget.syncStatus!,
              onRetry: widget.onRefreshEarnings,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Choose a platform',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Connect each account separately. You stay in control of what is shared.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          GlassSurface(
            padding: EdgeInsets.zero,
            radius: 18,
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < WorkPlatform.connectable.length;
                  index++
                ) ...[
                  _PlatformRow(
                    platform: WorkPlatform.connectable[index],
                    isBusy: _busyPlatform == WorkPlatform.connectable[index],
                    isConnected: _connectedPlatforms.contains(
                      WorkPlatform.connectable[index],
                    ),
                    onConnect: () => _connect(WorkPlatform.connectable[index]),
                  ),
                  if (index != WorkPlatform.connectable.length - 1)
                    const Divider(indent: 68),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PrivacyNote(),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );

  Future<void> _connect(WorkPlatform platform) async {
    if (_busyPlatform != null) return;
    setState(() => _busyPlatform = platform);
    try {
      final result = await widget.connectionGateway.connect(platform);
      if (!mounted) return;
      if (result == ConnectionLaunchResult.setupRequired) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          builder: (context) => const _SetupRequiredSheet(),
        );
      } else if (result == ConnectionLaunchResult.connected) {
        setState(() => _connectedPlatforms.add(platform));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${platform.displayName} connected. Earnings sync has started.',
            ),
          ),
        );
      }
    } on EarningsConnectionException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busyPlatform = null);
    }
  }
}

/// Surfaces the newest `sync_jobs` row. Without this the backend records every
/// import and failure and the driver never sees any of it.
class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.status, this.onRetry});

  final SyncStatus status;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final failed = status.state == SyncState.failed;
    final running = status.state == SyncState.running;
    return GlassSurface(
      key: const ValueKey('sync-status-card'),
      padding: const EdgeInsets.all(18),
      tint: failed ? colors.errorContainer.withValues(alpha: .7) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftIcon(switch (status.state) {
            SyncState.failed => Icons.error_outline_rounded,
            SyncState.running => Icons.sync_rounded,
            SyncState.succeeded => Icons.cloud_done_outlined,
          }, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  switch (status.state) {
                    SyncState.failed => 'Last import failed',
                    SyncState.running => 'Importing earnings…',
                    SyncState.succeeded => 'Earnings up to date',
                  },
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  failed
                      // The real cause, not a generic apology: this is what
                      // makes a stalled import diagnosable.
                      ? (status.errorMessage ?? 'The import did not complete.')
                      : running
                      ? 'Started ${_relative(status.startedAt)}.'
                      : '${status.recordsProcessed} records · '
                            '${_relative(status.finishedAt ?? status.startedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (failed && onRetry != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => onRetry!(),
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relative(DateTime moment) {
    final elapsed = DateTime.now().difference(moment);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }
}

class _ConnectionIntro extends StatelessWidget {
  const _ConnectionIntro();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      padding: const EdgeInsets.all(22),
      tint: colors.primaryContainer.withValues(alpha: .82),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoftIcon(Icons.account_balance_wallet_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All your income, together',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 7),
                Text(
                  'Import earnings from the platforms you work with and see one clear profit picture.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.platform,
    required this.isBusy,
    required this.isConnected,
    required this.onConnect,
  });

  final WorkPlatform platform;
  final bool isBusy;
  final bool isConnected;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: isConnected
          ? '${platform.displayName} connected'
          : 'Connect ${platform.displayName}',
      child: InkWell(
        onTap: isBusy || isConnected ? null : onConnect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              PlatformLogo(
                key: ValueKey('platform-logo-${platform.id}'),
                platform: platform,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platform.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      platform.category,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isBusy)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: colors.primary,
                  ),
                )
              else if (isConnected)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Connected',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Connect',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.lock_outline_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          'Connections are read-only. Driver Wealth never changes your work account or accepts jobs for you.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}

class _SetupRequiredSheet extends StatelessWidget {
  const _SetupRequiredSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: SoftIcon(Icons.shield_outlined),
          ),
          const SizedBox(height: 16),
          Text(
            'Secure sync setup is next',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'The account-connection experience is ready, but real earnings cannot be imported until the secure connection service is activated. No password or account data was requested.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    ),
  );
}
