// نقطة الدخول — هيكل مبدئي فقط.
//
// المرحلة 1 (محرّك الحسابات الفلكية) مكتملة في lib/core/solar_math.dart.
// المرحلة 2 (طبقة المستشعرات عبر Kotlin) والمرحلة 3 (الواجهة الميدانية)
// لم تبدآ بعد. هذه الشاشة مؤقّتة، غرضها إثبات ارتباط محرّك الحسابات
// بالتطبيق ليس إلّا.

import 'package:flutter/material.dart';

import 'core/solar_math.dart';

void main() => runApp(const SolarQiblaApp());

class SolarQiblaApp extends StatelessWidget {
  const SolarQiblaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قِبلة الشمس',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0B6E4F),
      ),
      // الواجهة عربية بالكامل: اتجاه من اليمين إلى اليسار على مستوى التطبيق.
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _ScaffoldPlaceholder(),
    );
  }
}

class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    final SolarEphemeris now = solarEphemeris(DateTime.now().toUtc());

    return Scaffold(
      appBar: AppBar(title: const Text('قِبلة الشمس')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'محرّك الحسابات الفلكية جاهز',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Text('الميل الشمسي الآن: '
                  '${now.declination.toStringAsFixed(2)}°'),
              Text('معادلة الزمن الآن: '
                  '${now.equationOfTime.toStringAsFixed(2)} دقيقة'),
              const SizedBox(height: 24),
              const Text(
                'الواجهة الميدانية وطبقة المستشعرات لم تُنفَّذا بعد.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
