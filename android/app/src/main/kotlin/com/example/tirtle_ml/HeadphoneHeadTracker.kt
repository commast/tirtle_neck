package com.example.tirtle_ml

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlin.math.PI

/**
 * 실험적 기능: BT 이어폰의 헤드 트래커 센서로 머리(경추) pitch 각도 추출.
 *
 * **현실 체크**: Sensor.TYPE_HEAD_TRACKER (API 33+) 는 시스템(공간 음향) 전용으로 설계되어
 * 일반 앱에는 거의 항상 차단된다. 따라서 대부분의 케이스에서 status = earphoneUnsupported.
 * 그래도 본인 기기가 노출하는지 확인용으로 진단 코드 + UI 카드를 제공한다.
 *
 * Flutter 통신:
 *   EventChannel  com.example.tirtle_ml/headphone_tracker         → 상태 스트림
 *   MethodChannel com.example.tirtle_ml/headphone_tracker_method  → checkSupport()
 *
 * 상태 페이로드 (sink.success):
 *   {
 *     "status":   "noEarphone" | "earphoneUnsupported" | "tracking",
 *     "device":   String?  (BT 장치 이름, 권한 없으면 null),
 *     "pitchDeg": Double?  (tracking 일 때만)
 *   }
 */
class HeadphoneHeadTracker(private val ctx: Context)
    : EventChannel.StreamHandler, SensorEventListener {

    companion object {
        private const val TAG = "HeadphoneTracker"
    }

    private val sensorMgr: SensorManager =
        ctx.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val btMgr: BluetoothManager? =
        ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager

    private var sink: EventChannel.EventSink? = null
    private var registered: Sensor? = null
    private var deviceName: String? = null
    private var receiverRegistered = false

    /** BT audio 연결/해제 감지 */
    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            val dev: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
            when (action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> {
                    deviceName = safeName(dev)
                    Log.d(TAG, "BT 연결: $deviceName")
                    tryRegisterHeadTracker()
                }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                    Log.d(TAG, "BT 해제: ${safeName(dev)}")
                    unregisterSensor()
                    refreshConnectedDevice()
                    emitState(null)
                }
            }
        }
    }

    // ── EventChannel.StreamHandler ────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        registerBtReceiver()
        refreshConnectedDevice()
        if (deviceName != null) tryRegisterHeadTracker()
        else emitState(null)
    }

    override fun onCancel(arguments: Any?) {
        unregisterSensor()
        if (receiverRegistered) {
            try { ctx.unregisterReceiver(btReceiver) } catch (_: Exception) {}
            receiverRegistered = false
        }
        sink = null
    }

    private fun registerBtReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        }
        ctx.registerReceiver(btReceiver, filter)
        receiverRegistered = true
    }

    /** 현재 연결돼 있는 BT audio 장치명 갱신. 권한 없으면 "(권한 없음)" */
    private fun refreshConnectedDevice() {
        val adapter: BluetoothAdapter? = btMgr?.adapter
        if (adapter == null || !adapter.isEnabled) {
            deviceName = null
            return
        }
        if (!hasBtConnectPermission()) {
            deviceName = "(BT 권한 없음)"
            return
        }
        try {
            val state = adapter.getProfileConnectionState(BluetoothProfile.HEADSET)
            // HEADSET (HFP) — 다른 프로필 (A2DP 등) 별도 체크는 생략. 헤드 트래커 자체가 어차피 막힘
            if (state != BluetoothProfile.STATE_CONNECTED) {
                // A2DP 도 한 번 확인 (음악용 BT 이어폰은 HFP 안 잡힐 수 있음)
                val a2dp = adapter.getProfileConnectionState(BluetoothProfile.A2DP)
                if (a2dp != BluetoothProfile.STATE_CONNECTED) {
                    deviceName = null
                    return
                }
            }
            // 연결된 본드 디바이스 중 첫 번째 audio 클래스를 사용
            val bonded = adapter.bondedDevices ?: emptySet()
            deviceName = bonded.firstOrNull { it.name != null }?.name
        } catch (e: SecurityException) {
            deviceName = "(권한 거부)"
        } catch (_: Exception) {
            deviceName = null
        }
    }

    // ── 헤드 트래커 등록 ──────────────────────────────────────

    private fun tryRegisterHeadTracker() {
        unregisterSensor()
        if (Build.VERSION.SDK_INT < 33) {
            Log.d(TAG, "API ${Build.VERSION.SDK_INT} < 33 — HEAD_TRACKER 지원 안 됨")
            emitState(null)
            return
        }
        val sensor = findHeadTrackerSensor()
        if (sensor == null) {
            Log.d(TAG, "HEAD_TRACKER 센서 없음 — 시스템 차단되었거나 미지원 기기")
            emitState(null) // earphoneUnsupported (deviceName 있으면)
            return
        }
        try {
            sensorMgr.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
            registered = sensor
            Log.d(TAG, "HEAD_TRACKER 등록 성공: ${sensor.name}")
        } catch (e: SecurityException) {
            Log.w(TAG, "HEAD_TRACKER 보안 예외: ${e.message}")
            registered = null
            emitState(null)
        }
    }

    /** static + dynamic 양쪽 lookup */
    private fun findHeadTrackerSensor(): Sensor? {
        if (Build.VERSION.SDK_INT < 33) return null
        try {
            sensorMgr.getDefaultSensor(Sensor.TYPE_HEAD_TRACKER)?.let { return it }
            val list = sensorMgr.getDynamicSensorList(Sensor.TYPE_HEAD_TRACKER)
            if (list.isNotEmpty()) return list[0]
        } catch (e: Exception) {
            Log.w(TAG, "센서 lookup 오류: ${e.message}")
        }
        return null
    }

    private fun unregisterSensor() {
        registered?.let { sensorMgr.unregisterListener(this, it) }
        registered = null
    }

    // ── SensorEventListener ───────────────────────────────────

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_HEAD_TRACKER) return
        val pitchDeg = rotationVectorToPitchDeg(event.values)
        sink?.success(mapOf(
            "status"   to "tracking",
            "device"   to deviceName,
            "pitchDeg" to pitchDeg,
        ))
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun rotationVectorToPitchDeg(values: FloatArray): Double {
        val R = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(R, values)
        val orient = FloatArray(3)
        SensorManager.getOrientation(R, orient)
        // orient[0]=azimuth, [1]=pitch(rad), [2]=roll
        return orient[1] * 180.0 / PI
    }

    // ── 상태 emit ────────────────────────────────────────────

    private fun emitState(pitchDeg: Double?) {
        val status = when {
            deviceName == null -> "noEarphone"
            registered != null -> "tracking"
            else               -> "earphoneUnsupported"
        }
        sink?.success(mapOf(
            "status"   to status,
            "device"   to deviceName,
            "pitchDeg" to pitchDeg,
        ))
    }

    private fun safeName(dev: BluetoothDevice?): String? {
        if (dev == null) return null
        return try {
            if (hasBtConnectPermission()) dev.name else "(BT 권한 없음)"
        } catch (_: SecurityException) {
            "(권한 거부)"
        }
    }

    private fun hasBtConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true // API 30 이하엔 런타임 권한 불필요
        return ctx.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
    }

    // ── 진단용 (MethodChannel) ────────────────────────────────

    fun checkSupport(): Map<String, Any?> {
        val sdk = Build.VERSION.SDK_INT
        val hasApi = sdk >= 33
        val sensor = if (hasApi) findHeadTrackerSensor() else null
        refreshConnectedDevice()
        return mapOf(
            "androidSdk"          to sdk,
            "headTrackerApiAvail" to hasApi,
            "headTrackerSensor"   to (sensor?.name),
            "device"              to deviceName,
            "btConnectPermission" to hasBtConnectPermission(),
        )
    }
}
