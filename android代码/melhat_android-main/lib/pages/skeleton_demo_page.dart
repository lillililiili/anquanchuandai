import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/hooks/use_skeleton.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../components/skeleton_view.dart';

Future<List<String>> fetchData(int seed) =>
    Future.delayed(const Duration(seconds: 2), () {
      // 模拟随机成功或失败
      return List.generate(10, (index) => '数据项 ${index + seed}');
    });

/// 骨架屏组件演示页面
class SkeletonDemoPage extends HookWidget {
  const SkeletonDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final skeleton = useSkeleton<List<String>>(
      emptyMsg: '暂无数据，点击刷新试试吧',
      isEmpty: (data) => data.isEmpty,
      request: () => fetchData(0),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('骨架屏组件演示'), centerTitle: true),
      body: Column(
        children: [
          // 状态切换按钮区
          _buildButtonBar(skeleton),
          const Divider(height: 1),
          // 骨架屏列表
          Expanded(
            child: SkeletonView.fromHook(
              skeleton,
              (data) => ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: data.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return _ListItemWidget(
                    title: '标题 ${index + 1}',
                    subtitle: data[index],
                    avatar:
                        'https://api.dicebear.com/7.x/avataaars/svg?seed=$index',
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建状态切换按钮区
  Widget _buildButtonBar(SkeletonBind<List<String>> skeleton) {
    return ValueListenableBuilder<SkeletonStatus>(
      valueListenable: skeleton.status,
      builder: (context, status, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              TextButton(
                onPressed: () => skeleton.execute(),
                child: const Text('刷新数据'),
              ),
              _StatusButton(
                label: '加载中',
                icon: Icons.hourglass_empty,
                status: SkeletonStatus.loading,
                currentStatus: status,
                onTap: () => skeleton.status.value = SkeletonStatus.loading,
              ),
              _StatusButton(
                label: '成功',
                icon: Icons.check_circle,
                status: SkeletonStatus.success,
                currentStatus: status,
                onTap: () => skeleton.status.value = SkeletonStatus.success,
              ),
              _StatusButton(
                label: '空数据',
                icon: Icons.inbox,
                status: SkeletonStatus.empty,
                currentStatus: status,
                onTap: () => skeleton.status.value = SkeletonStatus.empty,
              ),
              _StatusButton(
                label: '错误',
                icon: Icons.error_outline,
                status: SkeletonStatus.error,
                currentStatus: status,
                onTap: () => skeleton.status.value = SkeletonStatus.error,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 状态按钮
class _StatusButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final SkeletonStatus status;
  final SkeletonStatus currentStatus;
  final VoidCallback onTap;

  const _StatusButton({
    required this.label,
    required this.icon,
    required this.status,
    required this.currentStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = status == currentStatus;
    final color = isSelected ? Colors.green : Colors.grey[400];

    return Material(
      color: isSelected ? Colors.green[50] : Colors.grey[100],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 列表项 - 真实数据
class _ListItemWidget extends StatelessWidget {
  final String title;
  final String subtitle;
  final String avatar;

  const _ListItemWidget({
    required this.title,
    required this.subtitle,
    required this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[200],
            child: ClipOval(
              child: Image.network(
                avatar,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
