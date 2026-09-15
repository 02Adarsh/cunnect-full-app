import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cunnect_food/main.dart';

void main() {
  testWidgets('boot + unmount clean', (tester) async {
    await tester.pumpWidget(const CunnectFoodApp());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
