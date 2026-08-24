// حالة التطبيق المشتركة.
//
// ChangeNotifier من Flutter نفسه: المشروع لا يحتاج حزمة إدارة حالة، وعدد
// الشاشات ثلاث.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'guidance.dart';
import 'location_service.dart';
import 'orientation.dart';
import 'solar_math.dart';

/// وسائط تشغيل المحسِّن في عزلة (Isolate).
///
/// `compute` تنقل وسيطًا واحدًا قابلًا للنقل، فتُجمع المدخلات هنا.
class _OptimizationRequest {
  final double latitude;
  final double longitude;
  final int timeZoneOffsetHours;
  final int modeIndex;

  const _OptimizationRequest({
    required this.latitude,
    required this.longitude,
    required this.timeZoneOffsetHours,
    required this.modeIndex,
  });
}

/// نقطة دخول العزلة — يجب أن تكون دالة عليا لا طريقة في صنف.
List<double> _runOptimization(_OptimizationRequest request) {
  final Orientation result = findOptimalOrientation(
    latitude: request.latitude,
    longitude: request.longitude,
    timeZoneOffsetHours: request.timeZoneOffsetHours,
    mode: OptimizationMode.values[request.modeIndex],
  );
  return <double>[result.tilt, result.azimuth];
}

/// حالة التطبيق: الإعدادات، الموقع، التوجيه الهدف، وآخر قراءة.
class AppState extends ChangeNotifier {
  AppState({
    LocationService? locationService,
    OrientationService? orientationService,
    MethodChannel control = const MethodChannel('solar_qibla/control'),
  })  : _control = control,
        // القناة تُمرَّر إلى الخدمتين لا تُترك لافتراضهما: إغفال ذلك يجعل
        // الخدمتين تخاطبان قناة غير التي حُقنت، فتتعلّق الاستدعاءات إلى
        // الأبد في الاختبارات، ويصعب تتبّع السبب.
        _locationService = locationService ?? LocationService(control: control),
        _orientationService =
            orientationService ?? OrientationService(control: control);

  final LocationService _locationService;
  final OrientationService _orientationService;
  final MethodChannel _control;

  static const String _settingsKey = 'settings';

  // ── الموقع ────────────────────────────────────────────────────────────
  SiteLocation? _location;
  SiteLocation? get location => _location;

  // ── الإعدادات ─────────────────────────────────────────────────────────
  OptimizationMode _mode = OptimizationMode.annual;
  OptimizationMode get mode => _mode;

  PanelOrientation _panelOrientation = PanelOrientation.portrait;
  PanelOrientation get panelOrientation => _panelOrientation;

  double _panelLength = 2.278;
  double get panelLength => _panelLength;

  double _panelWidth = 1.134;
  double get panelWidth => _panelWidth;

  /// الميل الذي يُدخله المستخدم في الوضع اليدوي [درجة].
  double _manualTilt = 30.0;
  double get manualTilt => _manualTilt;

  /// السمت الذي يُدخله المستخدم في الوضع اليدوي [درجة].
  double _manualAzimuth = 180.0;
  double get manualAzimuth => _manualAzimuth;

  // ── التوجيه الهدف ─────────────────────────────────────────────────────
  double? _targetTilt;
  double? _targetAzimuth;

  /// الميل الهدف [درجة]، أو null قبل اكتمال الحساب.
  double? get targetTilt =>
      _mode == OptimizationMode.manual ? _manualTilt : _targetTilt;

  /// السمت الهدف [درجة]، أو null قبل اكتمال الحساب.
  double? get targetAzimuth =>
      _mode == OptimizationMode.manual ? _manualAzimuth : _targetAzimuth;

  bool _isOptimizing = false;
  bool get isOptimizing => _isOptimizing;

  // ── القراءة الحالية ───────────────────────────────────────────────────
  PanelReading? _reading;
  PanelReading? get reading => _reading;

  /// إزاحة المعايرة بالشمس المطبَّقة حاليًا [درجة].
  double get calibrationOffset => _orientationService.calibrationOffset;

  /// آخر قراءة ثبّتها المستخدم.
  SavedReading? _savedReading;
  SavedReading? get savedReading => _savedReading;

  /// تدفّق قراءات التوجيه.
  Stream<PanelReading> get readings => _orientationService.readings();

  /// يستقبل قراءة جديدة من التدفّق.
  void updateReading(PanelReading value) {
    _reading = value;
    notifyListeners();
  }

  /// موضع الشمس الآن، أو null قبل معرفة الموقع.
  SolarPosition? get sunNow {
    final SiteLocation? site = _location;
    if (site == null) return null;
    return solarPosition(
      latitude: site.latitude,
      longitude: site.longitude,
      timeZoneOffsetHours: site.timeZoneOffsetHours,
      localStandardTime: localStandardNow(site.timeZoneOffsetHours),
    );
  }

  /// الإرشاد الحالي، أو null إذا نقص الموقع أو الهدف أو القراءة.
  AimingGuidance? get guidance {
    final PanelReading? current = _reading;
    final double? tilt = targetTilt;
    final double? azimuth = targetAzimuth;
    if (current == null || tilt == null || azimuth == null) return null;
    return computeGuidance(
      reading: current,
      targetTilt: tilt,
      targetAzimuth: azimuth,
      sun: sunNow,
    );
  }

  /// تخطيط الصفوف وفق الميل الهدف وأبعاد اللوح، أو null قبل توفّر الهدف.
  RowLayout? get rowLayout {
    final SiteLocation? site = _location;
    final double? tilt = targetTilt;
    if (site == null || tilt == null) return null;
    try {
      return computeRowLayout(
        latitude: site.latitude,
        tilt: tilt,
        panelLength: _panelLength,
        panelWidth: _panelWidth,
        orientation: _panelOrientation,
      );
    } on StateError {
      // خط عرض قطبي: الشمس تحت الأفق عند لحظة التصميم.
      return null;
    }
  }

  // ── دورة الحياة ───────────────────────────────────────────────────────

  /// يستعيد الإعدادات والموقع المحفوظين ويحسب الهدف.
  Future<void> restore() async {
    await _loadSettings();
    final SiteLocation? cached = await _locationService.loadCached();
    if (cached != null) {
      await setLocation(cached);
    } else {
      notifyListeners();
    }
  }

  /// يعتمد موقعًا جديدًا: يحفظه، ويبلّغ طبقة المستشعرات، ويعيد الحساب.
  Future<void> setLocation(SiteLocation value) async {
    _location = value;
    notifyListeners();

    await _locationService.save(value);
    await _orientationService.setLocation(
      latitude: value.latitude,
      longitude: value.longitude,
      altitude: value.altitude,
    );
    await _recomputeTarget();
  }

  /// يحاول تحديد الموقع من GPS. يُرجع سبب الإخفاق أو null عند النجاح.
  Future<LocationFailure?> locateWithGps() async {
    final LocationResult result = await _locationService.fromGps();
    if (!result.isSuccess) return result.failure;
    await setLocation(result.location!);
    return null;
  }

  /// يعتمد موقعًا مُدخلًا يدويًا. يُرجع false إذا كانت الإحداثيات خارج المدى.
  Future<bool> setManualLocation({
    required double latitude,
    required double longitude,
    int? timeZoneOffsetHours,
  }) async {
    final SiteLocation? value = _locationService.fromManualInput(
      latitude: latitude,
      longitude: longitude,
      timeZoneOffsetHours: timeZoneOffsetHours,
    );
    if (value == null) return false;
    await setLocation(value);
    return true;
  }

  Future<void> setMode(OptimizationMode value) async {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
    await _saveSettings();
    await _recomputeTarget();
  }

  Future<void> setPanelOrientation(PanelOrientation value) async {
    _panelOrientation = value;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setPanelDimensions({
    required double length,
    required double width,
  }) async {
    if (length <= 0 || width <= 0) return;
    _panelLength = length;
    _panelWidth = width;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setManualOrientation({
    required double tilt,
    required double azimuth,
  }) async {
    _manualTilt = tilt.clamp(0.0, 90.0);
    _manualAzimuth = normalizeDegrees360(azimuth);
    notifyListeners();
    await _saveSettings();
  }

  /// يطبّق إزاحة معايرة مشتقّة من مشاهدة الشمس.
  void applyCalibration(double offset) {
    _orientationService.applyCalibrationOffset(offset);
    notifyListeners();
  }

  /// يلغي المعايرة ويعود إلى البوصلة المغناطيسية وحدها.
  void clearCalibration() {
    _orientationService.clearCalibration();
    notifyListeners();
  }

  /// يثبّت القراءة الحالية مع الطابع الزمني والموقع.
  ///
  /// يُرجع false إذا لم تكن هناك قراءة صالحة للتثبيت.
  bool pinCurrentReading() {
    final PanelReading? current = _reading;
    final SiteLocation? site = _location;
    final double? tilt = targetTilt;
    final double? azimuth = targetAzimuth;
    final double? currentAzimuth = current?.trueAzimuth;
    if (current == null ||
        site == null ||
        tilt == null ||
        azimuth == null ||
        currentAzimuth == null) {
      return false;
    }

    _savedReading = SavedReading(
      tilt: current.tilt,
      azimuth: currentAzimuth,
      targetTilt: tilt,
      targetAzimuth: azimuth,
      latitude: site.latitude,
      longitude: site.longitude,
      timestamp: DateTime.now(),
      accuracy: current.accuracy,
    );
    notifyListeners();
    return true;
  }

  // ── الحساب ────────────────────────────────────────────────────────────

  Future<void> _recomputeTarget() async {
    final SiteLocation? site = _location;
    if (site == null || _mode == OptimizationMode.manual) {
      notifyListeners();
      return;
    }

    _isOptimizing = true;
    notifyListeners();

    // المسح الشامل يستغرق ثوانيَ معدودة؛ تشغيله على خيط الواجهة يجمّدها.
    final List<double> result = await compute(
      _runOptimization,
      _OptimizationRequest(
        latitude: site.latitude,
        longitude: site.longitude,
        timeZoneOffsetHours: site.timeZoneOffsetHours,
        modeIndex: _mode.index,
      ),
    );

    _targetTilt = result[0];
    _targetAzimuth = result[1];
    _isOptimizing = false;
    notifyListeners();
  }

  // ── التخزين ───────────────────────────────────────────────────────────

  Future<void> _saveSettings() => _control.invokeMethod<void>(
        'writeString',
        <String, dynamic>{
          'key': _settingsKey,
          'value': jsonEncode(<String, dynamic>{
            'mode': _mode.index,
            'panelOrientation': _panelOrientation.index,
            'panelLength': _panelLength,
            'panelWidth': _panelWidth,
            'manualTilt': _manualTilt,
            'manualAzimuth': _manualAzimuth,
          }),
        },
      );

  Future<void> _loadSettings() async {
    final String? stored = await _control.invokeMethod<String>(
      'readString',
      <String, dynamic>{'key': _settingsKey},
    );
    if (stored == null || stored.isEmpty) return;

    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return; // محتوى تالف: نُبقي الافتراضات
    }
    if (decoded is! Map<String, dynamic>) return;

    final Object? mode = decoded['mode'];
    if (mode is int && mode >= 0 && mode < OptimizationMode.values.length) {
      _mode = OptimizationMode.values[mode];
    }
    final Object? orientation = decoded['panelOrientation'];
    if (orientation is int &&
        orientation >= 0 &&
        orientation < PanelOrientation.values.length) {
      _panelOrientation = PanelOrientation.values[orientation];
    }
    final Object? length = decoded['panelLength'];
    if (length is num && length > 0) _panelLength = length.toDouble();
    final Object? width = decoded['panelWidth'];
    if (width is num && width > 0) _panelWidth = width.toDouble();
    final Object? tilt = decoded['manualTilt'];
    if (tilt is num) _manualTilt = tilt.toDouble().clamp(0.0, 90.0);
    final Object? azimuth = decoded['manualAzimuth'];
    if (azimuth is num) _manualAzimuth = normalizeDegrees360(azimuth.toDouble());
  }
}

/// الزمن المحلي القياسي الآن، بلا توقيت صيفي.
///
/// `DateTime.now()` يعطي الزمن المدني الذي قد يشمل التوقيت الصيفي، بينما
/// محرّك الحسابات يعمل بالزمن القياسي. نُعيد البناء من UTC وإزاحة المنطقة
/// القياسية بدل الاعتماد على ساعة الجهاز المحلية.
DateTime localStandardNow(int timeZoneOffsetHours) =>
    DateTime.now().toUtc().add(Duration(hours: timeZoneOffsetHours));
