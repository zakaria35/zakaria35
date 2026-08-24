// طبقة توجيه اللوح: نموذج القراءة، الترشيح، ومعايرة البوصلة بالشمس.
//
// القراءات الخام تصل من Kotlin عبر EventChannel بمعدّل ‎~20Hz‎، وكل المعالجة
// هنا في Dart لتكون قابلة لاختبار الوحدة دون جهاز.
//
// اصطلاح السمت هو نفسه المعتمد في solar_math.dart: من الشمال باتجاه عقارب
// الساعة، في المدى ‎[0, 360)‎.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'solar_math.dart';

// ═══════════════════════════════════════════════════════════════════════════
// استخراج التوجيه من مصفوفة الدوران
// ═══════════════════════════════════════════════════════════════════════════

/// ما دون هذا الطول للمسقط الأفقي للعمود يفقد السمت معناه.
///
/// ‎0.03‎ يقابل ميلًا نحو ‎1.7°‎: عند لوح أفقي تمامًا يشير عموده إلى السماء
/// مباشرةً فلا يكون له اتجاه أفقي، وأي رقم يُعرض عندها ضجيج محض.
const double _minimumHorizontalProjection = 0.03;

/// التوجيه المستخرج من مصفوفة الدوران، قبل الترشيح.
class RawOrientation {
  /// زاوية ميل اللوح β عن الأفقي [درجة].
  final double tilt;

  /// السمت المغناطيسي للوح [درجة، من الشمال باتجاه عقارب الساعة].
  final double magneticAzimuth;

  /// هل للسمت معنى عند هذا الميل؟
  final bool azimuthReliable;

  const RawOrientation({
    required this.tilt,
    required this.magneticAzimuth,
    required this.azimuthReliable,
  });
}

/// يستخرج ميل اللوح وسمته من مصفوفة دوران أندرويد.
///
/// [rotationMatrix] مصفوفة ‎3×3‎ من `getRotationMatrixFromVector`، مخزّنة
/// صفًّا صفًّا (تسعة عناصر).
///
/// المصفوفة تحوّل من إحداثيات الجهاز إلى الإحداثيات العالمية
/// (X = شرق، Y = شمال، Z = أعلى). والهاتف مسطّح على اللوح وشاشته للأعلى،
/// فالعمود على اللوح هو محور الجهاز ‎+Z‎، وموضعه في الإحداثيات العالمية:
///
///     R · (0, 0, 1) = (R[2], R[5], R[8])
///
/// ومنه:
///     β = arccos(R[8])            زاوية الميل عن الأفقي
///     γ = atan2(R[2], R[5])       السمت من الشمال باتجاه عقارب الساعة
///
/// لاحظ ترتيب وسيطَي atan2: الشرق أوّلًا ثم الشمال. عكسه يعطي سمتًا
/// معكوسًا حول محور الشمال–الجنوب، وهو خطأ يمرّ صامتًا لأن القيمة تبقى
/// في المدى الصحيح.
///
/// يرمي [ArgumentError] إذا لم تكن المصفوفة من تسعة عناصر.
RawOrientation orientationFromRotationMatrix(List<double> rotationMatrix) {
  if (rotationMatrix.length != 9) {
    throw ArgumentError.value(
      rotationMatrix.length,
      'rotationMatrix',
      'يجب أن تحوي مصفوفة الدوران تسعة عناصر (3×3 صفًّا صفًّا)',
    );
  }

  final double east = rotationMatrix[2];
  final double north = rotationMatrix[5];
  final double up = rotationMatrix[8];

  final double tilt =
      math.acos(up.clamp(-1.0, 1.0)) * 180.0 / math.pi;

  final double horizontal = math.sqrt(east * east + north * north);
  final bool azimuthReliable = horizontal > _minimumHorizontalProjection;

  final double azimuth =
      normalizeDegrees360(math.atan2(east, north) * 180.0 / math.pi);

  return RawOrientation(
    tilt: tilt,
    magneticAzimuth: azimuth,
    azimuthReliable: azimuthReliable,
  );
}

/// حالة دقّة البوصلة كما يبلّغ عنها النظام.
///
/// القيم تطابق ثوابت `SensorManager.SENSOR_STATUS_*` في أندرويد.
enum CompassAccuracy {
  /// المستشعر لا يُعتمد عليه إطلاقًا — تلزم المعايرة.
  unreliable(0),

  /// دقّة منخفضة — تلزم المعايرة.
  low(1),

  /// دقّة متوسطة — مقبولة مع التحفّظ.
  medium(2),

  /// دقّة عالية.
  high(3);

  const CompassAccuracy(this.androidValue);

  /// قيمة الثابت المقابل في أندرويد.
  final int androidValue;

  /// يحوّل قيمة أندرويد الخام إلى تعداد؛ أي قيمة غير معروفة تُعامل
  /// معاملة "غير موثوقة" احتياطًا للسلامة.
  static CompassAccuracy fromAndroid(int? value) {
    for (final CompassAccuracy accuracy in CompassAccuracy.values) {
      if (accuracy.androidValue == value) return accuracy;
    }
    return CompassAccuracy.unreliable;
  }

  /// هل تحتاج القراءة إلى معايرة قبل الاعتماد عليها؟
  bool get needsCalibration =>
      this == CompassAccuracy.unreliable || this == CompassAccuracy.low;
}

/// قراءة توجيه واحدة للّوح.
class PanelReading {
  /// زاوية ميل اللوح β عن الأفقي [درجة]، 0 = أفقي تمامًا.
  final double tilt;

  /// سمت اللوح المغناطيسي [درجة، من الشمال باتجاه عقارب الساعة].
  final double magneticAzimuth;

  /// الانحراف المغناطيسي عند الموقع [درجة، موجب شرقًا]، أو null قبل معرفة
  /// الموقع. مصدره `GeomagneticField` في أندرويد (النموذج المغناطيسي العالمي).
  final double? declination;

  /// إزاحة تصحيح مشتقّة من المعايرة بالشمس [درجة]، صفر ما لم يعايِر المستخدم.
  final double calibrationOffset;

  /// هل السمت ذو معنى؟ يصبح بلا معنى عندما يكون اللوح أفقيًا تمامًا، إذ
  /// ينعدم المسقط الأفقي للعمود على اللوح.
  final bool azimuthReliable;

  /// حالة دقّة البوصلة.
  final CompassAccuracy accuracy;

  const PanelReading({
    required this.tilt,
    required this.magneticAzimuth,
    required this.declination,
    required this.accuracy,
    this.calibrationOffset = 0.0,
    this.azimuthReliable = true,
  });

  /// السمت الحقيقي للوح [درجة، من الشمال الجغرافي].
  ///
  ///   γ_true = γ_mag + declination + إزاحة المعايرة
  ///
  /// يُرجع null إذا لم يُعرف الانحراف بعد (أي قبل تحديد الموقع)، لأن عرض
  /// سمت مغناطيسي على أنه حقيقي خطأ يبلغ في بعض المواقع عدّة درجات.
  double? get trueAzimuth {
    final double? magneticDeclination = declination;
    if (magneticDeclination == null) return null;
    return normalizeDegrees360(
      magneticAzimuth + magneticDeclination + calibrationOffset,
    );
  }

  /// هل يمكن الوثوق بقراءة الاتجاه في هذه اللحظة؟
  bool get isUsable =>
      azimuthReliable && !accuracy.needsCalibration && declination != null;

  PanelReading copyWith({
    double? tilt,
    double? magneticAzimuth,
    double? declination,
    double? calibrationOffset,
    bool? azimuthReliable,
    CompassAccuracy? accuracy,
  }) =>
      PanelReading(
        tilt: tilt ?? this.tilt,
        magneticAzimuth: magneticAzimuth ?? this.magneticAzimuth,
        declination: declination ?? this.declination,
        calibrationOffset: calibrationOffset ?? this.calibrationOffset,
        azimuthReliable: azimuthReliable ?? this.azimuthReliable,
        accuracy: accuracy ?? this.accuracy,
      );
}

/// مرشّح تمرير منخفض أُسّي (EMA) صالح للزوايا الدائرية.
///
/// المتوسّط الحسابي المباشر للزوايا خاطئ عند عبور الشمال: متوسّط ‎359°‎ و‎1°‎
/// يساوي ‎180°‎ بدل ‎0°‎. لذلك يرشَّح هنا متجه الوحدة (جيب الزاوية وجيب تمامها)
/// ثم تُستعاد الزاوية بـatan2، وهي الطريقة الصحيحة للكميات الدائرية.
///
/// [alpha] معامل الترشيح في المدى ‎(0, 1]‎: كلما صغر زاد التنعيم وزاد التأخّر.
/// المدى العملي الموصى به ‎0.12–0.2‎ عند ‎20Hz‎.
class CircularEma {
  CircularEma({required this.alpha})
      : assert(alpha > 0.0 && alpha <= 1.0, 'alpha يجب أن يكون في (0, 1]');

  final double alpha;

  double _sin = 0.0;
  double _cos = 0.0;
  bool _seeded = false;

  /// هل استقبل المرشّح أي عيّنة بعد؟
  bool get hasValue => _seeded;

  /// القيمة المرشَّحة الحالية [درجة، 0–360)، أو null قبل أول عيّنة.
  double? get value {
    if (!_seeded) return null;
    return normalizeDegrees360(
      math.atan2(_sin, _cos) * 180.0 / math.pi,
    );
  }

  /// يُدخل عيّنة جديدة ويُرجع القيمة المرشَّحة.
  double add(double degrees) {
    final double radians = degrees * math.pi / 180.0;
    final double s = math.sin(radians);
    final double c = math.cos(radians);

    if (!_seeded) {
      // أول عيّنة تُتبنّى كما هي: البدء من صفر يُحدث قفزة أولية مرئية.
      _sin = s;
      _cos = c;
      _seeded = true;
    } else {
      _sin += alpha * (s - _sin);
      _cos += alpha * (c - _cos);
    }
    return value!;
  }

  /// يمسح حالة المرشّح.
  void reset() {
    _sin = 0.0;
    _cos = 0.0;
    _seeded = false;
  }
}

/// مرشّح تمرير منخفض أُسّي لكمية خطّية (زاوية الميل مثلًا).
///
/// الميل محصور في ‎[0°, 180°]‎ ولا يلتفّ، فلا يحتاج معالجة دائرية.
class LinearEma {
  LinearEma({required this.alpha})
      : assert(alpha > 0.0 && alpha <= 1.0, 'alpha يجب أن يكون في (0, 1]');

  final double alpha;

  double? _value;

  /// القيمة المرشَّحة الحالية، أو null قبل أول عيّنة.
  double? get value => _value;

  double add(double sample) {
    final double? previous = _value;
    _value = previous == null ? sample : previous + alpha * (sample - previous);
    return _value!;
  }

  void reset() => _value = null;
}

/// معامل الترشيح الافتراضي — منتصف المدى الموصى به.
const double kDefaultFilterAlpha = 0.16;

// ═══════════════════════════════════════════════════════════════════════════
// المعايرة بالشمس
// ═══════════════════════════════════════════════════════════════════════════

/// يحسب إزاحة تصحيح البوصلة من مشاهدة شمسية واحدة.
///
/// **لماذا هذه الميزة إلزامية:** هياكل التركيب وإطارات الألواح من الألمنيوم
/// والفولاذ تشوّه المجال المغناطيسي المحلي، فتنحرف قراءة البوصلة انحرافًا
/// منهجيًا قد يبلغ عشرات الدرجات قرب المعدن. الشمس مرجع اتجاه لا يتأثر
/// بالمعدن إطلاقًا، فتصلح مرجعًا بديلًا موثوقًا.
///
/// الطريقة: يوجّه المستخدم حافة الهاتف نحو الشمس (أو يحاذيها مع ظلّ عمود
/// رأسي)، فنقارن ما تقوله البوصلة بموضع الشمس المحسوب من الموقع والزمن.
///
///   الإزاحة = سمت الشمس المحسوب − سمت البوصلة المرصود
///
/// [observedAzimuth] قراءة البوصلة لحظة المحاذاة، **بعد** تطبيق الانحراف
/// المغناطيسي (أي السمت الحقيقي المُدّعى) وقبل أي إزاحة معايرة سابقة.
/// [trueSolarAzimuth] سمت الشمس المحسوب من [solarPosition].
///
/// يُرجع الإزاحة في المدى ‎(-180, 180]‎.
double solarCalibrationOffset({
  required double observedAzimuth,
  required double trueSolarAzimuth,
}) =>
    angularDifference(observedAzimuth, trueSolarAzimuth);

/// أقصى إزاحة معايرة تُقبل بلا تحذير [درجة].
///
/// إزاحة تتجاوز هذا الحد تعني غالبًا خطأ في المحاذاة لا تشويشًا معدنيًا،
/// فالأجدر تنبيه المستخدم إلى إعادة المعايرة بدل تبنّي رقم مضلِّل.
const double kSuspiciousCalibrationOffset = 45.0;

/// هل الإزاحة المكتشفة كبيرة إلى حدّ يستدعي التشكيك؟
bool isCalibrationOffsetSuspicious(double offset) =>
    offset.abs() > kSuspiciousCalibrationOffset;

/// هل الشمس مرتفعة بما يكفي لتصلح مرجعًا للمعايرة؟
///
/// قرب الأفق يصبح سمت الشمس حسّاسًا لخطأ الزمن والموقع، كما يصعب على
/// المستخدم تحديد اتجاهها بدقّة. نشترط ارتفاعًا لا يقلّ عن ‎5°‎، ولا يزيد
/// على ‎70°‎ لأن السمت يفقد معناه قرب سمت الرأس.
bool isSunSuitableForCalibration(SolarPosition sun) =>
    sun.elevation >= 5.0 && sun.elevation <= 70.0;

// ═══════════════════════════════════════════════════════════════════════════
// خدمة المستشعرات
// ═══════════════════════════════════════════════════════════════════════════

/// يقرأ توجيه اللوح من طبقة أندرويد ويبثّه مرشَّحًا.
class OrientationService {
  OrientationService({
    EventChannel? events,
    MethodChannel? control,
    double alpha = kDefaultFilterAlpha,
  })  : _events = events ?? const EventChannel('solar_qibla/orientation'),
        _control = control ?? const MethodChannel('solar_qibla/control'),
        _tiltFilter = LinearEma(alpha: alpha),
        _azimuthFilter = CircularEma(alpha: alpha);

  final EventChannel _events;
  final MethodChannel _control;
  final LinearEma _tiltFilter;
  final CircularEma _azimuthFilter;

  double _calibrationOffset = 0.0;

  /// إزاحة المعايرة المطبَّقة حاليًا [درجة].
  double get calibrationOffset => _calibrationOffset;

  /// يطبّق إزاحة معايرة جديدة على القراءات اللاحقة.
  void applyCalibrationOffset(double offset) => _calibrationOffset = offset;

  /// يلغي المعايرة ويعود إلى البوصلة المغناطيسية وحدها.
  void clearCalibration() => _calibrationOffset = 0.0;

  /// يزوّد طبقة أندرويد بالموقع لتحسب الانحراف المغناطيسي.
  Future<void> setLocation({
    required double latitude,
    required double longitude,
    double altitude = 0.0,
  }) =>
      _control.invokeMethod<void>('setLocation', <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
      });

  /// تدفّق قراءات التوجيه المرشَّحة.
  Stream<PanelReading> readings() {
    _tiltFilter.reset();
    _azimuthFilter.reset();

    return _events.receiveBroadcastStream().map((dynamic event) {
      final Map<Object?, Object?> raw = event as Map<Object?, Object?>;
      return _decode(raw);
    });
  }

  PanelReading _decode(Map<Object?, Object?> raw) {
    final List<double> matrix =
        (raw['rotationMatrix'] as List<Object?>).cast<num>()
            .map((num v) => v.toDouble())
            .toList(growable: false);

    final RawOrientation orientation = orientationFromRotationMatrix(matrix);
    final bool azimuthReliable = orientation.azimuthReliable;
    final num? rawDeclination = raw['declination'] as num?;

    return PanelReading(
      tilt: _tiltFilter.add(orientation.tilt),
      // لا يُغذّى مرشّح السمت بقراءة بلا معنى: تلويثه بها يُفسد الخرج
      // لثوانٍ بعد عودة اللوح إلى ميل معتبر.
      magneticAzimuth: azimuthReliable
          ? _azimuthFilter.add(orientation.magneticAzimuth)
          : (_azimuthFilter.value ?? orientation.magneticAzimuth),
      declination: rawDeclination?.toDouble(),
      calibrationOffset: _calibrationOffset,
      azimuthReliable: azimuthReliable,
      accuracy: CompassAccuracy.fromAndroid((raw['accuracy'] as num?)?.toInt()),
    );
  }
}
