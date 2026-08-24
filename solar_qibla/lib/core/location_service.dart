// طبقة الموقع الجغرافي.
//
// مبدأ حاكم: **التطبيق لا يتوقّف عند رفض إذن الموقع**. الإدخال اليدوي مسار
// أول لا احتياطي، لأن الفنّي قد يعمل في موقع بلا تغطية GPS، أو على جهاز
// رُفض فيه الإذن، أو في وضع الطيران.
//
// التخزين المحلي يمرّ عبر قناة المنصّة إلى SharedPreferences، تفاديًا
// لإضافة حزمة تخزين لا يحتاجها المشروع لغير هذا الغرض.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// مصدر إحداثيات الموقع.
enum LocationSource {
  /// من مستقبل GPS في الجهاز.
  gps,

  /// أدخلها المستخدم يدويًا.
  manual,

  /// مستعادة من التخزين المحلي (آخر موقع معروف).
  cached,
}

/// سبب تعذّر الحصول على الموقع من GPS.
enum LocationFailure {
  /// خدمة تحديد الموقع مُطفأة على مستوى الجهاز.
  serviceDisabled,

  /// المستخدم رفض الإذن هذه المرّة.
  permissionDenied,

  /// المستخدم رفض الإذن نهائيًا؛ يلزم فتح إعدادات التطبيق.
  permissionDeniedForever,

  /// انتهت المهلة أو أخفق المستقبل.
  unavailable,
}

/// رسالة عربية تشرح سبب الإخفاق وما العمل.
String locationFailureMessage(LocationFailure failure) {
  switch (failure) {
    case LocationFailure.serviceDisabled:
      return 'خدمة تحديد الموقع مُطفأة في الجهاز. '
          'شغّلها أو أدخل خط العرض وخط الطول يدويًا.';
    case LocationFailure.permissionDenied:
      return 'لم يُمنح إذن الموقع. '
          'يمكنك منحه أو إدخال خط العرض وخط الطول يدويًا.';
    case LocationFailure.permissionDeniedForever:
      return 'إذن الموقع مرفوض نهائيًا. '
          'امنحه من إعدادات التطبيق، أو أدخل الإحداثيات يدويًا.';
    case LocationFailure.unavailable:
      return 'تعذّر الحصول على الموقع من GPS. '
          'جرّب في مكان مكشوف، أو أدخل الإحداثيات يدويًا.';
  }
}

/// موقع جغرافي يعتمده التطبيق.
class SiteLocation {
  /// خط العرض [درجة، موجب شمالًا].
  final double latitude;

  /// خط الطول [درجة، موجب شرقًا].
  final double longitude;

  /// الارتفاع عن سطح البحر [متر]. يُستعمل في حساب الانحراف المغناطيسي فقط.
  final double altitude;

  /// إزاحة المنطقة الزمنية القياسية عن UTC [ساعة]، **بلا** توقيت صيفي.
  final int timeZoneOffsetHours;

  /// مصدر هذه الإحداثيات.
  final LocationSource source;

  const SiteLocation({
    required this.latitude,
    required this.longitude,
    required this.timeZoneOffsetHours,
    required this.source,
    this.altitude = 0.0,
  });

  /// هل الإحداثيات ضمن المدى الجغرافي الصالح؟
  static bool isValid(double latitude, double longitude) =>
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'timeZoneOffsetHours': timeZoneOffsetHours,
      };

  /// يستعيد موقعًا مخزّنًا. يُرجع null إذا كان المحتوى تالفًا أو خارج المدى.
  static SiteLocation? fromJson(Map<String, dynamic> json) {
    final Object? latitude = json['latitude'];
    final Object? longitude = json['longitude'];
    final Object? offset = json['timeZoneOffsetHours'];
    if (latitude is! num || longitude is! num || offset is! num) return null;
    if (!isValid(latitude.toDouble(), longitude.toDouble())) return null;

    return SiteLocation(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble() ?? 0.0,
      timeZoneOffsetHours: offset.toInt(),
      source: LocationSource.cached,
    );
  }
}

/// نتيجة محاولة تحديد الموقع: إمّا موقع، وإمّا سبب إخفاق.
class LocationResult {
  final SiteLocation? location;
  final LocationFailure? failure;

  const LocationResult.success(SiteLocation this.location) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : location = null;

  bool get isSuccess => location != null;
}

/// يوفّر الموقع من GPS أو يدويًا، ويحفظ آخر قيمة محليًا.
class LocationService {
  LocationService({MethodChannel? control})
      : _control = control ?? const MethodChannel('solar_qibla/control');

  final MethodChannel _control;

  static const String _storageKey = 'last_location';

  /// يحاول الحصول على الموقع من GPS.
  ///
  /// لا يرمي استثناءً عند الرفض أو الإخفاق: يُرجع [LocationResult.failed]
  /// ليتولّى المستدعي عرض المسار اليدوي.
  Future<LocationResult> fromGps({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failed(
        LocationFailure.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failed(LocationFailure.permissionDenied);
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return LocationResult.success(
        SiteLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          altitude: position.altitude,
          timeZoneOffsetHours: standardTimeZoneOffsetHours(),
          source: LocationSource.gps,
        ),
      );
    } on Object {
      // يشمل انتهاء المهلة وأخطاء المنصّة: كلاهما يقود إلى المسار اليدوي.
      return const LocationResult.failed(LocationFailure.unavailable);
    }
  }

  /// يبني موقعًا من إدخال يدوي. يُرجع null إذا كانت الإحداثيات خارج المدى.
  SiteLocation? fromManualInput({
    required double latitude,
    required double longitude,
    double altitude = 0.0,
    int? timeZoneOffsetHours,
  }) {
    if (!SiteLocation.isValid(latitude, longitude)) return null;
    return SiteLocation(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      timeZoneOffsetHours:
          timeZoneOffsetHours ?? standardTimeZoneOffsetHours(),
      source: LocationSource.manual,
    );
  }

  /// يحفظ الموقع محليًا.
  Future<void> save(SiteLocation location) =>
      _control.invokeMethod<void>('writeString', <String, dynamic>{
        'key': _storageKey,
        'value': jsonEncode(location.toJson()),
      });

  /// يستعيد آخر موقع محفوظ، أو null إن لم يوجد أو كان تالفًا.
  ///
  /// لا يرمي أبدًا: إخفاق التخزين لا يجوز أن يمنع التطبيق من الإقلاع؛
  /// أسوأ ما يحدث أن يُطلب من المستخدم تحديد موقعه من جديد.
  Future<SiteLocation?> loadCached() async {
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
      return SiteLocation.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }
}

/// إزاحة المنطقة الزمنية **القياسية** عن UTC بالساعات، بلا توقيت صيفي.
///
/// محرّك الحسابات يعمل بالزمن المحلي القياسي، فلو مُرّرت إزاحة صيفية لانزاح
/// الزمن الشمسي ساعة كاملة — أي ‎15°‎ في الزاوية الساعية.
///
/// نستنتج الإزاحة القياسية بأخذ **أصغر** إزاحة في السنة لنصف الكرة الشمالي،
/// إذ يرفع التوقيت الصيفي الإزاحة صيفًا ويتركها قياسية شتاءً. ولنصف الكرة
/// الجنوبي يكون العكس، فنأخذ الأصغر أيضًا لأن الشتاء هناك في منتصف السنة.
///
/// [now] لحقن زمن ثابت في الاختبارات.
int standardTimeZoneOffsetHours([DateTime? now]) {
  final DateTime reference = now ?? DateTime.now();
  final int january =
      DateTime(reference.year, 1, 1).timeZoneOffset.inMinutes;
  final int july = DateTime(reference.year, 7, 1).timeZoneOffset.inMinutes;
  final int standardMinutes = january < july ? january : july;
  return (standardMinutes / 60).round();
}
