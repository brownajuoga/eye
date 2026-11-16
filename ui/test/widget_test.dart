import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eye_ui/src/app.dart';

void main() {
  testWidgets('renders Wi-Fi Night-Vision Cam control center shell and navigation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const EyeApp());
    await tester.pump();

    expect(find.text('eye'), findsOneWidget);
    expect(find.text('Wi-Fi RF Control Center'), findsOneWidget);
    expect(find.text('Wi-Fi Night-Vision Cam'), findsWidgets);
    expect(find.text('Night Vision'), findsOneWidget);
    expect(find.text('Thermal RF'), findsOneWidget);
    expect(find.text('Radar'), findsOneWidget);
    expect(find.text('2.4GHz Spectrum'), findsOneWidget);

    // Navigate to Sensors & NodeMCU section
    await tester.tap(find.text('Sensors & NodeMCU'));
    await tester.pump();
    expect(find.text('ESP8266 NodeMCU Hardware Sensor (Plugged & Unplugged)'), findsOneWidget);

    // Navigate to Captures & Replay section
    await tester.tap(find.text('Captures & Replay'));
    await tester.pump();
    expect(find.text('Upload Capture'), findsOneWidget);
  });
}
