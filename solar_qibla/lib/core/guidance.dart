// منطق الإرشاد الميداني: تحويل الفرق بين التوجيه الحالي والهدف إلى
// تعليمات عربية وترميز لوني.
//
// نقي وقابل للاختبار بالكامل: لا يستورد شيئًا من طبقة الواجهة.

import 'orientation.dart';
import 'solar_math.dart';

/// نطاق المطابقة، وهو أساس الترميز اللوني الموحّد في الواجهة.
enum AlignmentBand {
  /// انحراف ‎≤ 3°‎ في المحورين — أخضر.
  onTarget,

  /// انحراف ‎≤ 10°‎ — أصفر.
  close,

  /// انحراف ‎> 10°‎ — برتقالي.
  far,
}

/// حدّ النطاق الأخضر [درجة].
const double kOnTargetThreshold = 3.0;

/// حدّ النطاق الأصفر [درجة].
const double kCloseThreshold = 10.0;

/// يصنّف انحرافًا مطلقًا إلى نطاق لوني.
AlignmentBand bandForDeviation(double deviationDegrees) {
  final double magnitude = deviationDegrees.abs();
  if (magnitude <= kOnTargetThreshold) return AlignmentBand.onTarget;
  if (magnitude <= kCloseThreshold) return AlignmentBand.close;
  return AlignmentBand.far;
}

/// يدمج نطاقَي محورين: النتيجة هي الأسوأ منهما.
///
/// المطابقة تتطلّب المحورين معًا؛ لوح مضبوط الميل ومنحرف السمت ليس مضبوطًا.
AlignmentBand worstBand(AlignmentBand a, AlignmentBand b) =>
    a.index >= b.index ? a : b;

/// جهة تحريك السمت.
enum TurnDirection {
  /// أدر باتجاه عقارب الساعة.
  clockwise,

  /// أدر عكس عقارب الساعة.
  counterClockwise,

  /// لا حاجة للتحريك.
  none,
}

/// جهة تحريك الميل.
enum TiltDirection {
  /// ارفع الحافة العليا (زد زاوية الميل).
  raise,

  /// اخفض الحافة العليا (أنقص زاوية الميل).
  lower,

  /// لا حاجة للتحريك.
  none,
}

/// دقّة عرض الزوايا في الواجهة [منزلة عشرية].
///
/// منزلة واحدة تكفي وتزيد: دقّة البوصلة نفسها أسوأ من ‎0.1°‎ بكثير، وعرض
/// منازل أكثر يوهم بدقّة غير موجودة.
const int kAngleDecimals = 1;

/// يصوغ زاوية بوحدتها وبدقّة عرض موحّدة.
String formatDegrees(double value) =>
    '${value.toStringAsFixed(kAngleDecimals)}°';

/// إرشاد كامل للحظة واحدة.
class AimingGuidance {
  /// الانحراف في السمت [درجة]: موجب يعني أن الهدف باتجاه عقارب الساعة.
  /// يساوي null إذا تعذّرت قراءة السمت.
  final double? azimuthDeviation;

  /// الانحراف في الميل [درجة]: موجب يعني أن اللوح أميل من الهدف.
  final double tiltDeviation;

  /// نسبة الاستفادة اللحظية ‎[0, 100]‎، أو null إذا كانت الشمس تحت الأفق
  /// أو تعذّرت قراءة السمت.
  final double? performanceRatio;

  /// النطاق اللوني الإجمالي.
  final AlignmentBand band;

  const AimingGuidance({
    required this.azimuthDeviation,
    required this.tiltDeviation,
    required this.performanceRatio,
    required this.band,
  });

  /// جهة إدارة اللوح.
  TurnDirection get turnDirection {
    final double? deviation = azimuthDeviation;
    if (deviation == null) return TurnDirection.none;
    if (deviation.abs() <= kOnTargetThreshold) return TurnDirection.none;
    return deviation > 0
        ? TurnDirection.clockwise
        : TurnDirection.counterClockwise;
  }

  /// جهة تعديل الميل.
  TiltDirection get tiltDirection {
    if (tiltDeviation.abs() <= kOnTargetThreshold) return TiltDirection.none;
    return tiltDeviation < 0 ? TiltDirection.raise : TiltDirection.lower;
  }

  /// هل بلغ اللوح الوضع الأمثل في المحورين؟
  bool get isOnTarget => band == AlignmentBand.onTarget;

  /// تعليمة السمت بالعربية، مع الوحدة.
  String get azimuthInstruction {
    final double? deviation = azimuthDeviation;
    if (deviation == null) return 'قراءة الاتجاه غير متاحة';
    switch (turnDirection) {
      case TurnDirection.none:
        return 'الاتجاه مضبوط';
      case TurnDirection.clockwise:
        return 'در ${formatDegrees(deviation.abs())} يمينًا';
      case TurnDirection.counterClockwise:
        return 'در ${formatDegrees(deviation.abs())} يسارًا';
    }
  }

  /// تعليمة الميل بالعربية، مع الوحدة.
  String get tiltInstruction {
    switch (tiltDirection) {
      case TiltDirection.none:
        return 'الميل مضبوط';
      case TiltDirection.raise:
        return 'ارفع ${formatDegrees(tiltDeviation.abs())}';
      case TiltDirection.lower:
        return 'اخفض ${formatDegrees(tiltDeviation.abs())}';
    }
  }
}

/// يحسب الإرشاد من القراءة الحالية والتوجيه الهدف وموضع الشمس.
///
/// [sun] موضع الشمس الآن؛ يُمرَّر null ليلًا فتسقط نسبة الاستفادة.
AimingGuidance computeGuidance({
  required PanelReading reading,
  required double targetTilt,
  required double targetAzimuth,
  SolarPosition? sun,
}) {
  final double tiltDeviation = reading.tilt - targetTilt;

  final double? currentAzimuth = reading.trueAzimuth;
  final double? azimuthDeviation =
      (currentAzimuth == null || !reading.azimuthReliable)
          ? null
          : angularDifference(currentAzimuth, targetAzimuth);

  // النطاق الإجمالي هو الأسوأ بين المحورين. وعند تعذّر قراءة السمت لا
  // يُدّعى أن اللوح مضبوط: يُعامل المحور المجهول معاملة الأسوأ.
  final AlignmentBand tiltBand = bandForDeviation(tiltDeviation);
  final AlignmentBand band = azimuthDeviation == null
      ? AlignmentBand.far
      : worstBand(tiltBand, bandForDeviation(azimuthDeviation));

  double? ratio;
  if (sun != null && sun.isDaylight && currentAzimuth != null) {
    ratio = instantaneousPerformanceRatio(
      sunZenith: sun.zenith,
      sunAzimuth: sun.azimuth,
      currentTilt: reading.tilt,
      currentAzimuth: currentAzimuth,
      optimalTilt: targetTilt,
      optimalAzimuth: targetAzimuth,
    );
  }

  return AimingGuidance(
    azimuthDeviation: azimuthDeviation,
    tiltDeviation: tiltDeviation,
    performanceRatio: ratio,
    band: band,
  );
}

/// قراءة مثبَّتة يحفظها المستخدم عند بلوغ الوضع المطلوب.
class SavedReading {
  /// زاوية الميل المسجَّلة [درجة].
  final double tilt;

  /// السمت الحقيقي المسجَّل [درجة من الشمال الجغرافي].
  final double azimuth;

  /// الميل الهدف وقت التسجيل [درجة].
  final double targetTilt;

  /// السمت الهدف وقت التسجيل [درجة].
  final double targetAzimuth;

  /// خط العرض [درجة].
  final double latitude;

  /// خط الطول [درجة].
  final double longitude;

  /// لحظة التسجيل.
  final DateTime timestamp;

  /// حالة دقّة البوصلة وقت التسجيل — جزء من مصداقية القراءة.
  final CompassAccuracy accuracy;

  const SavedReading({
    required this.tilt,
    required this.azimuth,
    required this.targetTilt,
    required this.targetAzimuth,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracy,
  });
}
