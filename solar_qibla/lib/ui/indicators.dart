// مؤشّرات الشاشة الرئيسية الثلاثة: حلقة البوصلة، ميزان الميل، وشريط
// الاستفادة اللحظية.
//
// كلها مصمّمة للقراءة تحت شمس مباشرة: تباين عالٍ، خطوط سميكة، أرقام كبيرة.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/guidance.dart';
import '../core/solar_math.dart';

/// ألوان النطاقات، موحّدة عبر التطبيق كلّه.
///
/// مختارة داكنة بما يكفي ليبقى التباين مع الخلفية البيضاء عاليًا تحت الشمس.
Color bandColor(AlignmentBand band) {
  switch (band) {
    case AlignmentBand.onTarget:
      return const Color(0xFF0F7B3F); // أخضر
    case AlignmentBand.close:
      return const Color(0xFFA66A00); // أصفر داكن
    case AlignmentBand.far:
      return const Color(0xFFC43E00); // برتقالي
  }
}

/// نصّ وصفي للنطاق.
String bandLabel(AlignmentBand band) {
  switch (band) {
    case AlignmentBand.onTarget:
      return 'مضبوط';
    case AlignmentBand.close:
      return 'قريب';
    case AlignmentBand.far:
      return 'بعيد';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. حلقة البوصلة
// ═══════════════════════════════════════════════════════════════════════════

/// حلقة بوصلة: الشمال ثابت للأعلى، مع علامة على الاتجاه الهدف وإبرة على
/// الاتجاه الحالي للوح.
class CompassRing extends StatelessWidget {
  const CompassRing({
    super.key,
    required this.currentAzimuth,
    required this.targetAzimuth,
    required this.band,
  });

  /// السمت الحقيقي الحالي للوح [درجة]، أو null إذا تعذّرت القراءة.
  final double? currentAzimuth;

  /// السمت الهدف [درجة].
  final double targetAzimuth;

  final AlignmentBand band;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: CustomPaint(
        painter: _CompassPainter(
          currentAzimuth: currentAzimuth,
          targetAzimuth: targetAzimuth,
          color: bandColor(band),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currentAzimuth == null ? '—' : formatDegrees(currentAzimuth!),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
              const Text(
                'اتجاه اللوح',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                'الهدف ${formatDegrees(targetAzimuth)}',
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.currentAzimuth,
    required this.targetAzimuth,
    required this.color,
  });

  final double? currentAzimuth;
  final double targetAzimuth;
  final Color color;

  static const Color _ink = Color(0xFF111111);
  static const Color _muted = Color(0xFF767676);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = math.min(size.width, size.height) / 2 - 6;

    // الحلقة الخارجية.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _ink,
    );

    // تدريج كل 15°، وأطول كل 45°.
    final Paint tick = Paint()..color = _muted;
    for (int degrees = 0; degrees < 360; degrees += 15) {
      final bool major = degrees % 45 == 0;
      tick
        ..strokeWidth = major ? 3 : 1.5
        ..color = major ? _ink : _muted;
      final double length = major ? 16 : 9;
      final Offset outer = _pointAt(center, radius - 2, degrees.toDouble());
      final Offset inner =
          _pointAt(center, radius - 2 - length, degrees.toDouble());
      canvas.drawLine(inner, outer, tick);
    }

    // الجهات الأصلية بالعربية.
    const Map<int, String> cardinals = <int, String>{
      0: 'ش',
      90: 'ق',
      180: 'ج',
      270: 'غ',
    };
    cardinals.forEach((int degrees, String label) {
      _drawText(
        canvas,
        label,
        _pointAt(center, radius - 34, degrees.toDouble()),
        fontSize: 20,
        weight: FontWeight.bold,
        color: _ink,
      );
    });

    // علامة الهدف: مثلّث ثابت خارج الحلقة.
    _drawTargetMarker(canvas, center, radius, targetAzimuth);

    // إبرة الاتجاه الحالي.
    final double? current = currentAzimuth;
    if (current != null) {
      _drawNeedle(canvas, center, radius, current);
    }
  }

  /// نقطة على دائرة عند سمت معطى — الشمال للأعلى والزوايا مع عقارب الساعة.
  Offset _pointAt(Offset center, double radius, double azimuth) {
    final double radians = (azimuth - 90.0) * math.pi / 180.0;
    return Offset(
      center.dx + radius * math.cos(radians),
      center.dy + radius * math.sin(radians),
    );
  }

  void _drawTargetMarker(
      Canvas canvas, Offset center, double radius, double azimuth) {
    final Offset tip = _pointAt(center, radius - 2, azimuth);
    final Offset left = _pointAt(center, radius + 12, azimuth - 4.5);
    final Offset right = _pointAt(center, radius + 12, azimuth + 4.5);

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
      Paint()..color = _ink,
    );

    // خطّ الهدف عبر الحلقة، ليبقى مرئيًا حتى عند تطابق الإبرة معه.
    canvas.drawLine(
      center,
      _pointAt(center, radius - 2, azimuth),
      Paint()
        ..color = _ink.withValues(alpha: 0.28)
        ..strokeWidth = 2,
    );
  }

  void _drawNeedle(
      Canvas canvas, Offset center, double radius, double azimuth) {
    final double needleLength = radius - 26;
    final Offset tip = _pointAt(center, needleLength, azimuth);
    final Offset baseLeft = _pointAt(center, 16, azimuth - 90);
    final Offset baseRight = _pointAt(center, 16, azimuth + 90);

    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(baseLeft.dx, baseLeft.dy)
        ..lineTo(baseRight.dx, baseRight.dy)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawCircle(center, 7, Paint()..color = color);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    required double fontSize,
    required FontWeight weight,
    required Color color,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          fontFamily: 'Tajawal',
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.currentAzimuth != currentAzimuth ||
      old.targetAzimuth != targetAzimuth ||
      old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. ميزان الميل
// ═══════════════════════════════════════════════════════════════════════════

/// ميزان فقاعي رقمي: يعرض الميل الحالي والهدف على مسطرة أفقية.
class TiltGauge extends StatelessWidget {
  const TiltGauge({
    super.key,
    required this.currentTilt,
    required this.targetTilt,
    required this.band,
  });

  /// الميل الحالي [درجة].
  final double currentTilt;

  /// الميل الهدف [درجة].
  final double targetTilt;

  final AlignmentBand band;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // الرقم الأساسي يتقلّص بدل أن يفيض: قيم مثل ‎−100.0°‎ أعرض
            // بكثير من ‎30.0°‎، والشاشة ضيّقة.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatDegrees(currentTilt),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  const Text(
                    'زاوية الميل',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'الهدف ${formatDegrees(targetTilt)}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 46,
          child: CustomPaint(
            painter: _TiltPainter(
              currentTilt: currentTilt,
              targetTilt: targetTilt,
              color: bandColor(band),
            ),
          ),
        ),
      ],
    );
  }
}

class _TiltPainter extends CustomPainter {
  _TiltPainter({
    required this.currentTilt,
    required this.targetTilt,
    required this.color,
  });

  final double currentTilt;
  final double targetTilt;
  final Color color;

  /// نصف مدى المسطرة حول الهدف [درجة].
  static const double _span = 25.0;

  static const Color _ink = Color(0xFF111111);

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height / 2;

    // القضيب.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - 9, size.width, 18),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFFE4E4E4),
    );

    /// موضع أفقي لزاوية معطاة.
    double xFor(double tilt) {
      final double fraction =
          ((tilt - targetTilt) / (2 * _span) + 0.5).clamp(0.0, 1.0);
      return fraction * size.width;
    }

    // نطاق المطابقة الأخضر حول الهدف.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          xFor(targetTilt - kOnTargetThreshold),
          midY - 9,
          xFor(targetTilt + kOnTargetThreshold),
          midY + 9,
        ),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF0F7B3F).withValues(alpha: 0.22),
    );

    // خطّ الهدف.
    final double targetX = xFor(targetTilt);
    canvas.drawLine(
      Offset(targetX, 0),
      Offset(targetX, size.height),
      Paint()
        ..color = _ink
        ..strokeWidth = 3,
    );

    // الفقاعة عند الميل الحالي.
    canvas.drawCircle(
      Offset(xFor(currentTilt), midY),
      13,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(xFor(currentTilt), midY),
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TiltPainter old) =>
      old.currentTilt != currentTilt ||
      old.targetTilt != targetTilt ||
      old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. شريط الاستفادة اللحظية
// ═══════════════════════════════════════════════════════════════════════════

/// نسبة الاستفادة اللحظية بشريط لوني.
class PerformanceBar extends StatelessWidget {
  const PerformanceBar({super.key, required this.ratio, required this.sun});

  /// النسبة ‎[0, 100]‎، أو null إذا تعذّر حسابها.
  final double? ratio;

  /// موضع الشمس، لتفسير سبب غياب النسبة.
  final SolarPosition? sun;

  @override
  Widget build(BuildContext context) {
    final double? value = ratio;

    if (value == null) {
      final bool isNight = sun != null && !sun!.isDaylight;
      return Text(
        isNight
            ? 'الشمس تحت الأفق — مؤشّر الاستفادة غير متاح ليلًا'
            : 'مؤشّر الاستفادة غير متاح: تعذّرت قراءة الاتجاه',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      );
    }

    // النطاق اللوني هنا يتبع النسبة لا الزاوية: 97٪ فأعلى تقابل عمليًا
    // انحرافًا ضمن بضع درجات.
    final Color color = value >= 97.0
        ? const Color(0xFF0F7B3F)
        : value >= 90.0
            ? const Color(0xFFA66A00)
            : const Color(0xFFC43E00);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${value.toStringAsFixed(0)}٪',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'الاستفادة اللحظية\nمن الوضع الأمثل',
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value / 100.0,
            minHeight: 16,
            backgroundColor: const Color(0xFFE4E4E4),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
