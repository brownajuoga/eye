import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eye_ui/src/app.dart';

void main() {
  testWidgets('renders control center shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const EyeApp());
    await tester.pump();

    expect(find.text('eye'), findsOneWidget);
    expect(find.text('Control Center'), findsOneWidget);
  });
}
