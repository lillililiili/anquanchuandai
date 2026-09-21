import '../models/user_model.dart';

/// 用户数据仓库
///
/// 负责数据获取、缓存策略、错误处理
/// ViewModel 通过 Repository 获取数据，不直接访问 API
class UserRepository {
  /// 单例实例
  static final UserRepository instance = UserRepository._internal();

  UserRepository._internal();

  /// 模拟数据 - 实际项目中替换为真实 API
  final List<UserModel> _mockUsers = [
    UserModel(
      id: 1,
      name: '张三',
      email: 'zhangsan@example.com',
      phone: '13800138001',
      department: '技术部',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
    UserModel(
      id: 2,
      name: '李四',
      email: 'lisi@example.com',
      phone: '13800138002',
      department: '产品部',
      createdAt: DateTime.now().subtract(const Duration(days: 25)),
    ),
    UserModel(
      id: 3,
      name: '王五',
      email: 'wangwu@example.com',
      phone: '13800138003',
      department: '设计部',
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
    ),
    UserModel(
      id: 4,
      name: '赵六',
      email: 'zhaoliu@example.com',
      phone: '13800138004',
      department: '运营部',
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
    ),
    UserModel(
      id: 5,
      name: '孙七',
      email: 'sunqi@example.com',
      phone: '13800138005',
      department: '市场部',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
  ];

  /// 获取用户列表（支持分页）
  ///
  /// [page] 页码，从 1 开始
  /// [pageSize] 每页数量
  /// [keyword] 搜索关键词（可选）
  Future<UserListResult> getUserList({
    int page = 1,
    int pageSize = 10,
    String? keyword,
  }) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      // 实际项目中替换为真实 API 调用
      // final response = await http.request(
      //   ReqOptions(
      //     path: '/api/users',
      //     method: 'GET',
      //     params: {
      //       'page': page,
      //       'pageSize': pageSize,
      //       'keyword': keyword,
      //     },
      //   ),
      // );
      // final page = DataPage.fromJson(response, UserModel.fromJson);
      // return UserListResult(
      //   users: page.records,
      //   total: page.total,
      //   hasMore: page.records.length >= pageSize,
      // );

      // 模拟数据处理
      var filteredUsers = _mockUsers;
      if (keyword != null && keyword.isNotEmpty) {
        filteredUsers = _mockUsers
            .where((u) =>
                u.name.contains(keyword) || u.email.contains(keyword))
            .toList();
      }

      final startIndex = (page - 1) * pageSize;
      final endIndex = startIndex + pageSize;
      final paginatedUsers = filteredUsers
          .sublist(
            startIndex.clamp(0, filteredUsers.length),
            endIndex.clamp(0, filteredUsers.length),
          )
          .toList();

      return UserListResult(
        users: paginatedUsers,
        total: filteredUsers.length,
        hasMore: endIndex < filteredUsers.length,
      );
    } catch (e) {
      throw UserRepositoryException('获取用户列表失败: $e');
    }
  }

  /// 获取用户详情
  Future<UserModel> getUserById(int id) async {
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // 实际项目中替换为真实 API 调用
      // final response = await http.request(
      //   ReqOptions(path: '/api/users/$id', method: 'GET'),
      // );
      // return UserModel.fromJson(response as Map<String, dynamic>);

      final user = _mockUsers.firstWhere(
        (u) => u.id == id,
        orElse: () => throw UserRepositoryException('用户不存在'),
      );
      return user;
    } catch (e) {
      if (e is UserRepositoryException) rethrow;
      throw UserRepositoryException('获取用户详情失败: $e');
    }
  }

  /// 创建用户
  Future<UserModel> createUser(UserModel user) async {
    await Future.delayed(const Duration(milliseconds: 1000));

    try {
      // 实际项目中替换为真实 API 调用
      // final response = await http.request(
      //   ReqOptions(
      //     path: '/api/users',
      //     method: 'POST',
      //     data: user.toJson(),
      //   ),
      // );
      // return UserModel.fromJson(response as Map<String, dynamic>);

      final newUser = user.copyWith(
        id: _mockUsers.length + 1,
        createdAt: DateTime.now(),
      );
      _mockUsers.add(newUser);
      return newUser;
    } catch (e) {
      throw UserRepositoryException('创建用户失败: $e');
    }
  }

  /// 更新用户
  Future<UserModel> updateUser(UserModel user) async {
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      // 实际项目中替换为真实 API 调用
      // final response = await http.request(
      //   ReqOptions(
      //     path: '/api/users/${user.id}',
      //     method: 'PUT',
      //     data: user.toJson(),
      //   ),
      // );
      // return UserModel.fromJson(response as Map<String, dynamic>);

      final index = _mockUsers.indexWhere((u) => u.id == user.id);
      if (index == -1) {
        throw UserRepositoryException('用户不存在');
      }
      _mockUsers[index] = user;
      return user;
    } catch (e) {
      if (e is UserRepositoryException) rethrow;
      throw UserRepositoryException('更新用户失败: $e');
    }
  }

  /// 删除用户
  Future<void> deleteUser(int id) async {
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      // 实际项目中替换为真实 API 调用
      // await http.request(
      //   ReqOptions(path: '/api/users/$id', method: 'DELETE'),
      // );

      final index = _mockUsers.indexWhere((u) => u.id == id);
      if (index == -1) {
        throw UserRepositoryException('用户不存在');
      }
      _mockUsers.removeAt(index);
    } catch (e) {
      if (e is UserRepositoryException) rethrow;
      throw UserRepositoryException('删除用户失败: $e');
    }
  }
}

/// 用户列表结果
class UserListResult {
  final List<UserModel> users;
  final int total;
  final bool hasMore;

  UserListResult({
    required this.users,
    required this.total,
    required this.hasMore,
  });
}

/// 用户仓库异常
class UserRepositoryException implements Exception {
  final String message;

  UserRepositoryException(this.message);

  @override
  String toString() => 'UserRepositoryException: $message';
}
