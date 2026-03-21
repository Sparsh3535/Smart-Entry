import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_desktop/screens/home_screen.dart';
import 'package:qr_scanner_desktop/screens/console_screen.dart';

void main() {
  testWidgets('HomeScreen has a menu icon that opens the console', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Verify that the menu icon is present
    expect(find.byIcon(Icons.menu), findsOneWidget);

    // Tap the menu icon to open the overflow menu
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // Verify that the console option is present in the overflow menu
    expect(find.text('Open Console'), findsOneWidget);

    // Tap the console option
    await tester.tap(find.text('Open Console'));
    await tester.pumpAndSettle();

    // Verify that the ConsoleScreen is displayed
    expect(find.byType(ConsoleScreen), findsOneWidget);
  });
}
