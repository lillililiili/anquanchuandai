import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import '../../api/hat.dart';
import '../../components/pagination_list_view.dart';
import '../../hooks/use_pagination.dart';
import '../../hooks/use_theme.dart';
import '../../models/hat.dart';
import 'person_select.dart' show SelectionMode;

/// 安全帽选择页面
class HatSelectPage extends HookWidget {
  /// 选择模式，默认为单选
  final SelectionMode selectionMode;

  final String? personName;
  final List<String>? teamNames;
  final bool? autoSelect;

  const HatSelectPage({
    super.key,
    this.selectionMode = SelectionMode.single,
    this.personName,
    this.autoSelect,
    this.teamNames,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    // 搜索状态
    final searchText = useState('');
    final searchByName = useState(true);
    final selectedStatus = useState<String?>(null);

    // 选中状态（使用 Set<Hat> 存储选中的 Hat 对象）
    final selectedHats = useState<Set<Hat>>({});

    // 分页 hook
    final pagination = usePaginationTable<Hat>(
      apiFun: (params) => HatApi.getHatPage(
        current: params['pageNum'],
        size: params['pageSize'],
        bindUserName: searchByName.value && searchText.value.isNotEmpty
            ? searchText.value
            : null,
        hatNumber: !searchByName.value && searchText.value.isNotEmpty
            ? searchText.value
            : null,
        status: selectedStatus.value,
      ),
      immediate: true,
      pageSize: 20,
      onComplete:
          ({
            required currentPage,
            required data,
            required isInitialLoad,
            required pageSize,
            required total,
          }) {
            if (!isInitialLoad || autoSelect != true) return;

            // teamNames 多选匹配
            if (teamNames != null && teamNames!.isNotEmpty) {
              final matched = data
                  .where((u) => teamNames!.contains(u.bindUserName))
                  .toList();
              AppLogger.i(
                'HatSelectPage: teamNames autoSelect, matched ${matched.length}/${teamNames!.length}',
              );
              Navigator.of(context).pop(matched.isNotEmpty ? matched : null);
              return;
            }

            // personName 单选匹配
            if (personName != null) {
              final matchedUser = data
                  .where((u) => u.bindUserName == personName)
                  .firstOrNull;
              AppLogger.i(
                'HatSelectPage: personName autoSelect, matched: $matchedUser',
              );
              Navigator.of(context).pop(matchedUser);
            }
          },
    );

    final searchController = useTextEditingController();
    final colors = Theme.of(context).colorScheme;
    void search() {
      FocusScope.of(context).unfocus();
      pagination.reload().ignore();
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('选择人员 / 安全帽'),
        leading: IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: searchController,
              onChanged: (value) => searchText.value = value.trim(),
              onSubmitted: (_) => search(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: searchByName.value ? '输入人员姓名' : '输入安全帽编号',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchText.value.isEmpty
                    ? IconButton(
                        tooltip: '搜索',
                        onPressed: search,
                        icon: const Icon(Icons.arrow_forward),
                      )
                    : IconButton(
                        tooltip: '清空搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          searchController.clear();
                          searchText.value = '';
                          search();
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<bool>(
                    value: searchByName.value,
                    items: const [
                      DropdownMenuItem(value: true, child: Text('按姓名')),
                      DropdownMenuItem(value: false, child: Text('按帽号')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        searchByName.value = value;
                        search();
                      }
                    },
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedStatus.value,
                    hint: const Text('全部状态'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部状态')),
                      DropdownMenuItem(value: '1', child: Text('在线')),
                      DropdownMenuItem(value: '0', child: Text('离线')),
                    ],
                    onChanged: (value) {
                      selectedStatus.value = value;
                      search();
                    },
                  ),
                ),
                Text(
                  '${pagination.total.value} 人 / 帽',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: PaginationListView<Hat>(
              bind: pagination,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemBuilder: (context, hat, index) {
                final selected = selectedHats.value.any((h) => h.id == hat.id);
                return _HatListItem(
                  hat: hat,
                  selected: selected,
                  onTap: () {
                    final next = Set<Hat>.from(selectedHats.value);
                    if (selectionMode == SelectionMode.single) {
                      next.clear();
                      next.add(hat);
                    } else if (selected) {
                      next.removeWhere((h) => h.id == hat.id);
                    } else {
                      next.add(hat);
                    }
                    selectedHats.value = next;
                  },
                );
              },
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              onRefresh: pagination.reload,
              emptyMsg: '没有匹配的人员或安全帽，请调整搜索条件',
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selectedHats.value.isEmpty
                        ? '尚未选择人员或安全帽'
                        : '已选 ${selectedHats.value.length} 项：${selectedHats.value.map((hat) => hat.bindUserName ?? hat.hatNumber ?? "未命名").join("、")}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: selectedHats.value.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(
                            selectionMode == SelectionMode.single
                                ? selectedHats.value.first
                                : selectedHats.value.toList(),
                          ),
                    child: Text(
                      selectionMode == SelectionMode.single ? '确认选择' : '下一步',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HatListItem extends StatelessWidget {
  final Hat hat;
  final bool selected;
  final VoidCallback onTap;
  const _HatListItem({
    required this.hat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.primary.withValues(alpha: .14)
                      : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.person_outline, color: colors.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hat.bindUserName?.isNotEmpty == true
                          ? hat.bindUserName!
                          : '未绑定人员',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '帽号 ${hat.hatNumber ?? "未知编号"}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${hat.status == "1"
                          ? "在线"
                          : hat.status == "0"
                          ? "离线"
                          : "状态未知"}${hat.electricityUsage == null ? "" : " · 电量 ${hat.electricityUsage}%"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            hat.electricityUsage != null &&
                                hat.electricityUsage! <= 20
                            ? Colors.deepOrange
                            : hat.status == "1"
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? colors.onSurface : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
