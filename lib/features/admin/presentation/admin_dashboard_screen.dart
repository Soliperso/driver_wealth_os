import 'dart:async';

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
  var _filter = AdminAccessFilter.all;

  AdminOverview? _overview;
  var _page = const AdminUserPage.empty();
  var _actions = const <AdminAction>[];

  var _loading = true;
  var _loadingMore = false;
  var _failed = false;
  String? _changingUserId;

  /// Guards against an out-of-order response. Searching, filtering and
  /// refreshing all issue their own load, and a slow earlier one landing after
  /// a fast later one would put the wrong drivers on screen under the current
  /// filter.
  var _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Reloads the overview, the first page of drivers, and the audit trail.
  ///
  /// [keepDepth] refetches as many rows as are already on screen instead of
  /// one page, so acting on a driver does not throw an owner back to the top
  /// of a list they had paged through.
  Future<void> _reload({bool keepDepth = false}) async {
    final token = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final depth = keepDepth
        ? _page.users.length.clamp(
            SupabaseAdminRepository.pageSize,
            AdminUserPage.maxRows,
          )
        : SupabaseAdminRepository.pageSize;
    try {
      final overview = await widget.repository.loadOverview();
      final page = await widget.repository.loadUsers(
        query: _search.text,
        filter: _filter,
        limit: depth,
      );
      final actions = await widget.repository.loadRecentActions();
      if (!mounted || token != _request) return;
      setState(() {
        _overview = overview;
        _page = page;
        _actions = actions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_page.hasMore) return;
    final token = _request;
    setState(() => _loadingMore = true);
    try {
      final next = await widget.repository.loadUsers(
        query: _search.text,
        filter: _filter,
        offset: _page.users.length,
      );
      if (!mounted || token != _request) return;
      setState(() {
        _page = _page.followedBy(next);
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || token != _request) return;
      setState(() => _loadingMore = false);
      _say('Could not load more drivers.');
    }
  }

  void _changeFilter(AdminAccessFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    unawaited(_reload());
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => SoftScaffold(
    title: 'Admin dashboard',
    actions: [
      IconButton(
        key: const ValueKey('admin-refresh'),
        tooltip: 'Refresh dashboard',
        onPressed: () => unawaited(_reload(keepDepth: true)),
        icon: const Icon(Icons.refresh_rounded),
      ),
      const SizedBox(width: Space.sm),
    ],
    body: PageFrame(maxWidth: 1180, child: _body(context)),
  );

  Widget _body(BuildContext context) {
    final overview = _overview;
    if (_failed && overview == null) {
      return _AdminError(onRetry: () => unawaited(_reload()));
    }
    if (_loading && overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (overview == null) {
      return _AdminError(onRetry: () => unawaited(_reload()));
    }
    final theme = Theme.of(context);
    return ListView(
      children: [
        Text(
          'Platform overview',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Space.gapXs,
        Text(
          'A live view of drivers, activity, and account connections.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Space.gapLg,
        _OverviewGrid(overview: overview),
        Space.gapLg,
        _PlatformHealth(overview: overview),
        Space.gapXl,
        _UsersHeader(
          controller: _search,
          onSearch: () => unawaited(_reload()),
          shown: _page.users.length,
          total: _page.total,
          filter: _filter,
          onFilterChanged: _changeFilter,
        ),
        Space.gapMd,
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_page.users.isEmpty)
          _NoUsers(filter: _filter)
        else ...[
          for (final user in _page.users) ...[
            _AdminUserCard(
              user: user,
              busy: _changingUserId == user.id,
              onCloudAccessChanged: (enabled) =>
                  unawaited(_changeCloudAccess(user, enabled)),
            ),
            Space.gapSm,
          ],
          if (_page.hasMore)
            _LoadMore(
              busy: _loadingMore,
              remaining: _page.total - _page.users.length,
              onPressed: () => unawaited(_loadMore()),
            ),
        ],
        Space.gapXl,
        _RecentActions(actions: _actions),
        const SizedBox(height: Space.xxl),
      ],
    );
  }

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
      setState(() => _changingUserId = null);
      _say(enabled ? 'Cloud access restored' : 'Cloud access paused');
      // Refetches the rows already on screen rather than the first page, so an
      // owner who paged deep to find this driver stays where they were.
      await _reload(keepDepth: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _changingUserId = null);
      // The control plane refuses some changes outright — an owner's own
      // account, or another owner's. Those arrive here as a failure, and the
      // switch has already snapped back, so the message has to say that the
      // change did not happen rather than that something went wrong.
      _say('That change was refused. Cloud access is unchanged.');
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
    required this.shown,
    required this.total,
    required this.filter,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSearch;
  final int shown;
  final int total;
  final AdminAccessFilter filter;
  final ValueChanged<AdminAccessFilter> onFilterChanged;

  /// "12 drivers" while everything matching is on screen, "50 of 900" once it
  /// is not — so the count never implies the list is complete when it is a
  /// page of something larger.
  String get _count {
    if (total == 0) return 'None shown';
    if (shown >= total) return '$total ${total == 1 ? 'driver' : 'drivers'}';
    return '$shown of $total';
  }

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
            _count,
            key: const ValueKey('admin-user-count'),
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
      final chips = Wrap(
        spacing: Space.sm,
        children: [
          for (final option in AdminAccessFilter.values)
            ChoiceChip(
              key: ValueKey('admin-filter-${option.name}'),
              label: Text(option.label),
              selected: option == filter,
              onSelected: (_) => onFilterChanged(option),
            ),
        ],
      );
      if (constraints.maxWidth < 600) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [title, Space.gapMd, search, Space.gapMd, chips],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              search,
            ],
          ),
          Space.gapMd,
          chips,
        ],
      );
    },
  );
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.busy,
    required this.remaining,
    required this.onPressed,
  });

  final bool busy;
  final int remaining;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: OutlinedButton.icon(
      key: const ValueKey('admin-load-more'),
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.expand_more_rounded),
      label: Text(busy ? 'Loading…' : 'Load $remaining more'),
    ),
  );
}

/// The record of who changed whose access.
///
/// Shown in the dashboard rather than left in the database because the point of
/// logging an owner action is that another owner can see it happened.
class _RecentActions extends StatelessWidget {
  const _RecentActions({required this.actions});

  final List<AdminAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      key: const ValueKey('admin-recent-actions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Access changes',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Space.gapXs,
        Text(
          'Every pause and restore, with the owner who made it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        Space.gapMd,
        GlassSurface(
          elevation: Elevation.flat,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          child: actions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.md),
                  child: Text(
                    'No access has been paused or restored yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : Column(
                  children: [
                    for (final (index, action) in actions.indexed) ...[
                      if (index > 0) const Divider(height: 1),
                      _ActionRow(action: action),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final AdminAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            action.paused
                ? Icons.pause_circle_outline_rounded
                : Icons.play_circle_outline_rounded,
            size: 20,
            color: action.paused ? colors.error : colors.primary,
          ),
          Space.gapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.summary, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  [
                    if (action.actorEmail case final actor?
                        when actor.isNotEmpty)
                      actor,
                    _when(context, action.at),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
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

  static String _when(BuildContext context, DateTime at) {
    final local = at.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(local)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
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
  const _NoUsers({required this.filter});

  final AdminAccessFilter filter;

  /// Names the filter, so an owner who has narrowed to Paused and found
  /// nothing reads "no paused drivers" rather than concluding the search
  /// itself came back empty.
  String get _message => switch (filter) {
    AdminAccessFilter.all => 'No drivers match this search.',
    AdminAccessFilter.active => 'No active drivers match this search.',
    AdminAccessFilter.paused => 'No drivers have their access paused.',
  };

  @override
  Widget build(BuildContext context) => GlassSurface(
    elevation: Elevation.flat,
    child: Text(
      _message,
      key: const ValueKey('admin-no-users'),
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
