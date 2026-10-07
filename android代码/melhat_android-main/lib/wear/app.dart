import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';
import 'auth_pages.dart';
import 'notifications.dart';
import 'mine_page.dart';
import 'duty_pages.dart';
import 'queries/queries.dart';
import 'queries/person_management.dart';
import 'queries/account_recovery.dart';
import 'events/events_page.dart';
import 'communications/communications.dart';
import 'communications/lab_calls.dart';
import '../theme/app_theme.dart';

class WearApp extends StatefulWidget {
  final WearSession? session;
  final bool enableNotifications;
  // Optional bundled font for the browser demo; Android keeps its original theme.
  final String? fontFamily;
  const WearApp({
    super.key,
    this.session,
    this.enableNotifications = true,
    this.fontFamily,
  });
  @override
  State<WearApp> createState() => _WearAppState();
}

class _WearAppState extends State<WearApp> {
  late final WearSession _session = widget.session ?? WearSession();
  late final WearNotifications _notifications;
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _notifications = WearNotifications(
      session: _session,
      openEvent: _openNotice,
    );
    _router = GoRouter(
      initialLocation: '/workbench',
      refreshListenable: _session,
      redirect: (context, state) {
        final path = state.uri.path;
        if (_session.me == null) return path == '/login' ? null : '/login';
        if (_session.siteId == null) return path == '/sites' ? null : '/sites';
        if (path == '/sites' && _session.callActive.value) {
          return '/communications';
        }
        if (path == '/login') return '/workbench';
        if (!_session.isAdmin &&
            !(path == '/workbench' ||
                path == '/communications' ||
                path == '/events' ||
                path == '/sos-events' ||
                path == '/tasks' ||
                RegExp(r'^/devices/[0-9]+$').hasMatch(path) ||
                RegExp(r'^/tasks/[^/]+$').hasMatch(path) ||
                path == '/me' ||
                path == '/sites')) {
          return '/workbench';
        }
        return null;
      },
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: WearEmpty(
            title: '页面暂不可用',
            onRetry: () => context.go('/workbench'),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: '/lab-call/:id',
          builder: (_, s) => LabCallPage(id: s.pathParameters['id']!),
        ),
        GoRoute(path: '/login', builder: (_, _) => const WearLoginPage()),
        GoRoute(path: '/sites', builder: (_, _) => const WearSitesPage()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) =>
              WearShell(shell: shell, notifications: _notifications),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/workbench',
                  builder: (_, _) => const WorkbenchPage(),
                ),
                GoRoute(
                  path: '/sos-events',
                  redirect: (_, _) =>
                      '/events?severity=emergency&status=active',
                ),
                GoRoute(
                  path: '/people',
                  builder: (_, s) =>
                      PeoplePage(initialName: s.uri.queryParameters['name']),
                ),
                GoRoute(
                  path: '/people-admin/equipment/:id',
                  builder: (_, s) =>
                      PersonEquipmentPage(id: s.pathParameters['id']!),
                ),
                GoRoute(
                  path: '/people-admin/recovery',
                  builder: (_, _) => const AccountRecoveryPage(),
                ),
                GoRoute(
                  path: '/people/:id',
                  builder: (_, s) => PersonPage(id: s.pathParameters['id']!),
                ),
                GoRoute(
                  path: '/devices',
                  builder: (_, _) => const DevicesPage(),
                ),
                GoRoute(
                  path: '/devices/:id',
                  builder: (_, s) => DevicePage(id: s.pathParameters['id']!),
                ),
                GoRoute(
                  path: '/tasks',
                  builder: (_, s) => TasksPage(
                    groupId: s.uri.queryParameters['groupId'],
                    allSite: s.uri.queryParameters['scope'] == 'all',
                  ),
                ),
                GoRoute(
                  path: '/tasks/:id',
                  builder: (_, s) => TaskPage(id: s.pathParameters['id']!),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/communications',
                  builder: (_, s) => CommunicationsPage(
                    filterRequest: s.uri.queryParameters['filterRequest'],
                    action: s.uri.queryParameters['action'],
                    deviceId: s.uri.queryParameters['deviceId'],
                    personId: s.uri.queryParameters['personId'],
                    eventId: s.uri.queryParameters['eventId'],
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
                  builder: (_, s) => EventsPage(
                    eventId: s.uri.queryParameters['eventId'],
                    personId: s.uri.queryParameters['personId'],
                    taskId: s.uri.queryParameters['taskId'],
                    initialStatus: s.uri.queryParameters['status'],
                    initialType: s.uri.queryParameters['type'],
                    initialSeverity: s.uri.queryParameters['severity'],
                    filterRequest: s.uri.queryParameters['filterRequest'],
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
                  builder: (_, _) =>
                      WearMinePage(notifications: _notifications),
                ),
                GoRoute(
                  path: '/settings',
                  builder: (_, _) => const WearDutyPage(settings: true),
                ),
                GoRoute(
                  path: '/handovers',
                  builder: (_, _) => const WearDutyPage(),
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
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final originalTheme = AppTheme.lightTheme;
    final cargoTheme = widget.fontFamily == null
        ? originalTheme
        : originalTheme.copyWith(
            textTheme: originalTheme.textTheme.apply(
              fontFamily: widget.fontFamily,
            ),
            primaryTextTheme: originalTheme.primaryTextTheme.apply(
              fontFamily: widget.fontFamily,
            ),
          );
    return WearScope(
      session: _session,
      child: MaterialApp.router(
        builder: (context, child) => LabCallHost(
          routeChanges: _router.routerDelegate,
          // The URI can still describe the parent for imperative pushes.
          // The last match is the actual top page, including pushed routes.
          callPageVisible: () => _router
              .routerDelegate
              .currentConfiguration
              .last
              .matchedLocation
              .startsWith('/lab-call/'),
          session: _session,
          openCall: (id) => _router.push('/lab-call/$id'),
          child: child ?? const SizedBox.shrink(),
        ),
        title: '智能穿戴管理平台',
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        themeMode: ThemeMode.light,
        theme: cargoTheme.copyWith(
          colorScheme: cargoTheme.colorScheme.copyWith(
            primary: WearColors.brand,
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFE8F1FF),
            secondary: WearColors.brand,
            onSecondary: Colors.white,
          ),
          scaffoldBackgroundColor: WearColors.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: WearColors.background,
            foregroundColor: WearColors.ink,
            scrolledUnderElevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              fontSize: 23,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: WearColors.ink,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WearColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WearColors.brand, width: 2),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: WearColors.line),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: WearColors.brand,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: WearColors.brand,
              side: const BorderSide(color: WearColors.brand),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            elevation: 0,
            backgroundColor: Colors.white,
            indicatorColor: WearColors.brand.withValues(alpha: 0.14),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                color: selected ? WearColors.brand : WearColors.muted,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? WearColors.brand : WearColors.muted,
              );
            }),
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        locale: const Locale('zh', 'CN'),
      ),
    );
  }
}

class WearShell extends StatefulWidget {
  final StatefulNavigationShell shell;
  final WearNotifications notifications;
  const WearShell({
    super.key,
    required this.shell,
    required this.notifications,
  });
  @override
  State<WearShell> createState() => _WearShellState();
}

class _WearShellState extends State<WearShell> {
  WearSession? _session;
  int? _count;
  int _generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (_session != session) {
      _session?.refreshTick.removeListener(_refresh);
      _session = session;
      session.refreshTick.addListener(_refresh);
      Future.microtask(_loadCount);
    }
  }

  void _refresh() {
    unawaited(_loadCount());
  }

  Future<void> _loadCount() async {
    if (_session == null || _session!.busy || _session!.siteId == null) return;
    final generation = ++_generation;
    try {
      final data = jsonMap(
        await _session!.api.get('/api/v1/events/inbox/count'),
      );
      if (mounted && generation == _generation) {
        setState(() => _count = intOf(data['count']));
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _count = null);
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
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ListenableBuilder(
              listenable: widget.notifications,
              builder: (context, _) {
                final notices = widget.notifications;
                if (notices.latest == null && notices.error == null) {
                  return const SizedBox.shrink();
                }
                return Material(
                  color: const Color(0xFFFFF0D9),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.notifications_active_outlined,
                      color: WearColors.warning,
                    ),
                    title: Text(notices.error ?? '有新的现场事件'),
                    subtitle: notices.error == null
                        ? const Text('点击查看最新状态')
                        : null,
                    onTap: notices.openLatest,
                    trailing: IconButton(
                      tooltip: '收起提示',
                      onPressed: notices.dismissLatest,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: session.busy
                  ? const Center(child: CircularProgressIndicator())
                  : KeyedSubtree(
                      key: ValueKey(session.scopeKey),
                      child: widget.shell,
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          RegExp(
                r'^/tasks/[^/]+$',
              ).hasMatch(GoRouterState.of(context).uri.path) ||
              (GoRouterState.of(context).uri.path == '/events' &&
                  (GoRouterState.of(
                        context,
                      ).uri.queryParameters['eventId']?.isNotEmpty ??
                      false))
          ? null
          : NavigationBar(
              height: 60,
              selectedIndex: widget.shell.currentIndex,
              onDestinationSelected: session.busy
                  ? null
                  : (index) {
                      FocusScope.of(context).unfocus();
                      widget.shell.goBranch(index);
                    },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: '现场',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.call_outlined),
                  selectedIcon: const Icon(Icons.call),
                  label: '通讯',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: (_count ?? 0) > 0,
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: (_count ?? 0) > 0,
                    child: const Icon(Icons.chat_bubble),
                  ),
                  label: '消息',
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
