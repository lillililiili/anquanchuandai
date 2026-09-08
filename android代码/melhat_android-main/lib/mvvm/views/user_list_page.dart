import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_theme.dart';
import 'package:rolling_intelligence_headband/theme/theme.dart';
import 'package:signals_hooks/signals_hooks.dart';
import '../models/user_model.dart';
import '../viewmodels/user_list_viewmodel.dart';

/// 用户列表页面
///
/// MVVM 架构示例：
/// - View 只负责 UI 渲染
/// - ViewModel 管理页面状态
/// - Repository 负责数据获取
class UserListPage extends HookWidget {
  const UserListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    // 1. 创建 ViewModel（使用 useMemoized 避免重复创建）
    // 页面切换时 ViewModel 会保持状态，直到页面被销毁
    final viewModel = useMemoized(() => UserListViewModel());

    // 2. 页面销毁时释放资源
    useEffect(() {
      return viewModel.dispose;
    }, []);

    // 3. 监听状态变化
    final users = useSignalValue(viewModel.usersSignal);
    final isLoading = useSignalValue(viewModel.isLoadingSignal);
    final error = useSignalValue(viewModel.errorSignal);
    final total = useSignalValue(viewModel.totalSignal);
    final isEmpty = useSignalValue(viewModel.isEmpty);
    final isFirstLoad = useSignalValue(viewModel.isFirstLoad);

    // 4. 首次加载数据
    useEffect(() {
      viewModel.loadUsers(forceRefresh: true);
      return null;
    }, []);

    // 5. 滚动控制器（用于下拉刷新和上拉加载更多）
    final scrollController = useScrollController();

    // 监听滚动到底部，加载更多
    useEffect(() {
      void onScroll() {
        if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 200) {
          viewModel.loadMore();
        }
      }

      scrollController.addListener(onScroll);
      return () => scrollController.removeListener(onScroll);
    }, [scrollController]);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme, viewModel, total),
      body: _buildBody(
        context,
        theme,
        viewModel,
        users,
        isLoading,
        error,
        isEmpty,
        isFirstLoad,
        scrollController,
        total,
      ),
    );
  }

  /// 构建 AppBar
  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeColors theme,
    UserListViewModel viewModel,
    int total,
  ) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: SpringColors.mintGreen.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            size: 18,
            color: SpringColors.mintGreen,
          ),
        ),
      ),
      title: Text(
        '用户列表 (MVVM 示例)',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
      actions: [
        // 刷新按钮
        IconButton(
          onPressed: () => viewModel.refresh(),
          icon: Icon(
            Icons.refresh,
            color: theme.textPrimary,
          ),
        ),
        // 添加按钮
        IconButton(
          onPressed: () => _showAddUserDialog(context, viewModel),
          icon: Icon(
            Icons.add,
            color: theme.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 构建主体内容
  Widget _buildBody(
    BuildContext context,
    ThemeColors theme,
    UserListViewModel viewModel,
    List<UserModel> users,
    bool isLoading,
    String? error,
    bool isEmpty,
    bool isFirstLoad,
    ScrollController scrollController,
    int total,
  ) {
    return Column(
      children: [
        // 搜索栏
        _buildSearchBar(theme, viewModel),

        // 统计信息
        _buildStatsBar(theme, total, users.length),

        // 列表内容
        Expanded(
          child: _buildContent(
            context,
            theme,
            viewModel,
            users,
            isLoading,
            error,
            isEmpty,
            isFirstLoad,
            scrollController,
          ),
        ),
      ],
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar(ThemeColors theme, UserListViewModel viewModel) {
    final keyword = useSignalValue(viewModel.keywordSignal);

    return Container(
      margin: AppSpacing.cardMargin,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        boxShadow: AppShadows.light,
      ),
      child: TextField(
        onChanged: (value) => viewModel.search(value),
        decoration: InputDecoration(
          hintText: '搜索用户...',
          prefixIcon: Icon(Icons.search, color: theme.textTertiary),
          suffixIcon: keyword != null && keyword.isNotEmpty
              ? IconButton(
                  onPressed: () => viewModel.clearSearch(),
                  icon: Icon(Icons.clear, color: theme.textTertiary),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),
        style: TextStyle(color: theme.textPrimary),
      ),
    );
  }

  /// 构建统计信息
  Widget _buildStatsBar(ThemeColors theme, int total, int currentCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '共 $total 人',
            style: TextStyle(
              fontSize: 13,
              color: theme.textTertiary,
            ),
          ),
          const Spacer(),
          Text(
            '已加载 $currentCount 条',
            style: TextStyle(
              fontSize: 13,
              color: theme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建内容区域
  Widget _buildContent(
    BuildContext context,
    ThemeColors theme,
    UserListViewModel viewModel,
    List<UserModel> users,
    bool isLoading,
    String? error,
    bool isEmpty,
    bool isFirstLoad,
    ScrollController scrollController,
  ) {
    // 首次加载中
    if (isFirstLoad) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(SpringColors.mintGreen),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '加载中...',
              style: TextStyle(color: theme.textSecondary),
            ),
          ],
        ),
      );
    }

    // 错误状态
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: SpringColors.cherryRed.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '加载失败',
              style: AppTypography.title.copyWith(color: theme.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              error,
              style: TextStyle(color: theme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => viewModel.refresh(),
              style: ElevatedButton.styleFrom(
                backgroundColor: SpringColors.mintGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 空状态
    if (isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: theme.textTertiary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '暂无数据',
              style: AppTypography.title.copyWith(color: theme.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '点击右上角 + 添加用户',
              style: TextStyle(color: theme.textSecondary),
            ),
          ],
        ),
      );
    }

    // 用户列表
    return RefreshIndicator(
      onRefresh: () => viewModel.refresh(),
      color: SpringColors.mintGreen,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: users.length + (viewModel.hasMoreSignal.value ? 1 : 0),
        itemBuilder: (context, index) {
          // 加载更多指示器
          if (index == users.length) {
            return _buildLoadMoreIndicator(theme, viewModel.isLoadingSignal.value);
          }

          final user = users[index];
          return _UserListTile(
            user: user,
            theme: theme,
            onTap: () => _showUserDetail(context, user, viewModel),
            onDelete: () => _showDeleteConfirm(context, user, viewModel),
          );
        },
      ),
    );
  }

  /// 构建加载更多指示器
  Widget _buildLoadMoreIndicator(ThemeColors theme, bool isLoading) {
    if (!isLoading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(SpringColors.mintGreen),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '加载中...',
              style: TextStyle(color: theme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示添加用户对话框
  void _showAddUserDialog(BuildContext context, UserListViewModel viewModel) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加用户'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '姓名',
                hintText: '请输入姓名',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: '邮箱',
                hintText: '请输入邮箱',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: '电话',
                hintText: '请输入电话',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty &&
                  emailController.text.isNotEmpty) {
                final user = UserModel(
                  id: 0,
                  name: nameController.text,
                  email: emailController.text,
                  phone: phoneController.text,
                );
                await viewModel.createUser(user);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 显示用户详情
  void _showUserDetail(
    BuildContext context,
    UserModel user,
    UserListViewModel viewModel,
  ) {
    viewModel.selectUser(user);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            child: _UserDetailContent(
              user: user,
              viewModel: viewModel,
            ),
          );
        },
      ),
    );
  }

  /// 显示删除确认对话框
  void _showDeleteConfirm(
    BuildContext context,
    UserModel user,
    UserListViewModel viewModel,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除用户 ${user.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await viewModel.deleteUser(user.id);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: SpringColors.cherryRed,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 用户列表项
class _UserListTile extends StatelessWidget {
  final UserModel user;
  final ThemeColors theme;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _UserListTile({
    required this.user,
    required this.theme,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        boxShadow: AppShadows.light,
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: SpringColors.mintGreen.withValues(alpha: 0.2),
          child: Text(
            user.name.isNotEmpty ? user.name[0] : '?',
            style: const TextStyle(
              color: SpringColors.mintGreen,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          user.name,
          style: AppTypography.title.copyWith(
            color: theme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          user.email,
          style: TextStyle(
            fontSize: 13,
            color: theme.textSecondary,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: AppSpacing.sm),
                  Text('删除'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 用户详情内容
class _UserDetailContent extends StatelessWidget {
  final UserModel user;
  final UserListViewModel viewModel;

  const _UserDetailContent({
    required this.user,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPaddingLarge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 用户头像
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: SpringColors.mintGreen.withValues(alpha: 0.2),
              child: Text(
                user.name.isNotEmpty ? user.name[0] : '?',
                style: const TextStyle(
                  fontSize: 36,
                  color: SpringColors.mintGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // 用户名
          Center(
            child: Text(
              user.name,
              style: AppTypography.headlineMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 详情信息
          _DetailItem(
            icon: Icons.email_outlined,
            label: '邮箱',
            value: user.email,
          ),
          const SizedBox(height: AppSpacing.md),

          _DetailItem(
            icon: Icons.phone_outlined,
            label: '电话',
            value: user.phone ?? '未设置',
          ),
          const SizedBox(height: AppSpacing.md),

          _DetailItem(
            icon: Icons.business_outlined,
            label: '部门',
            value: user.department ?? '未设置',
          ),
          const SizedBox(height: AppSpacing.md),

          _DetailItem(
            icon: Icons.calendar_today_outlined,
            label: '创建时间',
            value: user.createdAt?.toString().split(' ')[0] ?? '未知',
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// 详情项
class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.textTertiary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$label: ',
          style: TextStyle(
            color: theme.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: theme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
