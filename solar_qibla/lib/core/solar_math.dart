// محرّك الحسابات الفلكية لتطبيق "قِبلة الشمس".
//
// Dart نقي: لا واجهة، لا إنترنت، لا مستشعرات. كل الدوال هنا نقية وقابلة للاختبار.
//
// المراجع:
//   [1] Duffie, J.A. & Beckman, W.A. — "Solar Engineering of Thermal Processes".
//       مصدر هندسة السطح المائل: زاوية السقوط، تباعد الصفوف، منطق التحسين.
//   [2] Meeus, J. — "Astronomical Algorithms" (الصيغة منخفضة الدقة)، وهي
//       الخوارزمية التي تقوم عليها حاسبة NOAA Solar Calculator.
//       مصدر الميل الشمسي ومعادلة الزمن.
//
// ملاحظة على اختيار [2]: المواصفات الأولية نصّت على معادلة Cooper للميل
// والصيغة المبسّطة لمعادلة الزمن. جرى قياسهما مقابل مرجع NREL SPA فبلغ أقصى
// خطأ زاويّ 0.822°، وهو يتجاوز سماحية المشروع 0.5°، وكان الفشل كلّه عند
// الاعتدال حيث يبلغ خطأ Cooper ذروته. خوارزمية NOAA/Meeus أدناه قِيست بنفس
// الطريقة فبلغ أقصى خطأ 0.015°، فاعتُمدت بدلًا منهما.
//
// ── اصطلاحات الزوايا المعتمدة في هذا الملف ────────────────────────────────
//
//  * كل الزوايا العامّة (المُدخلة والمُخرجة) بالدرجات، لا بالراديان.
//
//  * خط الطول `longitude`: موجب شرقًا (اصطلاح ISO 6709 / GPS).
//    تنبيه: كتاب Duffie & Beckman يستخدم الاصطلاح المعاكس (موجب غربًا).
//    لذلك معادلة الزمن الشمسي هنا مكتوبة بالصيغة المكافئة شرقيّة‑الموجب.
//    راجع [trueSolarTime] للتفصيل.
//
//  * السمت `azimuth`: من الشمال، باتجاه عقارب الساعة، في المدى [0, 360).
//    شمال = 0°، شرق = 90°، جنوب = 180°، غرب = 270°.
//    تنبيه: زاوية السمت γs في Duffie & Beckman تُقاس من الجنوب (موجبة غربًا).
//    التحويل بين الاصطلاحين هو ±180°. راجع [solarAzimuth] و[cosIncidenceAngle].
//
//  * الزاوية الساعية ω: سالبة قبل الظهر الشمسي، موجبة بعده، 15° لكل ساعة.
//
//  * زاوية الميل β: 0° = اللوح أفقي (مواجه للسماء)، 90° = اللوح رأسي.

import 'dart:math' as math;

// ═══════════════════════════════════════════════════════════════════════════
// ثوابت
// ═══════════════════════════════════════════════════════════════════════════

/// ثابت الشمس — متوسّط الإشعاع خارج الغلاف الجوي [W/m²].
const double solarConstant = 1367.0;

const double _deg2rad = math.pi / 180.0;
const double _rad2deg = 180.0 / math.pi;

double _sinD(double deg) => math.sin(deg * _deg2rad);
double _cosD(double deg) => math.cos(deg * _deg2rad);

/// يحصر القيمة في [-1, 1] قبل تمريرها إلى acos/asin،
/// لتفادي NaN الناتج عن خطأ التقريب العشري.
double _clampUnit(double v) => v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v);

/// يُرجع الزاوية في المدى [0, 360).
double normalizeDegrees360(double deg) {
  final double m = deg % 360.0;
  return m < 0.0 ? m + 360.0 : m;
}

/// أصغر فرق زاوي بين اتجاهين، في المدى (-180, 180].
/// موجب = [to] يقع باتجاه عقارب الساعة من [from].
double angularDifference(double from, double to) {
  final double d = normalizeDegrees360(to - from);
  return d > 180.0 ? d - 360.0 : d;
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. رقم اليوم في السنة
// ═══════════════════════════════════════════════════════════════════════════

/// رقم اليوم في السنة N (1 = 1 يناير).
///
/// يُرجع 366 في السنوات الكبيسة ليوم 31 ديسمبر؛ المعادلات التقريبية أدناه
/// وُضعت لسنة من 365 يومًا، والفرق الناتج أقل من خطأها الأصلي.
int dayOfYear(DateTime date) {
  final DateTime startOfYear = DateTime(date.year, 1, 1);
  final DateTime day = DateTime(date.year, date.month, date.day);
  return day.difference(startOfYear).inDays + 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// 2 و 3. الميل الشمسي ومعادلة الزمن — خوارزمية NOAA / Meeus
// ═══════════════════════════════════════════════════════════════════════════

/// اليوم اليولياني JD الموافق للحظة UTC معطاة.
///
/// الحقبة اليوليانية 2440587.5 توافق 1970-01-01T00:00:00Z.
double julianDay(DateTime utc) =>
    utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;

/// حصيلة حساب الوضع الظاهري للشمس في لحظة محدّدة.
class SolarEphemeris {
  /// الميل الشمسي δ بالدرجات.
  final double declination;

  /// معادلة الزمن EoT بالدقائق.
  final double equationOfTime;

  const SolarEphemeris({
    required this.declination,
    required this.equationOfTime,
  });
}

/// يحسب الميل الشمسي ومعادلة الزمن للحظة UTC — خوارزمية NOAA / Meeus.
///
/// دقّة الموضع الناتجة نحو ‎0.015°‎ مقارنةً بـNREL SPA للفترة 1900–2100،
/// وهي أدقّ بخمسين ضعفًا من معادلة Cooper مع الصيغة المبسّطة لمعادلة الزمن.
///
/// تُهمل الخوارزمية فرق الزمن ΔT بين TT وUT (كما تفعل حاسبة NOAA نفسها)؛
/// أثر ذلك على موضع الشمس أقلّ من ‎0.001°‎.
SolarEphemeris solarEphemeris(DateTime utc) {
  // القرن اليولياني منذ حقبة J2000.0.
  final double t = (julianDay(utc) - 2451545.0) / 36525.0;

  // خط الطول الوسطي الهندسي للشمس [درجة].
  final double meanLongitude =
      normalizeDegrees360(280.46646 + t * (36000.76983 + t * 0.0003032));

  // الشذوذ الوسطي للشمس [درجة].
  final double meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t);

  // الانحراف المداري للأرض [بلا وحدة].
  final double eccentricity =
      0.016708634 - t * (0.000042037 + 0.0000001267 * t);

  // معادلة المركز [درجة].
  final double m = meanAnomaly * _deg2rad;
  final double center = math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * m) * (0.019993 - 0.000101 * t) +
      math.sin(3 * m) * 0.000289;

  // خط الطول الظاهري للشمس، مصحّحًا للانحراف والتزيّح [درجة].
  final double omegaNode = 125.04 - 1934.136 * t;
  final double apparentLongitude =
      meanLongitude + center - 0.00569 - 0.00478 * _sinD(omegaNode);

  // ميل دائرة البروج المصحّح [درجة].
  final double seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813));
  final double meanObliquity = 23.0 + (26.0 + seconds / 60.0) / 60.0;
  final double obliquity = meanObliquity + 0.00256 * _cosD(omegaNode);

  // الميل الشمسي: sin δ = sin ε · sin λ
  final double declination =
      math.asin(_clampUnit(_sinD(obliquity) * _sinD(apparentLongitude))) *
          _rad2deg;

  // معادلة الزمن [دقيقة].
  final double y = math.pow(math.tan(obliquity / 2.0 * _deg2rad), 2).toDouble();
  final double l0 = meanLongitude * _deg2rad;
  final double equationOfTime = 4.0 *
      _rad2deg *
      (y * math.sin(2 * l0) -
          2 * eccentricity * math.sin(m) +
          4 * eccentricity * y * math.sin(m) * math.cos(2 * l0) -
          0.5 * y * y * math.sin(4 * l0) -
          1.25 * eccentricity * eccentricity * math.sin(2 * m));

  return SolarEphemeris(
    declination: declination,
    equationOfTime: equationOfTime,
  );
}

/// يحوّل زمنًا محليًا قياسيًا (بلا توقيت صيفي) إلى UTC.
DateTime localStandardToUtc(DateTime localStandardTime, int timeZoneOffsetHours) =>
    DateTime.utc(
      localStandardTime.year,
      localStandardTime.month,
      localStandardTime.day,
      localStandardTime.hour,
      localStandardTime.minute,
      localStandardTime.second,
    ).subtract(Duration(hours: timeZoneOffsetHours));

// ═══════════════════════════════════════════════════════════════════════════
// 4. الزمن الشمسي الحقيقي
// ═══════════════════════════════════════════════════════════════════════════

/// الزمن الشمسي الحقيقي بالساعات العشرية [0, 24).
///
/// [localStandardTimeHours] الساعة المحلية القياسية بالساعات العشرية،
/// **بدون** التوقيت الصيفي (اطرح ساعة إن كان مُفعّلًا).
/// [longitude] خط الطول موجبًا شرقًا.
/// [timeZoneOffsetHours] إزاحة المنطقة الزمنية القياسية عن UTC (مثال: ‎+2‎ لغزة).
/// [equationOfTimeMinutes] معادلة الزمن للحظة نفسها، من [solarEphemeris].
///
/// صيغة Duffie & Beckman الأصلية (خط الطول موجب **غربًا**):
///   ST = LST + 4·(L_standard − L_local) + EoT
///
/// وبما أننا نستخدم خط الطول موجبًا **شرقًا** (اصطلاح GPS)، فإن كلتا القيمتين
/// تنقلب إشارتهما، فتصبح الصيغة المكافئة:
///   ST = LST + 4·(L_local − L_standard) + EoT ،  L_standard = 15 · tzOffset
///
/// إغفال هذا الانقلاب هو الخطأ الأشيع في تطبيقات هذه المعادلة، وأثره يبلغ
/// ضعف فرق خط الطول عن خط الطول المرجعي للمنطقة الزمنية.
double trueSolarTime({
  required double localStandardTimeHours,
  required double longitude,
  required int timeZoneOffsetHours,
  required double equationOfTimeMinutes,
}) {
  final double standardMeridian = 15.0 * timeZoneOffsetHours;
  final double correctionMinutes =
      4.0 * (longitude - standardMeridian) + equationOfTimeMinutes;
  return localStandardTimeHours + correctionMinutes / 60.0;
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. الزاوية الساعية
// ═══════════════════════════════════════════════════════════════════════════

/// الزاوية الساعية ω بالدرجات: ω = 15 · (ST − 12).
/// سالبة قبل الظهر الشمسي، موجبة بعده.
double hourAngle(double solarTimeHours) => 15.0 * (solarTimeHours - 12.0);

// ═══════════════════════════════════════════════════════════════════════════
// 6 و 7. موضع الشمس
// ═══════════════════════════════════════════════════════════════════════════

/// موضع الشمس الهندسي في لحظة ومكان محدّدين.
///
/// هندسي بحت: لا يتضمّن الانكسار الجوي، الذي يرفع الشمس الظاهرة نحو ‎0.5°‎
/// عند الأفق ويكاد ينعدم أثره فوق ارتفاع ‎15°‎.
class SolarPosition {
  /// زاوية سمت الرأس θz بالدرجات (0° = الشمس عموديًا فوق الرأس).
  final double zenith;

  /// سمت الشمس γs بالدرجات، من الشمال باتجاه عقارب الساعة، [0, 360).
  final double azimuth;

  /// الميل الشمسي δ بالدرجات.
  final double declination;

  /// الزاوية الساعية ω بالدرجات.
  final double hourAngle;

  const SolarPosition({
    required this.zenith,
    required this.azimuth,
    required this.declination,
    required this.hourAngle,
  });

  /// الارتفاع الشمسي α = 90 − θz بالدرجات. سالب = الشمس تحت الأفق.
  double get elevation => 90.0 - zenith;

  /// هل الشمس فوق الأفق هندسيًا؟
  bool get isDaylight => zenith < 90.0;
}

/// يحسب موضع الشمس من الموقع والزمن المحلي القياسي.
///
/// [localStandardTime] زمن مدني محلي **بدون** توقيت صيفي؛
/// حقول التاريخ منه تُستخدم لاشتقاق N، وحقول الساعة للزمن الشمسي.
SolarPosition solarPosition({
  required double latitude,
  required double longitude,
  required int timeZoneOffsetHours,
  required DateTime localStandardTime,
}) {
  final SolarEphemeris ephemeris = solarEphemeris(
    localStandardToUtc(localStandardTime, timeZoneOffsetHours),
  );

  final double hours = localStandardTime.hour +
      localStandardTime.minute / 60.0 +
      localStandardTime.second / 3600.0;

  final double st = trueSolarTime(
    localStandardTimeHours: hours,
    longitude: longitude,
    timeZoneOffsetHours: timeZoneOffsetHours,
    equationOfTimeMinutes: ephemeris.equationOfTime,
  );

  return solarPositionFromAngles(
    latitude: latitude,
    declination: ephemeris.declination,
    hourAngle: hourAngle(st),
  );
}

/// يحسب موضع الشمس مباشرةً من φ و δ و ω — نواة حسابية بلا تحويل زمني.
SolarPosition solarPositionFromAngles({
  required double latitude,
  required double declination,
  required double hourAngle,
}) {
  final double phi = latitude;
  final double delta = declination;
  final double omega = hourAngle;

  // (6) cos θz = sin φ · sin δ + cos φ · cos δ · cos ω
  final double cosZenith = _clampUnit(
    _sinD(phi) * _sinD(delta) + _cosD(phi) * _cosD(delta) * _cosD(omega),
  );
  final double zenith = math.acos(cosZenith) * _rad2deg;
  final double sinZenith = math.sin(zenith * _deg2rad);

  double azimuth;
  if (sinZenith.abs() < 1e-9) {
    // الشمس في سمت الرأس تمامًا: السمت غير معرّف رياضيًا. نُرجع 180°
    // اصطلاحًا. عمليًا لا أثر لهذا: عند θz ≈ 0 يكون cos θ شبه ثابت
    // مهما كان سمت اللوح.
    azimuth = 180.0;
  } else {
    // (7) γs = sign(ω) · |arccos((cos θz · sin φ − sin δ) / (sin θz · cos φ))|
    //
    // هذه صيغة Duffie & Beckman، ونتيجتها مقيسة **من الجنوب** وموجبة غربًا.
    // نضيف 180° للتحويل إلى السمت البوصلي من الشمال باتجاه عقارب الساعة.
    final double cosAz = _clampUnit(
      (cosZenith * _sinD(phi) - _sinD(delta)) / (sinZenith * _cosD(phi)),
    );
    final double magnitude = math.acos(cosAz) * _rad2deg;
    final double fromSouth = omega < 0.0 ? -magnitude : magnitude;
    azimuth = normalizeDegrees360(fromSouth + 180.0);
  }

  return SolarPosition(
    zenith: zenith,
    azimuth: azimuth,
    declination: delta,
    hourAngle: omega,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. زاوية السقوط على سطح مائل
// ═══════════════════════════════════════════════════════════════════════════

/// جيب تمام زاوية السقوط cos θ على سطح مائل — Duffie & Beckman.
///
/// [tilt] زاوية ميل اللوح β بالدرجات.
/// [surfaceAzimuth] سمت اللوح **من الشمال باتجاه عقارب الساعة** [0, 360).
///
/// المعادلة المرجعية تستخدم γ مقيسة من الجنوب، لذا نطرح 180° أولًا:
///
///   cos θ = sinδ·sinφ·cosβ − sinδ·cosφ·sinβ·cosγ + cosδ·cosφ·cosβ·cosω
///         + cosδ·sinφ·sinβ·cosγ·cosω + cosδ·sinβ·sinγ·sinω
///
/// قيمة سالبة تعني أن الشمس خلف مستوى اللوح (لا إشعاع مباشر).
double cosIncidenceAngle({
  required double latitude,
  required double declination,
  required double hourAngle,
  required double tilt,
  required double surfaceAzimuth,
}) {
  final double phi = latitude;
  final double delta = declination;
  final double omega = hourAngle;
  final double beta = tilt;
  final double gamma = surfaceAzimuth - 180.0; // إلى اصطلاح "من الجنوب"

  return _sinD(delta) * _sinD(phi) * _cosD(beta) -
      _sinD(delta) * _cosD(phi) * _sinD(beta) * _cosD(gamma) +
      _cosD(delta) * _cosD(phi) * _cosD(beta) * _cosD(omega) +
      _cosD(delta) * _sinD(phi) * _sinD(beta) * _cosD(gamma) * _cosD(omega) +
      _cosD(delta) * _sinD(beta) * _sinD(gamma) * _sinD(omega);
}

/// زاوية السقوط θ بالدرجات [0, 180].
double incidenceAngle({
  required double latitude,
  required double declination,
  required double hourAngle,
  required double tilt,
  required double surfaceAzimuth,
}) {
  return math.acos(_clampUnit(cosIncidenceAngle(
        latitude: latitude,
        declination: declination,
        hourAngle: hourAngle,
        tilt: tilt,
        surfaceAzimuth: surfaceAzimuth,
      ))) *
      _rad2deg;
}

/// جيب تمام زاوية السقوط محسوبًا من اتجاه الشمس مباشرةً (حاصل ضرب قياسي).
///
/// مكافئ رياضيًا لـ[cosIncidenceAngle] لكنه أسرع بكثير عند تكرار الحساب على
/// آلاف التوجيهات لنفس لحظة الشمس، لأنه يعيد استخدام اتجاه الشمس المحسوب مرة
/// واحدة. يستعمله المُحسِّن العددي في [findOptimalOrientation].
/// يتحقّق الاختبار من تطابق الصيغتين ضمن 1e-9.
double cosIncidenceFromSunDirection({
  required double sunZenith,
  required double sunAzimuth,
  required double tilt,
  required double surfaceAzimuth,
}) {
  // متجه اتجاه الشمس والعمود على اللوح، كلاهما في إطار (شرق، شمال، أعلى).
  final double sz = _sinD(sunZenith);
  final double sunE = sz * _sinD(sunAzimuth);
  final double sunN = sz * _cosD(sunAzimuth);
  final double sunU = _cosD(sunZenith);

  final double sb = _sinD(tilt);
  final double normalE = sb * _sinD(surfaceAzimuth);
  final double normalN = sb * _cosD(surfaceAzimuth);
  final double normalU = _cosD(tilt);

  return sunE * normalE + sunN * normalN + sunU * normalU;
}

// ═══════════════════════════════════════════════════════════════════════════
// 9. الإشعاع خارج الغلاف الجوي
// ═══════════════════════════════════════════════════════════════════════════

/// الإشعاع الشمسي خارج الغلاف الجوي G0 على سطح عمودي على الأشعة [W/m²].
///
///   G0 = 1367 · (1 + 0.033 · cos(360·N / 365))
double extraterrestrialIrradiance(int n) =>
    solarConstant * (1.0 + 0.033 * _cosD(360.0 * n / 365.0));

// ═══════════════════════════════════════════════════════════════════════════
// 10. نموذج السماء الصافية التقريبي
// ═══════════════════════════════════════════════════════════════════════════

/// كتلة الهواء النسبية AM بتصحيح Kasten–Young (1989).
///
///   AM = 1 / (cos θz + 0.50572 · (96.07995 − θz)^(−1.6364))
///
/// حيث θz بالدرجات. يُرجع [double.infinity] عند θz ≥ 90° (الشمس تحت الأفق).
double airMass(double zenithDegrees) {
  if (zenithDegrees >= 90.0) return double.infinity;
  final double denominator = _cosD(zenithDegrees) +
      0.50572 * math.pow(96.07995 - zenithDegrees, -1.6364);
  if (denominator <= 0.0) return double.infinity;
  return 1.0 / denominator;
}

/// ⚠️ نموذج تقريبي للسماء الصافية — لا يمثّل ظروفًا جوية فعلية.
///
/// يقدّر الإشعاع الشمسي المباشر العمودي (DNI) في سماء صافية:
///
///   Gb ≈ G0(N) · 0.7^(AM^0.678)
///
/// هذا نموذج تجريبي بسيط (Meinel & Meinel) يفترض جوًّا صافيًا نموذجيًا عند
/// مستوى سطح البحر. **لا يأخذ في الحسبان**: الغيوم، الغبار والعوالق الجوية،
/// بخار الماء، ارتفاع الموقع، ولا التلوّث. القيم الناتجة تصلح **للمقارنة
/// النسبية بين التوجيهات فقط** — أي لترتيب زوايا الميل والسمت من حيث
/// الأفضلية — ولا تصلح لتقدير الإنتاج الفعلي بالكيلوواط‑ساعة.
///
/// لتقدير إنتاج فعلي، تلزم بيانات إشعاع مقيسة للموقع (PVGIS أو NASA POWER).
double clearSkyBeamIrradianceForDay({
  required int n,
  required double zenithDegrees,
}) {
  if (zenithDegrees >= 90.0) return 0.0;
  return extraterrestrialIrradiance(n) *
      math.pow(0.7, math.pow(airMass(zenithDegrees), 0.678)).toDouble();
}

// ═══════════════════════════════════════════════════════════════════════════
// حساب الزاوية المثلى عدديًا
// ═══════════════════════════════════════════════════════════════════════════

/// وضع التحسين الذي يختاره المستخدم.
enum OptimizationMode {
  /// تحسين على مدار السنة كاملة.
  annual,

  /// تحسين لأشهر الصيف (5–8).
  summer,

  /// تحسين لأشهر الشتاء (11، 12، 1، 2) — ذروة الحمل الشتوية غالبًا أعلى.
  winter,

  /// المستخدم يُدخل الزاوية بنفسه؛ لا يُجرى أي تحسين عددي.
  manual,
}

/// الأشهر المشمولة بكل وضع.
Set<int> monthsForMode(OptimizationMode mode) {
  switch (mode) {
    case OptimizationMode.annual:
      return const {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
    case OptimizationMode.summer:
      return const {5, 6, 7, 8};
    case OptimizationMode.winter:
      return const {11, 12, 1, 2};
    case OptimizationMode.manual:
      return const {};
  }
}

/// نتيجة التحسين العددي.
class Orientation {
  /// زاوية الميل β بالدرجات عن الأفقي.
  final double tilt;

  /// سمت اللوح بالدرجات، من الشمال باتجاه عقارب الساعة [0, 360).
  final double azimuth;

  /// مجموع الطاقة الساقطة النسبي [Wh/m²] وفق نموذج السماء الصافية التقريبي.
  ///
  /// ⚠️ قيمة نسبية للمقارنة بين التوجيهات فقط، وليست تقديرًا للإنتاج الفعلي.
  final double relativeInsolation;

  const Orientation({
    required this.tilt,
    required this.azimuth,
    required this.relativeInsolation,
  });
}

/// حدود المسح العددي — نصف الكرة الشمالي.
const double _tiltMin = 0.0;
const double _tiltMax = 60.0;
const double _azimuthMin = 135.0;
const double _azimuthMax = 225.0;
const double _stepDegrees = 1.0;
const int _timeStepMinutes = 15;

/// يبحث عدديًا عن التوجيه الأمثل (الميل والسمت) لموقع ووضع تحسين محدّدين.
///
/// الطريقة: مسح شامل على β من 0° إلى 60° وعلى γ من 135° إلى 225° بخطوة 1°،
/// ولكل تركيبة يُجمع الإشعاع المباشر الساقط على مدار الفترة المختارة بخطوة
/// 15 دقيقة، مع تجاهل اللحظات التي تكون فيها الشمس تحت الأفق أو خلف مستوى
/// اللوح (cos θ ≤ 0).
///
/// ⚠️ يعتمد على نموذج السماء الصافية التقريبي: النتيجة هي التوجيه الأمثل
/// **هندسيًا** في جوٍّ صافٍ نموذجي. الغيوم والغبار الموسميّان قد يزيحان
/// الأمثل الفعلي بضع درجات.
///
/// الأداء: لا تُحسب الشمس إلا مرة واحدة لكل لحظة زمنية، ثم يُعاد استخدام
/// اتجاهها لكل التوجيهات، فينخفض الحمل الحسابي بثلاثة أوامر مقدار.
/// يستغرق ذلك ثوانيَ معدودة، لذا يجب تشغيله خارج خيط الواجهة (Isolate).
///
/// [year] السنة المستخدمة لتوليد الأيام؛ يُفضّل سنة غير كبيسة للاتّساق.
///
/// [monthlyScale] معاملات تصحيح شهرية اختيارية (12 عنصرًا، يناير أوّلًا).
/// عند تمريرها يُضرب إشعاع كل لحظة في معامل شهرها، فيُصحَّح التوزيع الموسمي
/// للطاقة ببيانات مقيسة بدل نموذج السماء الصافية التقريبي، مع الإبقاء على
/// شكل المنحنى اليومي من النموذج. تمريرها لا يغيّر شيئًا إن كانت كلّها 1.
///
/// يرمي [ArgumentError] إذا مُرِّر [OptimizationMode.manual]، أو إذا لم تكن
/// [monthlyScale] من اثني عشر عنصرًا.
Orientation findOptimalOrientation({
  required double latitude,
  required double longitude,
  required int timeZoneOffsetHours,
  required OptimizationMode mode,
  int year = 2025,
  List<double>? monthlyScale,
}) {
  if (mode == OptimizationMode.manual) {
    throw ArgumentError(
      'الوضع اليدوي لا يُحسب عدديًا — الزاوية يُدخلها المستخدم.',
    );
  }
  if (monthlyScale != null && monthlyScale.length != 12) {
    throw ArgumentError.value(
      monthlyScale.length,
      'monthlyScale',
      'يجب أن تحوي معاملات التصحيح الشهرية اثني عشر عنصرًا',
    );
  }
  final Set<int> months = monthsForMode(mode);

  // ── المرحلة 1: احسب اتجاه الشمس ووزنه الإشعاعي لكل لحظة نهارية مرة واحدة.
  final List<double> sunEast = <double>[];
  final List<double> sunNorth = <double>[];
  final List<double> sunUp = <double>[];
  final List<double> weight = <double>[]; // Gb · Δt  [Wh/m²]

  final double hoursPerStep = _timeStepMinutes / 60.0;
  final int daysInYear = dayOfYear(DateTime(year, 12, 31));

  for (int n = 1; n <= daysInYear; n++) {
    final DateTime day = DateTime(year, 1, 1).add(Duration(days: n - 1));
    if (!months.contains(day.month)) continue;

    for (int minute = 0; minute < 24 * 60; minute += _timeStepMinutes) {
      final DateTime localStandardTime = day.add(Duration(minutes: minute));
      final SolarEphemeris ephemeris = solarEphemeris(
        localStandardToUtc(localStandardTime, timeZoneOffsetHours),
      );
      final double omega = hourAngle(trueSolarTime(
        localStandardTimeHours: minute / 60.0,
        longitude: longitude,
        timeZoneOffsetHours: timeZoneOffsetHours,
        equationOfTimeMinutes: ephemeris.equationOfTime,
      ));

      final SolarPosition sun = solarPositionFromAngles(
        latitude: latitude,
        declination: ephemeris.declination,
        hourAngle: omega,
      );
      if (!sun.isDaylight) continue;

      double gb = clearSkyBeamIrradianceForDay(
        n: n,
        zenithDegrees: sun.zenith,
      );
      if (monthlyScale != null) gb *= monthlyScale[day.month - 1];
      if (gb <= 0.0) continue;

      final double sz = _sinD(sun.zenith);
      sunEast.add(sz * _sinD(sun.azimuth));
      sunNorth.add(sz * _cosD(sun.azimuth));
      sunUp.add(_cosD(sun.zenith));
      weight.add(gb * hoursPerStep);
    }
  }

  // ── المرحلة 2: امسح كل التوجيهات واجمع الطاقة الساقطة.
  double bestEnergy = double.negativeInfinity;
  double bestTilt = 0.0;
  double bestAzimuth = 180.0;
  final int sampleCount = weight.length;

  for (double tilt = _tiltMin; tilt <= _tiltMax; tilt += _stepDegrees) {
    final double sinBeta = _sinD(tilt);
    final double normalUp = _cosD(tilt);

    for (double az = _azimuthMin; az <= _azimuthMax; az += _stepDegrees) {
      final double normalEast = sinBeta * _sinD(az);
      final double normalNorth = sinBeta * _cosD(az);

      double energy = 0.0;
      for (int i = 0; i < sampleCount; i++) {
        final double cosTheta = sunEast[i] * normalEast +
            sunNorth[i] * normalNorth +
            sunUp[i] * normalUp;
        if (cosTheta > 0.0) energy += cosTheta * weight[i];
      }

      if (energy > bestEnergy) {
        bestEnergy = energy;
        bestTilt = tilt;
        bestAzimuth = az;
      }
    }
  }

  return Orientation(
    tilt: bestTilt,
    azimuth: bestAzimuth,
    relativeInsolation: bestEnergy,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// مؤشر الاستفادة اللحظي
// ═══════════════════════════════════════════════════════════════════════════

/// نسبة الاستفادة اللحظية ٪ = (cos θ الحالي ÷ cos θ عند الوضع الأمثل) × 100.
///
/// تُحصر في [0, 100]. تُرجع 0 إذا كانت الشمس تحت الأفق أو خلف اللوح المثالي.
double instantaneousPerformanceRatio({
  required double sunZenith,
  required double sunAzimuth,
  required double currentTilt,
  required double currentAzimuth,
  required double optimalTilt,
  required double optimalAzimuth,
}) {
  if (sunZenith >= 90.0) return 0.0;

  final double optimal = cosIncidenceFromSunDirection(
    sunZenith: sunZenith,
    sunAzimuth: sunAzimuth,
    tilt: optimalTilt,
    surfaceAzimuth: optimalAzimuth,
  );
  if (optimal <= 0.0) return 0.0;

  final double current = cosIncidenceFromSunDirection(
    sunZenith: sunZenith,
    sunAzimuth: sunAzimuth,
    tilt: currentTilt,
    surfaceAzimuth: currentAzimuth,
  );
  if (current <= 0.0) return 0.0;

  final double ratio = 100.0 * current / optimal;
  return ratio > 100.0 ? 100.0 : ratio;
}

// ═══════════════════════════════════════════════════════════════════════════
// تباعد الصفوف وارتفاع الحامل (يعتمد على اتجاه اللوح: رأسي/أفقي)
// ═══════════════════════════════════════════════════════════════════════════

/// اتجاه تركيب اللوح على الحامل.
///
/// ⚠️ لا أثر لهذا الخيار على الطاقة الساقطة: عند نفس زاوية الميل ونفس السمت،
/// اتجاه اللوح لا يغيّر الإشعاع الواصل إليه. أثره محصور في الأبعاد الهندسية
/// للتركيب (البُعد المائل، تباعد الصفوف، ارتفاع الحامل).
enum PanelOrientation {
  /// رأسي — الضلع الطويل عموديّ على محور الميل.
  portrait,

  /// أفقي — الضلع القصير عموديّ على محور الميل.
  landscape,
}

/// البُعد المائل للّوح L بالأمتار — الضلع الواقع في اتجاه الميل.
///
/// [length] الضلع الطويل و[width] الضلع القصير، بالأمتار.
double slopedPanelDimension({
  required double length,
  required double width,
  required PanelOrientation orientation,
}) =>
    orientation == PanelOrientation.portrait ? length : width;

/// نتيجة حسابات التخطيط الهندسي للصفوف.
class RowLayout {
  /// المسافة الدنيا بين مقدّمة صفٍّ ومقدّمة الصف التالي [متر].
  final double minimumRowSpacing;

  /// الارتفاع الرأسي المطلوب لأعلى نقطة في الحامل [متر].
  final double mountingHeight;

  /// الارتفاع الشمسي α المستخدم في الحساب [درجة].
  final double designSolarElevation;

  const RowLayout({
    required this.minimumRowSpacing,
    required this.mountingHeight,
    required this.designSolarElevation,
  });
}

/// يحسب تباعد الصفوف الأدنى والارتفاع الرأسي لتفادي التظليل الذاتي.
///
///   D = L·cos β + (L·sin β) / tan α
///   H = L·sin β
///
/// حيث α هو الارتفاع الشمسي عند **الانقلاب الشتوي الساعة 9 صباحًا** بالتوقيت
/// الشمسي المحلي — وهي حالة التصميم الأسوأ الشائعة في نصف الكرة الشمالي.
///
/// يرمي [StateError] إذا كانت الشمس تحت الأفق في لحظة التصميم (خطوط العرض
/// العالية جدًا)، لأن التباعد يصبح غير محدود عندها.
RowLayout computeRowLayout({
  required double latitude,
  required double tilt,
  required double panelLength,
  required double panelWidth,
  required PanelOrientation orientation,
  int year = 2025,
}) {
  final double l = slopedPanelDimension(
    length: panelLength,
    width: panelWidth,
    orientation: orientation,
  );

  // الانقلاب الشتوي: 21 ديسمبر. الساعة 9 صباحًا بالتوقيت الشمسي ⇒ ω = −45°.
  //
  // يُقيَّم الميل عند ظهر ذلك اليوم بتوقيت UTC: تغيّره خلال اليوم الواحد قرب
  // الانقلاب أقلّ من ‎0.01°‎، فلا حاجة لخط الطول هنا.
  final SolarPosition sun = solarPositionFromAngles(
    latitude: latitude,
    declination: solarEphemeris(DateTime.utc(year, 12, 21, 12)).declination,
    hourAngle: -45.0,
  );
  final double alpha = sun.elevation;

  if (alpha <= 0.0) {
    throw StateError(
      'الشمس تحت الأفق عند لحظة التصميم (الانقلاب الشتوي، 9 صباحًا) '
      'عند خط العرض $latitude°؛ لا يمكن حساب تباعد الصفوف.',
    );
  }

  final double spacing =
      l * _cosD(tilt) + (l * _sinD(tilt)) / math.tan(alpha * _deg2rad);

  return RowLayout(
    minimumRowSpacing: spacing,
    mountingHeight: l * _sinD(tilt),
    designSolarElevation: alpha,
  );
}
