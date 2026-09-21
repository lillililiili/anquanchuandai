import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import '../store/user_store.dart';
import '../views/home_view.dart';
import 'route_tree.dart';

final homeShellKey = GlobalKey<NavigatorState>();

/// Popup routes can live in the root or the home shell Navigator.
final fieldModalOpen = ValueNotifier<bool>(false);

class FieldModalObserver extends NavigatorObserver {
  static final _popups = <Route<dynamic>>{};
  static bool _queued = false;

  void _publish() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_queued) return;
      _queued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        fieldModalOpen.value = _popups.isNotEmpty;
      });
    } else {
      fieldModalOpen.value = _popups.isNotEmpty;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      _popups.add(route);
      _publish();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_popups.remove(route)) _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_popups.remove(route)) _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _popups.remove(oldRoute);
    if (newRoute is PopupRoute) _popups.add(newRoute);
    _publish();
  }
}

/// 创建监听登录状态变化的 Listenable
class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier() {
    // 监听登录状态变化，发生变化时通知 go_router
    UserStore.instance.statusSignal.subscribe((_) => notifyListeners());
  }
}

final _authNotifier = AuthStateNotifier();

/// 路由观察器，同步到 NavigationService
class AgentRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _syncRoute();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _syncRoute();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _syncRoute();
  }

  void _syncRoute() {}
}

/// 路由配置
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash', // 从启动页开始
  refreshListenable: _authNotifier, // 监听登录状态变化，自动触发 redirect
  observers: [AgentRouteObserver(), FieldModalObserver()],
  redirect: (context, state) {
    // 启动页不进行重定向检查
    if (state.matchedLocation == '/splash') {
      return null;
    }

    // 检查是否已登录
    final isLoggedIn = UserStore.instance.status == UserStatus.authorized;

    // 如果未登录，访问需要认证的页面时重定向到登录页
    final requiresAuth =
        state.matchedLocation != RouteNode.login.url &&
        state.matchedLocation != '/splash';

    if (!isLoggedIn && requiresAuth) {
      AppLogger.d('未登录，重定向到登录页');
      return RouteNode.login.url;
    }

    // 如果已登录，访问登录页时重定向到首页
    // if (isLoggedIn && state.matchedLocation == RouteNode.login.url) {
    //   return '/home/tab1';
    // }

    return null;
  },
  routes: [
    // 启动页路由
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) {
        // 根据登录状态重定向
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final isLoggedIn = UserStore.instance.status == UserStatus.authorized;
          if (isLoggedIn) {
            context.go('/home/tab1');
          } else {
            context.go(RouteNode.login.url);
          }
        });
        return const SizedBox.shrink();
      },
    ),
    // RouteNode 中的独立页面路由
    ...RouteRegistry.toGoRoutes(),
    // ShellRoute 绑定 /home 路径
    ShellRoute(
      navigatorKey: homeShellKey,
      observers: [FieldModalObserver()],
      builder: (context, state, child) => HomeView(child: child),
      routes: [
        GoRoute(
          path: RouteNode.homeTab1.url,
          name: RouteNode.homeTab1.name,
          builder: RouteNode.homeTab1.builder,
        ),
        GoRoute(
          path: RouteNode.homeTab2.url,
          name: RouteNode.homeTab2.name,
          builder: RouteNode.homeTab2.builder,
        ),
        GoRoute(
          path: RouteNode.homeTab3.url,
          name: RouteNode.homeTab3.name,
          builder: RouteNode.homeTab3.builder,
        ),
        GoRoute(
          path: RouteNode.homeTab4.url,
          name: RouteNode.homeTab4.name,
          builder: RouteNode.homeTab4.builder,
        ),
        GoRoute(
          path: '/home',
          name: 'home',
          redirect: (context, state) => RouteNode.homeTab1.url,
        ),
      ],
    ),
  ],
);
