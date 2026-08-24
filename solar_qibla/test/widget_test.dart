// اختبار دخانيّ للهيكل: يتحقّق من إقلاع التطبيق ومن كون اتجاهه RTL.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/main.dart';

void main() {
  testWidgets('التطبيق يُقلع ويعرض عنوانه بالعربية', (WidgetTester tester) async {
    await tester.pumpWidget(const SolarQiblaApp());
    expect(find.text('قِبلة الشمس'), findsOneWidget);
    expect(find.text('محرّك الحسابات الفلكية جاهز'), findsOneWidget);
  });

  testWidgets('اتجاه التطبيق من اليمين إلى اليسار', (WidgetTester tester) async {
    await tester.pumpWidget(const SolarQiblaApp());
    final Directionality directionality = tester.widget<Directionality>(
      find.ancestor(
        of: find.byType(Scaffold),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });
}
