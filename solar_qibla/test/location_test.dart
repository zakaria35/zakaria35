// اختبارات طبقة الموقع: التحقّق من المدى، التخزين المحلي، والمنطقة الزمنية.
//
// مسار GPS نفسه لا يُختبر هنا: يتطلّب محاكاة واجهة منصّة geolocator كاملةً،
// وقيمته الاختبارية أقلّ من كلفتها. المُختبَر هو ما يحمي المستخدم فعلًا:
// التحقّق من صحّة المدخلات، ومقاومة التخزين التالف، واستنتاج المنطقة الزمنية.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_qibla/core/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  group('التحقّق من الإحداثيات', () {
    test('يقبل المدى الجغرافي الصالح', () {
      expect(SiteLocation.isValid(31.5017, 34.4668), isTrue);
      expect(SiteLocation.isValid(0.0, 0.0), isTrue);
      expect(SiteLocation.isValid(-90.0, -180.0), isTrue);
      expect(SiteLocation.isValid(90.0, 180.0), isTrue);
    });

    test('يرفض ما خرج عن المدى', () {
      expect(SiteLocation.isValid(90.1, 0.0), isFalse);
      expect(SiteLocation.isValid(-90.1, 0.0), isFalse);
      expect(SiteLocation.isValid(0.0, 180.1), isFalse);
      expect(SiteLocation.isValid(0.0, -180.1), isFalse);
    });

    test('الإدخال اليدوي يرفض ما خرج عن المدى بدل قبوله صامتًا', () {
      final LocationService service = LocationService();
      expect(
        service.fromManualInput(latitude: 31.5, longitude: 34.5),
        isNotNull,
      );
      expect(
        service.fromManualInput(latitude: 131.5, longitude: 34.5),
        isNull,
      );
      expect(
        service.fromManualInput(latitude: 31.5, longitude: 200.0),
        isNull,
      );
    });

    test('الإدخال اليدوي يوسم المصدر بأنه يدوي', () {
      final SiteLocation? location = LocationService().fromManualInput(
        latitude: 31.5017,
        longitude: 34.4668,
        timeZoneOffsetHours: 2,
      );
      expect(location, isNotNull);
      expect(location!.source, LocationSource.manual);
      expect(location.timeZoneOffsetHours, 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('ترميز الموقع', () {
    test('دورة ترميز وفكّ ترميز كاملة', () {
      const SiteLocation original = SiteLocation(
        latitude: 31.5017,
        longitude: 34.4668,
        altitude: 45.0,
        timeZoneOffsetHours: 2,
        source: LocationSource.gps,
      );
      final SiteLocation? restored = SiteLocation.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored, isNotNull);
      expect(restored!.latitude, closeTo(31.5017, 1e-9));
      expect(restored.longitude, closeTo(34.4668, 1e-9));
      expect(restored.altitude, closeTo(45.0, 1e-9));
      expect(restored.timeZoneOffsetHours, 2);
      // المستعاد يُوسم دائمًا بأنه من التخزين، لا بمصدره الأصلي.
      expect(restored.source, LocationSource.cached);
    });

    test('المحتوى الناقص أو الخاطئ النوع يُرفض', () {
      expect(SiteLocation.fromJson(<String, dynamic>{}), isNull);
      expect(
        SiteLocation.fromJson(<String, dynamic>{
          'latitude': 31.5,
          'longitude': 34.5,
        }),
        isNull, // لا منطقة زمنية
      );
      expect(
        SiteLocation.fromJson(<String, dynamic>{
          'latitude': 'غير رقم',
          'longitude': 34.5,
          'timeZoneOffsetHours': 2,
        }),
        isNull,
      );
    });

    test('الإحداثيات المخزّنة خارج المدى تُرفض', () {
      expect(
        SiteLocation.fromJson(<String, dynamic>{
          'latitude': 999.0,
          'longitude': 34.5,
          'timeZoneOffsetHours': 2,
        }),
        isNull,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('التخزين المحلي عبر قناة وهمية', () {
    const MethodChannel channel = MethodChannel('solar_qibla/control_test');
    final Map<String, String?> store = <String, String?>{};

    setUp(() {
      store.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        final Map<Object?, Object?> args =
            (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
        final String key = args['key']! as String;
        switch (call.method) {
          case 'writeString':
            store[key] = args['value'] as String?;
            return null;
          case 'readString':
            return store[key];
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('الحفظ ثم الاستعادة يعيدان الموقع نفسه', () async {
      final LocationService service = LocationService(control: channel);
      const SiteLocation location = SiteLocation(
        latitude: 24.7136,
        longitude: 46.6753,
        timeZoneOffsetHours: 3,
        source: LocationSource.manual,
      );

      await service.save(location);
      final SiteLocation? restored = await service.loadCached();

      expect(restored, isNotNull);
      expect(restored!.latitude, closeTo(24.7136, 1e-9));
      expect(restored.longitude, closeTo(46.6753, 1e-9));
      expect(restored.timeZoneOffsetHours, 3);
      expect(restored.source, LocationSource.cached);
    });

    test('لا شيء مخزّن ⇒ null بلا استثناء', () async {
      final LocationService service = LocationService(control: channel);
      expect(await service.loadCached(), isNull);
    });

    test('محتوى تالف ⇒ null بلا انهيار', () async {
      final LocationService service = LocationService(control: channel);
      store['last_location'] = 'هذا ليس JSON على الإطلاق {{{';
      expect(await service.loadCached(), isNull);
    });

    test('JSON صالح لكنه ليس كائنًا ⇒ null', () async {
      final LocationService service = LocationService(control: channel);
      store['last_location'] = '[1, 2, 3]';
      expect(await service.loadCached(), isNull);
    });

    test('نص فارغ ⇒ null', () async {
      final LocationService service = LocationService(control: channel);
      store['last_location'] = '';
      expect(await service.loadCached(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('المنطقة الزمنية القياسية', () {
    test('يُرجع عددًا صحيحًا من الساعات ضمن المدى الأرضي', () {
      final int offset = standardTimeZoneOffsetHours();
      expect(offset, greaterThanOrEqualTo(-12));
      expect(offset, lessThanOrEqualTo(14));
    });

    test('لا يتغيّر باختلاف شهر لحظة الاستدعاء', () {
      // جوهر الدالة: تحصين ضد التوقيت الصيفي. لو تغيّرت النتيجة بين
      // الشتاء والصيف لانزاح الزمن الشمسي ساعة كاملة، أي ‎15°‎ في
      // الزاوية الساعية.
      expect(
        standardTimeZoneOffsetHours(DateTime(2026, 1, 15)),
        standardTimeZoneOffsetHours(DateTime(2026, 7, 15)),
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('رسائل الإخفاق', () {
    test('لكل سبب رسالة عربية تذكر البديل اليدوي', () {
      for (final LocationFailure failure in LocationFailure.values) {
        final String message = locationFailureMessage(failure);
        expect(message, isNotEmpty);
        expect(message, contains('يدوي'),
            reason: 'رسالة $failure يجب أن تدلّ على المسار اليدوي');
      }
    });
  });
}
