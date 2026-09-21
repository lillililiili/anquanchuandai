import 'package:signals_hooks/signals_hooks.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// AI 配置 Store
///
/// 使用方式:
/// ```dart
/// // 获取配置
/// final apiKey = AIConfigStore.instance.apiKey;
/// final baseUrl = AIConfigStore.instance.baseUrl;
/// final model = AIConfigStore.instance.model;
///
/// // 保存配置
/// await AIConfigStore.instance.saveConfig(
///   apiKey: 'new-key',
///   baseUrl: 'https://api.example.com/v1',
///   model: 'gpt-4',
/// );
/// ```
class AIConfigStore {
  /// 单例实例
  static final AIConfigStore instance = AIConfigStore._internal();

  /// 初始化标志
  static bool _isInitialized = false;

  /// 初始化 Future
  static Future<void> init() async {
    if (!_isInitialized) {
      await instance._init();
      _isInitialized = true;
    }
  }

  // ==================== 持久化 Key ====================

  static const String _apiKeyKey = 'ai_api_key';
  static const String _baseUrlKey = 'ai_base_url';
  static const String _modelKey = 'ai_model';

  // ==================== 信号定义 ====================

  /// API Key 信号
  final _apiKeySignal = Signal<String>('');

  /// Base URL 信号
  final _baseUrlSignal = Signal<String>('');

  /// Model 信号
  final _modelSignal = Signal<String>('');

  // ==================== 私有构造函数 ====================

  AIConfigStore._internal();

  // ==================== Getter（响应式） ====================

  /// 获取 API Key
  String get apiKey => _apiKeySignal.value;

  /// 获取 Base URL
  String get baseUrl => _baseUrlSignal.value;

  /// 获取 Model
  String get model => _modelSignal.value;

  /// 获取 API Key 信号
  Signal<String> get apiKeySignal => _apiKeySignal;

  /// 获取 Base URL 信号
  Signal<String> get baseUrlSignal => _baseUrlSignal;

  /// 获取 Model 信号
  Signal<String> get modelSignal => _modelSignal;

  /// 是否使用自定义配置
  bool get isCustomized =>
      _apiKeySignal.value.isNotEmpty ||
      _baseUrlSignal.value.isNotEmpty ||
      _modelSignal.value.isNotEmpty;

  // ==================== 初始化 ====================

  /// 初始化
  Future<void> _init() async {
    await _loadFromStorage();
  }

  /// 从存储加载配置
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _apiKeySignal.value = prefs.getString(_apiKeyKey) ?? '';
      _baseUrlSignal.value = prefs.getString(_baseUrlKey) ?? '';
      _modelSignal.value = prefs.getString(_modelKey) ?? '';
    } catch (e) {
      AppLogger.e('加载 AI 配置失败: $e');
    }
  }

  // ==================== Actions ====================

  /// 保存配置
  Future<void> saveConfig({
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_apiKeyKey, apiKey);
      await prefs.setString(_baseUrlKey, baseUrl);
      await prefs.setString(_modelKey, model);

      _apiKeySignal.value = apiKey;
      _baseUrlSignal.value = baseUrl;
      _modelSignal.value = model;
    } catch (e) {
      AppLogger.e('保存 AI 配置失败: $e');
      rethrow;
    }
  }

  /// 恢复默认配置
  Future<void> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_apiKeyKey);
      await prefs.remove(_baseUrlKey);
      await prefs.remove(_modelKey);

      _apiKeySignal.value = '';
      _baseUrlSignal.value = '';
      _modelSignal.value = '';
    } catch (e) {
      AppLogger.e('重置 AI 配置失败: $e');
      rethrow;
    }
  }
}

// ==================== Hooks 辅助函数 ====================

/// 获取 AI 配置 Store
AIConfigStore useAIConfigStore() {
  return AIConfigStore.instance;
}
