// المرحلة 4 — تحسين اختياري ببيانات إشعاع مقيسة.
//
// ⚠️ التطبيق يعمل كاملًا بلا هذه الطبقة. كل ما هنا تحسين إضافي: عند توفّر
// الاتصال تُجلب بيانات الإشعاع الفعلية للموقع فتُصحَّح بها الأوزان الموسمية
// في حساب الزاوية المثلى، وعند الإخفاق يُعاد بصمت إلى نموذج السماء الصافية.
//
// ── مصدر البيانات ─────────────────────────────────────────────────────────
//
// NASA POWER — خدمة مجانية بلا مفتاح استيثاق.
//
// اختيرت على PVGIS لسبب عملي: تعذّر التحقق من مواصفة واجهة PVGIS للإشعاع
// الشهري من مصدر موثوق، ولم يكن مقبولًا تخمين مسار واجهة برمجية.
//
// مواصفة الطلب أدناه مأخوذة من تنفيذ pvlib-python المرجعي
// (pvlib/iotools/nasa_power.py)، وهو عميل منشور ومُختبَر مقابل الخدمة
// الحيّة: مسار النقطة النهائية، وأسماء المعاملات، وبنية الاستجابة، واسم
// متغيّر الإشعاع المباشر.
//
// نستعمل التقسيم الزمني الساعي `hourly` لأنه وحده المتحقَّق منه، ونجمع
// المتوسّطات الشهرية على الجهاز. الطلب يُجلب مرّة واحدة ويُخزَّن محليًا،
// فكِبَر الاستجابة كلفة لمرّة واحدة لا كلفة متكرّرة.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// المضيف والمسار — راجع ترويسة الملف لمصدر التحقّق.
const String _nasaPowerHost = 'power.larc.nasa.gov';
const String _nasaPowerPath = '/api/temporal/hourly/point';

/// اسم متغيّر الإشعاع المباشر العمودي في NASA POWER.
const String _dniParameter = 'ALLSKY_SFC_SW_DNI';

/// مهلة الطلب. الفنّي في الميدان لا ينتظر طويلًا، والبديل الأوفلاين جاهز.
const Duration _requestTimeout = Duration(seconds: 45);

/// سبب تعذّر جلب البيانات.
enum IrradianceFetchFailure {
  /// لا اتصال بالشبكة، أو تعذّر الوصول إلى الخدمة.
  network,

  /// الخدمة ردّت بحالة خطأ.
  server,

  /// الاستجابة وصلت لكن تعذّر تفسيرها.
  malformed,
}

/// رسالة عربية موجزة تشرح سبب الإخفاق.
String irradianceFailureMessage(IrradianceFetchFailure failure) {
  switch (failure) {
    case IrradianceFetchFailure.network:
      return 'تعذّر الاتصال بخدمة بيانات الإشعاع. '
          'يُستعمل النموذج التقريبي المدمج.';
    case IrradianceFetchFailure.server:
      return 'خدمة بيانات الإشعاع لم تستجب. '
          'يُستعمل النموذج التقريبي المدمج.';
    case IrradianceFetchFailure.malformed:
      return 'بيانات الإشعاع الواردة غير مفهومة. '
          'يُستعمل النموذج التقريبي المدمج.';
  }
}

/// متوسّطات الإشعاع المباشر الشهرية لموقع، مع زمن الجلب.
class MonthlyIrradiance {
  /// متوسّط الإشعاع المباشر العمودي لكل شهر [W/m²]، يناير أوّلًا.
  final List<double> monthlyMeanDni;

  /// خط العرض الذي جُلبت له [درجة].
  final double latitude;

  /// خط الطول الذي جُلبت له [درجة].
  final double longitude;

  /// السنة التقويمية التي تمثّلها البيانات.
  final int year;

  /// لحظة الجلب — تُعرض للمستخدم كتاريخ آخر تحديث.
  final DateTime fetchedAt;

  const MonthlyIrradiance({
    required this.monthlyMeanDni,
    required this.latitude,
    required this.longitude,
    required this.year,
    required this.fetchedAt,
  });

  /// معاملات التصحيح الشهرية لتمريرها إلى المحسِّن.
  ///
  /// تُطبَّع حول متوسّطها، فيبقى مقياس الطاقة الكلّي كما هو ولا يتغيّر إلا
  /// **التوزيع النسبي** بين الأشهر — وهو وحده ما يؤثّر في اختيار الزاوية.
  ///
  /// يُرجع اثني عشر عنصرًا؛ ويُرجع أحادًا إذا كانت البيانات كلّها أصفارًا.
  List<double> get scaleFactors {
    final double sum = monthlyMeanDni.fold(0.0, (double a, double b) => a + b);
    if (sum <= 0.0) return List<double>.filled(12, 1.0);
    final double mean = sum / monthlyMeanDni.length;
    return monthlyMeanDni
        .map((double value) => value / mean)
        .toList(growable: false);
  }

  /// هل البيانات تخصّ هذا الموقع؟ يُسمح بفارق ‎0.5°‎ (نحو ‎55‎ كم).
  ///
  /// شبكة NASA POWER نصف درجة أصلًا، فطلب بيانات جديدة لإزاحة أصغر من ذلك
  /// لا يضيف دقّة.
  bool coversLocation(double latitude, double longitude) =>
      (this.latitude - latitude).abs() <= 0.5 &&
      (this.longitude - longitude).abs() <= 0.5;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'monthlyMeanDni': monthlyMeanDni,
        'latitude': latitude,
        'longitude': longitude,
        'year': year,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  /// يستعيد من التخزين. يُرجع null إذا كان المحتوى تالفًا أو ناقصًا.
  static MonthlyIrradiance? fromJson(Map<String, dynamic> json) {
    final Object? values = json['monthlyMeanDni'];
    final Object? latitude = json['latitude'];
    final Object? longitude = json['longitude'];
    final Object? year = json['year'];
    final Object? fetchedAt = json['fetchedAt'];

    if (values is! List || values.length != 12) return null;
    if (latitude is! num || longitude is! num || year is! num) return null;
    if (fetchedAt is! String) return null;

    final DateTime? parsed = DateTime.tryParse(fetchedAt);
    if (parsed == null) return null;

    final List<double> monthly = <double>[];
    for (final Object? value in values) {
      if (value is! num) return null;
      monthly.add(value.toDouble());
    }

    return MonthlyIrradiance(
      monthlyMeanDni: monthly,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      year: year.toInt(),
      fetchedAt: parsed,
    );
  }
}

/// نتيجة محاولة الجلب: إمّا بيانات، وإمّا سبب إخفاق.
class IrradianceResult {
  final MonthlyIrradiance? data;
  final IrradianceFetchFailure? failure;

  const IrradianceResult.success(MonthlyIrradiance this.data) : failure = null;
  const IrradianceResult.failed(IrradianceFetchFailure this.failure)
      : data = null;

  bool get isSuccess => data != null;
}

/// يحوّل استجابة NASA POWER الساعية إلى متوسّطات شهرية.
///
/// بنية الاستجابة المتوقَّعة:
///   properties.parameter.ALLSKY_SFC_SW_DNI : { "YYYYMMDDHH": قيمة, … }
///   header.fill_value : قيمة تُعلّم البيانات المفقودة (‎−999‎ عادةً)
///
/// القيم المفقودة والسالبة تُستبعد من المتوسّط لا تُعامَل أصفارًا: معاملتها
/// أصفارًا تخفض متوسّط الشهر زورًا وتزيح الزاوية المثلى.
///
/// يُرجع null إذا لم تكن البنية كما هو متوقَّع، أو إذا خلا شهر من أي قراءة.
List<double>? parseMonthlyMeanDni(Map<String, dynamic> body) {
  final Object? properties = body['properties'];
  if (properties is! Map) return null;
  final Object? parameter = properties['parameter'];
  if (parameter is! Map) return null;
  final Object? series = parameter[_dniParameter];
  if (series is! Map) return null;

  double fillValue = -999.0;
  final Object? header = body['header'];
  if (header is Map && header['fill_value'] is num) {
    fillValue = (header['fill_value'] as num).toDouble();
  }

  final List<double> sums = List<double>.filled(12, 0.0);
  final List<int> counts = List<int>.filled(12, 0);

  series.forEach((Object? key, Object? value) {
    if (key is! String || key.length < 6 || value is! num) return;
    final int? month = int.tryParse(key.substring(4, 6));
    if (month == null || month < 1 || month > 12) return;

    final double reading = value.toDouble();
    if (reading == fillValue || reading < 0.0) return;

    sums[month - 1] += reading;
    counts[month - 1]++;
  });

  if (counts.any((int count) => count == 0)) return null;

  return List<double>.generate(
    12,
    (int index) => sums[index] / counts[index],
    growable: false,
  );
}

/// السنة التي تُطلب بياناتها.
///
/// خدمة NASA POWER تتأخّر عن الزمن الحقيقي أشهرًا، فنطلب سنة مكتملة مؤكّدة
/// بدل السنة الجارية.
int referenceYear([DateTime? now]) => (now ?? DateTime.now()).year - 2;

/// عميل NASA POWER وتخزينه المحلي.
class IrradianceService {
  IrradianceService({
    MethodChannel control = const MethodChannel('solar_qibla/control'),
    HttpClient Function()? httpClientFactory,
  })  : _control = control,
        _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final MethodChannel _control;
  final HttpClient Function() _httpClientFactory;

  static const String _storageKey = 'monthly_irradiance';

  /// يبني الرابط المطلوب — معزول ليكون قابلًا للاختبار.
  static Uri buildRequestUri({
    required double latitude,
    required double longitude,
    required int year,
  }) =>
      Uri.https(_nasaPowerHost, _nasaPowerPath, <String, String>{
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'start': '${year}0101',
        'end': '${year}1231',
        'community': 're',
        'parameters': _dniParameter,
        'format': 'json',
        'time-standard': 'utc',
      });

  /// يجلب متوسّطات الإشعاع الشهرية للموقع.
  ///
  /// لا يرمي أبدًا: كل مسارات الإخفاق تُرجع [IrradianceResult.failed]،
  /// لأن هذه الطبقة تحسين اختياري ولا يجوز أن تُسقط التطبيق.
  Future<IrradianceResult> fetch({
    required double latitude,
    required double longitude,
    int? year,
  }) async {
    final int requestedYear = year ?? referenceYear();
    final HttpClient client = _httpClientFactory();

    try {
      final HttpClientRequest request = await client
          .getUrl(buildRequestUri(
            latitude: latitude,
            longitude: longitude,
            year: requestedYear,
          ))
          .timeout(_requestTimeout);
      final HttpClientResponse response =
          await request.close().timeout(_requestTimeout);

      if (response.statusCode != HttpStatus.ok) {
        return const IrradianceResult.failed(IrradianceFetchFailure.server);
      }

      final String payload =
          await response.transform(utf8.decoder).join().timeout(_requestTimeout);

      final Object? decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return const IrradianceResult.failed(IrradianceFetchFailure.malformed);
      }

      final List<double>? monthly = parseMonthlyMeanDni(decoded);
      if (monthly == null) {
        return const IrradianceResult.failed(IrradianceFetchFailure.malformed);
      }

      return IrradianceResult.success(
        MonthlyIrradiance(
          monthlyMeanDni: monthly,
          latitude: latitude,
          longitude: longitude,
          year: requestedYear,
          fetchedAt: DateTime.now(),
        ),
      );
    } on SocketException {
      return const IrradianceResult.failed(IrradianceFetchFailure.network);
    } on HttpException {
      return const IrradianceResult.failed(IrradianceFetchFailure.network);
    } on FormatException {
      return const IrradianceResult.failed(IrradianceFetchFailure.malformed);
    } on Object {
      // يشمل انتهاء المهلة وأخطاء TLS: كلّها تقود إلى النموذج الأوفلاين.
      return const IrradianceResult.failed(IrradianceFetchFailure.network);
    } finally {
      client.close(force: true);
    }
  }

  /// يحفظ البيانات محليًا.
  Future<void> save(MonthlyIrradiance data) => _control.invokeMethod<void>(
        'writeString',
        <String, dynamic>{
          'key': _storageKey,
          'value': jsonEncode(data.toJson()),
        },
      );

  /// يستعيد آخر بيانات محفوظة. لا يرمي أبدًا.
  Future<MonthlyIrradiance?> loadCached() async {
    final String? stored;
    try {
      stored = await _control.invokeMethod<String>(
        'readString',
        <String, dynamic>{'key': _storageKey},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    if (stored == null || stored.isEmpty) return null;

    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! Map<String, dynamic>) return null;
      return MonthlyIrradiance.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }
}
