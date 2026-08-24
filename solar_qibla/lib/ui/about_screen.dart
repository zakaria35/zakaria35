// شاشة "حول" — إخلاء المسؤولية والمراجع.

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حول التطبيق')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const <Widget>[
          Text(
            'قِبلة الشمس',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'أداة ميدانية لضبط ميل لوح شمسي على حامل ثابت واتجاهه.',
            style: TextStyle(fontSize: 18),
          ),
          SizedBox(height: 28),

          _Heading('إخلاء مسؤولية'),
          Text(
            'النتائج التي يعرضها هذا التطبيق تقديرية. تقوم على نماذج فلكية '
            'معيارية لحساب موضع الشمس، وعلى نموذج سماء صافية مبسّط لتقدير '
            'الإشعاع.\n\n'
            'نموذج السماء الصافية لا يأخذ في الحسبان الغيوم ولا الغبار ولا '
            'العوالق الجوية ولا بخار الماء ولا ارتفاع الموقع. لذلك تصلح قيم '
            'الإشعاع للمقارنة النسبية بين التوجيهات فقط، ولا تصلح لتقدير '
            'الإنتاج الفعلي بالكيلوواط‑ساعة.\n\n'
            'قراءة الاتجاه تعتمد على بوصلة الهاتف المغناطيسية، وهي تتأثر '
            'بالمعادن وبالتشويش المغناطيسي المحيط. هياكل التركيب وإطارات '
            'الألواح من الألمنيوم والفولاذ قد تُحدث انحرافًا يبلغ عشرات '
            'الدرجات. استعمل "المعايرة بالشمس" كلما شككت في القراءة.\n\n'
            'هذا التطبيق لا يغني عن الدراسة الهندسية للموقع.',
            style: TextStyle(fontSize: 17, height: 1.7),
          ),
          SizedBox(height: 28),

          _Heading('المراجع الحسابية'),
          Text(
            '• موضع الشمس: الصيغة منخفضة الدقة من كتاب Meeus '
            '«Astronomical Algorithms»، وهي الخوارزمية التي تقوم عليها '
            'حاسبة NOAA Solar Calculator.\n\n'
            '• هندسة السطح المائل وزاوية السقوط وتباعد الصفوف: '
            'Duffie & Beckman، «Solar Engineering of Thermal Processes».\n\n'
            '• الانحراف المغناطيسي: النموذج المغناطيسي العالمي عبر '
            'android.hardware.GeomagneticField.\n\n'
            '• بيانات الإشعاع المقيسة (اختيارية): NASA POWER.',
            style: TextStyle(fontSize: 17, height: 1.7),
          ),
          SizedBox(height: 28),

          _Heading('دقّة موضع الشمس'),
          Text(
            'قِيس موضع الشمس المحسوب مقابل خوارزمية NREL SPA المرجعية في '
            'ثلاثة مواقع وثلاثة تواريخ، فبلغ أقصى فارق زاوي ‎0.005°‎.\n\n'
            'الانحراف المغناطيسي مصدر خطأ أكبر من ذلك بكثير: النموذج '
            'المغناطيسي المدمج في أندرويد قد يكون أقدم من تاريخه، والانحراف '
            'يتغيّر نحو ‎0.1°‎ إلى ‎0.2°‎ في السنة.',
            style: TextStyle(fontSize: 17, height: 1.7),
          ),
          SizedBox(height: 28),

          _Heading('العمل بلا إنترنت'),
          Text(
            'التطبيق يعمل كاملًا بلا اتصال. كل الحسابات تجري على الجهاز، '
            'والخط العربي مضمَّن في التطبيق لا مُحمَّل عبر الشبكة. عند تعذّر '
            'GPS يمكن إدخال خط العرض وخط الطول يدويًا.\n\n'
            'تحديث بيانات الإشعاع من NASA POWER تحسين اختياري وحده يتطلّب '
            'اتصالًا. عند تعذّره يُستعمل النموذج المدمج بلا انقطاع في الخدمة، '
            'والبيانات المجلوبة تُخزَّن محليًا فتبقى متاحة بعد ذلك بلا اتصال.',
            style: TextStyle(fontSize: 17, height: 1.7),
          ),
          SizedBox(height: 28),

          _Heading('الخط'),
          Text(
            'خط Tajawal بترخيص SIL Open Font License 1.1، '
            'حقوق النشر لـBoutros International.',
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      );
}
