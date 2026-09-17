import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';
import 'auth_pages.dart';
import 'notifications.dart';
import 'mine_page.dart';
import 'queries/queries.dart';
import 'events/events_page.dart';
import 'communications/communications.dart';

/// Mobile presentation shell: communications, alerts and personal context.
/// API/session/controllers remain the source of authorization and server state.
class WearApp extends StatefulWidget {
  const WearApp({super.key, this.session, this.enableNotifications = true});
  final WearSession? session;
  final bool enableNotifications;
  @override
  State<WearApp> createState() => _WearAppState();
}

class _WearAppState extends State<WearApp> {
  late final WearSession _session = widget.session ?? WearSession();
  final _appearance = WearThemeController();
  late final WearNotifications _notifications;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    unawaited(_appearance.load());
    _notifications = WearNotifications(
      session: _session,
      openEvent: _openNotice,
    );
    _router = GoRouter(
      initialLocation: '/communications',
      refreshListenable: _session,
      redirect: (context, state) {
        final path = state.uri.path;
        if (_session.me == null) return path == '/login' ? null : '/login';
        if (_session.siteId == null) return path == '/sites' ? null : '/sites';
        if (path == '/sites' && _session.callActive.value) {
          return '/communications?intent=call';
        }
        if (path == '/login' || path == '/workbench') return '/communications';
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(
          title: const Text('页面暂不可用'),
          actions: const [WearThemeButton()],
        ),
        body: Center(
          child: WearEmpty(
            title: '未找到这个页面',
            detail: '请返回通讯或从告警重新进入。',
            onRetry: () => context.go('/communications'),
          ),
        ),
      ),
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const WearLoginPage()),
        GoRoute(path: '/sites', builder: (_, _) => const WearSitesPage()),
        GoRoute(path: '/workbench', redirect: (_, _) => '/communications'),
        // Context pages are real secondary routes, above the three-tab shell.
        GoRoute(
          path: '/people',
          builder: (_, s) =>
              PeoplePage(initialName: s.uri.queryParameters['name']),
        ),
        GoRoute(
          path: '/people/:id',
          builder: (_, s) => PersonPage(id: s.pathParameters['id']!),
        ),
        GoRoute(path: '/devices', builder: (_, _) => const DevicesPage()),
        GoRoute(
          path: '/devices/:id',
          builder: (_, s) => DevicePage(id: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/tracks',
          builder: (_, s) =>
              TracksPage(personId: s.uri.queryParameters['personId']),
        ),
        GoRoute(path: '/fences', builder: (_, _) => const FencesPage()),
        GoRoute(
          path: '/fences/:id',
          builder: (_, s) => FencePage(id: s.pathParameters['id']!),
        ),
        GoRoute(path: '/tasks', builder: (_, _) => const TasksPage()),
        GoRoute(
          path: '/tasks/:id',
          builder: (_, s) => TaskPage(id: s.pathParameters['id']!),
        ),
        GoRoute(
          path: '/supervision',
          builder: (_, _) => const SupervisionPage(),
        ),
        GoRoute(
          path: '/alerts',
          redirect: (_, s) => Uri(
            path: '/events',
            queryParameters: s.uri.queryParameters.isEmpty
                ? null
                : s.uri.queryParameters,
          ).toString(),
        ),
        GoRoute(
          path: '/alerts/:id',
          redirect: (_, s) =>
              '/events?eventId=${Uri.encodeComponent(s.pathParameters['id']!)}',
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              WearShell(shell: shell, notifications: _notifications),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/communications',
                  builder: (context, s) => CommunicationsPage(
                    key: ValueKey(
                      'communications:${WearScope.of(context).scopeKey}',
                    ),
                    deviceId: s.uri.queryParameters['deviceId'],
                    personId: s.uri.queryParameters['personId'],
                    eventId: s.uri.queryParameters['eventId'],
                    actionIntent: s.uri.queryParameters['intent'],
                    video: const [
                      'true',
                      '1',
                    ].contains(s.uri.queryParameters['video']),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/events',
                  builder: (context, s) => EventsPage(
                    key: ValueKey('events:${WearScope.of(context).scopeKey}'),
                    eventId: s.uri.queryParameters['eventId'],
                    personId: s.uri.queryParameters['personId'],
                    taskId: s.uri.queryParameters['taskId'],
                    initialStatus: s.uri.queryParameters['status'],
                    initialType: s.uri.queryParameters['type'],
                    initialClaimantUserId:
                        s.uri.queryParameters['claimantUserId'],
                    initialEscalated:
                        s.uri.queryParameters.containsKey('escalated')
                        ? s.uri.queryParameters['escalated'] == 'true'
                        : null,
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/me',
                  builder: (context, _) => WearMinePage(
                    key: ValueKey('me:${WearScope.of(context).scopeKey}'),
                    notifications: _notifications,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    if (!_session.initialized) unawaited(_session.initialize());
    if (widget.enableNotifications) unawaited(_notifications.start());
  }

  Future<void> _openNotice(WearNotice notice) async {
    final user = _session.userId;
    if (_session.siteId != notice.siteId) {
      await _session.selectSite(notice.siteId);
    }
    final event = jsonMap(
      await _session.api.get('/api/v1/events/${notice.eventId}'),
    );
    if (_session.userId != user ||
        idOf(event['siteId']) != _session.siteId ||
        idOf(event['id']) != notice.eventId) {
      throw const StaleSessionException();
    }
    if (mounted) {
      _router.go('/events?eventId=${Uri.encodeComponent(notice.eventId)}');
      _session.requestRefresh();
    }
  }

  @override
  void dispose() {
    _notifications.dispose();
    _router.dispose();
    _appearance.dispose();
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WearScope(
    session: _session,
    child: WearThemeScope(
      controller: _appearance,
      child: ListenableBuilder(
        listenable: _appearance,
        builder: (context, _) => MaterialApp.router(
          title: '智能穿戴管理平台',
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          themeMode: _appearance.dark ? ThemeMode.dark : ThemeMode.light,
          theme: WearThemes.make(Brightness.light),
          darkTheme: WearThemes.make(Brightness.dark),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).appBarTheme.systemOverlayStyle!,
            child: child!,
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          locale: const Locale('zh', 'CN'),
        ),
      ),
    ),
  );
}

class WearShell extends StatefulWidget {
  const WearShell({
    super.key,
    required this.shell,
    required this.notifications,
  });
  final StatefulNavigationShell shell;
  final WearNotifications notifications;
  @override
  State<WearShell> createState() => _WearShellState();
}

class _WearShellState extends State<WearShell> {
  WearSession? _session;
  int? _count;
  int _generation = 0;
  String? _scope;
  final Map<int, String> _branchScopes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session?.refreshTick.removeListener(_refresh);
      _session = session;
      session.refreshTick.addListener(_refresh);
    }
    if (_scope != session.scopeKey) {
      _scope = session.scopeKey;
      _count = null;
      Future.microtask(_loadCount);
    }
  }

  void _refresh() => unawaited(_loadCount());

  Future<void> _loadCount() async {
    if (_session == null || _session!.busy || _session!.siteId == null) return;
    final generation = ++_generation;
    final scope = _session!.scopeKey;
    try {
      final data = jsonMap(
        await _session!.api.get('/api/v1/events/inbox/count'),
      );
      if (mounted && generation == _generation && scope == _session!.scopeKey) {
        setState(() => _count = intOf(data['count']));
      }
    } catch (_) {
      if (mounted && generation == _generation && scope == _session!.scopeKey) {
        setState(() => _count = null);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _session?.refreshTick.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final colors = Theme.of(context).colorScheme;
    _branchScopes[widget.shell.currentIndex] = session.scopeKey;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const WearRollingWordmark(height: 22),
        actions: const [
          WearSiteSwitcher(),
          WearThemeButton(),
          SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: widget.notifications,
            builder: (context, _) {
              final notices = widget.notifications;
              if (notices.latest == null && notices.error == null) {
                return const SizedBox.shrink();
              }
              return Material(
                color: colors.surfaceContainerHigh,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.notifications_active_outlined,
                    color: colors.secondary,
                  ),
                  title: Text(notices.error != null ? '接警连接需要检查' : '收到新的现场告警'),
                  subtitle: Text(
                    notices.error != null
                        ? '可在“我的 → 接警设置”查看状态'
                        : '查看人员、位置并联系现场',
                  ),
                  onTap: notices.latest == null
                      ? () => widget.shell.goBranch(2)
                      : notices.openLatest,
                  trailing: IconButton(
                    tooltip: '收起提示',
                    onPressed: notices.dismissLatest,
                    icon: const Icon(Icons.close),
                  ),
                ),
              );
            },
          ),
          if (session.callActive.value && widget.shell.currentIndex != 0)
            Material(
              color: colors.primaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.phone_in_talk_outlined),
                title: const Text('通话进行中'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/communications?intent=call'),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                KeyedSubtree(
                  key: ValueKey(session.scopeKey),
                  child: widget.shell,
                ),
                if (session.busy)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x55000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: session.busy
            ? null
            : (index) {
                FocusScope.of(context).unfocus();
                if (index == widget.shell.currentIndex ||
                    _branchScopes[index] != session.scopeKey) {
                  context.go(
                    const ['/communications', '/events', '/me'][index],
                  );
                } else {
                  widget.shell.goBranch(index);
                }
              },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '通讯',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: (_count ?? 0) > 0,
              child: const Icon(Icons.notifications_none),
            ),
            selectedIcon: Badge(
              isLabelVisible: (_count ?? 0) > 0,
              child: const Icon(Icons.notifications),
            ),
            label: '告警',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
