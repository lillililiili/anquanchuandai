import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';
import 'auth_pages.dart';
import 'notifications.dart';
import 'mine_page.dart';
import 'queries/queries.dart';
import 'events/events_page.dart';
import 'communications/communications.dart';
import '../theme/app_theme.dart';

class WearApp extends StatefulWidget {
  final WearSession? session;
  final bool enableNotifications;
  const WearApp({super.key, this.session, this.enableNotifications = true});
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
                  path: '/people',
                  builder: (_, s) =>
                      PeoplePage(initialName: s.uri.queryParameters['name']),
                ),
                GoRoute(
                  path: '/supervision',
                  builder: (_, _) => const SupervisionPage(),
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
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/communications',
                  builder: (_, s) => CommunicationsPage(
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
    final cargoTheme = AppTheme.lightTheme;
    return WearScope(
      session: _session,
      child: MaterialApp.router(
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
          RegExp(r'^/tasks/[^/]+$').hasMatch(GoRouterState.of(context).uri.path)
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
                const NavigationDestination(
                  icon: Icon(Icons.call_outlined),
                  selectedIcon: Icon(Icons.call),
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
