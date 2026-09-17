import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Appearance belongs to the installation, independently of identity/site/RTC.
class WearThemeController extends ChangeNotifier {
  static const preferenceKey = 'wear.appearance.dark';
  bool dark = true;
  bool ready = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_disposed && revision == _revision) {
        dark = prefs.getBool(preferenceKey) ?? true;
      }
    } catch (_) {
      // A missing/corrupt preference uses the customer's dark baseline.
    } finally {
      if (!_disposed) {
        ready = true;
        notifyListeners();
      }
    }
  }

  Future<bool> toggle() async {
    final value = dark = !dark;
    _revision++;
    notifyListeners();
    var saved = false;
    final write = _writes.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      saved = await prefs.setBool(preferenceKey, value);
    });
    _writes = write;
    try {
      await write;
    } catch (_) {
      return false;
    }
    return saved;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class WearThemeScope extends InheritedNotifier<WearThemeController> {
  const WearThemeScope({
    super.key,
    required WearThemeController controller,
    required super.child,
  }) : super(notifier: controller);
  static WearThemeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WearThemeScope>()?.notifier;
}

class WearThemeButton extends StatelessWidget {
  const WearThemeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = WearThemeScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: controller.dark ? '切换浅色' : '切换深色',
      icon: Icon(
        controller.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      onPressed: () async {
        final saved = await controller.toggle();
        if (!saved && context.mounted) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('本次已切换，外观偏好未保存')));
        }
      },
    );
  }
}

class WearThemes {
  static const darkBackground = 'assets/field-brand/themes/industrial-dark.png';
  static const lightBackground =
      'assets/field-brand/themes/industrial-light.png';
  static String background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkBackground
      : lightBackground;

  static ThemeData make(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = Color(dark ? 0xFF141311 : 0xFFF4F2ED);
    final panel = Color(dark ? 0xFF211F1C : 0xFFFFFEFB);
    final shell = Color(dark ? 0xFF1A1816 : 0xFFECE9E2);
    final ink = Color(dark ? 0xFFF2EEE6 : 0xFF25231F);
    final muted = Color(dark ? 0xFFACA494 : 0xFF686154);
    final line = Color(dark ? 0xFF3C3832 : 0xFFD0CBC1);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FED),
          brightness: brightness,
        ).copyWith(
          primary: const Color(0xFF2F6FED),
          onPrimary: Colors.white,
          primaryContainer: Color(dark ? 0xFF253550 : 0xFFE5ECFA),
          onPrimaryContainer: Color(dark ? 0xFFB5CDFF : 0xFF234C98),
          secondary: Color(dark ? 0xFF8FB2FF : 0xFF245BC4),
          surface: panel,
          onSurface: ink,
          onSurfaceVariant: muted,
          surfaceContainerLowest: bg,
          surfaceContainerLow: shell,
          surfaceContainer: panel,
          surfaceContainerHigh: Color(dark ? 0xFF2A2723 : 0xFFE7E3DA),
          surfaceContainerHighest: Color(dark ? 0xFF35312C : 0xFFE0DBD1),
          outline: Color(dark ? 0xFF82796B : 0xFF877D6E),
          outlineVariant: line,
          error: Color(dark ? 0xFFE78C7F : 0xFFA53D32),
          errorContainer: Color(dark ? 0xFF432721 : 0xFFFBE9E5),
          onErrorContainer: Color(dark ? 0xFFFFC8BD : 0xFF802E24),
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: line),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: bg,
                systemNavigationBarColor: shell,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: bg,
                systemNavigationBarColor: shell,
              ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: Color(0xFF2F6FED), width: 2),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          minimumSize: const Size(48, 48),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: shell,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.secondary
                : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? ink : muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: ink),
      ),
    );
  }
}
