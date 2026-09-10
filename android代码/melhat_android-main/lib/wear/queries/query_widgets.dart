import 'package:flutter/material.dart';

import '../core.dart';

class QueryPage extends StatelessWidget {
  const QueryPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WearColors.background,
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  subtitle!,
                  style: const TextStyle(color: WearColors.muted),
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class QueryStateView extends StatelessWidget {
  const QueryStateView({
    super.key,
    required this.loading,
    required this.error,
    required this.empty,
    required this.onRetry,
    required this.child,
    this.emptyTitle = '暂无数据',
    this.emptyDetail,
  });

  final bool loading;
  final Object? error;
  final bool empty;
  final VoidCallback onRetry;
  final Widget child;
  final String emptyTitle;
  final String? emptyDetail;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: WearEmpty(
          title:
              error is WearApiException &&
                  (error as WearApiException).code == 403
              ? '暂无访问权限'
              : '加载失败',
          detail: error is WearApiException
              ? (error as WearApiException).message
              : '请检查网络后重试',
          onRetry: onRetry,
        ),
      );
    }
    if (empty) {
      return Center(
        child: WearEmpty(
          title: emptyTitle,
          detail: emptyDetail,
          onRetry: onRetry,
        ),
      );
    }
    return child;
  }
}

class QuerySection extends StatelessWidget {
  const QuerySection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class QueryRow extends StatelessWidget {
  const QueryRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WearCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: leading,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: subtitle == null
              ? null
              : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing:
              trailing ??
              (onTap == null ? null : const Icon(Icons.chevron_right)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class DetailField extends StatelessWidget {
  const DetailField({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: const TextStyle(color: WearColors.muted)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class PagingFooter extends StatelessWidget {
  const PagingFooter({
    super.key,
    required this.current,
    required this.total,
    required this.hasMore,
    required this.busy,
    required this.onPrevious,
    required this.onNext,
  });

  final int current;
  final int total;
  final bool hasMore;
  final bool busy;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 $total 条 · 第 $current 页',
              style: const TextStyle(color: WearColors.muted),
            ),
          ),
          IconButton(
            onPressed: busy || current <= 1 ? null : onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: busy || !hasMore ? null : onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
