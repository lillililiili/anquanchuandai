import '../../components/field_motion.dart';
import '../../components/field_brand.dart';
import '../../components/field_assistant_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import '../../theme/theme.dart';
import 'intercom/talk_tab.dart';
import 'intercom/tts_tab.dart';

/// Tab 名称常量
const _tabNames = ['对讲', 'TTS'];

class IntercomTab extends StatefulWidget {
  const IntercomTab({super.key});

  @override
  State<IntercomTab> createState() => _IntercomTabState();
}

class _IntercomTabState extends State<IntercomTab>
    with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_selectedIndex != _tabController.index) {
      setState(() => _selectedIndex = _tabController.index);
    }
  }

  void _onTabTap(int index) => _tabController.animateTo(
    index,
    duration: MotionPolicy.duration(context, 220),
  );

  /// 切换 Tab（供 AI 和 UI 共用）
  void _switchTab(String tabName) {
    final index = _tabNames.indexOf(tabName == '语音播报' ? 'TTS' : tabName);
    if (index == -1) {
      throw Exception('无效的Tab名称：$tabName，可选值："对讲"或"语音播报"');
    }
    _onTabTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeModeSignal.themeColorsSignal.value;
    final cardBgColor = theme.isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF3F4F6);

    return _AgentScope(
      switchTab: _switchTab,
      selectedIndex: _selectedIndex,
      builder: (pageController) => MotionActivity(
        child: Scaffold(
          backgroundColor: theme.background,
          extendBodyBehindAppBar: true,
          body: SafeArea(
            child: Column(
              children: [
                const MotionEntrance(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        FieldBrandMark(size: 32),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '现场通讯',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FieldAssistantAction(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      dividerColor: Colors.transparent,
                      labelColor: Theme.of(context).colorScheme.onPrimary,
                      unselectedLabelColor: theme.textSecondary,
                      labelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: SpringColors.mintGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tabs: const [
                        Tab(text: '对讲'),
                        Tab(text: '语音播报'),
                      ],
                    ),
                  ),
                ), // Tab 内容
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // TalkDispatchTab 接收 pageController，共享 Agent 控制器
                      TalkDispatchTab(
                        theme: theme,
                        pageController: pageController,
                      ),
                      // TTSTab 接收 pageController，共享 Agent 控制器
                      TTSTab(theme: theme, pageController: pageController),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Agent 作用域组件 - 在 HookWidget 中桥接 StatefulWidget 和 Agent 服务
class _AgentScope extends HookWidget {
  final Widget Function(PageAgentController controller) builder;
  final void Function(String tabName) switchTab;
  final int selectedIndex;

  const _AgentScope({
    required this.builder,
    required this.switchTab,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 页面 Agent 总控
    final pageController = useAgentPage(
      meta: RouteNode.homeTab2,
      greetingMessage: '已进入对讲调度页面，可切换对讲或语音播报页面',
    );

    // 绑定 AI 工具：切换 Tab
    usePageAgent(
      controller: pageController,
      toolName: 'switchTab',
      executeFn: (params) async {
        final tabName = params?['tabName'] as String?;
        if (tabName == null || tabName.isEmpty) {
          throw Exception('请指定要切换的Tab名称，可选值："对讲"或"语音播报"');
        }
        switchTab(tabName);
        return {'success': true, 'message': '已切换到$tabName页面'};
      },
    );

    usePageAgentGetData(pageController, "tabState", () {
      return {
        'currentTab': _tabNames[selectedIndex],
        'currentIndex': selectedIndex,
        'availableTabs': _tabNames,
      };
    }, deps: [selectedIndex]);

    // 通知 AI 页面就绪
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          pageController.completeEmptyInit();
        }
      });
      return null;
    }, []);

    return builder(pageController);
  }
}
