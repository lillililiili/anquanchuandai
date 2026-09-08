import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/main.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import 'package:rolling_intelligence_headband/router/app_router.dart';
import 'package:rolling_intelligence_headband/views/login_view.dart';

void main() {
  testWidgets('unauthenticated app starts at the real login page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    UserStore.instance.reset();
    appRouter.go('/login');
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.byType(LoginView), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
