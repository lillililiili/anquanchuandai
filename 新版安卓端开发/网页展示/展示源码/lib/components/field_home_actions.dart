import 'package:flutter/material.dart';
import 'field_motion.dart';

/// Home scope selection and person lookup share a compact action row.
class FieldHomeActions extends StatefulWidget {
  const FieldHomeActions({
    super.key,
    required this.groups,
    required this.group,
    required this.enabled,
    required this.onGroupChanged,
    required this.onSearch,
  });
  final Set<String> groups;
  final String group;
  final bool enabled;
  final ValueChanged<String> onGroupChanged;
  final VoidCallback onSearch;

  @override
  State<FieldHomeActions> createState() => _FieldHomeActionsState();
}

class _FieldHomeActionsState extends State<FieldHomeActions> {
  final menu = MenuController();
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = widget.group.isEmpty ? '全部分组' : widget.group;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
        final groupButton = MenuAnchor(
          controller: menu,
          consumeOutsideTap: true,
          onOpen: () => setState(() => open = true),
          onClose: () => setState(() => open = false),
          style: MenuStyle(
            maximumSize: WidgetStatePropertyAll(
              Size(constraints.maxWidth, 360),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          menuChildren: [
            for (final value in widget.groups)
              MenuItemButton(
                onPressed: widget.enabled
                    ? () => widget.onGroupChanged(value)
                    : null,
                leadingIcon: Icon(
                  value == widget.group ? Icons.check : Icons.groups_outlined,
                  size: 20,
                ),
                child: SizedBox(
                  width: (constraints.maxWidth - 80).clamp(80, 280),
                  child: Text(value.isEmpty ? '全部分组' : value, softWrap: true),
                ),
              ),
          ],
          builder: (context, controller, child) => MotionPress(
            enabled: widget.enabled,
            child: FilledButton.tonal(
              onPressed: widget.enabled
                  ? () {
                      controller.isOpen
                          ? controller.close()
                          : controller.open();
                    }
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onSurface,
                shape: shape,
              ),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: '作业分组：$label',
                      child: MotionSwap(
                        value: label,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? .5 : 0,
                    duration: MotionPolicy.duration(
                      context,
                      MotionPolicy.contentMs,
                    ),
                    curve: MotionPolicy.effectsCurve,
                    child: const Icon(Icons.expand_more, size: 20),
                  ),
                ],
              ),
            ),
          ),
        );
        final searchButton = MotionPress(
          enabled: widget.enabled,
          child: OutlinedButton.icon(
            onPressed: widget.enabled ? widget.onSearch : null,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text('查人员'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              foregroundColor: colors.onSurface,
              shape: shape,
            ),
          ),
        );
        if (stacked)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [groupButton, const SizedBox(height: 10), searchButton],
          );
        return Row(
          children: [
            Expanded(child: groupButton),
            const SizedBox(width: 10),
            SizedBox(width: 112, child: searchButton),
          ],
        );
      },
    );
  }
}
