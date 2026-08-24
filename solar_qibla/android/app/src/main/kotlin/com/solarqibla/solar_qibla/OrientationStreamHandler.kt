package com.solarqibla.solar_qibla

import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * يبثّ توجيه اللوح إلى Dart انطلاقًا من TYPE_ROTATION_VECTOR.
 *
 * الافتراض الميداني: الهاتف مسطّح على سطح اللوح وشاشته للأعلى، فيكون العمود
 * على اللوح هو محور الجهاز ‎+Z‎.
 *
 * مصفوفة الدوران R من getRotationMatrixFromVector تحوّل من إحداثيات الجهاز
 * إلى الإحداثيات العالمية (X = شرق، Y = شمال، Z = أعلى)، وهي مصفوفة 3×3
 * مخزّنة صفًّا صفًّا. لذلك يكون محور الجهاز ‎+Z‎ في الإحداثيات العالمية:
 *
 *     R · (0, 0, 1) = (R[2], R[5], R[8])
 *
 * (مُتحقَّق من الاصطلاح من مصدر AOSP لـSensorManager.)
 *
 * تُبثّ المصفوفة كما هي إلى Dart، ويجري هناك استخراج الميل والسمت والترشيح.
 * السبب: هذا أكثر الحسابات عرضةً للخطأ في المشروع كلّه (اصطلاح الإحداثيات،
 * ترتيب وسيطَي atan2، الحالات الحديّة)، ووضعه في Dart يجعله قابلًا لاختبار
 * الوحدة دون جهاز. كلفة نقل تسعة أعداد بدل اثنين عشرين مرة في الثانية
 * لا تُذكر.
 */
class OrientationStreamHandler(context: Context) : EventChannel.StreamHandler {

    private val sensorManager =
        context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var listener: SensorEventListener? = null

    /** آخر حالة دقّة أبلغ عنها النظام؛ 3 = عالية، 0 = غير موثوقة. */
    @Volatile private var currentAccuracy: Int = SensorManager.SENSOR_STATUS_UNRELIABLE

    /**
     * الانحراف المغناطيسي عند موقع المستخدم [درجة، موجب شرقًا]، أو null قبل
     * معرفة الموقع.
     *
     * يُحسب مرة واحدة عند تغيّر الموقع لا مع كل قراءة: النموذج المغناطيسي
     * العالمي بسطٌ بتوافقيات كروية، وتغيّره عبر الزمن بطيء جدًا (كسور الدرجة
     * في السنة) فلا معنى لإعادة حسابه عشرين مرة في الثانية.
     */
    @Volatile private var declination: Double? = null

    fun setLocation(latitude: Double, longitude: Double, altitudeMeters: Double) {
        declination = GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            altitudeMeters.toFloat(),
            System.currentTimeMillis(),
        ).declination.toDouble()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        // احتياط: لو استُدعي onListen مرّتين بلا onCancel بينهما، لا نترك
        // مستمعًا سابقًا مسجّلًا يستهلك الطاقة ويضاعف معدّل البثّ.
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null

        sink = events
        if (rotationSensor == null) {
            events?.error(
                "NO_ROTATION_SENSOR",
                "الجهاز لا يوفّر مستشعر ناقل الدوران (TYPE_ROTATION_VECTOR).",
                null,
            )
            return
        }

        val rotationMatrix = FloatArray(9)

        val sensorListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return

                SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

                val matrix = DoubleArray(9) { rotationMatrix[it].toDouble() }

                val payload = HashMap<String, Any?>(4)
                payload["rotationMatrix"] = matrix
                payload["declination"] = declination
                payload["accuracy"] = currentAccuracy
                payload["timestampMs"] = System.currentTimeMillis()

                handler.post { sink?.success(payload) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
                currentAccuracy = accuracy
            }
        }

        listener = sensorListener
        // 50000 ميكروثانية ≈ 20Hz. القيمة إرشادية؛ النظام قد يعطي معدّلًا أعلى.
        sensorManager.registerListener(sensorListener, rotationSensor, 50_000)
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { sensorManager.unregisterListener(it) }
        listener = null
        sink = null
    }
}
