import 'package:flutter/material.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/soft_surfaces.dart';
import '../application/admin_repository.dart';
import '../domain/admin_models.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, required this.repository});

  final AdminRepository repository;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _search = TextEditingController();
  late Future<_AdminDashboardData> _data;
  String? _changingUserId;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_AdminDashboardData> _load() async {
    final overview = await widget.repository.loadOverview();
    final users = await widget.repository.loadUsers(query: _search.text);
    return _AdminDashboardData(overview: overview, users: users);
  }

  void _refresh() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: 'Admin dashboard',
    actions: [
      IconButton(
        key: const ValueKey('admin-refresh'),
        tooltip: 'Refresh dashboard',
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
      ),
      const SizedBox(width: Space.sm),
    ],
    body: PageFrame(
      maxWidth: 1180,
      child: FutureBuilder<_AdminDashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _AdminError(onRetry: _refresh);
          }
          final data = snapshot.requireData;
          return ListView(
            children: [
              Text(
                'Platform overview',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Space.gapXs,
              Text(
                'A live view of drivers, activity, and account connections.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Space.gapLg,
              _OverviewGrid(overview: data.overview),
              Space.gapLg,
              _PlatformHealth(overview: data.overview),
              Space.gapXl,
              _UsersHeader(
                controller: _search,
                onSearch: _refresh,
                count: data.users.length,
              ),
              Space.gapMd,
              if (data.users.isEmpty)
                const _NoUsers()
              else
                for (final user in data.users) ...[
                  _AdminUserCard(
                    user: user,
                    busy: _changingUserId == user.id,
                    onCloudAccessChanged: (enabled) =>
                        _changeCloudAccess(user, enabled),
                  ),
                  Space.gapSm,
                ],
              const SizedBox(height: Space.xxl),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _changeCloudAccess(AdminUserSummary user, bool enabled) async {
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pause cloud access?'),
          content: Text(
            '${user.displayName} will keep on-device records, but syncing and '
            'connected-account data will pause until access is restored.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Pause access'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _changingUserId = user.id);
    try {
      await widget.repository.setCloudAccess(userId: user.id, enabled: enabled);
      if (!mounted) return;
      setState(() {
        _changingUserId = null;
        _data = _load();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Cloud access restored' : 'Cloud access paused',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _changingUserId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update cloud access.')),
      );
    }
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      final width = (constraints.maxWidth - Space.md * (columns - 1)) / columns;
      final metrics = [
        (
          label: 'Drivers',
          value: '${overview.drivers}',
          detail: '${overview.activeDrivers} active',
          icon: Icons.people_outline_rounded,
        ),
        (
          label: 'Completed sessions',
          value: '${overview.shifts}',
          detail: 'All time',
          icon: Icons.route_outlined,
        ),
        (
          label: 'Work accounts',
          value: '${overview.connectedAccounts}',
          detail: 'Connected',
          icon: Icons.link_rounded,
        ),
        (
          label: 'Driver profit',
          value: Money.whole(overview.profit30Days),
          detail: 'Last 30 days',
          icon: Icons.trending_up_rounded,
        ),
      ];
      return Wrap(
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          for (final metric in metrics)
            SizedBox(
              width: width,
              child: _OverviewMetric(
                label: metric.label,
                value: metric.value,
                detail: metric.detail,
                icon: metric.icon,
              ),
            ),
        ],
      );
    },
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      elevation: Elevation.flat,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: Space.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          Space.gapXs,
          Text(
            detail,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PlatformHealth extends StatelessWidget {
  const _PlatformHealth({required this.overview});

  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final healthy = overview.failedSyncs == 0;
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      elevation: Elevation.flat,
      padding: const EdgeInsets.all(Space.lg),
      child: Row(
        children: [
          Icon(
            healthy ? Icons.check_circle_outline_rounded : Icons.sync_problem,
            color: healthy ? colors.primary : colors.error,
          ),
          Space.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import health',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  healthy
                      ? 'No failed earning imports in the last 24 hours.'
                      : '${overview.failedSyncs} failed earning '
                            '${overview.failedSyncs == 1 ? 'import' : 'imports'} in the last 24 hours.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _UsersHeader extends StatelessWidget {
  const _UsersHeader({
    required this.controller,
    required this.onSearch,
    required this.count,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final int count;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Drivers',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            '$count shown',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      final search = SizedBox(
        width: constraints.maxWidth >= 600 ? 300 : double.infinity,
        child: TextField(
          key: const ValueKey('admin-user-search'),
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            hintText: 'Search name or email',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Search',
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ),
      );
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, Space.gapMd, search],
        );
      }
      return Row(
        children: [
          Expanded(child: title),
          search,
        ],
      );
    },
  );
}

class _AdminUserCard extends StatelessWidget {
  const _AdminUserCard({
    required this.user,
    required this.busy,
    required this.onCloudAccessChanged,
  });

  final AdminUserSummary user;
  final bool busy;
  final ValueChanged<bool> onCloudAccessChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassSurface(
      key: ValueKey('admin-user-${user.id}'),
      elevation: Elevation.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (user.email != null &&
                        user.email != user.displayName) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch.adaptive(
                  key: ValueKey('admin-cloud-access-${user.id}'),
                  value: user.cloudAccessEnabled,
                  onChanged: onCloudAccessChanged,
                ),
            ],
          ),
          const Divider(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: _UserMetric(
                  label: 'Joined',
                  value: _date(context, user.createdAt),
                ),
              ),
              Expanded(
                child: _UserMetric(
                  label: 'Sessions',
                  value: '${user.shiftCount}',
                ),
              ),
              Expanded(
                child: _UserMetric(
                  label: 'Profit',
                  value: Money.whole(user.totalProfit),
                ),
              ),
              Expanded(
                child: _UserMetric(
                  label: 'Accounts',
                  value: '${user.workAccountCount}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _date(BuildContext context, DateTime date) =>
      MaterialLocalizations.of(context).formatShortDate(date.toLocal());
}

class _UserMetric extends StatelessWidget {
  const _UserMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w800,
          fontFeatures: tabularFigures,
        ),
      ),
    ],
  );
}

class _NoUsers extends StatelessWidget {
  const _NoUsers();

  @override
  Widget build(BuildContext context) => GlassSurface(
    elevation: Elevation.flat,
    child: Text(
      'No drivers match this search.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _AdminError extends StatelessWidget {
  const _AdminError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: GlassSurface(
      elevation: Elevation.flat,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 36),
          Space.gapMd,
          const Text('The admin dashboard could not be loaded.'),
          Space.gapMd,
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class _AdminDashboardData {
  const _AdminDashboardData({required this.overview, required this.users});

  final AdminOverview overview;
  final List<AdminUserSummary> users;
}
