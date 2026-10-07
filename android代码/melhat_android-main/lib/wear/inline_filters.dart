import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'core.dart';

class InlineFilterGroup {
  const InlineFilterGroup(
    this.id,
    this.label,
    this.options, {
    this.presets = const {},
  });
  final String id;
  final String label;
  final Map<String, String> options;
  // Convenience presets yield to the first concrete choice in the same group.
  final Set<String> presets;
}

/// Common direct filters for events and contacts. Selections stay visible and
/// stable while a short debounce coalesces network queries; no modal or Apply.
class InlineFilters extends StatefulWidget {
  const InlineFilters({
    super.key,
    required this.title,
    required this.groups,
    required this.value,
    required this.onApply,
    this.fields = const {},
    this.fieldValues = const {},
    this.onOpen,
    this.loading = false,
    this.error,
    this.enabled = true,
    this.footer,
    this.initiallyExpanded = false,
  });
  final String title;
  final List<InlineFilterGroup> groups;
  final Map<String, Set<String>> value;
  final Map<String, String> fields;
  final Map<String, String> fieldValues;
  final void Function(Map<String, Set<String>>, Map<String, String>) onApply;
  final VoidCallback? onOpen;
  final bool loading;
  final String? error;
  final bool enabled;
  final Widget? footer;
  final bool initiallyExpanded;
  @override
  State<InlineFilters> createState() => _InlineFiltersState();
}

class _InlineFiltersState extends State<InlineFilters> {
  late bool _isExpanded;
  String? _expanded;
  String _query = '';
  bool _more = false;
  int _revision = 0;
  Timer? _debounce;
  late Map<String, Set<String>> _selected;
  late Map<String, String> _fields;
  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _sync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOpen?.call();
    });
  }

  void _sync() {
    _selected = {
      for (final e in widget.value.entries) e.key: {...e.value},
    };
    _fields = {...widget.fieldValues};
  }

  @override
  void didUpdateWidget(covariant InlineFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final same =
        oldWidget.value.length == widget.value.length &&
        widget.value.entries.every(
          (e) => setEquals(e.value, oldWidget.value[e.key]),
        );
    if ((!same || !mapEquals(oldWidget.fieldValues, widget.fieldValues)) &&
        !(_debounce?.isActive ?? false)) {
      _sync();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _emit);
  }

  void _emit() {
    widget.onApply(
      {
        for (final e in _selected.entries) e.key: {...e.value},
      },
      {..._fields},
    );
  }

  void _choose(InlineFilterGroup group, String key) {
    if (!widget.enabled) return;
    setState(() {
      final choices = _selected.putIfAbsent(group.id, () => {});
      if (key.isEmpty) {
        choices.clear();
      } else if (choices.contains(key)) {
        choices.remove(key);
      } else {
        if (group.presets.contains(key)) {
          choices.clear();
        } else {
          choices.removeAll(group.presets);
        }
        choices.add(key);
      }
    });
    _schedule();
  }

  void _reset() {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = {};
      _fields = {};
      _query = '';
      _revision++;
    });
    _emit();
  }

  int get _concreteFilterCount {
    var count = 0;
    for (final group in widget.groups) {
      final choices = _selected[group.id] ?? {};
      for (final key in choices) {
        if (!group.presets.contains(key)) {
          count++;
        }
      }
    }
    for (final v in _fields.values) {
      if (v.trim().isNotEmpty) count++;
    }
    return count;
  }

  bool get _hasConcreteFilters => _concreteFilterCount > 0;

  String get _concreteSummary => [
    for (final group in widget.groups)
      for (final value in _selected[group.id] ?? <String>{})
        if (!group.presets.contains(value))
          group.options[value] ?? value,
    for (final e in _fields.entries)
      if (e.value.trim().isNotEmpty)
        '${widget.fields[e.key] ?? e.key}: ${e.value.trim()}',
  ].join(' · ');

  String get _presetSummary => [
    for (final group in widget.groups)
      for (final value in _selected[group.id] ?? <String>{})
        if (group.presets.contains(value))
          group.options[value] ?? value,
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _isExpanded ? _buildExpandedView() : _buildCollapsedBar(),
    );
  }

  Widget _buildCollapsedBar() {
    final hasConcrete = _hasConcreteFilters;
    final presetText = _presetSummary;
    return InkWell(
      key: const ValueKey('inline-filter-toggle'),
      borderRadius: BorderRadius.circular(10),
      onTap: widget.enabled
          ? () {
              setState(() => _isExpanded = true);
              widget.onOpen?.call();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 18,
                  color: WearColors.brand,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: WearColors.ink,
                          ),
                        ),
                      ),
                      if (!hasConcrete && presetText.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '· $presetText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WearColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasConcrete) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5EFFF),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFFADCAFF), width: 0.8),
                    ),
                    child: Text(
                      '已选 $_concreteFilterCount 项',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: WearColors.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _concreteSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: WearColors.muted,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('filter-reset'),
                    onPressed: widget.enabled ? _reset : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(36, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('重置', style: TextStyle(fontSize: 12)),
                  ),
                ],
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '展开',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.enabled ? WearColors.brand : WearColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: widget.enabled ? WearColors.brand : WearColors.muted,
                    ),
                  ],
                ),
              ],
            ),
            if (widget.loading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedView() {
    final hasConcrete = _hasConcreteFilters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              size: 18,
              color: WearColors.brand,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WearColors.ink,
                    ),
                  ),
                  if (hasConcrete)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5EFFF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFADCAFF), width: 0.8),
                      ),
                      child: Text(
                        '已选 $_concreteFilterCount 项',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: WearColors.brand,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('filter-reset'),
              onPressed: widget.enabled ? _reset : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('重置', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 4),
            InkWell(
              key: const ValueKey('inline-filter-collapse-top'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _isExpanded = false),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '收起',
                      style: TextStyle(
                        fontSize: 12,
                        color: WearColors.brand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.expand_less,
                      size: 18,
                      color: WearColors.brand,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final group in widget.groups) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    '${group.label}${(_selected[group.id]?.isNotEmpty ?? false) ? ' ${_selected[group.id]!.length}' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: WearColors.muted,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('filter-row-${group.id}'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(group, '', '不限'),
                        for (final e in group.options.entries)
                          _chip(group, e.key, e.value),
                      ],
                    ),
                  ),
                ),
                if (group.options.length > 4)
                  IconButton(
                    key: ValueKey('filter-expand-${group.id}'),
                    tooltip: _expanded == group.id
                        ? '收起${group.label}'
                        : '展开全部${group.label}',
                    constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _expanded == group.id ? Icons.expand_less : Icons.expand_more,
                      size: 19,
                      color: WearColors.brand,
                    ),
                    onPressed: () => setState(() {
                      _expanded = _expanded == group.id ? null : group.id;
                      _query = '';
                    }),
                  ),
              ],
            ),
          ),
          if (_expanded == group.id) _expandedChoices(group),
        ],
        if (hasConcrete && _concreteSummary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD6E4FF), width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: WearColors.brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已选：$_concreteSummary',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1D4ED8),
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (widget.loading) const LinearProgressIndicator(minHeight: 2),
        if (widget.error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.error!,
                  style: const TextStyle(fontSize: 12, color: WearColors.danger),
                ),
              ),
              TextButton(onPressed: widget.onOpen, child: const Text('重试')),
            ],
          ),
        if (widget.fields.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('filter-more'),
              onPressed: () => setState(() => _more = !_more),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _more
                    ? '收起补充条件'
                    : '人员、任务等条件${_fields.values.any((v) => v.isNotEmpty) ? ' · 已设置' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_more)
            for (final e in widget.fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  key: ValueKey('filter-field-${e.key}-$_revision'),
                  initialValue: _fields[e.key] ?? '',
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: e.value,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (value) {
                    _fields[e.key] = value.trim();
                    _schedule();
                  },
                ),
              ),
        ],
        if (widget.footer != null) widget.footer!,
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Center(
            child: InkWell(
              key: const ValueKey('inline-filter-collapse-bottom'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _isExpanded = false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '收起筛选',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WearColors.muted,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_up, size: 16, color: WearColors.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(InlineFilterGroup group, String key, String label) {
    final choices = _selected[group.id] ?? {};
    final selected = key.isEmpty ? choices.isEmpty : choices.contains(key);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        key: ValueKey('filter-${group.id}-${key.isEmpty ? 'all' : key}'),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? WearColors.brand : WearColors.muted,
          ),
        ),
        selected: selected,
        showCheckmark: false,
        avatar: key.isEmpty
            ? null
            : SizedBox(
                width: 16,
                height: 16,
                child: selected
                    ? const Icon(Icons.check, size: 16, color: WearColors.brand)
                    : null,
              ),
        checkmarkColor: WearColors.brand,
        backgroundColor: const Color(0xFFF5F7FB),
        selectedColor: const Color(0xFFE5EFFF),
        side: BorderSide(
          color: selected ? const Color(0xFFADCAFF) : const Color(0xFFE2E8F1),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: widget.enabled ? (_) => _choose(group, key) : null,
      ),
    );
  }

  Widget _expandedChoices(InlineFilterGroup group) {
    final options = group.options.entries.where(
      (e) => e.value.toLowerCase().contains(_query.toLowerCase()),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (group.options.length > 8)
            TextFormField(
              key: ValueKey('filter-search-${group.id}'),
              decoration: InputDecoration(
                hintText: '搜索${group.label}',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _query = v),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .25,
            ),
            child: SingleChildScrollView(
              primary: false,
              child: options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('没有匹配选项', style: TextStyle(fontSize: 12)),
                    )
                  : Wrap(
                      children: [
                        for (final e in options)
                          KeyedSubtree(
                            key: ValueKey('expanded-${group.id}-${e.key}'),
                            child: _chip(group, e.key, e.value),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
