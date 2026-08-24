// الشاشة الرئيسية: ثلاثة مؤشّرات لا رابع لها.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/guidance.dart';
import '../core/orientation.dart';
import 'about_screen.dart';
import 'calibration_screen.dart';
import 'indicators.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription<PanelReading>? _subscription;

  /// لمنع تكرار الاهتزاز طوال بقاء اللوح في النطاق الأخضر.
  bool _wasOnTarget = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.state.readings.listen(
      widget.state.updateReading,
      onError: (Object _) {
        // انقطاع المستشعر لا يُسقط الشاشة؛ تبقى القراءة الأخيرة معروضة
        // وتظهر لافتة تعذّر القراءة.
      },
    );
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _subscription?.cancel();
    super.dispose();
  }

  void _onStateChanged() {
    final AimingGuidance? guidance = widget.state.guidance;
    final bool onTarget = guidance?.isOnTarget ?? false;
    if (onTarget && !_wasOnTarget) {
      HapticFeedback.mediumImpact();
    }
    _wasOnTarget = onTarget;
  }

  Future<void> _open(Widget screen) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (BuildContext _) => screen),
      );

  void _pin() {
    final bool saved = widget.state.pinCurrentReading();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'تم تثبيت القراءة' : 'لا توجد قراءة كاملة للتثبيت',
          style: const TextStyle(fontSize: 17),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, Widget? _) {
        final AppState state = widget.state;

        return Scaffold(
          appBar: AppBar(
            title: const Text('قِبلة الشمس'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.wb_sunny_outlined, size: 28),
                tooltip: 'معايرة بالشمس',
                onPressed: () => _open(CalibrationScreen(state: state)),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 28),
                tooltip: 'الإعدادات',
                onPressed: () => _open(SettingsScreen(state: state)),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 28),
                tooltip: 'حول',
                onPressed: () => _open(const AboutScreen()),
              ),
            ],
          ),
          body: SafeArea(child: _body(state)),
        );
      },
    );
  }

  Widget _body(AppState state) {
    if (state.location == null) {
      return _needsSetup(state);
    }
    if (state.isOptimizing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'يجري حساب الزاوية المثلى…',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final double? targetTilt = state.targetTilt;
    final double? targetAzimuth = state.targetAzimuth;
    final PanelReading? reading = state.reading;
    final AimingGuidance? guidance = state.guidance;

    if (targetTilt == null || targetAzimuth == null) {
      return _needsSetup(state);
    }
    if (reading == null || guidance == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'في انتظار قراءة المستشعرات…\n'
            'ضع الهاتف مسطّحًا على سطح اللوح والشاشة للأعلى.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        _metalWarning(),
        if (reading.accuracy.needsCalibration) ...<Widget>[
          const SizedBox(height: 10),
          _calibrationWarning(state),
        ],
        const SizedBox(height: 16),

        // ── 1. حلقة البوصلة ──
        CompassRing(
          currentAzimuth: reading.trueAzimuth,
          targetAzimuth: targetAzimuth,
          band: guidance.azimuthDeviation == null
              ? AlignmentBand.far
              : bandForDeviation(guidance.azimuthDeviation!),
        ),
        const SizedBox(height: 10),
        _instruction(
          guidance.azimuthInstruction,
          guidance.azimuthDeviation == null
              ? AlignmentBand.far
              : bandForDeviation(guidance.azimuthDeviation!),
        ),

        const Divider(height: 36, thickness: 1.5),

        // ── 2. ميزان الميل ──
        TiltGauge(
          currentTilt: reading.tilt,
          targetTilt: targetTilt,
          band: bandForDeviation(guidance.tiltDeviation),
        ),
        const SizedBox(height: 10),
        _instruction(
          guidance.tiltInstruction,
          bandForDeviation(guidance.tiltDeviation),
        ),

        const Divider(height: 36, thickness: 1.5),

        // ── 3. مؤشّر الاستفادة ──
        PerformanceBar(ratio: guidance.performanceRatio, sun: state.sunNow),

        const SizedBox(height: 28),
        _pinButton(guidance),
        if (state.savedReading != null) ...<Widget>[
          const SizedBox(height: 16),
          _savedSummary(state.savedReading!),
        ],
      ],
    );
  }

  // ── لافتات ──────────────────────────────────────────────────────────────

  /// تحذير دائم لا يُخفى: التشويش المعدني أهمّ مصدر خطأ في هذا الاستعمال.
  Widget _metalWarning() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC43E00), width: 2),
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFC43E00), size: 30),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'أبعد الهاتف عن الأسطح المعدنية 30 سم على الأقل '
                'عند قراءة الاتجاه.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );

  Widget _calibrationWarning(AppState state) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFB3261E), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'دقّة البوصلة منخفضة. حرّك الهاتف في الهواء على شكل الرقم 8 '
              'عدّة مرات لمعايرتها.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _open(CalibrationScreen(state: state)),
                child: const Text(
                  'أو عايِر بالشمس',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _instruction(String text, AlignmentBand band) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bandColor(band).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: bandColor(band), width: 2),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: bandColor(band),
          ),
        ),
      );

  Widget _pinButton(AimingGuidance guidance) {
    final bool onTarget = guidance.isOnTarget;
    return SizedBox(
      height: 68,
      child: FilledButton.icon(
        onPressed: _pin,
        icon: Icon(onTarget ? Icons.check_circle : Icons.push_pin_outlined,
            size: 30),
        label: Text(
          onTarget ? 'الوضع الأمثل — ثبّت القراءة' : 'تثبيت القراءة',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor:
              onTarget ? const Color(0xFF0F7B3F) : const Color(0xFF37474F),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _savedSummary(SavedReading saved) {
    final String time = '${saved.timestamp.year}-'
        '${saved.timestamp.month.toString().padLeft(2, '0')}-'
        '${saved.timestamp.day.toString().padLeft(2, '0')} '
        '${saved.timestamp.hour.toString().padLeft(2, '0')}:'
        '${saved.timestamp.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'القراءة المثبَّتة',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('الميل: ${formatDegrees(saved.tilt)}  '
              '(الهدف ${formatDegrees(saved.targetTilt)})'),
          Text('الاتجاه: ${formatDegrees(saved.azimuth)} من الشمال الجغرافي  '
              '(الهدف ${formatDegrees(saved.targetAzimuth)})'),
          Text('الموقع: ${saved.latitude.toStringAsFixed(4)}° شمالًا، '
              '${saved.longitude.toStringAsFixed(4)}° شرقًا'),
          Text('الوقت: $time'),
          Text('دقّة البوصلة وقت التسجيل: ${_accuracyLabel(saved.accuracy)}'),
        ],
      ),
    );
  }

  static String _accuracyLabel(CompassAccuracy accuracy) {
    switch (accuracy) {
      case CompassAccuracy.high:
        return 'عالية';
      case CompassAccuracy.medium:
        return 'متوسطة';
      case CompassAccuracy.low:
        return 'منخفضة';
      case CompassAccuracy.unreliable:
        return 'غير موثوقة';
    }
  }

  Widget _needsSetup(AppState state) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.place_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'حدّد الموقع أولًا',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'يلزم خط العرض وخط الطول لحساب موضع الشمس والزاوية المثلى. '
                'يمكنك استعمال GPS أو إدخالهما يدويًا.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 60,
                child: FilledButton(
                  onPressed: () => _open(SettingsScreen(state: state)),
                  child: const Text(
                    'فتح الإعدادات',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
