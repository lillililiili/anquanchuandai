import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PreviewMode { light, dark }

/// Installation preference only; session, navigation and media remain owned by
/// their existing controllers. Each UI region opts in as its task is completed.
class PreviewAppearanceController extends ChangeNotifier {
  PreviewAppearanceController({
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'wear.preview.appearance';
  final Future<SharedPreferences> Function() _preferences;
  PreviewMode _mode = PreviewMode.light;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _disposed = false;
  bool _saveFailed = false;

  PreviewMode get mode => _mode;
  bool get saveFailed => _saveFailed;

  Future<void> load() async {
    final revision = _revision;
    PreviewMode restored;
    try {
      final prefs = await _preferences();
      restored = prefs.getString(_key) == 'dark'
          ? PreviewMode.dark
          : PreviewMode.light;
    } catch (_) {
      restored = PreviewMode.light;
    }
    // A slow initial read must not override a choice already made on screen.
    if (_disposed || revision != _revision) return;
    _mode = restored;
    notifyListeners();
  }

  Future<bool> setMode(PreviewMode value) {
    if (_disposed) return Future.value(false);
    final revision = ++_revision;
    _mode = value;
    _saveFailed = false;
    notifyListeners();
    // Serialize writes so rapid taps also persist the last visible selection.
    final saved = _writes.then((_) async {
      try {
        return await (await _preferences()).setString(_key, value.name);
      } catch (_) {
        return false;
      }
    });
    _writes = saved.then<void>((success) {
      if (_disposed || revision != _revision) return;
      _saveFailed = !success;
      notifyListeners();
    });
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PreviewAppearanceScope
    extends InheritedNotifier<PreviewAppearanceController> {
  const PreviewAppearanceScope({
    super.key,
    required PreviewAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static PreviewAppearanceController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PreviewAppearanceScope>()!
      .notifier!;
}

class PreviewAppearancePanel extends StatelessWidget {
  const PreviewAppearancePanel({super.key, required this.controller});
  final PreviewAppearanceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final dark = controller.mode == PreviewMode.dark;
      final colors = dark
          ? const ColorScheme.dark(
              primary: Color(0xFF23A7F2),
              surface: Color(0xFF08263E),
              onSurface: Color(0xFFF2F7FC),
              onSurfaceVariant: Color(0xFFB5CEE4),
              outline: Color(0xFF244861),
            )
          : const ColorScheme.light(
              primary: Color(0xFF168FFF),
              surface: Colors.white,
              onSurface: Color(0xFF112344),
              onSurfaceVariant: Color(0xFF60799D),
              outline: Color(0xFFDCE8F5),
            );
      return Theme(
        data: ThemeData(useMaterial3: true, colorScheme: colors),
        child: Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            side: BorderSide(color: colors.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '外观设置',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭外观设置',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择外观',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    for (final mode in PreviewMode.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          selected: controller.mode == mode,
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: controller.mode == mode
                                    ? colors.primary
                                    : colors.outline,
                              ),
                            ),
                            leading: Icon(
                              mode == PreviewMode.light
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                            ),
                            title: Text(
                              mode == PreviewMode.light ? '浅色' : '深色',
                            ),
                            trailing: Icon(
                              controller.mode == mode
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: controller.mode == mode
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            onTap: () => controller.setMode(mode),
                          ),
                        ),
                      ),
                    if (controller.saveFailed)
                      Text(
                        '偏好未保存，请重新选择后重试',
                        style: TextStyle(color: colors.error),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
