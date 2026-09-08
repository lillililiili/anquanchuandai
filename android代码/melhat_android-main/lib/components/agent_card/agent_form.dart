import 'package:flutter/material.dart';

/// 表单字段定义
class _FormFieldDef {
  final String key;
  final String label;
  final String type;
  final bool required;
  final String? placeholder;
  final List<String>? options;
  final num? min;
  final num? max;
  final int? maxLines;
  final dynamic defaultValue;

  _FormFieldDef({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.placeholder,
    this.options,
    this.min,
    this.max,
    this.maxLines,
    this.defaultValue,
  });

  factory _FormFieldDef.fromJson(Map<String, dynamic> json) {
    return _FormFieldDef(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      required: json['required'] as bool? ?? false,
      placeholder: json['placeholder'] as String?,
      options: (json['options'] as List?)?.cast<String>(),
      min: json['min'] as num?,
      max: json['max'] as num?,
      maxLines: json['maxLines'] as int?,
      defaultValue: json['defaultValue'],
    );
  }
}

/// 动态表单卡片组件
class AgentForm extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  final void Function(Map<String, dynamic> formData) onSubmit;

  const AgentForm({super.key, this.arguments, required this.onSubmit});

  @override
  State<AgentForm> createState() => _AgentFormState();
}

class _AgentFormState extends State<AgentForm> {
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  late final List<_FormFieldDef> _fields;
  late final Map<String, dynamic> _values;
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void initState() {
    super.initState();
    _fields = _parseFields(widget.arguments);
    _values = {};
    for (final f in _fields) {
      _values[f.key] = f.defaultValue ?? (f.type == 'switch' ? false : null);
      if (f.type == 'text' || f.type == 'number' || f.type == 'textarea') {
        _textControllers[f.key] = TextEditingController(
          text: f.defaultValue?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<_FormFieldDef> _parseFields(Map<String, dynamic>? args) {
    if (args == null || args['fields'] == null) return [];
    final fieldsList = args['fields'] as List? ?? [];
    return fieldsList
        .map((f) => _FormFieldDef.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  String? get _title => widget.arguments?['title'] as String?;
  String? get _description => widget.arguments?['description'] as String?;
  String get _submitLabel =>
      (widget.arguments?['submitLabel'] as String?) ?? '提交';

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    // 收集文本字段的值
    for (final entry in _textControllers.entries) {
      _values[entry.key] = entry.value.text;
    }

    setState(() => _submitted = true);
    widget.onSubmit(Map<String, dynamic>.from(_values));
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSubmittedState();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_title != null) ...[
              Row(
                children: [
                  const Icon(Icons.edit_note, size: 18, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _title!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (_description != null) ...[
              Text(
                _description!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
            ],
            ..._fields.map(_buildFieldWidget),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(_submitLabel, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmittedState() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                '表单已提交',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._fields.where((f) => _values[f.key] != null).map((f) {
            final value = _values[f.key];
            final displayValue = value is bool ? (value ? '是' : '否') : '$value';
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${f.label}: $displayValue',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFieldWidget(_FormFieldDef field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: field.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
                if (field.required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _buildInput(field),
        ],
      ),
    );
  }

  Widget _buildInput(_FormFieldDef field) {
    switch (field.type) {
      case 'text':
        return TextFormField(
          controller: _textControllers[field.key],
          decoration: _inputDecoration(field.placeholder),
          validator: field.required
              ? (v) => (v == null || v.isEmpty) ? '${field.label}不能为空' : null
              : null,
          onSaved: (v) => _values[field.key] = v,
        );

      case 'number':
        return TextFormField(
          controller: _textControllers[field.key],
          keyboardType: TextInputType.number,
          decoration: _inputDecoration(field.placeholder),
          validator: (v) {
            if (field.required && (v == null || v.isEmpty)) {
              return '${field.label}不能为空';
            }
            if (v != null && v.isNotEmpty) {
              final n = num.tryParse(v);
              if (n == null) return '请输入有效数字';
              if (field.min != null && n < field.min!) return '不能小于${field.min}';
              if (field.max != null && n > field.max!) return '不能大于${field.max}';
            }
            return null;
          },
          onSaved: (v) => _values[field.key] = num.tryParse(v ?? ''),
        );

      case 'textarea':
        return TextFormField(
          controller: _textControllers[field.key],
          maxLines: field.maxLines ?? 3,
          decoration: _inputDecoration(field.placeholder),
          validator: field.required
              ? (v) => (v == null || v.isEmpty) ? '${field.label}不能为空' : null
              : null,
          onSaved: (v) => _values[field.key] = v,
        );

      case 'select':
        return DropdownButtonFormField<String>(
          value: _values[field.key] as String?,
          items: (field.options ?? [])
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          decoration: _inputDecoration(field.placeholder ?? '请选择'),
          validator: field.required
              ? (v) => v == null ? '${field.label}不能为空' : null
              : null,
          onChanged: (v) => _values[field.key] = v,
        );

      case 'radio':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: (field.options ?? []).map((o) {
            return RadioListTile<String>(
              title: Text(o, style: const TextStyle(fontSize: 13)),
              value: o,
              groupValue: _values[field.key] as String?,
              dense: true,
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() => _values[field.key] = v),
            );
          }).toList(),
        );

      case 'date':
        return TextFormField(
          readOnly: true,
          controller: TextEditingController(
            text: _values[field.key]?.toString() ?? '',
          ),
          decoration: _inputDecoration(field.placeholder ?? '请选择日期')
              .copyWith(suffixIcon: const Icon(Icons.calendar_today, size: 18)),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date != null) {
              setState(() {
                _values[field.key] =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
              });
            }
          },
          validator: field.required
              ? (v) => (v == null || v.isEmpty) ? '${field.label}不能为空' : null
              : null,
        );

      case 'switch':
        return SwitchListTile(
          title: Text(field.placeholder ?? '', style: const TextStyle(fontSize: 13)),
          value: _values[field.key] as bool? ?? false,
          dense: true,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => setState(() => _values[field.key] = v),
        );

      default:
        return TextFormField(
          controller: _textControllers[field.key],
          decoration: _inputDecoration(field.placeholder),
          onSaved: (v) => _values[field.key] = v,
        );
    }
  }

  InputDecoration _inputDecoration(String? placeholder) {
    return InputDecoration(
      hintText: placeholder,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF3B82F6)),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      isDense: true,
    );
  }
}
