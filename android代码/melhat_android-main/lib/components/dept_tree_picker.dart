import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../api/system.dart';
import '../../hooks/use_theme.dart';
import '../../hooks/use_skeleton.dart';
import '../../theme/theme.dart';
import '../../theme/theme_signal.dart';
import '../../components/skeleton_view.dart';
import '../../models/dept.dart';

/// 部门树选择器组件
///
/// 展示树形部门列表，支持单选
/// [onSelected] 选择部门的回调
/// [initialDeptId] 初始选中的部门 ID
class DeptTreePicker extends HookWidget {
  final Function(DeptTree)? onSelected;
  final String? initialDeptId;

  const DeptTreePicker({super.key, this.onSelected, this.initialDeptId});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final selectedDeptId = useState<String?>(initialDeptId);
    final expandedNodeIds = useState<Set<String>>({});

    // 加载部门树
    final skeleton = useSkeleton<List<DeptTree>>(
      emptyMsg: '暂无部门数据',
      isEmpty: (data) => data.isEmpty,
      request: () async => await SystemApi.getDeptTree(),
    );

    return SkeletonView.fromHook(
      skeleton,
      (data) =>
          _buildDeptTree(context, theme, data, selectedDeptId, expandedNodeIds),
    );
  }

  Widget _buildDeptTree(
    BuildContext context,
    ThemeColors theme,
    List<DeptTree> depts,
    ValueNotifier<String?> selectedDeptId,
    ValueNotifier<Set<String>> expandedNodeIds,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: depts.length,
      itemBuilder: (context, index) {
        return _DeptTreeNode(
          dept: depts[index],
          theme: theme,
          selectedDeptId: selectedDeptId,
          expandedNodeIds: expandedNodeIds,
          onSelected: (dept) {
            selectedDeptId.value = dept.id;
            onSelected?.call(dept);
          },
          onToggleExpand: (deptId) {
            final Set<String> newExpanded = Set.from(expandedNodeIds.value);
            if (newExpanded.contains(deptId)) {
              newExpanded.remove(deptId);
            } else {
              newExpanded.add(deptId);
            }
            expandedNodeIds.value = newExpanded;
          },
        );
      },
    );
  }
}

// ==================== 部门树节点 ====================
class _DeptTreeNode extends HookWidget {
  final DeptTree dept;
  final ThemeColors theme;
  final ValueNotifier<String?> selectedDeptId;
  final ValueNotifier<Set<String>> expandedNodeIds;
  final Function(DeptTree) onSelected;
  final Function(String) onToggleExpand;
  final int indentLevel;

  const _DeptTreeNode({
    required this.dept,
    required this.theme,
    required this.selectedDeptId,
    required this.expandedNodeIds,
    required this.onSelected,
    required this.onToggleExpand,
    this.indentLevel = 0,
  });

  bool get hasChildren => dept.children != null && dept.children!.isNotEmpty;
  bool get isExpanded => expandedNodeIds.value.contains(dept.id);
  bool get isSelected => selectedDeptId.value == dept.id;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeptItem(context),
        // 渲染子节点
        if (hasChildren && isExpanded) ..._buildChildren(),
      ],
    );
  }

  Widget _buildDeptItem(BuildContext context) {
    final isPressed = useState(false);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(dept),
        onTapDown: (_) => isPressed.value = true,
        onTapUp: (_) => isPressed.value = false,
        onTapCancel: () => isPressed.value = false,
        child: AnimatedScale(
          scale: isPressed.value ? AppSpacing.pressScale : 1,
          duration: AppSpacing.pressDuration,
          child: Container(
            padding: EdgeInsets.only(
              left: AppSpacing.md + (indentLevel * AppSpacing.lg),
              right: AppSpacing.md,
              top: AppSpacing.sm,
              bottom: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? SpringColors.mintGreen.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                // 展开/折叠图标
                SizedBox(
                  width: 24,
                  height: 24,
                  child: hasChildren
                      ? GestureDetector(
                          onTap: () => onToggleExpand(dept.id),
                          child: AnimatedRotation(
                            turns: isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: theme.textSecondary,
                            ),
                          ),
                        )
                      : const SizedBox(width: 24),
                ),
                const SizedBox(width: AppSpacing.xs),
                // 部门名称
                Expanded(
                  child: Text(
                    dept.label,
                    style: AppTypography.body.copyWith(
                      color: isSelected
                          ? SpringColors.mintGreen
                          : theme.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 选中状态
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    size: 18,
                    color: SpringColors.mintGreen,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChildren() {
    return dept.children!
        .whereType<DeptTree>()
        .map(
          (child) => _DeptTreeNode(
            dept: child,
            theme: theme,
            selectedDeptId: selectedDeptId,
            expandedNodeIds: expandedNodeIds,
            onSelected: onSelected,
            onToggleExpand: onToggleExpand,
            indentLevel: indentLevel + 1,
          ),
        )
        .toList();
  }
}
