import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'wear/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SignalsObserver.instance = null;
  runApp(const MyApp());
}

/// Android uses the shared backend unless WEAR_MOCK is explicitly enabled.
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const WearApp();
}
