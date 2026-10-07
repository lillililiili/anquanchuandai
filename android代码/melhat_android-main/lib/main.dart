import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'wear/app.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rolling_intelligence_headband/components/app_copilot_portal.dart';
import 'package:signals/signals_flutter.dart';
import 'package:voice_recognizer/voice_recognizer.dart';
import 'router/app_router.dart';
import 'theme/theme.dart';
import 'store/user_store.dart';
import 'store/chat_store.dart';
import 'store/ai_config_store.dart';

void main() async {
  // 确保 Flutter 绑定已初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 关闭 signals 日志输出
  SignalsObserver.instance = null;

  // Production and normal debug builds use only the authorized /api/v1 platform.
  // The former app remains available explicitly for development comparison.
  if (!kDebugMode || !const bool.fromEnvironment('LEGACY_DEMO')) {
    runApp(const WearApp());
    return;
  }

  // 初始化 UserStore（会从持久化加载数据）
  await UserStore.init();

  // 初始化 AI 配置
  await AIConfigStore.init();

  // 加载聊天历史消息
  await ChatStore.instance.loadMessages();

  // 配置语音模型下载地址
  VoiceRecognizerRegistry.instance.configure(
    modelDownloadUrl: 'http://192.168.1.17:82/models/model.int8.onnx',
    tokensDownloadUrl: 'http://192.168.1.17:82/models/tokens.txt',
  );
  VoiceRecognizerRegistry.instance.preInitialize();

  // 全局错误捕获，防止未处理异常导致白屏崩溃
  // FlutterError.onError = (details) {
  //   AppLogger.e('FlutterError: ${details.exception}', details.stack);
  // };

  // PlatformDispatcher.instance.onError = (error, stack) {
  //   AppLogger.e('PlatformDispatcher error: $error', error, stack);
  //   return true;
  // };

  // await ImmersiveUtil.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '智能安全头环',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      builder: (context, child) {
        // builder 返回的 widget 在 Navigator 中，可以访问 Overlay/Directionality/Localizations
        // 不需要包裹 Material，因为 Navigator 外层已有 Material context
        return AppCopilotPortal(child: child ?? const SizedBox.shrink());
        // return child ?? const SizedBox.shrink();
      },
    );
  }
}
