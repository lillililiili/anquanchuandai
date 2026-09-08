import '../../components/field_brand.dart';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/components/app_map.dart';
import 'package:rolling_intelligence_headband/components/map_fence.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_dict.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../hooks/use_theme.dart';
import '../../theme/theme.dart';
import '../../api/fence.dart' as api;
import '../../models/fence.dart';

/// 电子围栏编辑/添加页面
class GeoFenceEditPage extends HookWidget {
  final String? fenceId;

  const GeoFenceEditPage({super.key, this.fenceId});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final isEditing = fenceId != null;

    // 页面 Agent 总控
    final pageController = useAgentPage(
      meta: RouteNode.geoFenceEdit,
      greetingMessage: '已进入围栏编辑页面，请设置围栏名称和类型，区域范围需手动在地图上绘制',
    );

    // 表单控制器
    final nameController = useTextEditingController();
    final fenceType = useState<String?>(null);
    final isLoading = useState(false);
    final isSaving = useState(false);
    final originalFence = useState<Fence?>(null);
    final validationError = useState<String?>(null);
    final detailError = useState<String?>(null);

    // 字典数据
    final fenceTypeDict = useDict('elec_fence_type');

    // 地图编辑器状态
    final showMapEditor = useState(false);
    final fencePoints = useState<List<LatLng>>([]);

    // 绑定 AI 工具：设置围栏名称
    usePageAgent(
      controller: pageController,
      toolName: 'setFenceName',
      executeFn: (params) async {
        final name = params?['name'] as String?;
        if (name == null || name.isEmpty) {
          throw Exception('围栏名称不能为空');
        }
        nameController.text = name;
        return {'success': true, 'message': '围栏名称已设置为：$name'};
      },
    );

    // 绑定 AI 工具：设置围栏类型
    usePageAgent(
      controller: pageController,
      toolName: 'setFenceType',
      executeFn: (params) async {
        final type = params?['type'] as String?;
        if (type == null || type.isEmpty) {
          throw Exception('围栏类型不能为空');
        }
        final dictData = fenceTypeDict.data;
        final matched = dictData
            .where((e) => e.label == type || e.value == type)
            .toList();
        AppLogger.i(
          "匹配围栏类型：fenceTypeDict=$dictData, type=$type, matched=$matched",
        );
        if (matched.isEmpty) {
          final available = dictData.map((e) => e.label).join('、');
          throw Exception('无效的围栏类型：$type，可选值：$available');
        }
        fenceType.value = matched.first.label;
        return {'success': true, 'message': '围栏类型已设置为：${matched.first.label}'};
      },
    );

    usePageAgentGetData(pageController, "formState", () {
      return {
        'fenceName': nameController.text,
        'fenceType': fenceType.value,
        'hasArea': fencePoints.value.isNotEmpty,
        'areaPointCount': fencePoints.value.length,
        'isEditing': isEditing,
        'fenceId': fenceId,
        'availableTypes': fenceTypeDict.data.map((e) => e.label).toList(),
      };
    });

    // 加载围栏详情
    final editContext = context;

    Future<void> loadFenceDetail() async {
      if (fenceId == null) return;

      isLoading.value = true;
      detailError.value = null;
      try {
        final fence = await api.FenceApi.getFenceById(fenceId!);
        if (!editContext.mounted) return;
        originalFence.value = fence;
        nameController.text = fence.fenceName ?? '';
        fenceType.value = fence.fenceType;
        // 回显围栏坐标
        if (fence.coordinates != null && fence.coordinates!.isNotEmpty) {
          fencePoints.value = fence.coordinates!
              .where(
                (c) =>
                    c.latitude != null &&
                    c.longitude != null &&
                    c.latitude!.isFinite &&
                    c.longitude!.isFinite &&
                    c.latitude! >= -90 &&
                    c.latitude! <= 90 &&
                    c.longitude! >= -180 &&
                    c.longitude! <= 180,
              )
              .map((c) => LatLng(c.latitude!, c.longitude!))
              .toList();
        }
      } catch (e, t) {
        AppLogger.e("getFenceById", e, t);
        if (!editContext.mounted) return;
        detailError.value = '围栏详情加载失败，请重试后编辑';
        ScaffoldMessenger.of(
          editContext,
        ).showSnackBar(SnackBar(content: Text('加载失败：$e')));
      } finally {
        if (editContext.mounted) {
          isLoading.value = false;
        }
      }
    }

    // 保存围栏
    Future<void> saveFence() async {
      if (isSaving.value || isLoading.value) return;
      final name = nameController.text.trim();
      validationError.value = name.isEmpty
          ? '请输入围栏名称'
          : fenceType.value == null || fenceType.value!.trim().isEmpty
          ? '请选择围栏类型'
          : !isValidFenceArea(fencePoints.value)
          ? '请绘制并应用有效区域，至少需要3个不同且不共线的点'
          : isEditing && originalFence.value == null
          ? '请先重新加载围栏详情'
          : null;
      if (validationError.value != null) return;

      isSaving.value = true;
      try {
        final coordinates = fencePoints.value
            .map(
              (p) => Coordinates(latitude: p.latitude, longitude: p.longitude),
            )
            .toList();

        final fence = Fence(
          id: fenceId,
          fenceName: name,
          fenceType: fenceType.value,
          status: isEditing ? originalFence.value!.status : 1,
          fenceShape: originalFence.value?.fenceShape,
          coordinates: coordinates,
        );

        if (isEditing) {
          await api.FenceApi.updateFence(fence);
        } else {
          await api.FenceApi.saveFence(fence);
        }

        if (!editContext.mounted) return;
        Navigator.of(editContext).pop(true);
      } catch (e) {
        if (!editContext.mounted) return;
        ScaffoldMessenger.of(
          editContext,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      } finally {
        if (editContext.mounted) {
          isSaving.value = false;
        }
      }
    }

    // 编辑模式加载详情
    useEffect(() {
      if (isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (editContext.mounted) {
            loadFenceDetail();
          }
        });
      }
      return null;
    }, []);

    // 等待字典数据加载完成后，通知 AI 页面就绪
    useEffect(() {
      if (fenceTypeDict.loaded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (editContext.mounted) {
            AppLogger.d('围栏类型字典加载完成，页面准备就绪fenceTypeDict=${fenceTypeDict.data}');
            pageController.completeEmptyInit();
          }
        });
      }
      return null;
    }, [fenceTypeDict.loaded]);

    useListenable(nameController);
    final previous = originalFence.value;
    final unchangedPoints = previous?.coordinates ?? <Coordinates>[];
    final dirty =
        nameController.text != (previous?.fenceName ?? '') ||
        fenceType.value != previous?.fenceType ||
        fencePoints.value.length != unchangedPoints.length ||
        fencePoints.value.asMap().entries.any(
          (entry) =>
              entry.key >= unchangedPoints.length ||
              entry.value.latitude != unchangedPoints[entry.key].latitude ||
              entry.value.longitude != unchangedPoints[entry.key].longitude,
        );
    final mapWasVisible = showMapEditor.value;
    Future<void> leaveEditor() async {
      if (isSaving.value) return;
      if (dirty) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('放弃未保存的围栏？'),
            content: const Text('名称、类型及已应用区域的修改尚未保存，返回后将丢失。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
        );
        if (discard != true || !context.mounted) return;
      }
      if (context.mounted) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: !dirty && !isSaving.value && !mapWasVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !mapWasVisible) leaveEditor();
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: theme.background,
            appBar: _buildAppBar(context, theme, isEditing, leaveEditor),
            body: isLoading.value
                ? const Center(child: CircularProgressIndicator())
                : detailError.value != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(detailError.value!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: loadFenceDetail,
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.lg),
                        _GeoFenceForm(
                          theme: theme,
                          isEditing: isEditing,
                          nameController: nameController,
                          fenceType: fenceType,
                          fenceTypeDict: fenceTypeDict,
                          isSaving: isSaving,
                          onSave: saveFence,
                          onCancel: leaveEditor,
                          showMapEditor: showMapEditor,
                          fencePoints: fencePoints,
                          validationError: validationError.value,
                        ),
                      ],
                    ),
                  ),
          ),
          // 地图编辑器
          MapFenceEditor(
            visible: showMapEditor.value,
            initialPoints: fencePoints.value,
            onClose: () => showMapEditor.value = false,
            onSave: (points) {
              fencePoints.value = points;
              showMapEditor.value = false;
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ThemeColors theme,
    bool isEditing,
    VoidCallback onBack,
  ) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: '返回',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        isEditing ? '编辑围栏' : '添加围栏',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
    );
  }
}

// ==================== 表单内容 ====================
class _GeoFenceForm extends HookWidget {
  final ThemeColors theme;
  final bool isEditing;
  final TextEditingController nameController;
  final ValueNotifier<String?> fenceType;
  final DictState fenceTypeDict;
  final ValueNotifier<bool> isSaving;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ValueNotifier<bool> showMapEditor;
  final ValueNotifier<List<LatLng>> fencePoints;
  final String? validationError;

  const _GeoFenceForm({
    required this.theme,
    required this.isEditing,
    required this.nameController,
    required this.fenceType,
    required this.fenceTypeDict,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    required this.showMapEditor,
    required this.fencePoints,
    this.validationError,
  });

  @override
  Widget build(BuildContext context) {
    final mapController = useMemoized(() => MapController());

    // 当围栏点变化时，自动调整地图视图
    useEffect(() {
      if (fencePoints.value.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(fencePoints.value),
                padding: const EdgeInsets.all(50),
              ),
            );
          } catch (_) {
            // 忽略控制器未挂载的错误
          }
        });
      }
      return null;
    }, [fencePoints.value]);

    return Container(
      margin: AppSpacing.cardMargin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 围栏名称
          _buildFormItem(
            label: '围栏名称 *',
            child: _buildTextField(
              controller: nameController,
              hint: '请输入围栏名称',
              theme: theme,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 围栏类型
          _buildFormItem(
            label: '围栏类型 *',
            child: _buildDropdownField(
              hint: '请选择围栏类型',
              value:
                  fenceTypeDict.data
                      .where((e) => e.value == fenceType.value)
                      .firstOrNull
                      ?.label ??
                  fenceType.value,
              items: fenceTypeDict.data.map((e) => e.label ?? '').toList(),
              theme: theme,
              onChanged: (v) => fenceType.value = v,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // 设置区域范围
          _buildFormItem(
            label: '区域范围 * · ${fencePoints.value.length} 个点',
            accent: fencePoints.value.isEmpty
                ? FieldSceneAccent(scene: 'fence-card', size: 40)
                : null,
            child: _buildMapArea(theme: theme, mapController: mapController),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (validationError != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                validationError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 底部按钮
          _buildBottomButtons(theme: theme, context: context),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildFormItem({
    required String label,
    required Widget child,
    Widget? accent,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (accent != null) ...[const SizedBox(width: 8), accent],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
        if ((label.startsWith('围栏名称') && validationError == '请输入围栏名称') ||
            (label.startsWith('围栏类型') && validationError == '请选择围栏类型'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              validationError!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required ThemeColors theme,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: theme.isDark
              ? const Color(0xFF3A3A3A)
              : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          color: theme.isDark ? const Color(0xFF2A2A2A) : Colors.white,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 14, color: theme.textTertiary),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            style: TextStyle(fontSize: 14, color: theme.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String hint,
    required String? value,
    required List<String> items,
    required ThemeColors theme,
    required void Function(String?) onChanged,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(
          color: theme.isDark
              ? const Color(0xFF3A3A3A)
              : const Color(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          color: theme.isDark ? const Color(0xFF2A2A2A) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: items.contains(value) ? value : null,
                hint: Text(
                  hint,
                  style: TextStyle(fontSize: 14, color: theme.textTertiary),
                ),
                items: items.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text(
                      item,
                      style: TextStyle(fontSize: 14, color: theme.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: theme.textSecondary,
                ),
                dropdownColor: theme.cardBackground,
                style: TextStyle(fontSize: 14, color: theme.textPrimary),
                isExpanded: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapArea({
    required ThemeColors theme,
    required MapController mapController,
  }) {
    // 过滤有效坐标（纬度 -90~90，经度 -180~180）
    final validPoints = fencePoints.value.where((p) {
      return p.latitude >= -90 &&
          p.latitude <= 90 &&
          p.longitude >= -180 &&
          p.longitude <= 180;
    }).toList();
    final hasPoints = validPoints.isNotEmpty;

    return Stack(
      children: [
        Container(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            border: Border.all(
              color: theme.isDark
                  ? const Color(0xFF3A3A3A)
                  : const Color(0xFFE0E0E0),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            child: AppMap(
              mapController: mapController,
              children: [
                // 显示绘制的围栏
                if (hasPoints && validPoints.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: validPoints,
                        color: SpringColors.skyBlue.withValues(alpha: 0.25),
                        borderColor: SpringColors.skyBlue,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (hasPoints && validPoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: validPoints,
                        color: SpringColors.skyBlue,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        // 编辑按钮
        Positioned(
          top: AppSpacing.sm,
          right: AppSpacing.sm,
          child: FilledButton.tonalIcon(
            onPressed: isSaving.value ? null : () => showMapEditor.value = true,
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: Text(hasPoints ? '编辑区域' : '绘制区域'),
            style: FilledButton.styleFrom(foregroundColor: theme.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons({
    required ThemeColors theme,
    required BuildContext context,
  }) {
    return SafeArea(
      top: false,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: isSaving.value ? null : onCancel,
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: isSaving.value ? null : onSave,
              child: isSaving.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存围栏'),
            ),
          ),
        ],
      ),
    );
  }
}
