import '../components/field_navigation_bar.dart';
import '../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/views/tabs/intercom_tab.dart';
import 'package:rolling_intelligence_headband/views/tabs/mine_tab.dart';
import 'package:rolling_intelligence_headband/views/tabs/monitor_tab.dart';
import 'package:go_router/go_router.dart';
import 'tabs/home_tab.dart';

/// 导航占据独立布局空间，页面滚动内容和操作不会被遮住。
class HomeView extends StatelessWidget {
  final Widget child;
  const HomeView({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final paths = [
      RouteNode.homeTab1.url,
      RouteNode.homeTab2.url,
      RouteNode.homeTab3.url,
      RouteNode.homeTab4.url,
    ];
    final location = GoRouterState.of(context).uri.path;
    final selected = paths.indexWhere(
      (path) => location == path || location.startsWith('$path/'),
    );
    final labels = ['首页', '对讲', '监控', '我的'];
    final icons = [
      Icons.home_outlined,
      Icons.mic_none,
      Icons.videocam_outlined,
      Icons.person_outline,
    ];
    return Scaffold(
      body: MotionActivity(child: child),
      bottomNavigationBar: MotionActivity(
        child: FieldNavigationBar(
          selected: selected < 0 ? 0 : selected,
          labels: labels,
          icons: icons,
          onSelected: (index) => context.go(paths[index]),
        ),
      ),
    );
  }
}

// 标签页视图组件
class Tab1View extends StatelessWidget {
  const Tab1View({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeTabPage();
  }
}

class Tab2View extends StatelessWidget {
  const Tab2View({super.key});

  @override
  Widget build(BuildContext context) {
    return IntercomTab();
  }
}

class Tab3View extends StatelessWidget {
  const Tab3View({super.key});

  @override
  Widget build(BuildContext context) {
    return MonitorTab();
  }
}

class Tab4View extends StatelessWidget {
  const Tab4View({super.key});

  @override
  Widget build(BuildContext context) {
    return MineTabPage();
  }
}
