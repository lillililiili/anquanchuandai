import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/models/chat_models.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:rolling_intelligence_headband/views/login_view.dart';
import 'package:rolling_intelligence_headband/views/home_view.dart';
import 'package:rolling_intelligence_headband/views/home_children/check_in.dart';
import 'package:rolling_intelligence_headband/views/home_children/playback_of_trajectory.dart';
import 'package:rolling_intelligence_headband/views/home_children/person_select.dart';
import 'package:rolling_intelligence_headband/views/home_children/hat_select.dart';
import 'package:rolling_intelligence_headband/views/home_children/geo_fence.dart';
import 'package:rolling_intelligence_headband/views/home_children/geo_fence_edit.dart';
import 'package:rolling_intelligence_headband/views/home_children/alarm_record.dart';
import 'package:rolling_intelligence_headband/views/home_children/alarm_detail.dart';
import 'package:rolling_intelligence_headband/views/intercom_children/select_group.dart';
import 'package:rolling_intelligence_headband/views/monitor_children/monitor_detail.dart';
import 'package:rolling_intelligence_headband/views/mine_children/my_safety_hat.dart';
import 'package:rolling_intelligence_headband/views/mine_children/ai_config.dart';

import 'package:rolling_intelligence_headband/models/agora_credentials.dart';
import 'package:rolling_intelligence_headband/views/video_player/video_player_view.dart';
import 'package:rolling_intelligence_headband/views/rtc_page/video_page.dart';

/// Tab 名称常量
class AppTab {
  static const String home = 'home';
  static const String monitor = 'monitor';
  static const String intercom = 'intercom';
  static const String mine = 'mine';

  static const Map<String, String> labels = {
    home: '首页',
    monitor: '监控',
    intercom: '对讲',
    mine: '我的',
  };
}

class RouteMeta {
  final String name;
  final String description;
  final String url;
  final Map<String, ToolCall> tools;
  final Widget Function(BuildContext ctx, GoRouterState state) builder;
  final bool includeInGoRoutes;
  final String? parentTab;
  final bool isSecondary;
  final bool isAgentPage;
  final Map<String, dynamic>? arguments;

  const RouteMeta({
    required this.name,
    required this.description,
    required this.url,
    required this.builder,
    this.tools = const {},
    this.includeInGoRoutes = true,
    this.parentTab,
    this.isSecondary = true,
    this.arguments,
    this.isAgentPage = true,
  });

  /// 通过名字取工具：RouteNode.login['logout']
  ToolCall? operator [](String name) => tools[name];

  /// 工具列表（用于遍历）
  Iterable<ToolCall> get toolValues => tools.values;

  /// 转换为 JSON，用于 AI 提示词
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'url': url,
      'tools': tools.values.map((t) => t.toJson()).toList(),
      if (arguments != null) 'arguments': arguments,
    };
  }
}

/// 路由节点 - 定义所有路由常量
class RouteNode {
  static final login = RouteRegistry.register(
    RouteMeta(
      name: 'Login',
      description: '登录页面',
      url: '/login',
      tools: {
        'logout': ToolCall(
          name: 'logout',
          description: '退出登录',
          useWhen: '当用户选择退出登录时',
          type: ToolCallType.dataFun,
          resultType: 'void',
          arguments: {},
        ),
      },
      builder: (ctx, state) => const LoginView(),
      isSecondary: false,
    ),
  );

  static final checkIn = RouteRegistry.register(
    RouteMeta(
      name: 'CheckIn',
      description: '签到页面',
      url: '/check-in',
      builder: (ctx, state) => const CheckInPage(),
      parentTab: AppTab.home,
    ),
  );

  static final playbackOfTrajectory = RouteRegistry.register(
    RouteMeta(
      name: 'PlaybackOfTrajectory',
      description: '轨迹回放页面',
      url: '/playback-of-trajectory',
      builder: (ctx, state) {
        final params = state.extra is Map ? state.extra as Map : const {};
        return PlaybackOfTrajectoryPage(
          initialHatId: params['hatId']?.toString(),
          initialHatNumber: params['hatNumber']?.toString(),
          initialUserName: params['userName']?.toString(),
          initialDate: DateTime.tryParse(params['date']?.toString() ?? ''),
        );
      },
      parentTab: AppTab.home,
      includeInGoRoutes: true,
      tools: {
        'selectPerson': ToolCall(
          name: 'selectPerson',
          description: '选择人员',
          useWhen: '当用户需要选择人员时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {'name': ToolParam(description: '人员姓名', required: true)},
        ),
        'selectDateRange': ToolCall(
          name: 'selectDateRange',
          description: '选择日期范围',
          useWhen: '当用户需要选择日期范围时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'startTime': ToolParam(
              description: '开始日期,格式YYYY-MM-DD HH:mm:ss',
              required: true,
            ),
            'endTime': ToolParam(
              description: '结束日期,格式YYYY-MM-DD HH:mm:ss',
              required: true,
            ),
          },
        ),
        'executeQuery': ToolCall(
          name: 'executeQuery',
          description: '执行查询',
          useWhen: '当用户选择好人员和日期范围后，执行查询以获取轨迹数据',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
      },
    ),
  );

  static final personSelect = RouteRegistry.register(
    RouteMeta(
      name: 'PersonSelect',
      description: '人员选择页面',
      url: '/person-select',
      isAgentPage: false,
      builder: (ctx, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final mode = extra?['mode'] as SelectionMode? ?? SelectionMode.multiple;
        final personName = extra?['personName'] as String?;
        final autoSelect = extra?['autoSelect'] as bool? ?? false;
        return PersonSelectPage(
          selectionMode: mode,
          personName: personName,
          autoSelect: autoSelect,
        );
      },
      parentTab: AppTab.home,
    ),
  );

  static final hatSelect = RouteRegistry.register(
    RouteMeta(
      name: 'HatSelect',
      description: '安全帽选择页面',
      url: '/hat-select',
      isAgentPage: false,
      builder: (ctx, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final mode = extra?['mode'] as SelectionMode? ?? SelectionMode.single;
        final personName = extra?['personName'] as String?;
        final autoSelect = extra?['autoSelect'] as bool? ?? false;
        final teamNames = extra?['teamNames'] as List<String>?;
        return HatSelectPage(
          selectionMode: mode,
          personName: personName,
          autoSelect: autoSelect,
          teamNames: teamNames,
        );
      },
      parentTab: AppTab.home,
    ),
  );

  static final geoFence = RouteRegistry.register(
    RouteMeta(
      name: 'GeoFence',
      description: '电子围栏页面',
      url: '/geo-fence',
      builder: (ctx, state) => const GeoFencePage(),
      parentTab: AppTab.home,
      tools: {
        'queryFenceList': ToolCall(
          name: 'queryFenceList',
          description: '查询电子围栏列表',
          useWhen: '当用户询问围栏列表、围栏数据时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'fenceName': ToolParam(description: '围栏名称筛选'),
            'fenceType': ToolParam(description: '围栏类型筛选'),
          },
        ),
        'addFence': ToolCall(
          name: 'addFence',
          description: '添加电子围栏，跳转到添加页面',
          useWhen: '当用户要求添加新围栏时',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
        'editFence': ToolCall(
          name: 'editFence',
          description: '编辑电子围栏，跳转到编辑页面',
          useWhen: '当用户要求编辑某个围栏时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'fenceId': ToolParam(description: '围栏ID', required: true),
          },
        ),
        'deleteFence': ToolCall(
          name: 'deleteFence',
          description: '删除电子围栏',
          useWhen: '当用户要求删除某个围栏时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'fenceId': ToolParam(description: '围栏ID', required: true),
          },
        ),
      },
    ),
  );

  static final geoFenceEdit = RouteRegistry.register(
    RouteMeta(
      name: 'GeoFenceEdit',
      description: '电子围栏编辑/添加页面',
      url: '/geo-fence-edit',
      builder: (ctx, state) {
        final fenceId = state.uri.queryParameters['fenceId'];
        return GeoFenceEditPage(fenceId: fenceId);
      },
      parentTab: AppTab.home,
      arguments: {'fenceId': 'string? - 围栏ID，编辑时必填，新增时可为空'},
      tools: {
        'setFenceName': ToolCall(
          name: 'setFenceName',
          description: '设置围栏名称',
          useWhen: '当用户要求设置或修改围栏名称时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {'name': ToolParam(description: '围栏名称', required: true)},
        ),
        'setFenceType': ToolCall(
          name: 'setFenceType',
          description: '设置围栏类型',
          useWhen: '当用户要求设置或修改围栏类型时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {'type': ToolParam(description: '围栏类型', required: true)},
        ),
      },
    ),
  );

  static final alarmRecord = RouteRegistry.register(
    RouteMeta(
      name: 'AlarmRecord',
      description: '告警记录页面',
      url: '/alarm-record',
      builder: (ctx, state) => const AlarmRecordPage(),
      parentTab: AppTab.home,
      tools: {
        'queryAlarmRecord': ToolCall(
          name: 'queryAlarmRecord',
          description: '查询告警记录',
          useWhen: '当用户询问告警记录时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'pageNum': ToolParam(
              type: ToolParamType.integer,
              description: '页码',
            ),
            'pageSize': ToolParam(
              type: ToolParamType.integer,
              description: '每页大小',
            ),
          },
        ),
      },
    ),
  );

  static final alarmDetail = RouteRegistry.register(
    RouteMeta(
      name: 'AlarmDetail',
      description: '告警详情页面',
      url: '/alarm-detail',
      builder: (ctx, state) {
        final alarmId = state.uri.queryParameters['alarmId'];
        return AlarmDetailPage(alarmId: alarmId);
      },
      parentTab: AppTab.home,
      arguments: {'alarmId': 'string - 告警ID，必填'},
    ),
  );

  static final selectGroup = RouteRegistry.register(
    RouteMeta(
      name: 'SelectGroup',
      description: '选择群组页面',
      url: '/select-group',
      isAgentPage: false,
      builder: (ctx, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final groupName = extra?['groupName'] as String?;
        final autoSelect = extra?['autoSelect'] as bool? ?? false;
        return SelectGroupPage(groupName: groupName, autoSelect: autoSelect);
      },
      parentTab: AppTab.intercom,
    ),
  );

  static final monitorDetail = RouteRegistry.register(
    RouteMeta(
      name: 'MonitorDetail',
      description: '监控详情页面',
      url: '/monitor-detail',
      builder: (ctx, state) {
        final deviceId = state.uri.queryParameters['deviceId'];
        final credentialsJson = state.uri.queryParameters['credentialsJson'];
        final hatNumber = state.uri.queryParameters['hatNumber'];
        return MonitorDetailPage(
          deviceId: deviceId,
          hatNumber: hatNumber,
          credentialsJson: credentialsJson,
        );
      },
      parentTab: AppTab.monitor,
      isAgentPage: false,
      arguments: {
        'deviceId': 'string - 设备ID，必填',
        'credentialsJson': 'string - Agora凭证JSON，可选，用于复用token',
        'hatNumber': 'string - 安全帽编号，必填',
      },
    ),
  );

  static final mySafetyHat = RouteRegistry.register(
    RouteMeta(
      name: 'MySafetyHat',
      description: '我的安全帽页面',
      url: '/my-safety-hat',
      builder: (ctx, state) => const MySafetyHatPage(),
      parentTab: AppTab.mine,
    ),
  );

  static final aiConfig = RouteRegistry.register(
    RouteMeta(
      name: 'AIConfig',
      description: 'AI 配置页面，可配置 API Key、Base URL 和模型',
      url: '/ai-config',
      builder: (ctx, state) => const AIConfigPage(),
      parentTab: AppTab.mine,
    ),
  );

  static final videoPlayer = RouteRegistry.register(
    RouteMeta(
      name: 'VideoPlayer',
      description: '视频播放页面',
      url: '/video-player',
      builder: (ctx, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final url = extra?['url'] as String? ?? '';
        final title = extra?['title'] as String? ?? '视频播放';
        return VideoPlayerView(url: url, title: title);
      },
      parentTab: AppTab.home,
      arguments: {
        'url': 'string - 视频URL，必填',
        'title': 'string - 页面标题，可选，默认"视频播放"',
      },
    ),
  );

  static final rtcVideo = RouteRegistry.register(
    RouteMeta(
      name: 'RTCVideo',
      description: 'RTC视频通话页面',
      url: '/rtc-video',
      builder: (ctx, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return VideoPage(credentials: AgoraCredentials.fromJson(extra ?? {}));
      },
      parentTab: AppTab.monitor,
      arguments: {
        'appId': 'string - 声网AppID，必填',
        'token': 'string - 声网Token，可选',
        'channelName': 'string - 频道名称，必填',
        'uid': 'int - 用户ID，可选，默认0',
      },
    ),
  );

  // ShellRoute 中的 Tab 页面（路径相对于 /home）
  static final homeTab1 = RouteRegistry.register(
    RouteMeta(
      name: 'HomeTab1',
      description: '首页-工作台，可以查看最近告警、设备状态',
      url: '/home/tab1',
      builder: (ctx, state) => const Tab1View(),
      includeInGoRoutes: false,
      parentTab: AppTab.home,
      isSecondary: false,
    ),
  );

  static final homeTab2 = RouteRegistry.register(
    RouteMeta(
      name: 'HomeTab2',
      description: '首页-对讲，包含对讲、TTS播报两个tab，可以选择人、组进行对讲或发送播报，查询既往记录。',
      url: '/home/tab2',
      builder: (ctx, state) => const Tab2View(),
      includeInGoRoutes: false,
      parentTab: AppTab.intercom,
      isSecondary: false,
      tools: {
        'switchTab': ToolCall(
          name: 'switchTab',
          description: '切换对讲页面的子Tab',
          useWhen: '当用户要求切换到对讲或TTS页面时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'tabName': ToolParam(
              description: 'Tab名称，可选值："对讲"或"TTS"',
              required: true,
            ),
          },
        ),
        'setBroadcastText': ToolCall(
          name: 'setBroadcastText',
          description: '设置TTS播报的文本内容',
          useWhen: '当用户要求设置播报内容时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'content': ToolParam(description: '要播报的文本内容', required: true),
          },
        ),
        'selectBroadcastTarget': ToolCall(
          name: 'selectBroadcastTarget',
          description: '选择TTS播报对象，跳转到选择页面',
          useWhen: '当用户要求选择播报对象（单播、组播、群播）时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'type': ToolParam(
              description: '播报类型："单播"/"组播"/"群播"',
              required: true,
            ),
            'personName': ToolParam(description: '人员姓名，选择单播时传递'),
            'groupName': ToolParam(description: '组名称，选择组播时传递'),
            'teamNames': ToolParam(
              description: '人员姓名列表，选择群播时传递，格式如["张三","李四"]',
            ),
          },
        ),
        'queryBroadcastRecords': ToolCall(
          name: 'queryBroadcastRecords',
          description: '查询TTS播报记录列表',
          useWhen: '当用户询问播报记录、播报历史时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'broadcastType': ToolParam(
              description: '播报类型筛选："01"单播/"02"群播/"03"组播',
            ),
            'pageNum': ToolParam(
              type: ToolParamType.integer,
              description: '页码，默认1',
            ),
            'pageSize': ToolParam(
              type: ToolParamType.integer,
              description: '每页大小，默认20',
            ),
          },
        ),
        'sendBroadcast': ToolCall(
          name: 'sendBroadcast',
          description: '发送TTS播报',
          useWhen: '当用户确认发送播报时',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
        'selectCallTarget': ToolCall(
          name: 'selectCallTarget',
          description: '选择对讲呼叫对象，跳转到选择页面',
          useWhen: '当用户要求选择对讲对象（单呼、组呼、群呼）时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'type': ToolParam(
              description: '对讲类型："单呼"/"组呼"/"群呼"',
              required: true,
            ),
            'personName': ToolParam(description: '人员姓名，单呼时使用'),
            'groupName': ToolParam(description: '组名称，组呼时使用'),
            'teamNames': ToolParam(description: '人员姓名列表，群呼时使用，格式如["张三","李四"]'),
          },
        ),
        'startIntercomCall': ToolCall(
          name: 'startIntercomCall',
          description: '发起对讲呼叫',
          useWhen: '当用户确认发起对讲时',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
        'queryIntercomRecords': ToolCall(
          name: 'queryIntercomRecords',
          description: '查询对讲记录列表',
          useWhen: '当用户询问对讲记录、对讲历史时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'intercomType': ToolParam(
              description: '对讲类型筛选："01"单呼/"02"群呼/"03"组呼',
            ),
            'pageNum': ToolParam(
              type: ToolParamType.integer,
              description: '页码，默认1',
            ),
            'pageSize': ToolParam(
              type: ToolParamType.integer,
              description: '每页大小，默认20',
            ),
          },
        ),
        'deleteIntercomRecord': ToolCall(
          name: 'deleteIntercomRecord',
          description: '删除指定的对讲记录',
          useWhen: '当用户要求删除某条对讲记录时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'id': ToolParam(
              type: ToolParamType.integer,
              description: '要删除的记录ID',
              required: true,
            ),
          },
        ),
      },
    ),
  );

  static final homeTab3 = RouteRegistry.register(
    RouteMeta(
      name: 'HomeTab3',
      description: '首页-监控，查看可监控设备列表，选择设备进入监控详情',
      url: '/home/tab3',
      builder: (ctx, state) => const Tab3View(),
      includeInGoRoutes: false,
      parentTab: AppTab.monitor,
      isSecondary: false,
      tools: {
        'queryMonitorDevices': ToolCall(
          name: 'queryMonitorDevices',
          description: '查询监控设备列表',
          useWhen: '当用户询问有哪些监控设备、设备列表时',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
        'selectMonitorDevice': ToolCall(
          name: 'selectMonitorDevice',
          description: '切换到指定监控设备的实时画面',
          useWhen: '当用户要求切换到某个设备的监控、查看某人的监控时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          paramSchema: {
            'hatNumber': ToolParam(description: '设备编号'),
            'bindUserName': ToolParam(description: '绑定人员姓名'),
          },
        ),
        'enterMonitorDetail': ToolCall(
          name: 'enterMonitorDetail',
          description: '进入当前选中设备的监控详情页面',
          useWhen: '当用户要求查看详情、进入监控详情时',
          type: ToolCallType.dataFun,
          resultType: 'json',
        ),
      },
    ),
  );

  static final homeTab4 = RouteRegistry.register(
    RouteMeta(
      name: 'HomeTab4',
      description: '首页-我的，展示个人信息，退出登录，可进入安全帽详情',
      url: '/home/tab4',
      builder: (ctx, state) => const Tab4View(),
      includeInGoRoutes: false,
      parentTab: AppTab.mine,
      isSecondary: false,
      tools: {
        'logout': ToolCall(
          name: 'logout',
          description: '退出登录',
          useWhen: '当用户要求退出登录、登出账号时',
          type: ToolCallType.action,
          resultType: 'void',
          arguments: {},
        ),
        'getUserInfo': ToolCall(
          name: 'getUserInfo',
          description: '获取当前用户信息',
          useWhen: '当用户询问个人信息、用户信息时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          arguments: {},
        ),
        'getStatistics': ToolCall(
          name: 'getStatistics',
          description: '获取应用统计数据',
          useWhen: '当用户询问统计数据、安全帽数量、告警数量时',
          type: ToolCallType.dataFun,
          resultType: 'json',
          arguments: {},
        ),
      },
    ),
  );

  /// 确保所有路由已初始化（触发静态变量注册）
  static void ensureInitialized() {
    // 访问所有路由变量以触发注册
    final routes = [
      login,
      checkIn,
      playbackOfTrajectory,
      personSelect,
      hatSelect,
      geoFence,
      geoFenceEdit,
      alarmRecord,
      alarmDetail,
      selectGroup,
      monitorDetail,
      mySafetyHat,
      aiConfig,
      videoPlayer,
      rtcVideo,
      homeTab1,
      homeTab2,
      homeTab3,
      homeTab4,
    ];
    AppLogger.d('RouteNode 已初始化，共 ${routes.length} 个路由');
  }
}

/// 路由注册表 - 管理路由列表和工具函数
class RouteRegistry {
  // 内部注册表：List 保持顺序，Map 做快速查找
  static final _routesList = <RouteMeta>[];

  /// 注册并返回 RouteMeta，用于自注册
  static RouteMeta register(RouteMeta meta) {
    _routesList.add(meta);
    return meta;
  }

  /// 所有路由列表（只读）
  static List<RouteMeta> get all => List.unmodifiable(_routesList);

  /// 转换为 GoRoute 列表（用于 go_router，仅包含独立路由）
  static List<GoRoute> toGoRoutes() {
    // 确保所有路由已初始化
    RouteNode.ensureInitialized();

    final routes = _routesList
        .where((meta) => meta.includeInGoRoutes)
        .map(
          (meta) =>
              GoRoute(path: meta.url, name: meta.name, builder: meta.builder),
        )
        .toList();

    AppLogger.d('转换 GoRoute 列表: ${routes.map((r) => r.path).toList()}');

    return routes;
  }

  /// 转换为 GoRoute 列表（包含 redirect 支持）
  static List<GoRoute> toGoRoutesWithRedirect({
    String? Function(RouteMeta meta)? redirect,
  }) {
    return _routesList.map((meta) {
      final redir = redirect?.call(meta);
      return GoRoute(
        path: meta.url,
        name: meta.name,
        builder: meta.builder,
        redirect: redir != null ? (_, __) => redir : null,
      );
    }).toList();
  }

  /// API 1: 查询简版路由列表（给 AI 用）
  /// [tab] 可选，指定 tab 名称则只返回该 tab 下的二级路由
  /// 返回 Markdown 列表格式，例如：
  /// 1. Login - 登录页面 (tools: logout)
  /// 2. GeoFenceEdit - 电子围栏编辑/添加页面 (params: fenceId)
  static List<String> getSimpleListForAi({String? tab}) {
    final routes = tab != null
        ? _routesList.where((r) => r.parentTab == tab && r.isSecondary)
        : _routesList.where((r) => r.includeInGoRoutes);

    return routes.where((e) => e.isAgentPage == true).toList().asMap().entries.map((
      entry,
    ) {
      final index = entry.key + 1;
      final meta = entry.value;
      final toolsStr = meta.tools.isNotEmpty
          ? ' [tools: ${meta.tools.keys.join(', ')}]'
          : '';
      final argsStr = meta.arguments != null && meta.arguments!.isNotEmpty
          ? ' [params: ${meta.arguments!.entries.map((e) => '${e.key}(${e.value})').join(', ')}]'
          : '';
      return '$index. ${meta.name} - ${meta.description}$toolsStr$argsStr';
    }).toList();
  }

  /// API 2: 根据路由 name 查询详细信息（给 AI 用）
  static Map<String, dynamic>? getDetailByNameForAi(String name) {
    final meta = _routesList.where((r) => r.name == name).firstOrNull;
    return meta?.toJson();
  }

  /// 根据名称获取路由
  static RouteMeta? getRouteByName(String name) {
    return _routesList.where((r) => r.name == name).firstOrNull;
  }

  /// 获取所有一级页面（Tab 页面，parentTab 不为 null 且 isSecondary 为 false）
  static List<RouteMeta> getPrimaryRoutes() {
    return _routesList
        .where((r) => !r.isSecondary && r.parentTab != null)
        .toList();
  }

  /// 获取所有二级页面
  static List<RouteMeta> getSecondaryRoutes() {
    return _routesList.where((r) => r.isSecondary).toList();
  }

  /// 按 tab 分组获取二级路由（返回 AI 友好的字符串列表）
  static List<String> getRoutesByTab(String tab) {
    return getSimpleListForAi(tab: tab);
  }
}

/// BuildContext 扩展 - 路由导航
extension BuildContextRouteExtension on BuildContext {
  /// 根据 RouteMeta 推入新页面
  /// [route] 路由元数据
  /// [params] 可选的 URL 查询参数（会显示在 URL 中）
  /// [extra] 可选的额外数据（不显示在 URL 中，可传递任意类型）
  Future<T?> goto<T>(
    RouteMeta route, {
    Map<String, String>? params,
    Object? extra,
  }) {
    String url = route.url;
    if (params != null && params.isNotEmpty) {
      final uri = Uri.parse(url).replace(queryParameters: params);
      url = uri.toString();
    }
    return GoRouter.of(this).push(url, extra: extra);
  }

  /// 根据 RouteMeta 替换当前页面（无法返回）
  /// [route] 路由元数据
  /// [params] 可选的 URL 查询参数（会显示在 URL 中）
  /// [extra] 可选的额外数据（不显示在 URL 中，可传递任意类型）
  void replace(RouteMeta route, {Map<String, String>? params, Object? extra}) {
    String url = route.url;
    if (params != null && params.isNotEmpty) {
      final uri = Uri.parse(url).replace(queryParameters: params);
      url = uri.toString();
    }
    GoRouter.of(this).go(url, extra: extra);
  }
}
