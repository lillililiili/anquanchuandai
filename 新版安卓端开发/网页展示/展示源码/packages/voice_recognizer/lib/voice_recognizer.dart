/// 语音识别组件库
///
/// 基于阿里 Paraformer-zh 模型的离线语音识别组件
/// 支持流式识别（边录边识别）、长按录音交互
///
/// ## 核心组件
///
/// - [VoiceRecordButton] - 长按录音按钮，松开结束识别
/// - [VoiceRecordOverlay] - 语音录入弹窗，带动画效果
/// - [VoiceRecognizerRegistry] - 语音识别服务注册中心（推荐使用）
/// - [ParaformerRecognizerService] - Paraformer 流式识别服务
///
/// ## 推荐使用方式（提前初始化，优化用户体验）
///
/// ```dart
/// // 1. 在应用启动时提前初始化（异步，不阻塞启动）
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // 提前初始化语音识别服务
///   VoiceRecognizerRegistry.instance.preInitialize();
///
///   runApp(MyApp());
/// }
///
/// // 2. 使用按钮组件（自动使用全局服务）
/// VoiceRecordButton(
///   maxDuration: 10,
///   onResult: (text) => print('识别结果: $text'),
/// )
///
/// // 3. 使用弹窗（自动使用全局服务）
/// final result = await showVoiceRecordOverlay(
///   context: context,
///   maxDuration: 10,
/// );
/// ```
///
/// ## 自定义配置
///
/// ```dart
/// // 在初始化前配置模型下载地址
/// VoiceRecognizerRegistry.instance.configure(
///   modelDownloadUrl: 'https://your-cdn.com/model.int8.onnx',
///   tokensDownloadUrl: 'https://your-cdn.com/tokens.txt',
/// );
///
/// // VoiceRecordButton 会自动显示下载提示
/// // 用户点击后自动下载并初始化
/// ```
library voice_recognizer;

// 服务
export 'src/services/paraformer_recognizer.dart';
export 'src/services/audio_recorder_service.dart';
export 'src/services/voice_recognizer_registry.dart';
export 'src/services/model_download_service.dart';

// 组件
export 'src/widgets/voice_record_button.dart';
export 'src/widgets/voice_record_overlay.dart';

// 动画
export 'src/animations/voice_animations.dart';

// 模型
export 'src/models/recognition_result.dart';

// 工具
export 'src/utils/text_corrector.dart';
