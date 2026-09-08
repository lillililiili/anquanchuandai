import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/api/system.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import '../../hooks/use_theme.dart';
import '../../components/dept_tree_picker.dart';
import '../../theme/theme.dart';
import '../../theme/theme_signal.dart';
import '../../models/user.dart';
import '../../models/dept.dart';

/// 选择模式
enum SelectionMode {
  /// 单选
  single,

  /// 多选
  multiple,
}

/// 人员选择页面
class PersonSelectPage extends HookWidget {
  /// 选择模式，默认为多选
  final SelectionMode selectionMode;
  final String? personName;
  final bool? autoSelect;

  const PersonSelectPage({
    super.key,
    this.selectionMode = SelectionMode.single,
    this.personName,
    this.autoSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final selectedPersons = useState<Set<String>>({});
    final searchText = useState('');
    final selectedDept = useState<DeptTree?>(null);

    // 用户列表分页状态
    final currentPage = useState(1);
    final pageSize = 20;
    final hasMore = useState(true);
    final allUsers = useState<List<UserInfo>>([]);
    final isLoading = useState(false);
    final isLoadingMore = useState(false);
    final errorMsg = useState<String?>(null);

    // 刷新控制器
    final easyRefreshController = useMemoized(() => EasyRefreshController());

    // 加载用户数据函数
    final personContext = context;

    Future<void> loadUsers({
      required int current,
      required int size,
      String? nickName,
      String? deptName,
      bool isRefresh = false,
    }) async {
      try {
        if (isRefresh) {
          isLoading.value = true;
        } else {
          isLoadingMore.value = true;
        }
        errorMsg.value = null;

        final result = await SystemApi.getUserList(
          current: current,
          size: size,
          nickName: nickName,
          deptName: deptName,
        );

        if (!personContext.mounted) return;

        if (result.records == null || result.records!.isEmpty) {
          if (isRefresh) {
            allUsers.value = [];
          }
          hasMore.value = false;
          return;
        }

        if (isRefresh) {
          allUsers.value = result.records!;
        } else {
          allUsers.value = [...allUsers.value, ...result.records!];
        }

        hasMore.value = allUsers.value.length < (result.total ?? 0);
      } catch (e) {
        if (!personContext.mounted) return;
        errorMsg.value = e.toString();
        if (isRefresh) {
          allUsers.value = [];
        }
      } finally {
        if (personContext.mounted) {
          isLoading.value = false;
          isLoadingMore.value = false;
        }
      }
    }

    // 首次加载
    useEffect(() {
      loadUsers(
        current: 1,
        size: pageSize,
        isRefresh: true,
        nickName: personName,
      ).then((_) {
        // 自动选中逻辑
        if (autoSelect == true && personName != null) {
          AppLogger.i(
            'PersonSelectPage: autoSelect enabled, trying to match personName "$personName"',
          );

          UserInfo? matchedUser = allUsers.value
              .where(
                (u) => u.nickName == personName || u.userName == personName,
              )
              .firstOrNull;
          if (matchedUser != null) {
            AppLogger.i(
              'PersonSelectPage: autoSelect enabled, trying to match personName "$matchedUser"',
            );

            Navigator.of(context).pop(matchedUser);
          } else {
            Navigator.of(context).pop(null);
          }
        }
      });
      return null;
    }, []);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, theme),
      body: Column(
        children: [
          const SizedBox(height: AppSpacing.lg),
          // 搜索栏
          _buildSearchBar(
            theme: theme,
            searchText: searchText,
            selectedDept: selectedDept,
            onShowDeptPicker: () =>
                _showDeptPicker(context, theme, selectedDept, () {
                  currentPage.value = 1;
                  easyRefreshController.callRefresh();
                }),
            onSearch: () {
              currentPage.value = 1;
              easyRefreshController.callRefresh();
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          // 人员列表
          Expanded(
            child: EasyRefresh(
              controller: easyRefreshController,
              header: const ClassicHeader(
                dragText: '下拉刷新',
                readyText: '释放刷新',
                processingText: '刷新中...',
                processedText: '刷新成功',
                failedText: '刷新失败',
              ),
              footer: ClassicFooter(
                dragText: '上拉加载',
                readyText: '释放加载',
                processingText: '加载中...',
                processedText: '加载成功',
                failedText: '加载失败',
                noMoreText: '没有更多了',
              ),
              onRefresh: () async {
                currentPage.value = 1;
                await loadUsers(
                  current: 1,
                  size: pageSize,
                  nickName: searchText.value.isEmpty ? null : searchText.value,
                  deptName: selectedDept.value?.label,
                  isRefresh: true,
                );
              },
              onLoad: () async {
                if (hasMore.value && !isLoadingMore.value) {
                  currentPage.value++;
                  await loadUsers(
                    current: currentPage.value,
                    size: pageSize,
                    nickName: searchText.value.isEmpty
                        ? null
                        : searchText.value,
                    deptName: selectedDept.value?.label,
                  );
                }
              },
              child: _buildUserList(
                theme,
                allUsers.value,
                selectedPersons,
                isLoading.value,
                isLoadingMore.value,
                errorMsg.value,
                () => easyRefreshController.callRefresh(),
                selectionMode,
              ),
            ),
          ),
          // 底部下一步按钮
          _buildBottomButton(
            context,
            theme,
            selectedPersons,
            selectionMode,
            allUsers.value,
          ),
        ],
      ),
    );
  }

  /// 显示部门选择器弹窗
  void _showDeptPicker(
    BuildContext context,
    ThemeColors theme,
    ValueNotifier<DeptTree?> selectedDept,
    VoidCallback onConfirm,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeptPickerContent(
        theme: theme,
        selectedDept: selectedDept,
        onConfirm: onConfirm,
      ),
    );
  }

  Widget _buildUserList(
    ThemeColors theme,
    List<UserInfo> users,
    ValueNotifier<Set<String>> selectedPersons,
    bool isLoading,
    bool isLoadingMore,
    String? errorMsg,
    VoidCallback? onRetry,
    SelectionMode selectionMode,
  ) {
    if (isLoading && users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMsg != null && users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '加载失败：$errorMsg',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }

    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '暂无用户数据',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: users.length,
          itemBuilder: (context, index) {
            final person = users[index];
            return _PersonListItem(
              person: person,
              theme: theme,
              isSelected: selectedPersons.value.contains(person.userId),
              selectionMode: selectionMode,
              onSelected: (selected) {
                final newSet = Set<String>.from(selectedPersons.value);
                if (selectionMode == SelectionMode.single) {
                  // 单选模式：清除其他选中项，只保留当前
                  newSet.clear();
                  newSet.add(person.userId);
                } else {
                  // 多选模式：切换选中状态
                  if (selected) {
                    newSet.add(person.userId);
                  } else {
                    newSet.remove(person.userId);
                  }
                }
                selectedPersons.value = newSet;
              },
            );
          },
        ),
        // 加载更多提示
        if (isLoadingMore)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              color: theme.cardBackground,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeColors theme) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: SpringColors.mintGreen.withValues(alpha: 0.15),
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
        '选择人员',
        style: AppTypography.headlineMedium.copyWith(
          color: theme.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildSearchBar({
    required ThemeColors theme,
    required ValueNotifier<String> searchText,
    required ValueNotifier<DeptTree?> selectedDept,
    VoidCallback? onShowDeptPicker,
    VoidCallback? onSearch,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.light,
      ),
      child: Row(
        children: [
          // 部门选择按钮
          GestureDetector(
            onTap: onShowDeptPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_tree,
                    size: 18,
                    color: selectedDept.value != null
                        ? SpringColors.mintGreen
                        : theme.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 80,
                    child: Text(
                      selectedDept.value?.label ?? '部门',
                      style: TextStyle(
                        fontSize: 13,
                        color: selectedDept.value != null
                            ? SpringColors.mintGreen
                            : theme.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 分割线
          Container(width: 1, height: 24, color: theme.divider),
          // 搜索输入框
          Expanded(
            child: TextField(
              onChanged: (value) => searchText.value = value,
              onSubmitted: (_) => onSearch?.call(),
              decoration: InputDecoration(
                hintText: '搜索人员',
                hintStyle: TextStyle(fontSize: 14, color: theme.textTertiary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ),
              style: TextStyle(fontSize: 14, color: theme.textPrimary),
            ),
          ),
          // 搜索按钮
          GestureDetector(
            onTap: onSearch,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: const Icon(
                Icons.arrow_forward,
                size: 20,
                color: SpringColors.mintGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton(
    BuildContext context,
    ThemeColors theme,
    ValueNotifier<Set<String>> selectedPersons,
    SelectionMode selectionMode,
    List<UserInfo> users,
  ) {
    final selectedCount = selectedPersons.value.length;
    final isEnabled = selectedCount > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: isEnabled
            ? () {
                if (selectionMode == SelectionMode.single) {
                  // 单选模式：返回选中的 UserInfo 对象
                  final selectedUserId = selectedPersons.value.first;
                  final selectedUser = users.firstWhere(
                    (u) => u.userId == selectedUserId,
                  );
                  Navigator.of(context).pop(selectedUser);
                } else {
                  // 多选模式：返回 Set
                  Navigator.of(context).pop(selectedPersons.value);
                }
              }
            : null,
        child: AnimatedScale(
          scale: isEnabled ? 1 : 0.98,
          duration: AppSpacing.pressDuration,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: isEnabled
                  ? const LinearGradient(
                      colors: [SpringColors.skyBlue, Color(0xFF2563EB)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: isEnabled
                  ? null
                  : (theme.isDark ? Colors.grey[700] : Colors.grey[300]),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: SpringColors.skyBlue.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isEnabled && selectionMode == SelectionMode.multiple)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    selectionMode == SelectionMode.single ? '确认' : '下一步',
                    style: AppTypography.button.copyWith(
                      color: isEnabled ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 部门选择器内容组件 ====================
class _DeptPickerContent extends HookWidget {
  final ThemeColors theme;
  final ValueNotifier<DeptTree?> selectedDept;
  final VoidCallback? onConfirm;

  const _DeptPickerContent({
    required this.theme,
    required this.selectedDept,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: double.infinity,
      height: screenHeight * 0.85,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLarge),
        ),
      ),
      child: Column(
        children: [
          // 顶部标题栏
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '选择部门',
                    style: AppTypography.title.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: Colors.white24,
                  ),
                ),
              ],
            ),
          ),
          // 分割线
          Container(height: 1, color: theme.divider),
          // 部门树 - 可滚动
          Expanded(
            child: DeptTreePicker(
              initialDeptId: selectedDept.value?.id,
              onSelected: (dept) {
                selectedDept.value = dept;
              },
            ),
          ),
          // 分割线
          Container(height: 1, color: theme.divider),
          // 底部按钮
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 清空按钮
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      selectedDept.value = null;
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardBackground,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                        border: Border.all(color: theme.divider, width: 1),
                      ),
                      child: const Center(
                        child: Text(
                          '清空',
                          style: TextStyle(
                            fontSize: 14,
                            color: SpringColors.cherryRed,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 确认按钮
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pop();
                      onConfirm?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [SpringColors.skyBlue, Color(0xFF2563EB)],
                        ),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMedium,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '确认',
                          style: AppTypography.button.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 人员列表项 ====================
class _PersonListItem extends HookWidget {
  final UserInfo person;
  final ThemeColors theme;
  final bool isSelected;
  final Function(bool) onSelected;
  final SelectionMode selectionMode;

  const _PersonListItem({
    required this.person,
    required this.theme,
    required this.isSelected,
    required this.onSelected,
    this.selectionMode = SelectionMode.multiple,
  });

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final primaryColor = SpringColors.mintGreen;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.3)
              : (theme.isDark
                    ? const Color(0x0DFFFFFF)
                    : const Color(0x0A000000)),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: AppShadows.light,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          onTap: () {
            if (selectionMode == SelectionMode.single) {
              // 单选模式：直接选中当前项（传入 true）
              onSelected(true);
            } else {
              // 多选模式：切换选中状态
              onSelected(!isSelected);
            }
          },
          onTapDown: (_) => isPressed.value = true,
          onTapUp: (_) => isPressed.value = false,
          onTapCancel: () => isPressed.value = false,
          child: AnimatedScale(
            scale: isPressed.value ? AppSpacing.pressScale : 1,
            duration: AppSpacing.pressDuration,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  // 头像
                  AnimatedContainer(
                    duration: AppSpacing.pressDuration,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? SpringColors.skyBlue.withValues(alpha: 0.15)
                          : SpringColors.skyBlue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 24,
                      color: SpringColors.skyBlue,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  // 人员信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              person.nickName.isNotEmpty
                                  ? person.nickName
                                  : person.userName,
                              style: AppTypography.body.copyWith(
                                color: theme.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            // 在线状态
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SpringColors.mintGreen.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: SpringColors.mintGreen,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '在线',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: SpringColors.mintGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '${person.phonenumber} · ${person.deptId}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // 选择指示器（单选/多选）
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.elasticOut,
                    switchOutCurve: Curves.easeIn,
                    child: selectionMode == SelectionMode.single
                        // 单选模式：圆形单选按钮
                        ? Container(
                            key: const ValueKey('single'),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? SpringColors.skyBlue
                                    : (theme.isDark
                                          ? Colors.white38
                                          : Colors.black38),
                                width: 2,
                              ),
                              color: isSelected
                                  ? SpringColors.skyBlue.withValues(alpha: 0.1)
                                  : Colors.transparent,
                            ),
                            child: isSelected
                                ? const Center(
                                    child: Icon(
                                      Icons.check,
                                      size: 14,
                                      color: SpringColors.skyBlue,
                                    ),
                                  )
                                : null,
                          )
                        // 多选模式：方形复选框
                        : isSelected
                        ? Container(
                            key: const ValueKey('selected'),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  SpringColors.skyBlue,
                                  Color(0xFF2563EB),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          )
                        : Container(
                            key: const ValueKey('unselected'),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.isDark
                                    ? Colors.white38
                                    : Colors.black38,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.transparent,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
