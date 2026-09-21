import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';

void usePageAgentGetData(
  PageAgentController pageController,
  String dataKey,
  Map<String, dynamic> Function() getDataCallback, {
  deps = const [],
}) {
  // 注册页面数据回调
  useEffect(() {
    pageController.onGetData(dataKey, getDataCallback);
    return () {
      pageController.offGetData(dataKey);
    };
  }, deps);
}
