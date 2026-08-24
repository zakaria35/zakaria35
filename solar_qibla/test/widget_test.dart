// اختبارات الواجهة: الإقلاع، اتجاه RTL، وظهور المؤشّرات الثلاثة.
//
// تُشغَّل في الوضع اليدوي عمدًا: الوضع السنوي يستدعي المسح العددي الشامل
// في عزلة، وهو أبطأ من أن يُشغَّل في اختبار واجهة، وليس موضوع الاختبار هنا.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/core/app_state.dart';
import 'package:solar_qibla/core/orientation.dart';
import 'package:solar_qibla/core/solar_math.dart';
import 'package:solar_qibla/main.dart';
import 'package:solar_qibla/ui/indicators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel control = MethodChannel('solar_qibla/control_ui');
  const EventChannel events = EventChannel('solar_qibla/orientation_ui');

  final Map<String, String?> store = <String, String?>{};

  /// مصفوفة دوران للوح بميل وسمت معلومين (انظر test/orientation_test.dart).
  List<double> matrixFor({required double tilt, required double azimuth}) {
    double sinD(double d) => math.sin(d * math.pi / 180.0);
    double cosD(double d) => math.cos(d * math.pi / 180.0);
    final double sb = sinD(tilt);
    final double cb = cosD(tilt);
    final double sg = sinD(azimuth);
    final double cg = cosD(azimuth);
    return <double>[
      -cg, -cb * sg, sb * sg, //
      sg, -cb * cg, sb * cg, //
      0.0, sb, cb,
    ];
  }

  void mockChannels({
    required double tilt,
    required double azimuth,
    bool withLocation = true,
  }) {
    store.clear();
    if (withLocation) {
      store['last_location'] = jsonEncode(<String, dynamic>{
        'latitude': 31.5017,
        'longitude': 34.4668,
        'altitude': 0.0,
        'timeZoneOffsetHours': 2,
      });
    }
    // الوضع اليدوي مع هدف معلوم: ميل ‎30°‎ وسمت ‎180°‎.
    store['settings'] = jsonEncode(<String, dynamic>{
      'mode': OptimizationMode.manual.index,
      'panelOrientation': PanelOrientation.portrait.index,
      'panelLength': 2.278,
      'panelWidth': 1.134,
      'manualTilt': 30.0,
      'manualAzimuth': 180.0,
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(control, (MethodCall call) async {
      final Map<Object?, Object?> args =
          (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
      switch (call.method) {
        case 'readString':
          return store[args['key'] as String];
        case 'writeString':
          store[args['key']! as String] = args['value'] as String?;
          return null;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? _, MockStreamHandlerEventSink sink) {
          // عيّنات متكرّرة ليستقرّ المرشّح على القيمة المطلوبة.
          for (int i = 0; i < 120; i++) {
            sink.success(<String, Object?>{
              'rotationMatrix': matrixFor(tilt: tilt, azimuth: azimuth),
              'declination': 0.0,
              'accuracy': 3,
              'timestampMs': 0,
            });
          }
        },
      ),
    );
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(control, null)
      ..setMockStreamHandler(events, null);
  });

  Future<AppState> buildState() async {
    final AppState state = AppState(
      control: control,
      orientationService: OrientationService(events: events, control: control),
    );
    await state.restore();
    return state;
  }

  Future<void> pumpApp(WidgetTester tester, AppState state) async {
    // نافذة الاختبار الافتراضية ‎800×600‎ منطقية، وهي أقصر من أن تبني
    // مؤشّرات ListView الثلاثة معًا، فتختفي عناصر أسفل الطيّة من الشجرة.
    // نضبطها على شاشة الجهاز الهدف تقريبًا، مع ارتفاع يكفي المحتوى كلّه.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(SolarQiblaApp(state: state));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('التطبيق يُقلع واتجاهه من اليمين إلى اليسار', (tester) async {
    mockChannels(tilt: 30.0, azimuth: 180.0);
    await pumpApp(tester, await buildState());

    expect(find.text('قِبلة الشمس'), findsOneWidget);

    final Directionality directionality = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.byType(Scaffold),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  });

  testWidgets('تحذير المعادن ظاهر دائمًا', (tester) async {
    mockChannels(tilt: 30.0, azimuth: 180.0);
    await pumpApp(tester, await buildState());

    expect(
      find.textContaining('أبعد الهاتف عن الأسطح المعدنية'),
      findsOneWidget,
    );
  });

  testWidgets('المؤشّرات الثلاثة تظهر عند اكتمال القراءة', (tester) async {
    mockChannels(tilt: 30.0, azimuth: 180.0);
    await pumpApp(tester, await buildState());

    expect(find.byType(CompassRing), findsOneWidget);
    expect(find.byType(TiltGauge), findsOneWidget);
    expect(find.byType(PerformanceBar), findsOneWidget);
  });

  testWidgets('اللوح المطابق للهدف يُعلَن مضبوطًا في المحورين', (tester) async {
    mockChannels(tilt: 30.0, azimuth: 180.0);
    await pumpApp(tester, await buildState());

    expect(find.text('الاتجاه مضبوط'), findsOneWidget);
    expect(find.text('الميل مضبوط'), findsOneWidget);
    // ثلاث علامات صحّ: تعليمة الاتجاه، تعليمة الميل، وزرّ التثبيت الذي
    // يتحوّل إلى حالة "الوضع الأمثل".
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
    expect(find.text('الوضع الأمثل — ثبّت القراءة'), findsOneWidget);
  });

  testWidgets('اللوح المنحرف يعرض جهة التحريك ومقداره', (tester) async {
    // ميل ‎18°‎ مقابل هدف ‎30°‎ ⇒ ارفع ‎12°‎.
    // سمت ‎160°‎ مقابل هدف ‎180°‎ ⇒ الهدف باتجاه عقارب الساعة ⇒ در يمينًا.
    mockChannels(tilt: 18.0, azimuth: 160.0);
    await pumpApp(tester, await buildState());

    expect(find.text('ارفع 12.0°'), findsOneWidget);
    expect(find.text('در 20.0° يمينًا'), findsOneWidget);
    // السهم مطلوب في المواصفات إلى جانب المقدار.
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.rotate_right), findsOneWidget);
  });

  testWidgets('الانحراف في الجهة المقابلة يعكس التعليمة', (tester) async {
    // ميل ‎42°‎ ⇒ اخفض ‎12°‎؛ سمت ‎200°‎ ⇒ در ‎20°‎ يسارًا.
    mockChannels(tilt: 42.0, azimuth: 200.0);
    await pumpApp(tester, await buildState());

    expect(find.text('اخفض 12.0°'), findsOneWidget);
    expect(find.text('در 20.0° يسارًا'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.rotate_left), findsOneWidget);
  });

  group('مسطرة الميل تحترم اتجاه الواجهة', () {
    test('الهدف في المنتصف مهما كان الاتجاه', () {
      for (final bool rtl in <bool>[false, true]) {
        expect(
          tiltGaugeFraction(tilt: 30.0, targetTilt: 30.0, isRightToLeft: rtl),
          closeTo(0.5, 1e-12),
        );
      }
    });

    test('من اليمين إلى اليسار: الميل الأكبر يقع يسارًا', () {
      // اتساقًا مع شريط التقدّم الذي يعكسه Flutter تلقائيًا في RTL.
      final double higher =
          tiltGaugeFraction(tilt: 40.0, targetTilt: 30.0, isRightToLeft: true);
      final double lower =
          tiltGaugeFraction(tilt: 20.0, targetTilt: 30.0, isRightToLeft: true);
      expect(higher, lessThan(0.5));
      expect(lower, greaterThan(0.5));
    });

    test('من اليسار إلى اليمين: الاتجاه معكوس', () {
      final double higher =
          tiltGaugeFraction(tilt: 40.0, targetTilt: 30.0, isRightToLeft: false);
      expect(higher, greaterThan(0.5));
    });

    test('القيم خارج المدى تُحصر في طرفَي المسطرة', () {
      expect(
        tiltGaugeFraction(tilt: 300.0, targetTilt: 30.0, isRightToLeft: false),
        1.0,
      );
      expect(
        tiltGaugeFraction(tilt: -300.0, targetTilt: 30.0, isRightToLeft: false),
        0.0,
      );
      expect(
        tiltGaugeFraction(tilt: 300.0, targetTilt: 30.0, isRightToLeft: true),
        0.0,
      );
    });
  });

  testWidgets('بلا موقع تُعرض شاشة الإعداد لا المؤشّرات', (tester) async {
    mockChannels(tilt: 30.0, azimuth: 180.0, withLocation: false);
    await pumpApp(tester, await buildState());

    expect(find.text('حدّد الموقع أولًا'), findsOneWidget);
    expect(find.byType(CompassRing), findsNothing);
  });
}
