// شاشة الإعدادات: الموقع، وضع التحسين، اتجاه اللوح وأبعاده.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/guidance.dart';
import '../core/irradiance_data.dart';
import '../core/location_service.dart';
import '../core/solar_math.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _manualTilt;
  late final TextEditingController _manualAzimuth;

  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final AppState state = widget.state;
    _latitude = TextEditingController(
      text: state.location?.latitude.toStringAsFixed(4) ?? '',
    );
    _longitude = TextEditingController(
      text: state.location?.longitude.toStringAsFixed(4) ?? '',
    );
    _length = TextEditingController(text: state.panelLength.toString());
    _width = TextEditingController(text: state.panelWidth.toString());
    _manualTilt = TextEditingController(text: state.manualTilt.toString());
    _manualAzimuth = TextEditingController(text: state.manualAzimuth.toString());
  }

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _length.dispose();
    _width.dispose();
    _manualTilt.dispose();
    _manualAzimuth.dispose();
    super.dispose();
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 17)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    final LocationFailure? failure = await widget.state.locateWithGps();
    if (!mounted) return;
    setState(() => _locating = false);

    if (failure != null) {
      _notify(locationFailureMessage(failure));
      return;
    }
    final SiteLocation? location = widget.state.location;
    if (location != null) {
      _latitude.text = location.latitude.toStringAsFixed(4);
      _longitude.text = location.longitude.toStringAsFixed(4);
    }
    _notify('تم تحديد الموقع من GPS');
  }

  Future<void> _applyManualLocation() async {
    final double? latitude = double.tryParse(_latitude.text.trim());
    final double? longitude = double.tryParse(_longitude.text.trim());
    if (latitude == null || longitude == null) {
      _notify('أدخل رقمين صالحين لخط العرض وخط الطول');
      return;
    }
    final bool ok = await widget.state.setManualLocation(
      latitude: latitude,
      longitude: longitude,
    );
    _notify(ok
        ? 'تم اعتماد الموقع اليدوي'
        : 'الإحداثيات خارج المدى: العرض ‎−90..90‎ والطول ‎−180..180‎');
  }

  Future<void> _applyPanelDimensions() async {
    final double? length = double.tryParse(_length.text.trim());
    final double? width = double.tryParse(_width.text.trim());
    if (length == null || width == null || length <= 0 || width <= 0) {
      _notify('أدخل أبعادًا موجبة بالمتر');
      return;
    }
    await widget.state.setPanelDimensions(length: length, width: width);
    _notify('تم حفظ أبعاد اللوح');
  }

  Future<void> _applyManualOrientation() async {
    final double? tilt = double.tryParse(_manualTilt.text.trim());
    final double? azimuth = double.tryParse(_manualAzimuth.text.trim());
    if (tilt == null || azimuth == null) {
      _notify('أدخل رقمين صالحين للميل والسمت');
      return;
    }
    await widget.state.setManualOrientation(tilt: tilt, azimuth: azimuth);
    _notify('تم حفظ الزاوية اليدوية');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, Widget? _) {
        final AppState state = widget.state;
        return Scaffold(
          appBar: AppBar(title: const Text('الإعدادات')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _section('الموقع'),
              _locationSection(state),
              const Divider(height: 36, thickness: 1.5),
              _section('وضع التحسين'),
              _modeSection(state),
              const Divider(height: 36, thickness: 1.5),
              _section('اتجاه اللوح وأبعاده'),
              _panelSection(state),
              const Divider(height: 36, thickness: 1.5),
              _section('بيانات الإشعاع'),
              _irradianceSection(state),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      );

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        style: const TextStyle(fontSize: 20),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 17),
          border: const OutlineInputBorder(),
        ),
      );

  Widget _locationSection(AppState state) {
    final SiteLocation? location = state.location;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (location != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'الحالي: ${location.latitude.toStringAsFixed(4)}° عرضًا، '
              '${location.longitude.toStringAsFixed(4)}° طولًا  '
              '(${_sourceLabel(location.source)})\n'
              'المنطقة الزمنية القياسية: '
              'UTC${location.timeZoneOffsetHours >= 0 ? '+' : ''}'
              '${location.timeZoneOffsetHours}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: _locating ? null : _useGps,
            icon: _locating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.my_location, size: 26),
            label: Text(
              _locating ? 'يجري التحديد…' : 'تحديد بواسطة GPS',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'أو أدخل الإحداثيات يدويًا (بالدرجات العشرية، موجب شمالًا وشرقًا):',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 10),
        _numberField(_latitude, 'خط العرض (درجة)'),
        const SizedBox(height: 10),
        _numberField(_longitude, 'خط الطول (درجة)'),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: _applyManualLocation,
            child: const Text(
              'اعتماد الموقع اليدوي',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  static String _sourceLabel(LocationSource source) {
    switch (source) {
      case LocationSource.gps:
        return 'GPS';
      case LocationSource.manual:
        return 'يدوي';
      case LocationSource.cached:
        return 'محفوظ';
    }
  }

  Widget _modeSection(AppState state) {
    const Map<OptimizationMode, String> labels = <OptimizationMode, String>{
      OptimizationMode.annual: 'سنوي — الأمثل على مدار السنة',
      OptimizationMode.summer: 'صيفي — تحسين لأشهر 5 إلى 8',
      OptimizationMode.winter: 'شتوي — تحسين لأشهر 11 إلى 2',
      OptimizationMode.manual: 'يدوي — أُدخل الزاوية بنفسي',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        RadioGroup<OptimizationMode>(
          groupValue: state.mode,
          onChanged: (OptimizationMode? value) {
            if (value != null) state.setMode(value);
          },
          child: Column(
            children: <Widget>[
              for (final MapEntry<OptimizationMode, String> entry
                  in labels.entries)
                RadioListTile<OptimizationMode>(
                  value: entry.key,
                  title:
                      Text(entry.value, style: const TextStyle(fontSize: 18)),
                  contentPadding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
        if (state.mode == OptimizationMode.manual) ...<Widget>[
          const SizedBox(height: 10),
          _numberField(_manualTilt, 'الميل اليدوي (درجة، 0–90)'),
          const SizedBox(height: 10),
          _numberField(_manualAzimuth, 'السمت اليدوي (درجة من الشمال)'),
          const SizedBox(height: 10),
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: _applyManualOrientation,
              child: const Text(
                'حفظ الزاوية اليدوية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ] else if (state.targetTilt != null && state.targetAzimuth != null) ...[
          const SizedBox(height: 10),
          Text(
            'المحسوب: ميل ${formatDegrees(state.targetTilt!)}، '
            'سمت ${formatDegrees(state.targetAzimuth!)} من الشمال',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }

  Future<void> _refreshIrradiance() async {
    final IrradianceFetchFailure? failure =
        await widget.state.refreshIrradiance();
    if (!mounted) return;
    _notify(failure == null
        ? 'تم تحديث بيانات الإشعاع وإعادة حساب الزاوية'
        : irradianceFailureMessage(failure));
  }

  Widget _irradianceSection(AppState state) {
    final MonthlyIrradiance? data = state.irradiance;
    final bool measured = state.usesMeasuredIrradiance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: measured
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: measured ? const Color(0xFF0F7B3F) : const Color(0xFFBDBDBD),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                measured
                    ? 'المصدر الحالي: بيانات مقيسة (NASA POWER)'
                    : 'المصدر الحالي: النموذج التقريبي المدمج',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              if (measured && data != null)
                Text(
                  'سنة البيانات: ${data.year}\n'
                  'آخر تحديث: ${_formatDate(data.fetchedAt)}',
                  style: const TextStyle(fontSize: 16),
                )
              else
                const Text(
                  'نموذج سماء صافية مبسّط: يهمل الغيوم والغبار وبخار الماء. '
                  'التطبيق يعمل به كاملًا بلا إنترنت.',
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: state.location == null || state.isFetchingIrradiance
                ? null
                : _refreshIrradiance,
            icon: state.isFetchingIrradiance
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.cloud_download_outlined, size: 24),
            label: Text(
              state.isFetchingIrradiance
                  ? 'يجري التحديث…'
                  : 'تحديث بيانات الإشعاع (يتطلّب إنترنت)',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (measured) ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: TextButton(
              onPressed: state.useOfflineModel,
              child: const Text(
                'العودة إلى النموذج المدمج',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDate(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Widget _panelSection(AppState state) {
    final RowLayout? layout = state.rowLayout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<PanelOrientation>(
          segments: const <ButtonSegment<PanelOrientation>>[
            ButtonSegment<PanelOrientation>(
              value: PanelOrientation.portrait,
              label: Text('رأسي', style: TextStyle(fontSize: 18)),
            ),
            ButtonSegment<PanelOrientation>(
              value: PanelOrientation.landscape,
              label: Text('أفقي', style: TextStyle(fontSize: 18)),
            ),
          ],
          selected: <PanelOrientation>{state.panelOrientation},
          onSelectionChanged: (Set<PanelOrientation> selection) =>
              state.setPanelOrientation(selection.first),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'عند نفس زاوية الميل ونفس السمت، اتجاه اللوح لا يغيّر الطاقة '
            'الساقطة عليه. أثره هنا محصور في المسافة بين الصفوف وارتفاع '
            'الحامل.\n\n'
            'تنبيه لا قاعدة قاطعة: في بعض تخطيطات صمامات الالتفاف يعطّل '
            'التظليل الجزئي عددًا أقل من صفوف الخلايا في الوضع الأفقي — '
            'لكن هذا يعتمد على تصميم اللوح نفسه، فراجع ورقة بياناته.',
            style: TextStyle(fontSize: 15, height: 1.5),
          ),
        ),
        const SizedBox(height: 16),
        _numberField(_length, 'الطول (متر)'),
        const SizedBox(height: 10),
        _numberField(_width, 'العرض (متر)'),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: _applyPanelDimensions,
            child: const Text(
              'حفظ الأبعاد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (layout != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF0F7B3F), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'تخطيط الصفوف',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'المسافة الدنيا بين الصفوف: '
                  '${layout.minimumRowSpacing.toStringAsFixed(2)} متر',
                  style: const TextStyle(fontSize: 17),
                ),
                Text(
                  'الارتفاع الرأسي للحامل: '
                  '${layout.mountingHeight.toStringAsFixed(2)} متر',
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  'محسوبة عند الانقلاب الشتوي الساعة 9 صباحًا بالتوقيت '
                  'الشمسي، حيث ارتفاع الشمس '
                  '${layout.designSolarElevation.toStringAsFixed(1)}°.',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          )
        else
          const Text(
            'تخطيط الصفوف غير متاح: يلزم تحديد الموقع والزاوية الهدف أولًا.',
            style: TextStyle(fontSize: 16),
          ),
      ],
    );
  }
}
