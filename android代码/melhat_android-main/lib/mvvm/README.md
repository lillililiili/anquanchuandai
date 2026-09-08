# MVVM 架构示例

本示例展示了如何在 Flutter 中实现类似 Android ViewModel 的设计模式，使用 Signal 持有页面状态。

## 架构说明

```
lib/mvvm/
├── models/          # 数据模型层
│   └── user_model.dart
├── repositories/    # 数据仓库层（Repository）
│   └── user_repository.dart
├── viewmodels/      # ViewModel 层（使用 Signal 持有状态）
│   └── user_list_viewmodel.dart
└── views/           # 视图层（View）
    └── user_list_page.dart
```

## 核心特性

### 1. 页面级别 ViewModel
- 每个页面创建独立的 ViewModel 实例
- 页面切换时保持状态，不重新请求数据
- 页面销毁时自动释放资源

### 2. Signal 状态管理
```dart
// 在 ViewModel 中使用 Signal 持有数据
final usersSignal = Signal<List<UserModel>>([]);
final isLoadingSignal = Signal<bool>(false);
final errorSignal = Signal<String?>(null);

// 使用 Computed 派生状态
late final isEmpty = computed(() => usersSignal.value.isEmpty);
```

### 3. 缓存控制
```dart
// 缓存有效期（5分钟）
Duration get cacheDuration => const Duration(minutes: 5);

// 是否需要刷新
bool get needRefresh =>
    usersSignal.value.isEmpty ||
    _lastFetchTime == null ||
    DateTime.now().difference(_lastFetchTime!) > cacheDuration;

// 加载数据时判断是否需要刷新
Future<void> loadUsers({bool forceRefresh = false}) async {
  if (!forceRefresh && !needRefresh) return;
  // ... 请求数据
}
```

### 4. 分页加载
```dart
// 加载更多
Future<void> loadMore() async {
  if (!canLoadMore.value) return;
  _currentPage++;
  await loadUsers();
}
```

## 使用方法

### 1. 在路由中添加页面
```dart
// lib/router/app_router.dart
GoRoute(
  path: '/mvvm-demo',
  builder: (context, state) => const UserListPage(),
),
```

### 2. 导航到页面
```dart
context.push('/mvvm-demo');
```

### 3. 在 ViewModel 中使用
```dart
// 创建 ViewModel
final viewModel = useMemoized(() => UserListViewModel());

// 监听状态
final users = useSignalValue(viewModel.usersSignal);
final isLoading = useSignalValue(viewModel.isLoadingSignal);

// 加载数据
await viewModel.loadUsers(forceRefresh: true);

// 搜索
await viewModel.search('张三');

// 刷新
await viewModel.refresh();

// 加载更多
await viewModel.loadMore();
```

## 与 Android ViewModel 对比

| 特性 | Android ViewModel | Flutter MVVM |
|------|-------------------|--------------|
| 状态持有 | LiveData / StateFlow | Signal |
| 生命周期 | ViewModelScope | HookWidget 生命周期 |
| 数据缓存 | ViewModel 内存 | ViewModel 内存 + 时间控制 |
| 页面切换保持 | 自动保持 | useMemoized 自动保持 |
| 资源释放 | onCleared() | useEffect 返回 dispose |

## 扩展建议

1. **依赖注入**：使用 GetIt 或 Riverpod 管理 ViewModel 实例
2. **错误处理**：添加统一的错误处理和重试机制
3. **网络层**：集成 Dio 拦截器处理 Token 刷新
4. **持久化**：添加本地缓存（SharedPreferences / SQLite）
5. **单元测试**：为 ViewModel 和 Repository 编写测试用例
