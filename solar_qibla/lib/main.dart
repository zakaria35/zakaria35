// نقطة الدخول: الثيم العربي عالي التباين، وتشغيل التطبيق.

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/app_state.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // التطبيق يُستعمل واليدان مشغولتان بضبط اللوح؛ إطفاء الشاشة أثناء ذلك
  // يُفقد الفنّي القراءة في أسوأ لحظة.
  await WakelockPlus.enable();

  final AppState state = AppState();
  await state.restore();

  runApp(SolarQiblaApp(state: state));
}

/// لون النصّ الأساسي — قريب من الأسود لأقصى تباين تحت الشمس.
const Color _ink = Color(0xFF111111);

class SolarQiblaApp extends StatelessWidget {
  const SolarQiblaApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قِبلة الشمس',
      debugShowCheckedModeBanner: false,
      theme: _sunlightTheme(),
      // الواجهة عربية بالكامل: الاتجاه من اليمين إلى اليسار على مستوى
      // التطبيق، فيشمل حتى حواراتِ النظام وشرائطَ التنبيه.
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomeScreen(state: state),
    );
  }
}

/// ثيم فاتح عالي السطوع، مصمَّم للقراءة تحت شمس مباشرة.
///
/// لا يوجد ثيم داكن عمدًا: الشاشة الداكنة تحت الشمس المباشرة أقلّ قراءةً
/// بكثير من الفاتحة، والتطبيق يُستعمل على سطح مكشوف في وضح النهار.
ThemeData _sunlightTheme() {
  const ColorScheme scheme = ColorScheme.light(
    primary: Color(0xFF0B5FA5),
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: _ink,
    error: Color(0xFFB3261E),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    fontFamily: 'Tajawal',

    // نصوص داكنة وثقيلة: الخطوط الرفيعة تختفي تحت الوهج.
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 18, color: _ink),
      bodyMedium: TextStyle(fontSize: 17, color: _ink, height: 1.5),
      bodySmall: TextStyle(fontSize: 15, color: _ink),
      titleMedium: TextStyle(
        fontSize: 19,
        color: _ink,
        fontWeight: FontWeight.w500,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Tajawal',
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: _ink,
      ),
    ),

    dividerTheme: const DividerThemeData(color: Color(0xFFBDBDBD)),

    // مساحات لمس كبيرة: التطبيق يُستعمل بقفّازات عمل أحيانًا.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: _ink,
        side: const BorderSide(color: _ink, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF263238),
      contentTextStyle: TextStyle(
        fontFamily: 'Tajawal',
        fontSize: 17,
        color: Colors.white,
      ),
    ),
  );
}
