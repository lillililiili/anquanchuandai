import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'wear/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SignalsObserver.instance = null;
  runApp(const MyApp());
}

/// The Android entry always uses the offline app, even with old build defines.
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const WearApp();
}
