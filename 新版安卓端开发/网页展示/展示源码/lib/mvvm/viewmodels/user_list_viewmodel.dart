import 'package:signals_hooks/signals_hooks.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

/// 用户列表 ViewModel
///
/// 使用 Signal 持有页面状态，支持：
/// 1. 页面切换时保持状态
/// 2. 缓存控制，避免重复请求
/// 3. 分页加载
/// 4. 搜索过滤
class UserListViewModel {
  /// Repository 实例
  final UserRepository _repository;

  /// 当前页码
  int _currentPage = 1;

  /// 每页数量
  final int _pageSize = 10;

  /// 最后一次获取数据的时间
  DateTime? _lastFetchTime;

  /// 缓存有效期（5分钟）
  Duration get cacheDuration => const Duration(minutes: 5);

  // ==================== Signal 定义 ====================

  /// 用户列表
  final usersSignal = Signal<List<UserModel>>([]);

  /// 加载状态
  final isLoadingSignal = Signal<bool>(false);

  /// 错误信息
  final errorSignal = Signal<String?>(null);

  /// 总数
  final totalSignal = Signal<int>(0);

  /// 是否还有更多数据
  final hasMoreSignal = Signal<bool>(true);

  /// 搜索关键词
  final keywordSignal = Signal<String?>('');

  /// 当前选中的用户（用于详情页）
  final selectedUserSignal = Signal<UserModel?>(null);

  // ==================== Computed 信号 ====================

  /// 是否为空
  late final isEmpty = computed(() => usersSignal.value.isEmpty);

  /// 是否首次加载
  late final isFirstLoad = computed(() =>
      usersSignal.value.isEmpty && isLoadingSignal.value && errorSignal.value == null);

  /// 是否可以加载更多
  late final canLoadMore = computed(() =>
      hasMoreSignal.value && !isLoadingSignal.value && errorSignal.value == null);

  /// 是否有搜索关键词
  late final hasSearchKeyword = computed(() =>
      keywordSignal.value != null && keywordSignal.value!.isNotEmpty);

  // ==================== 构造函数 ====================

  UserListViewModel({UserRepository? repository})
      : _repository = repository ?? UserRepository.instance;

  // ==================== 缓存控制 ====================

  /// 是否需要刷新
  bool get needRefresh =>
      usersSignal.value.isEmpty ||
      _lastFetchTime == null ||
      DateTime.now().difference(_lastFetchTime!) > cacheDuration;

  // ==================== 数据操作 ====================

  /// 加载用户列表
  ///
  /// [forceRefresh] 是否强制刷新
  /// [reset] 是否重置分页
  Future<void> loadUsers({
    bool forceRefresh = false,
    bool reset = false,
  }) async {
    // 如果不需要刷新，直接返回
    if (!forceRefresh && !needRefresh && !reset) {
      return;
    }

    // 如果是重置，清除当前数据
    if (reset) {
      _currentPage = 1;
      usersSignal.value = [];
      hasMoreSignal.value = true;
    }

    // 防止重复请求
    if (isLoadingSignal.value) return;

    isLoadingSignal.value = true;
    errorSignal.value = null;

    try {
      final result = await _repository.getUserList(
        page: _currentPage,
        pageSize: _pageSize,
        keyword: keywordSignal.value,
      );

      if (reset || _currentPage == 1) {
        usersSignal.value = result.users;
      } else {
        usersSignal.value = [...usersSignal.value, ...result.users];
      }

      totalSignal.value = result.total;
      hasMoreSignal.value = result.hasMore;
      _lastFetchTime = DateTime.now();
    } catch (e) {
      errorSignal.value = e.toString();
    } finally {
      isLoadingSignal.value = false;
    }
  }

  /// 加载更多（分页）
  Future<void> loadMore() async {
    if (!canLoadMore.value) return;

    _currentPage++;
    await loadUsers();
  }

  /// 刷新（强制）
  Future<void> refresh() async {
    _currentPage = 1;
    await loadUsers(forceRefresh: true);
  }

  /// 搜索用户
  Future<void> search(String? keyword) async {
    keywordSignal.value = keyword;
    _currentPage = 1;
    await loadUsers(forceRefresh: true, reset: true);
  }

  /// 清空搜索
  Future<void> clearSearch() async {
    keywordSignal.value = null;
    _currentPage = 1;
    await loadUsers(forceRefresh: true, reset: true);
  }

  /// 选中用户
  void selectUser(UserModel? user) {
    selectedUserSignal.value = user;
  }

  /// 获取用户详情
  Future<void> getUserById(int id) async {
    isLoadingSignal.value = true;
    errorSignal.value = null;

    try {
      final user = await _repository.getUserById(id);
      selectedUserSignal.value = user;
    } catch (e) {
      errorSignal.value = e.toString();
    } finally {
      isLoadingSignal.value = false;
    }
  }

  /// 创建用户
  Future<bool> createUser(UserModel user) async {
    isLoadingSignal.value = true;
    errorSignal.value = null;

    try {
      final newUser = await _repository.createUser(user);
      usersSignal.value = [newUser, ...usersSignal.value];
      totalSignal.value++;
      return true;
    } catch (e) {
      errorSignal.value = e.toString();
      return false;
    } finally {
      isLoadingSignal.value = false;
    }
  }

  /// 更新用户
  Future<bool> updateUser(UserModel user) async {
    isLoadingSignal.value = true;
    errorSignal.value = null;

    try {
      final updatedUser = await _repository.updateUser(user);
      final index = usersSignal.value.indexWhere((u) => u.id == user.id);
      if (index != -1) {
        final newList = List<UserModel>.from(usersSignal.value);
        newList[index] = updatedUser;
        usersSignal.value = newList;
      }
      return true;
    } catch (e) {
      errorSignal.value = e.toString();
      return false;
    } finally {
      isLoadingSignal.value = false;
    }
  }

  /// 删除用户
  Future<bool> deleteUser(int id) async {
    isLoadingSignal.value = true;
    errorSignal.value = null;

    try {
      await _repository.deleteUser(id);
      usersSignal.value = usersSignal.value.where((u) => u.id != id).toList();
      totalSignal.value--;
      return true;
    } catch (e) {
      errorSignal.value = e.toString();
      return false;
    } finally {
      isLoadingSignal.value = false;
    }
  }

  /// 重置状态（用于测试或页面销毁时）
  void reset() {
    _currentPage = 1;
    _lastFetchTime = null;
    usersSignal.value = [];
    isLoadingSignal.value = false;
    errorSignal.value = null;
    totalSignal.value = 0;
    hasMoreSignal.value = true;
    keywordSignal.value = '';
    selectedUserSignal.value = null;
  }

  /// 释放资源
  void dispose() {
    usersSignal.dispose();
    isLoadingSignal.dispose();
    errorSignal.dispose();
    totalSignal.dispose();
    hasMoreSignal.dispose();
    keywordSignal.dispose();
    selectedUserSignal.dispose();
  }
}
