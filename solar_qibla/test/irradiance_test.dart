// اختبارات طبقة بيانات الإشعاع (المرحلة 4).
//
// الطلب الشبكي الحيّ لا يُختبر هنا: يتطلّب إنترنت وخدمة خارجية. المُختبَر هو
// ما يقرّر سلامة التطبيق فعلًا: بناء الرابط، تفسير الاستجابة، مقاومة البيانات
// التالفة، والسقوط الصامت إلى النموذج المدمج.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/core/irradiance_data.dart';
import 'package:solar_qibla/core/solar_math.dart';

/// يبني استجابة على شاكلة NASA POWER الساعية.
///
/// بنيتها مطابقة لما يفكّه عميل pvlib المرجعي:
///   properties.parameter.ALLSKY_SFC_SW_DNI : { "YYYYMMDDHH": قيمة }
Map<String, dynamic> buildResponse({
  required List<double> monthlyValue,
  double fillValue = -999.0,
  int hoursPerMonth = 24,
  Set<int> emptyMonths = const <int>{},
}) {
  final Map<String, dynamic> series = <String, dynamic>{};
  for (int month = 1; month <= 12; month++) {
    if (emptyMonths.contains(month)) continue;
    for (int hour = 0; hour < hoursPerMonth; hour++) {
      final String key = '2023'
          '${month.toString().padLeft(2, '0')}'
          '01'
          '${hour.toString().padLeft(2, '0')}';
      series[key] = monthlyValue[month - 1];
    }
  }
  return <String, dynamic>{
    'header': <String, dynamic>{'fill_value': fillValue},
    'geometry': <String, dynamic>{
      'coordinates': <double>[34.4668, 31.5017, 45.0],
    },
    'properties': <String, dynamic>{
      'parameter': <String, dynamic>{'ALLSKY_SFC_SW_DNI': series},
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  group('بناء رابط الطلب', () {
    test('المضيف والمسار والمعاملات مطابقة للمواصفة المتحقَّق منها', () {
      final Uri uri = IrradianceService.buildRequestUri(
        latitude: 31.5017,
        longitude: 34.4668,
        year: 2023,
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'power.larc.nasa.gov');
      expect(uri.path, '/api/temporal/hourly/point');
      expect(uri.queryParameters['latitude'], '31.5017');
      expect(uri.queryParameters['longitude'], '34.4668');
      expect(uri.queryParameters['start'], '20230101');
      expect(uri.queryParameters['end'], '20231231');
      expect(uri.queryParameters['community'], 're');
      expect(uri.queryParameters['parameters'], 'ALLSKY_SFC_SW_DNI');
      expect(uri.queryParameters['format'], 'json');
      expect(uri.queryParameters['time-standard'], 'utc');
    });

    test('السنة المرجعية سنة مكتملة مؤكّدة لا الجارية', () {
      // الخدمة تتأخّر أشهرًا عن الزمن الحقيقي.
      expect(referenceYear(DateTime(2026, 8, 24)), 2024);
      expect(referenceYear(DateTime(2030, 1, 1)), 2028);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('تفسير الاستجابة', () {
    test('يستخرج المتوسّطات الشهرية الاثني عشر', () {
      final List<double> expected = <double>[
        180, 220, 260, 300, 340, 380, 375, 350, 310, 260, 200, 165,
      ];
      final List<double>? parsed =
          parseMonthlyMeanDni(buildResponse(monthlyValue: expected));

      expect(parsed, isNotNull);
      expect(parsed, hasLength(12));
      for (int i = 0; i < 12; i++) {
        expect(parsed![i], closeTo(expected[i], 1e-9));
      }
    });

    test('القيم المفقودة تُستبعد من المتوسّط لا تُعامل أصفارًا', () {
      // معاملتها أصفارًا تخفض متوسّط الشهر زورًا وتزيح الزاوية المثلى.
      final Map<String, dynamic> body =
          buildResponse(monthlyValue: List<double>.filled(12, 300.0));
      final Map<String, dynamic> series = body['properties']['parameter']
          ['ALLSKY_SFC_SW_DNI'] as Map<String, dynamic>;
      series['2023010105'] = -999.0;
      series['2023010106'] = -999.0;

      final List<double>? parsed = parseMonthlyMeanDni(body);
      expect(parsed, isNotNull);
      expect(parsed![0], closeTo(300.0, 1e-9));
    });

    test('القيم السالبة تُستبعد كذلك', () {
      final Map<String, dynamic> body =
          buildResponse(monthlyValue: List<double>.filled(12, 250.0));
      final Map<String, dynamic> series = body['properties']['parameter']
          ['ALLSKY_SFC_SW_DNI'] as Map<String, dynamic>;
      series['2023030103'] = -12.5;

      expect(parseMonthlyMeanDni(body)![2], closeTo(250.0, 1e-9));
    });

    test('يحترم fill_value المعلن في الترويسة', () {
      final Map<String, dynamic> body = buildResponse(
        monthlyValue: List<double>.filled(12, 400.0),
        fillValue: -111.0,
      );
      final Map<String, dynamic> series = body['properties']['parameter']
          ['ALLSKY_SFC_SW_DNI'] as Map<String, dynamic>;
      series['2023060110'] = -111.0;

      expect(parseMonthlyMeanDni(body)![5], closeTo(400.0, 1e-9));
    });

    test('شهر بلا أي قراءة يُبطل النتيجة كلّها', () {
      // متوسّط شهر مفقود لا يُخترع: نصف بيانات أسوأ من لا بيانات.
      final List<double>? parsed = parseMonthlyMeanDni(buildResponse(
        monthlyValue: List<double>.filled(12, 300.0),
        emptyMonths: <int>{7},
      ));
      expect(parsed, isNull);
    });

    test('البنى الناقصة أو الخاطئة تُرفض بلا انهيار', () {
      expect(parseMonthlyMeanDni(<String, dynamic>{}), isNull);
      expect(
        parseMonthlyMeanDni(<String, dynamic>{'properties': 'ليس كائنًا'}),
        isNull,
      );
      expect(
        parseMonthlyMeanDni(<String, dynamic>{
          'properties': <String, dynamic>{'parameter': <String, dynamic>{}},
        }),
        isNull,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('معاملات التصحيح الشهرية', () {
    MonthlyIrradiance sample(List<double> values) => MonthlyIrradiance(
          monthlyMeanDni: values,
          latitude: 31.5017,
          longitude: 34.4668,
          year: 2023,
          fetchedAt: DateTime(2026, 8, 24, 10, 30),
        );

    test('البيانات المنتظمة تعطي معاملات كلّها واحد', () {
      final List<double> factors =
          sample(List<double>.filled(12, 300.0)).scaleFactors;
      for (final double factor in factors) {
        expect(factor, closeTo(1.0, 1e-12));
      }
    });

    test('المعاملات مطبَّعة حول المتوسّط فلا يتغيّر المقياس الكلّي', () {
      final List<double> factors = sample(<double>[
        100, 150, 200, 250, 300, 350, 350, 300, 250, 200, 150, 100,
      ]).scaleFactors;
      final double mean =
          factors.reduce((double a, double b) => a + b) / factors.length;
      expect(mean, closeTo(1.0, 1e-12));
      // الشهر الأغزر إشعاعًا يأخذ أكبر معامل.
      expect(factors[5], greaterThan(factors[0]));
    });

    test('البيانات الصفرية لا تُنتج قسمة على صفر', () {
      final List<double> factors =
          sample(List<double>.filled(12, 0.0)).scaleFactors;
      expect(factors, hasLength(12));
      for (final double factor in factors) {
        expect(factor, 1.0);
      }
    });

    test('تغطية الموقع محدودة بنصف درجة', () {
      final MonthlyIrradiance data = sample(List<double>.filled(12, 300.0));
      expect(data.coversLocation(31.5017, 34.4668), isTrue);
      expect(data.coversLocation(31.9, 34.8), isTrue);
      expect(data.coversLocation(33.0, 34.4668), isFalse); // بعيد شمالًا
      expect(data.coversLocation(31.5017, 40.0), isFalse); // بعيد شرقًا
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('الترميز والتخزين', () {
    const MethodChannel channel = MethodChannel('solar_qibla/control_irr');
    final Map<String, String?> store = <String, String?>{};

    setUp(() {
      store.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        final Map<Object?, Object?> args =
            (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
        final String key = args['key']! as String;
        if (call.method == 'writeString') {
          store[key] = args['value'] as String?;
          return null;
        }
        if (call.method == 'readString') return store[key];
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('دورة حفظ واستعادة كاملة', () async {
      final IrradianceService service = IrradianceService(control: channel);
      final MonthlyIrradiance original = MonthlyIrradiance(
        monthlyMeanDni: <double>[
          180, 220, 260, 300, 340, 380, 375, 350, 310, 260, 200, 165,
        ],
        latitude: 31.5017,
        longitude: 34.4668,
        year: 2023,
        fetchedAt: DateTime(2026, 8, 24, 10, 30),
      );

      await service.save(original);
      final MonthlyIrradiance? restored = await service.loadCached();

      expect(restored, isNotNull);
      expect(restored!.year, 2023);
      expect(restored.latitude, closeTo(31.5017, 1e-9));
      expect(restored.fetchedAt, original.fetchedAt);
      expect(restored.monthlyMeanDni[5], closeTo(380.0, 1e-9));
    });

    test('لا شيء مخزّن ⇒ null', () async {
      expect(await IrradianceService(control: channel).loadCached(), isNull);
    });

    test('محتوى تالف ⇒ null بلا انهيار', () async {
      store['monthly_irradiance'] = 'ليس JSON {{{';
      expect(await IrradianceService(control: channel).loadCached(), isNull);
    });

    test('عدد شهور خاطئ ⇒ null', () async {
      store['monthly_irradiance'] = jsonEncode(<String, dynamic>{
        'monthlyMeanDni': <double>[1, 2, 3],
        'latitude': 31.5,
        'longitude': 34.5,
        'year': 2023,
        'fetchedAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(await IrradianceService(control: channel).loadCached(), isNull);
    });

    test('طابع زمني غير صالح ⇒ null', () async {
      store['monthly_irradiance'] = jsonEncode(<String, dynamic>{
        'monthlyMeanDni': List<double>.filled(12, 300.0),
        'latitude': 31.5,
        'longitude': 34.5,
        'year': 2023,
        'fetchedAt': 'ليس تاريخًا',
      });
      expect(await IrradianceService(control: channel).loadCached(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('أثر البيانات المقيسة على الزاوية المثلى', () {
    test('معاملات محايدة تعطي النتيجة نفسها كالنموذج المدمج', () {
      final Orientation offline = findOptimalOrientation(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.annual,
      );
      final Orientation neutral = findOptimalOrientation(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.annual,
        monthlyScale: List<double>.filled(12, 1.0),
      );
      expect(neutral.tilt, offline.tilt);
      expect(neutral.azimuth, offline.azimuth);
    });

    test('ترجيح الشتاء يرفع الميل الأمثل، وترجيح الصيف يخفضه', () {
      Orientation withWeights(List<double> scale) => findOptimalOrientation(
            latitude: 31.5017,
            longitude: 34.4668,
            timeZoneOffsetHours: 2,
            mode: OptimizationMode.annual,
            monthlyScale: scale,
          );

      // أشهر الشتاء (1، 2، 11، 12) أثقل بكثير.
      final Orientation winterHeavy = withWeights(<double>[
        3, 3, 1, 1, 0.3, 0.3, 0.3, 0.3, 1, 1, 3, 3,
      ]);
      // أشهر الصيف (5–8) أثقل بكثير.
      final Orientation summerHeavy = withWeights(<double>[
        0.3, 0.3, 1, 1, 3, 3, 3, 3, 1, 1, 0.3, 0.3,
      ]);

      expect(winterHeavy.tilt, greaterThan(summerHeavy.tilt));
    });

    test('عدد معاملات خاطئ يُرفض صراحةً', () {
      expect(
        () => findOptimalOrientation(
          latitude: 31.5,
          longitude: 34.5,
          timeZoneOffsetHours: 2,
          mode: OptimizationMode.annual,
          monthlyScale: <double>[1, 1, 1],
        ),
        throwsArgumentError,
      );
    });
  });
}
