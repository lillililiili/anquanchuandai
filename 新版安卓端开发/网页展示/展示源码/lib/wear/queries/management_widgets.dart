import 'package:flutter/material.dart';
import '../core.dart';

void managementMessage(BuildContext context, Object message) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$message')));
}

class ManagementSection extends StatelessWidget {
  const ManagementSection({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: WearCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
        ],
      ),
    ),
  );
}

class ManagementField extends StatelessWidget {
  const ManagementField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.keyboard,
    this.obscure = false,
    this.lines = 1,
  });
  final TextEditingController controller;
  final String label;
  final bool required, obscure;
  final TextInputType? keyboard;
  final int lines;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    maxLines: lines,
    obscureText: obscure,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label),
    validator: (v) =>
        required && (v == null || v.trim().isEmpty) ? '请填写$label' : null,
  );
}

Future<bool> confirmManagement(
  BuildContext context,
  String title,
  String detail,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

class ManagementDate extends StatelessWidget {
  const ManagementDate({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(value ?? '') ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (selected != null && context.mounted) {
              onChanged(selected.toIso8601String().substring(0, 10));
            }
          },
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text('$label：${value ?? '不限'}'),
        ),
      ),
      if (value != null)
        IconButton(
          tooltip: '清除$label',
          onPressed: () => onChanged(null),
          icon: const Icon(Icons.close, size: 18),
        ),
    ],
  );
}
