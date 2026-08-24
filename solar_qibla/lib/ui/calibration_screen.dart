// شاشة المعايرة بالشمس — البديل عن البوصلة المغناطيسية عند التشويش المعدني.


import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/guidance.dart';
import '../core/orientation.dart';
import '../core/solar_math.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.state});

  final AppState state;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  double? _detectedOffset;

  void _capture() {
    final AppState state = widget.state;
    final PanelReading? reading = state.reading;
    final SolarPosition? sun = state.sunNow;

    if (reading == null || sun == null) {
      _notify('لا توجد قراءة أو موقع بعد');
      return;
    }
    if (!isSunSuitableForCalibration(sun)) {
      _notify(
        sun.elevation < 5.0
            ? 'الشمس منخفضة جدًا (${formatDegrees(sun.elevation)}) — '
                'المعايرة غير موثوقة الآن'
            : 'الشمس قريبة من سمت الرأس (${formatDegrees(sun.elevation)}) — '
                'اتجاهها غير محدّد بدقّة',
      );
      return;
    }

    // نقيس مقابل السمت المغناطيسي مصحَّحًا بالانحراف فقط، دون أي إزاحة
    // معايرة سابقة، وإلّا تراكمت الإزاحات فوق بعضها.
    final double? declination = reading.declination;
    if (declination == null) {
      _notify('الانحراف المغناطيسي غير معروف بعد');
      return;
    }
    final double observed =
        normalizeDegrees360(reading.magneticAzimuth + declination);

    final double offset = solarCalibrationOffset(
      observedAzimuth: observed,
      trueSolarAzimuth: sun.azimuth,
    );

    setState(() => _detectedOffset = offset);
    state.applyCalibration(offset);
  }

  void _clear() {
    widget.state.clearCalibration();
    setState(() => _detectedOffset = null);
    _notify('أُلغيت المعايرة — عادت البوصلة المغناطيسية وحدها');
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 17)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, Widget? _) {
        final AppState state = widget.state;
        final SolarPosition? sun = state.sunNow;
        final double? offset = _detectedOffset;

        return Scaffold(
          appBar: AppBar(title: const Text('المعايرة بالشمس')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              const Text(
                'لماذا المعايرة بالشمس؟',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'هياكل التركيب وإطارات الألواح من الألمنيوم والفولاذ تشوّه '
                'المجال المغناطيسي، فتنحرف البوصلة انحرافًا منهجيًا. '
                'الشمس مرجع اتجاه لا يتأثر بالمعدن إطلاقًا.',
                style: TextStyle(fontSize: 17, height: 1.6),
              ),
              const SizedBox(height: 24),

              if (sun == null)
                const Text(
                  'حدّد الموقع أولًا لحساب موضع الشمس.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                )
              else ...<Widget>[
                _sunPanel(sun),
                const SizedBox(height: 24),
                const Text(
                  'الخطوات',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '١. اختر إحدى الطريقتين:\n'
                  '   • وجّه الحافة العليا للهاتف نحو الشمس مباشرةً '
                  '(دون النظر إليها).\n'
                  '   • أو انصب عمودًا رأسيًا وحاذِ حافة الهاتف مع ظلّه، '
                  'فالظلّ يقع في عكس اتجاه الشمس تمامًا.\n\n'
                  '٢. أمِل الهاتف قليلًا حتى تصبح قراءة الاتجاه صالحة '
                  '(لوح أفقي تمامًا لا اتجاه له).\n\n'
                  '٣. اضغط "التقاط الإزاحة" مع ثبات الهاتف.',
                  style: TextStyle(fontSize: 17, height: 1.7),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    onPressed: _capture,
                    icon: const Icon(Icons.wb_sunny, size: 28),
                    label: const Text(
                      'التقاط الإزاحة',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],

              if (offset != null) ...<Widget>[
                const SizedBox(height: 20),
                _resultPanel(offset),
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text(
                      'إلغاء المعايرة',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ] else if (state.calibrationOffset != 0.0) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  'إزاحة مطبَّقة حاليًا: '
                  '${formatDegrees(state.calibrationOffset)}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _clear,
                    child: const Text(
                      'إلغاء المعايرة',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sunPanel(SolarPosition sun) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFA66A00), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'موضع الشمس الآن',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'الاتجاه: ${formatDegrees(sun.azimuth)} من الشمال الجغرافي',
              style: const TextStyle(fontSize: 17),
            ),
            Text(
              'الارتفاع فوق الأفق: ${formatDegrees(sun.elevation)}',
              style: const TextStyle(fontSize: 17),
            ),
            if (!isSunSuitableForCalibration(sun)) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                sun.elevation < 5.0
                    ? 'الشمس منخفضة جدًا للمعايرة الموثوقة (يلزم ‎5°‎ فأكثر).'
                    : 'الشمس مرتفعة جدًا؛ اتجاهها غير محدّد بدقّة '
                        '(يلزم ‎70°‎ فأقل).',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC43E00),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _resultPanel(double offset) {
    final bool suspicious = isCalibrationOffsetSuspicious(offset);
    final Color color =
        suspicious ? const Color(0xFFC43E00) : const Color(0xFF0F7B3F);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'الإزاحة المكتشفة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            formatDegrees(offset),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            offset >= 0
                ? 'البوصلة كانت تقرأ أقلّ من الحقيقة بهذا المقدار.'
                : 'البوصلة كانت تقرأ أكثر من الحقيقة بهذا المقدار.',
            style: const TextStyle(fontSize: 16),
          ),
          if (suspicious) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              'إزاحة كبيرة على غير المعتاد. الأرجح أن المحاذاة مع الشمس لم '
              'تكن دقيقة. أعد المعايرة قبل الاعتماد عليها.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC43E00),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
