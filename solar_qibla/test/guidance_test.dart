// اختبارات منطق الإرشاد: النطاقات اللونية، جهات التحريك، ونصوص التعليمات.

import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/core/guidance.dart';
import 'package:solar_qibla/core/orientation.dart';
import 'package:solar_qibla/core/solar_math.dart';

PanelReading readingAt({
  required double tilt,
  required double azimuth,
  double declination = 0.0,
  bool azimuthReliable = true,
  CompassAccuracy accuracy = CompassAccuracy.high,
}) =>
    PanelReading(
      tilt: tilt,
      magneticAzimuth: azimuth,
      declination: declination,
      azimuthReliable: azimuthReliable,
      accuracy: accuracy,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  group('النطاقات اللونية', () {
    test('الحدود مطابقة للمواصفات: ‎3°‎ و‎10°‎', () {
      expect(bandForDeviation(0.0), AlignmentBand.onTarget);
      expect(bandForDeviation(3.0), AlignmentBand.onTarget);
      expect(bandForDeviation(3.01), AlignmentBand.close);
      expect(bandForDeviation(10.0), AlignmentBand.close);
      expect(bandForDeviation(10.01), AlignmentBand.far);
    });

    test('الإشارة لا تغيّر النطاق', () {
      expect(bandForDeviation(-2.0), AlignmentBand.onTarget);
      expect(bandForDeviation(-7.0), AlignmentBand.close);
      expect(bandForDeviation(-40.0), AlignmentBand.far);
    });

    test('دمج نطاقين يأخذ الأسوأ', () {
      expect(worstBand(AlignmentBand.onTarget, AlignmentBand.far),
          AlignmentBand.far);
      expect(worstBand(AlignmentBand.close, AlignmentBand.onTarget),
          AlignmentBand.close);
      expect(worstBand(AlignmentBand.onTarget, AlignmentBand.onTarget),
          AlignmentBand.onTarget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('جهة التحريك ونصّ التعليمة', () {
    test('اللوح المطابق: لا تحريك في المحورين', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.turnDirection, TurnDirection.none);
      expect(g.tiltDirection, TiltDirection.none);
      expect(g.isOnTarget, isTrue);
      expect(g.azimuthInstruction, 'الاتجاه مضبوط');
      expect(g.tiltInstruction, 'الميل مضبوط');
    });

    test('السمت أقلّ من الهدف ⇒ در يمينًا', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 160.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.azimuthDeviation, closeTo(20.0, 1e-9));
      expect(g.turnDirection, TurnDirection.clockwise);
      expect(g.azimuthInstruction, 'در 20.0° يمينًا');
    });

    test('السمت أكبر من الهدف ⇒ در يسارًا', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 200.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.azimuthDeviation, closeTo(-20.0, 1e-9));
      expect(g.turnDirection, TurnDirection.counterClockwise);
      expect(g.azimuthInstruction, 'در 20.0° يسارًا');
    });

    test('الفرق يُحسب بأقصر مسار عبر الشمال', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 350.0),
        targetTilt: 30.0,
        targetAzimuth: 10.0,
      );
      // لا ‎−340°‎ بل ‎+20°‎.
      expect(g.azimuthDeviation, closeTo(20.0, 1e-9));
      expect(g.turnDirection, TurnDirection.clockwise);
    });

    test('الميل دون الهدف ⇒ ارفع، وفوقه ⇒ اخفض', () {
      final AimingGuidance low = computeGuidance(
        reading: readingAt(tilt: 18.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(low.tiltDirection, TiltDirection.raise);
      expect(low.tiltInstruction, 'ارفع 12.0°');

      final AimingGuidance high = computeGuidance(
        reading: readingAt(tilt: 42.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(high.tiltDirection, TiltDirection.lower);
      expect(high.tiltInstruction, 'اخفض 12.0°');
    });

    test('كل رقم معروض مصحوب بوحدته', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 18.0, azimuth: 160.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.azimuthInstruction, contains('°'));
      expect(g.tiltInstruction, contains('°'));
      expect(formatDegrees(12.345), '12.3°'); // دقّة عرض موحّدة
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('المحور المجهول لا يُحسب مضبوطًا', () {
    test('السمت غير الموثوق يُسقط النطاق إلى "بعيد"', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 180.0, azimuthReliable: false),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.azimuthDeviation, isNull);
      expect(g.isOnTarget, isFalse);
      expect(g.band, AlignmentBand.far);
      expect(g.azimuthInstruction, 'قراءة الاتجاه غير متاحة');
    });

    test('غياب الانحراف المغناطيسي يُسقط النطاق كذلك', () {
      const PanelReading reading = PanelReading(
        tilt: 30.0,
        magneticAzimuth: 180.0,
        declination: null,
        accuracy: CompassAccuracy.high,
      );
      final AimingGuidance g = computeGuidance(
        reading: reading,
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.azimuthDeviation, isNull);
      expect(g.isOnTarget, isFalse);
    });

    test('ميل مضبوط وسمت منحرف ليس وضعًا مضبوطًا', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 150.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(bandForDeviation(g.tiltDeviation), AlignmentBand.onTarget);
      expect(g.band, AlignmentBand.far);
      expect(g.isOnTarget, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('نسبة الاستفادة اللحظية', () {
    SolarPosition sunOverGaza(int hour) => solarPosition(
          latitude: 31.5017,
          longitude: 34.4668,
          timeZoneOffsetHours: 2,
          localStandardTime: DateTime(2026, 3, 21, hour),
        );

    test('تبلغ 100٪ عند مطابقة الهدف', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
        sun: sunOverGaza(10),
      );
      expect(g.performanceRatio, closeTo(100.0, 1e-6));
    });

    test('تتناقص مع الانحراف', () {
      final SolarPosition sun = sunOverGaza(10);
      double? previous;
      for (final double offset in <double>[0, 10, 25, 45]) {
        final AimingGuidance g = computeGuidance(
          reading: readingAt(tilt: 30.0, azimuth: 180.0 + offset),
          targetTilt: 30.0,
          targetAzimuth: 180.0,
          sun: sun,
        );
        final double? ratio = g.performanceRatio;
        expect(ratio, isNotNull);
        if (previous != null) expect(ratio!, lessThan(previous));
        previous = ratio;
      }
    });

    test('غير متاحة ليلًا', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
        sun: sunOverGaza(2), // قبل الشروق
      );
      expect(g.performanceRatio, isNull);
    });

    test('غير متاحة بلا موضع شمس', () {
      final AimingGuidance g = computeGuidance(
        reading: readingAt(tilt: 30.0, azimuth: 180.0),
        targetTilt: 30.0,
        targetAzimuth: 180.0,
      );
      expect(g.performanceRatio, isNull);
    });
  });
}
