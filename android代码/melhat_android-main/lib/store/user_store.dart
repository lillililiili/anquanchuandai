import '../field/field_session.dart';
import 'dart:convert';
import 'package:rolling_intelligence_headband/models/user.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';

/// 用户状态枚举
enum UserStatus {
  /// 未登录
  unauthorized,

  /// 已登录
  authorized,

  /// 登录中
  loggingIn,

  /// 登出中
  loggingOut,
}

/// 用户 Store（类似 Vue/React 的 Store 模式）
///
/// 使用方式:
/// ```dart
/// // 在 HookWidget 中使用
/// final userStore = useUserStore();
/// final token = userStore.token;
/// final userInfo = userStore.userInfo;
/// final isLoggedIn = userStore.isLoggedIn;
///
/// // 执行操作
/// await userStore.login(username, password);
/// await userStore.logout();
/// ```
class UserStore {
  /// 单例实例
  static final UserStore instance = UserStore._internal();

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

  static const String _tokenKey = 'user_token';
  static const String _userInfoKey = 'user_info';

  // ==================== 信号定义 ====================

  /// 用户状态信号
  final _statusSignal = Signal(UserStatus.unauthorized);

  /// Token 信号
  final _tokenSignal = Signal<String?>('');

  /// 用户信息信号
  final _userInfoSignal = Signal<UserInfo?>(null);

  // ==================== Computed 信号 ====================

  /// 是否已登录
  static final isLoggedIn = computed(
    () => instance._statusSignal.value == UserStatus.authorized,
  );

  /// 是否未登录
  static final isUnauthorized = computed(
    () => instance._statusSignal.value == UserStatus.unauthorized,
  );

  /// 是否正在登出
  static final isLoggingOut = computed(
    () => instance._statusSignal.value == UserStatus.loggingOut,
  );

  // ==================== 私有构造函数 ====================

  /// 私有构造函数
  UserStore._internal() {
    // 不在构造函数中初始化，由静态 init 方法控制
  }

  // ==================== Getter（响应式） ====================

  /// 获取用户状态
  UserStatus get status => _statusSignal.value;

  /// 获取 Token
  String? get token => _tokenSignal.value;

  /// 获取用户信息
  UserInfo? get userInfo => _userInfoSignal.value;

  /// 获取用户状态信号（用于监听）
  Signal<UserStatus> get statusSignal => _statusSignal;

  /// 获取 Token 信号（用于监听）
  Signal<String?> get tokenSignal => _tokenSignal;

  /// 获取用户信息信号（用于监听）
  Signal<UserInfo?> get userInfoSignal => _userInfoSignal;

  // ==================== 初始化 ====================

  /// 初始化 - 从持久化加载数据
  Future<void> _init() async {
    await _loadFromStorage();
  }

  /// 从持久化加载数据
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userInfoJson = prefs.getString(_userInfoKey);

      if (token != null && token.isNotEmpty) {
        _tokenSignal.value = token;
        if (userInfoJson != null) {
          final userInfoMap = UserInfo.fromJson(jsonDecode(userInfoJson));
          _userInfoSignal.value = userInfoMap;
          _statusSignal.value = UserStatus.authorized;
        }
      }
    } catch (e) {
      // _errorSignal.value = '加载用户数据失败：$e';
      print(e);
      _statusSignal.value = UserStatus.unauthorized;
    }
  }

  // ==================== Actions ====================

  /// 登录
  ///
  /// [username] 用户名
  /// [password] 密码
  /// [remember] 是否记住登录状态（持久化）
  Future<bool> login({required String token}) async {
    _statusSignal.value = UserStatus.loggingIn;

    try {
      // 更新状态
      _tokenSignal.value = token;
      _statusSignal.value = UserStatus.authorized;

      return true;
    } catch (e) {
      _statusSignal.value = UserStatus.unauthorized;
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    FieldSession.instance.clear();
    _statusSignal.value = UserStatus.loggingOut;
    try {
      await _clearStorage();
      // 清除状态
      _tokenSignal.value = null;
      _userInfoSignal.value = null;
      _statusSignal.value = UserStatus.unauthorized;
      // 清空路由栈并重定向到登录页
      appRouter.go('/login');
    } catch (e) {
      _statusSignal.value = UserStatus.unauthorized;
    }
  }

  /// 更新用户信息
  Future<void> updateUserInfo(UserInfo userInfo) async {
    _userInfoSignal.value = userInfo;
    await _saveToStorage(_tokenSignal.value ?? '', userInfo);
  }

  // ==================== 持久化 ====================

  /// 保存到持久化
  Future<void> _saveToStorage(String token, UserInfo userInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userInfoKey, jsonEncode(userInfo.toJson()));
    } catch (e) {
      // _errorSignal.value = '保存数据失败：$e';
      print(e);
    }
  }

  /// 清除持久化数据
  Future<void> _clearStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userInfoKey);
    } catch (e) {
      print(e);
    }
  }

  // ==================== 重置 ====================

  /// 重置所有状态（用于测试）
  void reset() {
    FieldSession.instance.clear();
    _statusSignal.value = UserStatus.unauthorized;
    _tokenSignal.value = null;
    _userInfoSignal.value = null;
  }
}

// ==================== Hooks 辅助函数 ====================

/// 在 HookWidget 中获取 userStore
///
/// 使用示例:
/// ```dart
/// class MyWidget extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final userStore = useUserStore();
///     final token = userStore.token;
///     final isLoggedIn = userStore.isLoggedIn;
///     // ...
///   }
/// }
/// ```
UserStore useUserStore() {
  return UserStore.instance;
}

/// 监听是否已登录
///
/// 当登录状态变化时自动触发组件重建
bool useIsLoggedIn() {
  return useSignalValue(UserStore.isLoggedIn);
}

/// 监听用户信息
///
/// 当用户信息变化时自动触发组件重建
UserInfo? useUserInfo() {
  return useSignalValue(UserStore.instance.userInfoSignal);
}

/// 监听 Token
///
/// 当 Token 变化时自动触发组件重建
String? useUserToken() {
  return useSignalValue(UserStore.instance.tokenSignal);
}

/// 监听用户状态
///
/// 当用户状态变化时自动触发组件重建
UserStatus useUserStatus() {
  return useSignalValue(UserStore.instance.statusSignal);
}
