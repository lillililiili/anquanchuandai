import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:voice_recognizer/voice_recognizer.dart';

/// 语音识别服务注册中心
///
/// 提供全局单例管理，支持提前异步初始化，避免每次使用时等待。
///
/// ## 使用方式
///
/// ```dart
/// // 1. 应用启动时提前注册（推荐在 main.dart 或 App 初始化时调用）
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // 提前初始化语音识别服务（异步，不阻塞启动）
///   VoiceRecognizerRegistry.instance.preInitialize();
///
///   runApp(MyApp());
/// }
///
/// // 2. 使用时直接获取已初始化的实例
/// final recognizer = VoiceRecognizerRegistry.instance.recognizer;
/// if (recognizer != null && recognizer.isInitialized) {
///   // 可以直接使用
/// }
///
/// // 3. 或者等待初始化完成
/// await VoiceRecognizerRegistry.instance.ensureInitialized();
/// final recognizer = VoiceRecognizerRegistry.instance.recognizer!;
/// ```
class VoiceRecognizerRegistry extends ChangeNotifier {
  // 单例
  static VoiceRecognizerRegistry? _instance;
  static VoiceRecognizerRegistry get instance {
    _instance ??= VoiceRecognizerRegistry._();
    return _instance!;
  }

  VoiceRecognizerRegistry._();

  /// 重置单例（主要用于测试）
  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  // 识别器实例
  SimpleParaformerRecognizer? _recognizer;

  // 下载服务
  final ModelDownloadService _downloadService = ModelDownloadService.instance;

  // 初始化状态
  InitializationStatus _status = InitializationStatus.notStarted;
  String? _errorMessage;
  Completer<bool>? _initCompleter;

  // 模型配置
  String _modelFileName = 'model.int8.onnx';
  String _tokensFileName = 'tokens.txt';
  int _sampleRate = 16000;
  /// 推理线程数，移动端建议 1 以减轻发热
  int _numThreads = 1;

  /// 获取识别器实例（可能为 null 如果未初始化）
  SimpleParaformerRecognizer? get recognizer => _recognizer;

  /// 当前初始化状态
  InitializationStatus get status => _status;

  /// 是否已初始化完成
  bool get isInitialized => _status == InitializationStatus.ready;

  /// 是否正在初始化
  bool get isInitializing => _status == InitializationStatus.initializing;

  /// 是否初始化失败
  bool get hasError => _status == InitializationStatus.error;

  /// 错误信息
  String? get errorMessage => _errorMessage;

  /// 下载服务实例
  ModelDownloadService get downloadService => _downloadService;

  /// 模型是否已下载
  bool get isModelDownloaded => _downloadService.isModelReady;

  /// 模型下载状态
  DownloadState get downloadState => _downloadService.state;

  /// 配置识别器参数
  ///
  /// 必须在 [preInitialize] 之前调用
  ///
  /// [modelDownloadUrl] 模型文件下载地址
  /// [tokensDownloadUrl] 词表文件下载地址
  /// [numThreads] 推理线程数，移动端建议 1 以减轻发热与耗电，桌面端可设为 2。
  void configure({
    String? modelFileName,
    String? tokensFileName,
    int? sampleRate,
    int? numThreads,
    String? modelDownloadUrl,
    String? tokensDownloadUrl,
  }) {
    if (_status == InitializationStatus.initializing) {
      debugPrint('VoiceRecognizerRegistry: 初始化中，无法修改配置');
      return;
    }

    if (modelFileName != null) _modelFileName = modelFileName;
    if (tokensFileName != null) _tokensFileName = tokensFileName;
    if (sampleRate != null) _sampleRate = sampleRate;
    if (numThreads != null) _numThreads = numThreads;

    // 配置下载 URL
    if (modelDownloadUrl != null && tokensDownloadUrl != null) {
      _downloadService.configure(
        modelUrl: modelDownloadUrl,
        tokensUrl: tokensDownloadUrl,
      );
    }

    debugPrint('VoiceRecognizerRegistry: 配置已更新');
  }

  /// 提前初始化（异步，不阻塞）
  ///
  /// 推荐在应用启动时调用，这样使用语音识别功能时无需等待。
  /// 多次调用是安全的，会自动忽略重复调用。
  ///
  /// 如果模型文件已下载，会使用本地路径初始化；否则需要先调用 [downloadModel] 下载模型。
  Future<bool> preInitialize() async {
    // 如果已经初始化成功，直接返回
    if (_status == InitializationStatus.ready) {
      debugPrint('VoiceRecognizerRegistry: 已初始化完成，跳过');
      return true;
    }

    // 如果正在初始化，返回现有的 Future
    if (_status == InitializationStatus.initializing &&
        _initCompleter != null) {
      debugPrint('VoiceRecognizerRegistry: 正在初始化中，等待完成');
      return _initCompleter!.future;
    }

    // 开始初始化
    _initCompleter = Completer<bool>();
    _updateStatus(InitializationStatus.initializing);

    try {
      debugPrint('VoiceRecognizerRegistry: 开始初始化语音识别服务...');

      // 检查模型是否已下载，获取本地路径
      final modelPath = await _downloadService.getModelPath();
      debugPrint('VoiceRecognizerRegistry: 模型路径 = ${modelPath ?? "未下载"}');

      _recognizer = SimpleParaformerRecognizer(
        modelLocalPath: modelPath,
        modelFileName: _modelFileName,
        tokensFileName: _tokensFileName,
        sampleRate: _sampleRate,
        numThreads: _numThreads,
      );

      final success = await _recognizer!.initialize();

      if (success) {
        _updateStatus(InitializationStatus.ready);
        debugPrint('VoiceRecognizerRegistry: 初始化成功');
        _initCompleter!.complete(true);
        return true;
      } else {
        _errorMessage = _recognizer!.errorMessage;
        _updateStatus(InitializationStatus.error);
        debugPrint('VoiceRecognizerRegistry: 初始化失败 - $_errorMessage');
        _initCompleter!.complete(false);
        return false;
      }
    } catch (e, stack) {
      _errorMessage = e.toString();
      _updateStatus(InitializationStatus.error);
      debugPrint('VoiceRecognizerRegistry: 初始化异常 - $e');
      debugPrint('Stack: $stack');
      _initCompleter!.complete(false);
      return false;
    }
  }

  /// 下载模型文件
  ///
  /// 下载完成后会自动初始化识别器
  Future<bool> downloadModel() async {
    final success = await _downloadService.downloadModel();
    if (success) {
      // 下载成功后自动初始化
      _status = InitializationStatus.notStarted;
      _initCompleter = null;
      return await preInitialize();
    }
    return false;
  }

  /// 确保已初始化
  ///
  /// 如果尚未初始化，会自动开始初始化并等待完成。
  /// 如果已初始化，立即返回。
  Future<bool> ensureInitialized() async {
    if (_status == InitializationStatus.ready) {
      return true;
    }

    if (_status == InitializationStatus.error) {
      // 如果之前失败了，重试
      _status = InitializationStatus.notStarted;
      _errorMessage = null;
    }

    return preInitialize();
  }

  /// 获取或创建识别器
  ///
  /// 如果全局实例已初始化，返回全局实例；
  /// 否则创建一个新的实例（需要提供 modelLocalPath）
  SimpleParaformerRecognizer getOrCreateRecognizer({
    required String? modelLocalPath,
    String? modelFileName,
    String? tokensFileName,
    int? sampleRate,
    int? numThreads,
  }) {
    // 如果全局实例已初始化，直接返回
    if (_recognizer != null && _status == InitializationStatus.ready) {
      debugPrint('VoiceRecognizerRegistry: 返回已初始化的全局实例');
      return _recognizer!;
    }

    // 否则创建新实例
    debugPrint('VoiceRecognizerRegistry: 创建新的识别器实例');
    return SimpleParaformerRecognizer(
      modelLocalPath: modelLocalPath,
      modelFileName: modelFileName ?? _modelFileName,
      tokensFileName: tokensFileName ?? _tokensFileName,
      sampleRate: sampleRate ?? _sampleRate,
      numThreads: numThreads ?? _numThreads,
    );
  }

  /// 重置服务（释放资源）
  void reset() {
    _recognizer?.dispose();
    _recognizer = null;
    _status = InitializationStatus.notStarted;
    _errorMessage = null;
    _initCompleter = null;
    notifyListeners();
    debugPrint('VoiceRecognizerRegistry: 已重置');
  }

  void _updateStatus(InitializationStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  @override
  void dispose() {
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }
}

/// 初始化状态
enum InitializationStatus {
  /// 尚未开始
  notStarted,

  /// 初始化中
  initializing,

  /// 就绪
  ready,

  /// 错误
  error,
}

/// 便捷扩展方法
extension VoiceRecognizerRegistryX on VoiceRecognizerRegistry {
  /// 监听初始化状态变化
  void onStatusChanged(void Function(InitializationStatus status) callback) {
    void listener() {
      callback(status);
    }

    addListener(listener);
  }
}
