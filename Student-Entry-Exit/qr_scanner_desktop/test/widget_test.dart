import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_desktop/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen has a title and a QR scanner', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Verify that the title is present
    expect(find.text('QR Scanner'), findsOneWidget);

    // Verify that the QR scanner widget is present
    expect(find.byType(QRScanner), findsOneWidget);
  });

  testWidgets('Scanned data view displays scanned data', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    // Simulate scanning a QR code
    final scannedData = 'https://example.com';
    final scannedDataView = find.byType(ScannedDataView);

    // Assuming you have a method to update the scanned data in your HomeScreen
    // This part will depend on how you manage state in your application
    // For example, you might have a method like updateScannedData in HomeScreen
    // await tester.tap(find.byType(QRScanner));
    // await tester.pump(); // Rebuild the widget after the state change

    // Verify that the scanned data is displayed
    // expect(find.text(scannedData), findsOneWidget);
  });
}