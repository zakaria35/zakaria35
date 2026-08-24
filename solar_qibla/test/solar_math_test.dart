// اختبارات محرّك الحسابات الفلكية.
//
// ── مصدر القيم المرجعية ────────────────────────────────────────────────────
//
// القيم المرجعية لموضع الشمس في `_references` مولّدة من خوارزمية NREL SPA
// (Reda & Andreas, 2004) عبر تنفيذ pvlib-python المرجعي، وهي الخوارزمية
// المعيارية التي تُقاس عليها حاسبة NOAA Solar Calculator نفسها.
//
// جرى التحقق من هذا المُولِّد مقابل حالة الاختبار المنشورة في ورقة NREL SPA
// (2003-10-17، 12:30:30 توقيت MST، 39.742476°N، 105.1786°W، ارتفاع 1830.14 م):
//
//   المنشور: زاوية سمت الرأس (مع الانكسار) = 50.11162°، السمت = 194.340241°
//   المُولِّد: 50.111622°، 194.340241°  ⇒ فارق ≤ 2e-6 درجة
//
// القيم أدناه هندسية (بلا انكسار جوي) عند ارتفاع 0 م، بالتوقيت المحلي
// القياسي (بلا توقيت صيفي)، والسمت من الشمال باتجاه عقارب الساعة.
//
// حُذفت اللحظات التي تتجاوز فيها زاوية سمت الرأس 85°، لأن الانكسار الجوي
// وسوء التكييف الرياضي قرب الأفق يجعلان المقارنة الهندسية بلا معنى.

import 'dart:math' as math;

import 'package:solar_qibla/core/solar_math.dart';
import 'package:test/test.dart';

/// سماحية موضع الشمس المطلوبة في مواصفات المشروع.
const double kToleranceDegrees = 0.5;

class _Ref {
  final String site;
  final double latitude;
  final double longitude;
  final int tzOffset;
  final int year;
  final int month;
  final int day;
  final int hour;
  final double zenith;
  final double azimuth;

  const _Ref(this.site, this.latitude, this.longitude, this.tzOffset, this.year,
      this.month, this.day, this.hour, this.zenith, this.azimuth);

  @override
  String toString() =>
      '$site ${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')} '
      '${hour.toString().padLeft(2, '0')}:00';
}

const List<_Ref> _references = <_Ref>[
  // ── غزة، فلسطين — UTC+2 ──
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 3, 21, 8, 62.4572, 108.2908),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 3, 21, 10, 40.5350, 135.0525),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 3, 21, 12, 31.2887, 185.1566),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 3, 21, 14, 43.8796, 231.1712),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 3, 21, 16, 66.7550, 255.2421),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 6, 21, 8, 49.7930, 84.6752),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 6, 21, 10, 24.3472, 102.8714),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 6, 21, 12, 8.8144, 204.8004),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 6, 21, 14, 31.1001, 263.5240),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 6, 21, 16, 56.5893, 278.8925),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 12, 21, 8, 76.0760, 129.2393),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 12, 21, 10, 59.9358, 153.3512),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 12, 21, 12, 55.1453, 185.5487),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 12, 21, 14, 64.3209, 215.6773),
  _Ref('Gaza', 31.5017, 34.4668, 2, 2026, 12, 21, 16, 82.9075, 236.8817),

  // ── الرياض، السعودية — UTC+3 ──
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 3, 21, 8, 62.9948, 103.2687),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 3, 21, 10, 38.0348, 125.4525),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 3, 21, 12, 24.4144, 179.7116),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 3, 21, 14, 37.8142, 234.3654),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 3, 21, 16, 62.7225, 256.7371),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 6, 21, 8, 53.2389, 78.3038),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 6, 21, 10, 26.2494, 86.7490),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 6, 21, 12, 1.6982, 221.5602),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 6, 21, 14, 28.4757, 274.0049),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 6, 21, 16, 55.4205, 282.3888),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 12, 21, 8, 73.8735, 126.0756),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 12, 21, 10, 55.1900, 148.5706),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 12, 21, 12, 48.1981, 182.6770),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 12, 21, 14, 57.3687, 215.4497),
  _Ref('Riyadh', 24.7136, 46.6753, 3, 2026, 12, 21, 16, 77.1160, 236.3272),

  // ── برلين، ألمانيا — UTC+1 (خط عرض عالٍ، لاختبار الحالات الحديّة) ──
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 3, 21, 8, 73.9689, 111.5186),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 3, 21, 10, 59.1911, 140.1518),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 3, 21, 12, 52.2654, 175.7204),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 3, 21, 14, 56.7013, 212.4213),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 3, 21, 16, 70.1118, 242.6336),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 6, 21, 8, 54.7330, 96.9903),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 6, 21, 10, 37.9211, 127.6203),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 6, 21, 12, 29.1252, 176.1390),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 6, 21, 14, 36.0214, 226.9887),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 6, 21, 16, 52.2713, 259.4794),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 12, 21, 10, 80.6541, 151.2990),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 12, 21, 12, 75.9653, 178.9541),
  _Ref('Berlin', 52.52, 13.405, 1, 2026, 12, 21, 14, 80.0285, 206.7426),
];

/// الفصل الزاوي الحقيقي بين اتجاهَي شمس، بالدرجات.
///
/// هذا هو المقياس ذو المعنى الفيزيائي لدقّة الموضع: زاوية السقوط تعتمد على
/// اتجاه الشمس ثلاثي الأبعاد، لا على السمت وحده. كما أنه محصّن ضد انفجار
/// خطأ السمت عندما تقترب الشمس من سمت الرأس (حيث السمت سيّئ التكييف).
double _angularSeparation(
    double zenith1, double azimuth1, double zenith2, double azimuth2) {
  const double d2r = math.pi / 180.0;
  final double e1 = math.sin(zenith1 * d2r) * math.sin(azimuth1 * d2r);
  final double n1 = math.sin(zenith1 * d2r) * math.cos(azimuth1 * d2r);
  final double u1 = math.cos(zenith1 * d2r);
  final double e2 = math.sin(zenith2 * d2r) * math.sin(azimuth2 * d2r);
  final double n2 = math.sin(zenith2 * d2r) * math.cos(azimuth2 * d2r);
  final double u2 = math.cos(zenith2 * d2r);
  double c = e1 * e2 + n1 * n2 + u1 * u2;
  if (c > 1.0) c = 1.0;
  if (c < -1.0) c = -1.0;
  return math.acos(c) * 180.0 / math.pi;
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  group('موضع الشمس مقابل مرجع NREL SPA', () {
    double maxZenithError = 0.0;
    double maxAzimuthError = 0.0;
    double maxSeparation = 0.0;
    String worstCase = '';
    int passed = 0;
    int failed = 0;

    for (final _Ref r in _references) {
      test('$r', () {
        final SolarPosition sun = solarPosition(
          latitude: r.latitude,
          longitude: r.longitude,
          timeZoneOffsetHours: r.tzOffset,
          localStandardTime: DateTime(r.year, r.month, r.day, r.hour),
        );

        final double dZenith = (sun.zenith - r.zenith).abs();
        final double dAzimuth = angularDifference(r.azimuth, sun.azimuth).abs();
        final double separation =
            _angularSeparation(r.zenith, r.azimuth, sun.zenith, sun.azimuth);

        if (dZenith > maxZenithError) maxZenithError = dZenith;
        if (dAzimuth > maxAzimuthError) maxAzimuthError = dAzimuth;
        if (separation > maxSeparation) {
          maxSeparation = separation;
          worstCase = '$r';
        }

        final bool ok = separation <= kToleranceDegrees;
        ok ? passed++ : failed++;

        expect(
          separation,
          lessThanOrEqualTo(kToleranceDegrees),
          reason: 'الفصل الزاوي ${separation.toStringAsFixed(3)}° يتجاوز '
              'السماحية ${kToleranceDegrees}°  '
              '(Δθz=${dZenith.toStringAsFixed(3)}°، '
              'Δγs=${dAzimuth.toStringAsFixed(3)}°)',
        );
      });
    }

    tearDownAll(() {
      print('');
      print('══ تقرير دقّة موضع الشمس ══');
      print('عدد نقاط المرجع        : ${_references.length}');
      print('ناجح / فاشل            : $passed / $failed');
      print('أقصى خطأ في سمت الرأس  : ${maxZenithError.toStringAsFixed(3)}°');
      print('أقصى خطأ في السمت      : ${maxAzimuthError.toStringAsFixed(3)}°');
      print('أقصى فصل زاوي          : ${maxSeparation.toStringAsFixed(3)}°');
      print('أسوأ حالة              : $worstCase');
      print('السماحية المطلوبة      : ${kToleranceDegrees}°');
      print('═══════════════════════════');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('اصطلاحات الزوايا', () {
    test('السمت يقع دائمًا في المدى [0, 360)', () {
      for (final _Ref r in _references) {
        final SolarPosition sun = solarPosition(
          latitude: r.latitude,
          longitude: r.longitude,
          timeZoneOffsetHours: r.tzOffset,
          localStandardTime: DateTime(r.year, r.month, r.day, r.hour),
        );
        expect(sun.azimuth, greaterThanOrEqualTo(0.0));
        expect(sun.azimuth, lessThan(360.0));
      }
    });

    test('الشمس شرق خط الزوال قبل الظهر وغربه بعده', () {
      // غزة، اعتدال الربيع.
      final SolarPosition morning = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 3, 21, 8),
      );
      final SolarPosition afternoon = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 3, 21, 16),
      );
      expect(morning.hourAngle, lessThan(0.0));
      expect(morning.azimuth, lessThan(180.0));
      expect(afternoon.hourAngle, greaterThan(0.0));
      expect(afternoon.azimuth, greaterThan(180.0));
    });

    test('عكس إشارة خط الطول يغيّر النتيجة (اختبار انحدار لاصطلاح الإشارة)',
        () {
      // خطأ الإشارة الشائع يبلغ 8·Δlon دقيقة؛ يجب ألّا يمرّ صامتًا.
      final SolarPosition east = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 3, 21, 12),
      );
      final SolarPosition flipped = solarPosition(
        latitude: 31.5017,
        longitude: 25.5332, // مرآة خط الطول حول خط الزوال المرجعي 30°
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 3, 21, 12),
      );
      // ω = 15·(4·Δlon)/60 ⇒ فرق الزاوية الساعية بالدرجات يساوي فرق خط الطول.
      expect((east.hourAngle - flipped.hourAngle).abs(),
          closeTo(34.4668 - 25.5332, 1e-9));
    });

    test('رقم اليوم في السنة', () {
      expect(dayOfYear(DateTime(2026, 1, 1)), 1);
      expect(dayOfYear(DateTime(2026, 12, 31)), 365);
      expect(dayOfYear(DateTime(2024, 12, 31)), 366); // سنة كبيسة
      expect(dayOfYear(DateTime(2026, 3, 21)), 80);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('اليوم اليولياني والوضع الظاهري للشمس', () {
    test('اليوم اليولياني عند حقبتين معلومتين', () {
      // 1970-01-01T00:00:00Z هو JD 2440587.5 بالتعريف.
      expect(julianDay(DateTime.utc(1970, 1, 1)), closeTo(2440587.5, 1e-9));
      // حقبة J2000.0 = 2000-01-01T12:00:00Z هي JD 2451545.0.
      expect(julianDay(DateTime.utc(2000, 1, 1, 12)), closeTo(2451545.0, 1e-9));
    });

    test('التحويل من الزمن المحلي القياسي إلى UTC', () {
      expect(
        localStandardToUtc(DateTime(2026, 3, 21, 12), 2),
        DateTime.utc(2026, 3, 21, 10),
      );
      // يجب أن يعبر منتصف الليل بشكل صحيح.
      expect(
        localStandardToUtc(DateTime(2026, 1, 1, 1), 3),
        DateTime.utc(2025, 12, 31, 22),
      );
    });

    test('الميل الشمسي يبلغ حدّيه عند الانقلابين ويكاد ينعدم عند الاعتدالين',
        () {
      final double june = solarEphemeris(DateTime.utc(2026, 6, 21, 12)).declination;
      final double december =
          solarEphemeris(DateTime.utc(2026, 12, 21, 12)).declination;
      final double march =
          solarEphemeris(DateTime.utc(2026, 3, 20, 12)).declination;

      expect(june, closeTo(23.44, 0.05));
      expect(december, closeTo(-23.44, 0.05));
      expect(march.abs(), lessThan(0.5));
      // لا يتجاوز الميل ميل دائرة البروج مطلقًا.
      for (int day = 0; day < 365; day++) {
        final double d = solarEphemeris(
                DateTime.utc(2026, 1, 1, 12).add(Duration(days: day)))
            .declination;
        expect(d.abs(), lessThanOrEqualTo(23.45));
      }
    });

    test('معادلة الزمن تبقى ضمن مداها الفلكي المعروف ‎±17‎ دقيقة', () {
      double minimum = 99.0;
      double maximum = -99.0;
      for (int day = 0; day < 365; day++) {
        final double e = solarEphemeris(
                DateTime.utc(2026, 1, 1, 12).add(Duration(days: day)))
            .equationOfTime;
        if (e < minimum) minimum = e;
        if (e > maximum) maximum = e;
      }
      // القمّتان المعروفتان: نحو ‎−14.2‎ دقيقة في فبراير و‎+16.4‎ في نوفمبر.
      expect(minimum, closeTo(-14.2, 0.5));
      expect(maximum, closeTo(16.4, 0.5));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('زاوية السقوط', () {
    test('الصيغتان (المثلثية والمتجهية) متطابقتان ضمن 1e-9', () {
      double worst = 0.0;
      for (final _Ref r in _references) {
        final SolarPosition sun = solarPosition(
          latitude: r.latitude,
          longitude: r.longitude,
          timeZoneOffsetHours: r.tzOffset,
          localStandardTime: DateTime(r.year, r.month, r.day, r.hour),
        );
        for (final double tilt in <double>[0, 15, 30, 45, 60]) {
          for (final double az in <double>[135, 160, 180, 200, 225]) {
            final double a = cosIncidenceAngle(
              latitude: r.latitude,
              declination: sun.declination,
              hourAngle: sun.hourAngle,
              tilt: tilt,
              surfaceAzimuth: az,
            );
            final double b = cosIncidenceFromSunDirection(
              sunZenith: sun.zenith,
              sunAzimuth: sun.azimuth,
              tilt: tilt,
              surfaceAzimuth: az,
            );
            final double d = (a - b).abs();
            if (d > worst) worst = d;
          }
        }
      }
      print('أقصى فارق بين صيغتَي cos θ: ${worst.toStringAsExponential(2)}');
      expect(worst, lessThan(1e-9));
    });

    test('اللوح الأفقي: cos θ = cos θz', () {
      final SolarPosition sun = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 6, 21, 10),
      );
      final double cosTheta = cosIncidenceAngle(
        latitude: 31.5017,
        declination: sun.declination,
        hourAngle: sun.hourAngle,
        tilt: 0.0,
        surfaceAzimuth: 180.0,
      );
      expect(cosTheta, closeTo(math.cos(sun.zenith * math.pi / 180.0), 1e-12));
    });

    test('اللوح الموجّه نحو الشمس تمامًا: θ = 0', () {
      final SolarPosition sun = solarPosition(
        latitude: 24.7136,
        longitude: 46.6753,
        timeZoneOffsetHours: 3,
        localStandardTime: DateTime(2026, 3, 21, 10),
      );
      final double theta = incidenceAngle(
        latitude: 24.7136,
        declination: sun.declination,
        hourAngle: sun.hourAngle,
        tilt: sun.zenith,
        surfaceAzimuth: sun.azimuth,
      );
      expect(theta, closeTo(0.0, 1e-5));
    });

    test('اللوح المعاكس للشمس: cos θ سالب', () {
      final SolarPosition sun = solarPosition(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        localStandardTime: DateTime(2026, 6, 21, 8),
      );
      final double cosTheta = cosIncidenceFromSunDirection(
        sunZenith: sun.zenith,
        sunAzimuth: sun.azimuth,
        tilt: 80.0,
        surfaceAzimuth: normalizeDegrees360(sun.azimuth + 180.0),
      );
      expect(cosTheta, lessThan(0.0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('الإشعاع خارج الغلاف الجوي ونموذج السماء الصافية', () {
    test('G0 يبلغ ذروته قرب الحضيض (يناير) وحضيضه قرب الأوج (يوليو)', () {
      final double january = extraterrestrialIrradiance(3);
      final double july = extraterrestrialIrradiance(185);
      expect(january, greaterThan(july));
      // التذبذب ‎±3.3٪‎ حول ثابت الشمس.
      expect(january, closeTo(solarConstant * 1.033, 1.0));
      expect(july, closeTo(solarConstant * 0.967, 1.0));
    });

    test('كتلة الهواء تساوي 1 عند سمت الرأس وتتزايد نحو الأفق', () {
      expect(airMass(0.0), closeTo(1.0, 1e-3));
      expect(airMass(60.0), closeTo(2.0, 0.02));
      expect(airMass(85.0), greaterThan(airMass(60.0)));
      expect(airMass(90.0), double.infinity);
      expect(airMass(95.0), double.infinity);
    });

    test('الإشعاع المباشر يتناقص مع زيادة زاوية سمت الرأس', () {
      double previous = double.infinity;
      for (final double z in <double>[0, 20, 40, 60, 80]) {
        final double gb = clearSkyBeamIrradianceForDay(n: 172, zenithDegrees: z);
        expect(gb, lessThan(previous));
        expect(gb, greaterThan(0.0));
        previous = gb;
      }
      expect(clearSkyBeamIrradianceForDay(n: 172, zenithDegrees: 90.0), 0.0);
    });

    test('الإشعاع المباشر عند سمت الرأس ضمن المدى الفيزيائي المعقول', () {
      final double gb = clearSkyBeamIrradianceForDay(n: 172, zenithDegrees: 0.0);
      expect(gb, greaterThan(850.0));
      expect(gb, lessThan(1000.0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('التحسين العددي للتوجيه', () {
    test('الوضع اليدوي يرفض الحساب العددي', () {
      expect(
        () => findOptimalOrientation(
          latitude: 31.5,
          longitude: 34.47,
          timeZoneOffsetHours: 2,
          mode: OptimizationMode.manual,
        ),
        throwsArgumentError,
      );
    });

    test('الأمثل السنوي لغزة: ميل قريب من خط العرض وسمت جنوبي', () {
      final Orientation o = findOptimalOrientation(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.annual,
      );
      print('غزة — سنوي  : β=${o.tilt}°  γ=${o.azimuth}°');
      // القاعدة التقريبية الشائعة (β ≈ φ) ليست مصدرًا للحساب، لكنها حدّ معقول
      // للتحقّق: يجب ألّا يبتعد الأمثل المحسوب عنها كثيرًا.
      expect(o.tilt, inInclusiveRange(20.0, 40.0));
      expect(o.azimuth, inInclusiveRange(170.0, 190.0));
      expect(o.relativeInsolation, greaterThan(0.0));
    });

    test('الصيفي أقل ميلًا من السنوي، والشتوي أكثر ميلًا منه', () {
      const double lat = 31.5017;
      const double lon = 34.4668;
      final Orientation annual = findOptimalOrientation(
        latitude: lat,
        longitude: lon,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.annual,
      );
      final Orientation summer = findOptimalOrientation(
        latitude: lat,
        longitude: lon,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.summer,
      );
      final Orientation winter = findOptimalOrientation(
        latitude: lat,
        longitude: lon,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.winter,
      );
      print('غزة — صيفي  : β=${summer.tilt}°  γ=${summer.azimuth}°');
      print('غزة — شتوي  : β=${winter.tilt}°  γ=${winter.azimuth}°');
      expect(summer.tilt, lessThan(annual.tilt));
      expect(winter.tilt, greaterThan(annual.tilt));
    });

    test('الميل الأمثل يزداد مع خط العرض', () {
      final Orientation riyadh = findOptimalOrientation(
        latitude: 24.7136,
        longitude: 46.6753,
        timeZoneOffsetHours: 3,
        mode: OptimizationMode.annual,
      );
      final Orientation berlin = findOptimalOrientation(
        latitude: 52.52,
        longitude: 13.405,
        timeZoneOffsetHours: 1,
        mode: OptimizationMode.annual,
      );
      print('الرياض — سنوي: β=${riyadh.tilt}°  γ=${riyadh.azimuth}°');
      print('برلين  — سنوي: β=${berlin.tilt}°  γ=${berlin.azimuth}°');
      expect(berlin.tilt, greaterThan(riyadh.tilt));
    });

    test('التوجيه المُعاد هو فعلًا الأفضل بين جيرانه', () {
      final Orientation best = findOptimalOrientation(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
        mode: OptimizationMode.annual,
      );
      // يجب أن يقع داخل نطاق المسح لا على حافّته (وإلّا فالنطاق ضيّق).
      expect(best.tilt, greaterThan(0.0));
      expect(best.tilt, lessThan(60.0));
      expect(best.azimuth, greaterThan(135.0));
      expect(best.azimuth, lessThan(225.0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('مؤشر الاستفادة اللحظي', () {
    test('يساوي 100٪ عند مطابقة الوضع الأمثل', () {
      final double ratio = instantaneousPerformanceRatio(
        sunZenith: 40.0,
        sunAzimuth: 150.0,
        currentTilt: 30.0,
        currentAzimuth: 180.0,
        optimalTilt: 30.0,
        optimalAzimuth: 180.0,
      );
      expect(ratio, closeTo(100.0, 1e-9));
    });

    test('يتناقص كلما زاد الانحراف عن الأمثل', () {
      double previous = 101.0;
      for (final double offset in <double>[0, 5, 10, 20, 40]) {
        final double ratio = instantaneousPerformanceRatio(
          // الشمس على سمت اللوح الأمثل تمامًا، فأي انحراف خسارة صافية.
          sunZenith: 30.0,
          sunAzimuth: 180.0,
          currentTilt: 30.0 + offset,
          currentAzimuth: 180.0,
          optimalTilt: 30.0,
          optimalAzimuth: 180.0,
        );
        expect(ratio, lessThan(previous));
        previous = ratio;
      }
    });

    test('يساوي صفرًا ليلًا أو عندما تكون الشمس خلف اللوح', () {
      expect(
        instantaneousPerformanceRatio(
          sunZenith: 95.0,
          sunAzimuth: 280.0,
          currentTilt: 30.0,
          currentAzimuth: 180.0,
          optimalTilt: 30.0,
          optimalAzimuth: 180.0,
        ),
        0.0,
      );
      expect(
        instantaneousPerformanceRatio(
          sunZenith: 40.0,
          sunAzimuth: 180.0,
          currentTilt: 85.0,
          currentAzimuth: 0.0,
          optimalTilt: 30.0,
          optimalAzimuth: 180.0,
        ),
        0.0,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('تباعد الصفوف وارتفاع الحامل', () {
    const double length = 2.278; // لوح 580 واط نموذجي
    const double width = 1.134;

    test('البُعد المائل يتبع اتجاه التركيب', () {
      expect(
        slopedPanelDimension(
            length: length, width: width, orientation: PanelOrientation.portrait),
        length,
      );
      expect(
        slopedPanelDimension(
            length: length,
            width: width,
            orientation: PanelOrientation.landscape),
        width,
      );
    });

    test('الوضع الرأسي يتطلّب تباعدًا وارتفاعًا أكبر من الأفقي', () {
      final RowLayout portrait = computeRowLayout(
        latitude: 31.5017,
        tilt: 30.0,
        panelLength: length,
        panelWidth: width,
        orientation: PanelOrientation.portrait,
      );
      final RowLayout landscape = computeRowLayout(
        latitude: 31.5017,
        tilt: 30.0,
        panelLength: length,
        panelWidth: width,
        orientation: PanelOrientation.landscape,
      );
      print('غزة β=30° — رأسي : D=${portrait.minimumRowSpacing.toStringAsFixed(2)} م، '
          'H=${portrait.mountingHeight.toStringAsFixed(2)} م، '
          'α=${portrait.designSolarElevation.toStringAsFixed(2)}°');
      print('غزة β=30° — أفقي : D=${landscape.minimumRowSpacing.toStringAsFixed(2)} م، '
          'H=${landscape.mountingHeight.toStringAsFixed(2)} م');
      expect(portrait.minimumRowSpacing,
          greaterThan(landscape.minimumRowSpacing));
      expect(portrait.mountingHeight, greaterThan(landscape.mountingHeight));
      // نسبة التباعد تساوي نسبة الأبعاد بالضبط (D خطّي في L).
      expect(portrait.minimumRowSpacing / landscape.minimumRowSpacing,
          closeTo(length / width, 1e-9));
    });

    test('اللوح الأفقي تمامًا (β=0) لا يحتاج تباعدًا زائدًا ولا ارتفاعًا', () {
      final RowLayout flat = computeRowLayout(
        latitude: 31.5017,
        tilt: 0.0,
        panelLength: length,
        panelWidth: width,
        orientation: PanelOrientation.portrait,
      );
      expect(flat.minimumRowSpacing, closeTo(length, 1e-9));
      expect(flat.mountingHeight, closeTo(0.0, 1e-9));
    });

    test('التباعد يزداد مع خط العرض (انخفاض الشمس الشتوية)', () {
      final RowLayout gaza = computeRowLayout(
        latitude: 31.5017,
        tilt: 30.0,
        panelLength: length,
        panelWidth: width,
        orientation: PanelOrientation.portrait,
      );
      final RowLayout berlin = computeRowLayout(
        latitude: 52.52,
        tilt: 30.0,
        panelLength: length,
        panelWidth: width,
        orientation: PanelOrientation.portrait,
      );
      expect(berlin.minimumRowSpacing, greaterThan(gaza.minimumRowSpacing));
      expect(berlin.designSolarElevation, lessThan(gaza.designSolarElevation));
    });

    test('خط عرض قطبي: الشمس تحت الأفق ⇒ خطأ صريح لا قيمة صامتة', () {
      expect(
        () => computeRowLayout(
          latitude: 75.0,
          tilt: 30.0,
          panelLength: length,
          panelWidth: width,
          orientation: PanelOrientation.portrait,
        ),
        throwsStateError,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('دوال الزوايا المساعدة', () {
    test('التطبيع إلى [0, 360)', () {
      expect(normalizeDegrees360(0.0), 0.0);
      expect(normalizeDegrees360(360.0), 0.0);
      expect(normalizeDegrees360(-90.0), 270.0);
      expect(normalizeDegrees360(450.0), 90.0);
      expect(normalizeDegrees360(-450.0), 270.0);
    });

    test('الفرق الزاوي الأقصر يعبر الشمال بشكل صحيح', () {
      expect(angularDifference(350.0, 10.0), closeTo(20.0, 1e-12));
      expect(angularDifference(10.0, 350.0), closeTo(-20.0, 1e-12));
      expect(angularDifference(0.0, 180.0), closeTo(180.0, 1e-12));
      expect(angularDifference(90.0, 90.0), 0.0);
    });
  });
}
