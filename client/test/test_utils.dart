import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestUtils {
  /// Updates test screen size.
  ///
  /// By default screen size is 800x600.
  static void updateScreenSize(
    WidgetTester tester,
    double width,
    double height,
  ) {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
  }
}
