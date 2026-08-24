// اختبارات طبقة التوجيه: الترشيح، المعايرة بالشمس، وفكّ ترميز القراءات.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/core/orientation.dart';
import 'package:solar_qibla/core/solar_math.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  // مصفوفة دوران صالحة للوح بميل β وسمت γ، بترتيب أندرويد (صفًّا صفًّا).
  //
  // أعمدة R هي محاور الجهاز معبَّرًا عنها بالإحداثيات العالمية
  // (شرق، شمال، أعلى)، لأن world = R · device:
  //   العمود 2 = محور الجهاز +Z = العمود على اللوح
  //   العمود 1 = محور الجهاز +Y = أعلى الهاتف، صاعدًا في اتجاه الميل
  //   العمود 0 = محور الجهاز +X = حافة الهاتف اليمنى، أفقية دائمًا
  List<double> rotationMatrixFor({required double tilt, required double azimuth}) {
    double sinD(double d) => math.sin(d * math.pi / 180.0);
    double cosD(double d) => math.cos(d * math.pi / 180.0);
    final double sb = sinD(tilt);
    final double cb = cosD(tilt);
    final double sg = sinD(azimuth);
    final double cg = cosD(azimuth);
    return <double>[
      -cg, -cb * sg, sb * sg, // صف الشرق
      sg, -cb * cg, sb * cg, // صف الشمال
      0.0, sb, cb, // صف الأعلى
    ];
  }

  // ═════════════════════════════════════════════════════════════════════════
  group('استخراج التوجيه من مصفوفة الدوران', () {
    test('اللوح الأفقي: ميل صفر وسمت بلا معنى', () {
      final RawOrientation o = orientationFromRotationMatrix(
        rotationMatrixFor(tilt: 0.0, azimuth: 180.0),
      );
      expect(o.tilt, closeTo(0.0, 1e-9));
      expect(o.azimuthReliable, isFalse);
    });

    test('يستعيد الميل والسمت لتوجيهات معلومة', () {
      const List<List<double>> cases = <List<double>>[
        <double>[30.0, 180.0], // جنوب
        <double>[30.0, 135.0], // جنوب شرق
        <double>[30.0, 225.0], // جنوب غرب
        <double>[45.0, 90.0], // شرق
        <double>[45.0, 270.0], // غرب
        <double>[15.0, 0.0], // شمال
        <double>[60.0, 350.0], // قرب الشمال، لاختبار الالتفاف
        <double>[5.0, 200.0], // ميل صغير لكنه معتبر
      ];
      for (final List<double> c in cases) {
        final double tilt = c[0];
        final double azimuth = c[1];
        final RawOrientation o = orientationFromRotationMatrix(
          rotationMatrixFor(tilt: tilt, azimuth: azimuth),
        );
        expect(o.tilt, closeTo(tilt, 1e-9), reason: 'الميل عند β=$tilt γ=$azimuth');
        expect(o.azimuthReliable, isTrue, reason: 'الموثوقية عند β=$tilt');
        expect(angularDifference(azimuth, o.magneticAzimuth).abs(),
            lessThan(1e-9),
            reason: 'السمت عند β=$tilt γ=$azimuth');
      }
    });

    test('السمت مضبوط الاتجاه: لوح مائل شرقًا عموده يشير شرقًا', () {
      // ضمانة ضد انعكاس وسيطَي atan2، وهو خطأ يمرّ صامتًا.
      final RawOrientation east = orientationFromRotationMatrix(
        rotationMatrixFor(tilt: 40.0, azimuth: 90.0),
      );
      final List<double> matrix =
          rotationMatrixFor(tilt: 40.0, azimuth: 90.0);
      expect(east.magneticAzimuth, closeTo(90.0, 1e-9));
      expect(matrix[2], greaterThan(0.5)); // مركّبة الشرق موجبة
      expect(matrix[5].abs(), lessThan(1e-9)); // ولا مركّبة شمالية
    });

    test('عتبة موثوقية السمت تقع عند ميل ‎~1.7°‎', () {
      expect(
        orientationFromRotationMatrix(
          rotationMatrixFor(tilt: 1.0, azimuth: 180.0),
        ).azimuthReliable,
        isFalse,
      );
      expect(
        orientationFromRotationMatrix(
          rotationMatrixFor(tilt: 3.0, azimuth: 180.0),
        ).azimuthReliable,
        isTrue,
      );
    });

    test('المقروء هو عمود الجهاز لا حافته العليا', () {
      // اختبار انحدار لخطأ في خطوات المعايرة بالشمس: كانت التعليمات تطلب
      // تسديد الحافة العليا نحو الشمس، بينما القراءة هي اتجاه العمود على
      // الجهاز (محور +Z). الحافة العليا (محور +Y) تشير إلى الجهة المقابلة
      // تمامًا، فكانت الإزاحة المحسوبة تنقلب ‎180°‎.
      const double tilt = 35.0;
      const double azimuth = 200.0;
      final List<double> matrix =
          rotationMatrixFor(tilt: tilt, azimuth: azimuth);

      final RawOrientation o = orientationFromRotationMatrix(matrix);
      expect(o.magneticAzimuth, closeTo(azimuth, 1e-9));

      // محور +Y هو العمود الأوسط من المصفوفة: (R[1], R[4], R[7]).
      final double topEdgeAzimuth = normalizeDegrees360(
        math.atan2(matrix[1], matrix[4]) * 180.0 / math.pi,
      );
      expect(
        angularDifference(o.magneticAzimuth, topEdgeAzimuth).abs(),
        closeTo(180.0, 1e-9),
      );
    });

    test('مصفوفة بطول خاطئ تُرفض', () {
      expect(
        () => orientationFromRotationMatrix(<double>[1, 0, 0, 0, 1, 0]),
        throwsArgumentError,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('المرشّح الدائري', () {
    test('أول عيّنة تُتبنّى كما هي بلا قفزة من الصفر', () {
      final CircularEma filter = CircularEma(alpha: 0.16);
      expect(filter.hasValue, isFalse);
      expect(filter.value, isNull);
      expect(filter.add(217.0), closeTo(217.0, 1e-9));
      expect(filter.hasValue, isTrue);
    });

    test('يعبر الشمال بشكل صحيح — الخطأ الذي يقع فيه المتوسّط المباشر', () {
      // متوسّط 359° و1° هو 0°، لا 180°.
      final CircularEma filter = CircularEma(alpha: 0.5);
      filter.add(359.0);
      final double result = filter.add(1.0);
      final double distanceFromNorth = angularDifference(0.0, result).abs();
      expect(distanceFromNorth, lessThan(1.0),
          reason: 'النتيجة $result° يجب أن تكون قرب الشمال لا قرب الجنوب');
    });

    test('يستقرّ على القيمة الثابتة بعد عيّنات كافية', () {
      final CircularEma filter = CircularEma(alpha: 0.16);
      filter.add(10.0);
      for (int i = 0; i < 200; i++) {
        filter.add(95.0);
      }
      expect(filter.value, closeTo(95.0, 0.01));
    });

    test('يخمد الضجيج: تشتّت الخرج أصغر كثيرًا من تشتّت الدخل', () {
      final math.Random random = math.Random(1234);
      final CircularEma filter = CircularEma(alpha: 0.16);
      const double truth = 180.0;

      double inputSquares = 0.0;
      double outputSquares = 0.0;
      int counted = 0;

      for (int i = 0; i < 600; i++) {
        // ضجيج ‎±5°‎ حول القيمة الحقيقية.
        final double noisy = truth + (random.nextDouble() - 0.5) * 10.0;
        final double filtered = filter.add(noisy);
        if (i < 100) continue; // تجاوز فترة الاستقرار
        inputSquares += math.pow(angularDifference(truth, noisy), 2).toDouble();
        outputSquares +=
            math.pow(angularDifference(truth, filtered), 2).toDouble();
        counted++;
      }

      final double inputRms = math.sqrt(inputSquares / counted);
      final double outputRms = math.sqrt(outputSquares / counted);
      expect(outputRms, lessThan(inputRms / 3.0),
          reason: 'دخل $inputRms° مقابل خرج $outputRms°');
    });

    test('alpha = 1 يعني بلا ترشيح', () {
      final CircularEma filter = CircularEma(alpha: 1.0);
      filter.add(10.0);
      expect(filter.add(200.0), closeTo(200.0, 1e-9));
    });

    test('alpha خارج المدى يُرفض', () {
      expect(() => CircularEma(alpha: 0.0), throwsA(isA<AssertionError>()));
      expect(() => CircularEma(alpha: 1.5), throwsA(isA<AssertionError>()));
    });

    test('reset يمسح الحالة', () {
      final CircularEma filter = CircularEma(alpha: 0.16);
      filter.add(90.0);
      filter.reset();
      expect(filter.hasValue, isFalse);
      expect(filter.add(270.0), closeTo(270.0, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('المرشّح الخطّي', () {
    test('أول عيّنة تُتبنّى كما هي', () {
      final LinearEma filter = LinearEma(alpha: 0.16);
      expect(filter.value, isNull);
      expect(filter.add(34.0), closeTo(34.0, 1e-9));
    });

    test('يقترب من القيمة الجديدة أُسّيًا', () {
      final LinearEma filter = LinearEma(alpha: 0.5);
      filter.add(0.0);
      expect(filter.add(10.0), closeTo(5.0, 1e-9));
      expect(filter.add(10.0), closeTo(7.5, 1e-9));
    });

    test('يستقرّ على القيمة الثابتة', () {
      final LinearEma filter = LinearEma(alpha: 0.16);
      filter.add(0.0);
      for (int i = 0; i < 300; i++) {
        filter.add(31.5);
      }
      expect(filter.value, closeTo(31.5, 1e-6));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('حالة دقّة البوصلة', () {
    test('تحويل قيم أندرويد', () {
      expect(CompassAccuracy.fromAndroid(3), CompassAccuracy.high);
      expect(CompassAccuracy.fromAndroid(2), CompassAccuracy.medium);
      expect(CompassAccuracy.fromAndroid(1), CompassAccuracy.low);
      expect(CompassAccuracy.fromAndroid(0), CompassAccuracy.unreliable);
    });

    test('القيم المجهولة تُعامل معاملة غير الموثوقة', () {
      expect(CompassAccuracy.fromAndroid(null), CompassAccuracy.unreliable);
      expect(CompassAccuracy.fromAndroid(-1), CompassAccuracy.unreliable);
      expect(CompassAccuracy.fromAndroid(99), CompassAccuracy.unreliable);
    });

    test('المنخفضة وغير الموثوقة تستدعيان المعايرة', () {
      expect(CompassAccuracy.unreliable.needsCalibration, isTrue);
      expect(CompassAccuracy.low.needsCalibration, isTrue);
      expect(CompassAccuracy.medium.needsCalibration, isFalse);
      expect(CompassAccuracy.high.needsCalibration, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('قراءة اللوح', () {
    PanelReading reading({
      double tilt = 30.0,
      double magneticAzimuth = 175.0,
      double? declination = 4.5,
      double calibrationOffset = 0.0,
      bool azimuthReliable = true,
      CompassAccuracy accuracy = CompassAccuracy.high,
    }) =>
        PanelReading(
          tilt: tilt,
          magneticAzimuth: magneticAzimuth,
          declination: declination,
          calibrationOffset: calibrationOffset,
          azimuthReliable: azimuthReliable,
          accuracy: accuracy,
        );

    test('السمت الحقيقي = المغناطيسي + الانحراف + إزاحة المعايرة', () {
      expect(reading().trueAzimuth, closeTo(179.5, 1e-9));
      expect(
        reading(calibrationOffset: -2.0).trueAzimuth,
        closeTo(177.5, 1e-9),
      );
    });

    test('السمت الحقيقي يلتفّ حول الشمال', () {
      expect(
        reading(magneticAzimuth: 358.0, declination: 5.0).trueAzimuth,
        closeTo(3.0, 1e-9),
      );
      expect(
        reading(magneticAzimuth: 2.0, declination: -5.0).trueAzimuth,
        closeTo(357.0, 1e-9),
      );
    });

    test('لا يُدّعى سمت حقيقي قبل معرفة الانحراف', () {
      expect(reading(declination: null).trueAzimuth, isNull);
      expect(reading(declination: null).isUsable, isFalse);
    });

    test('القراءة غير صالحة عند تدنّي الدقّة أو انعدام معنى السمت', () {
      expect(reading().isUsable, isTrue);
      expect(reading(accuracy: CompassAccuracy.low).isUsable, isFalse);
      expect(reading(azimuthReliable: false).isUsable, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('المعايرة بالشمس', () {
    test('الإزاحة هي الفرق بين الشمس المحسوبة والبوصلة المرصودة', () {
      expect(
        solarCalibrationOffset(observedAzimuth: 130.0, trueSolarAzimuth: 142.0),
        closeTo(12.0, 1e-9),
      );
      expect(
        solarCalibrationOffset(observedAzimuth: 150.0, trueSolarAzimuth: 142.0),
        closeTo(-8.0, 1e-9),
      );
    });

    test('الإزاحة تعبر الشمال بأقصر مسار', () {
      expect(
        solarCalibrationOffset(observedAzimuth: 355.0, trueSolarAzimuth: 5.0),
        closeTo(10.0, 1e-9),
      );
      expect(
        solarCalibrationOffset(observedAzimuth: 5.0, trueSolarAzimuth: 355.0),
        closeTo(-10.0, 1e-9),
      );
    });

    test('تطبيق الإزاحة يُطابق البوصلة على الشمس', () {
      const double observed = 130.0;
      const double solar = 142.0;
      final double offset = solarCalibrationOffset(
        observedAzimuth: observed,
        trueSolarAzimuth: solar,
      );
      expect(normalizeDegrees360(observed + offset), closeTo(solar, 1e-9));
    });

    test('الإزاحات الكبيرة تُوسم بالمشبوهة', () {
      expect(isCalibrationOffsetSuspicious(12.0), isFalse);
      expect(isCalibrationOffsetSuspicious(-44.0), isFalse);
      expect(isCalibrationOffsetSuspicious(60.0), isTrue);
      expect(isCalibrationOffsetSuspicious(-120.0), isTrue);
    });

    test('صلاحية الشمس مرجعًا تعتمد على ارتفاعها', () {
      SolarPosition at(double elevation) => SolarPosition(
            zenith: 90.0 - elevation,
            azimuth: 180.0,
            declination: 0.0,
            hourAngle: 0.0,
          );
      expect(isSunSuitableForCalibration(at(2.0)), isFalse); // منخفضة جدًا
      expect(isSunSuitableForCalibration(at(30.0)), isTrue);
      expect(isSunSuitableForCalibration(at(80.0)), isFalse); // قرب سمت الرأس
    });

    test('معايرة واقعية: تشويش معدني يُكتشف ويُصحَّح', () {
      // غزة، 21 مارس، الساعة 10 صباحًا بالتوقيت المحلي القياسي.
      final SolarPosition sun = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 3, 21, 10),
      );
      expect(isSunSuitableForCalibration(sun), isTrue);

      // هيكل التركيب يزيح البوصلة 17° — قيمة واقعية قرب الفولاذ.
      const double metalBias = 17.0;
      final double observed = normalizeDegrees360(sun.azimuth + metalBias);

      final double offset = solarCalibrationOffset(
        observedAzimuth: observed,
        trueSolarAzimuth: sun.azimuth,
      );
      expect(offset, closeTo(-metalBias, 1e-9));
      expect(isCalibrationOffsetSuspicious(offset), isFalse);
      expect(normalizeDegrees360(observed + offset), closeTo(sun.azimuth, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('خدمة التوجيه — فكّ الترميز عبر قناة وهمية', () {
    const EventChannel channel = EventChannel('solar_qibla/orientation_test');

    /// يُغذّي القناة الوهمية بسلسلة قراءات خام كما تبثّها Kotlin.
    void mockStream(List<Map<String, Object?>> samples) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            for (final Map<String, Object?> sample in samples) {
              events.success(sample);
            }
            events.endOfStream();
          },
        ),
      );
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(channel, null);
    });

    Map<String, Object?> sample({
      double tilt = 30.0,
      double azimuth = 180.0,
      double? declination = 4.5,
      int accuracy = 3,
    }) =>
        <String, Object?>{
          'rotationMatrix': rotationMatrixFor(tilt: tilt, azimuth: azimuth),
          'declination': declination,
          'accuracy': accuracy,
          'timestampMs': 0,
        };

    test('يفكّ ترميز القراءة الخام ويطبّق الانحراف', () async {
      mockStream(<Map<String, Object?>>[sample()]);
      final OrientationService service = OrientationService(events: channel);
      final PanelReading first = await service.readings().first;

      expect(first.tilt, closeTo(30.0, 1e-9));
      expect(first.magneticAzimuth, closeTo(180.0, 1e-9));
      expect(first.declination, closeTo(4.5, 1e-9));
      expect(first.trueAzimuth, closeTo(184.5, 1e-9));
      expect(first.accuracy, CompassAccuracy.high);
      expect(first.isUsable, isTrue);
    });

    test('يرشّح تدفّقًا مضطربًا نحو القيمة الحقيقية', () async {
      final math.Random random = math.Random(7);
      final List<Map<String, Object?>> samples = List<Map<String, Object?>>
          .generate(
        300,
        (_) => sample(
          tilt: 30.0 + (random.nextDouble() - 0.5) * 6.0,
          azimuth: 180.0 + (random.nextDouble() - 0.5) * 8.0,
        ),
      );
      mockStream(samples);

      final OrientationService service = OrientationService(events: channel);
      final List<PanelReading> readings = await service.readings().toList();
      final PanelReading last = readings.last;

      expect(readings, hasLength(300));
      expect(last.tilt, closeTo(30.0, 0.5));
      expect(last.magneticAzimuth, closeTo(180.0, 0.5));
    });

    test('القراءة غير الموثوقة لا تلوّث مرشّح السمت', () async {
      mockStream(<Map<String, Object?>>[
        for (int i = 0; i < 60; i++) sample(azimuth: 200.0),
        // اللوح صار أفقيًا تمامًا: عموده يشير للسماء فلا سمت له.
        sample(azimuth: 17.0, tilt: 0.4),
      ]);

      final OrientationService service = OrientationService(events: channel);
      final List<PanelReading> readings = await service.readings().toList();
      final PanelReading last = readings.last;

      expect(last.azimuthReliable, isFalse);
      expect(last.isUsable, isFalse);
      // يبقى على آخر قيمة معتبرة بدل تبنّي الـ17°.
      expect(last.magneticAzimuth, closeTo(200.0, 0.5));
    });

    test('غياب الانحراف يمنع ادّعاء سمت حقيقي', () async {
      mockStream(<Map<String, Object?>>[sample(declination: null)]);
      final OrientationService service = OrientationService(events: channel);
      final PanelReading first = await service.readings().first;

      expect(first.declination, isNull);
      expect(first.trueAzimuth, isNull);
      expect(first.isUsable, isFalse);
    });

    test('إزاحة المعايرة تنعكس على القراءات اللاحقة', () async {
      mockStream(<Map<String, Object?>>[sample()]);
      final OrientationService service = OrientationService(events: channel);
      service.applyCalibrationOffset(-17.0);

      final PanelReading first = await service.readings().first;
      expect(first.calibrationOffset, closeTo(-17.0, 1e-9));
      expect(first.trueAzimuth, closeTo(167.5, 1e-9));

      service.clearCalibration();
      expect(service.calibrationOffset, 0.0);
    });
  });
}
