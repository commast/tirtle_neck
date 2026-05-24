package com.example.tirtle_ml

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val OVERLAY_CHANNEL = "com.example.tirtle_ml/overlay"
        private const val POSE_CHANNEL    = "com.example.tirtle_ml/pose_analyzer"
        private const val CAMERA_CHANNEL  = "com.example.tirtle_ml/camera_bg"
        private const val NATIVE_CAM_CH   = "com.example.tirtle_ml/native_camera"
        private const val FG_APP_EVENT_CH = "com.example.tirtle_ml/foreground_app_events"
        private const val FG_APP_METHOD_CH = "com.example.tirtle_ml/foreground_app"
        private const val PHONE_EVENT_CH  = "com.example.tirtle_ml/phone_state_events"
        private const val HP_EVENT_CH    = "com.example.tirtle_ml/headphone_tracker"
        private const val HP_METHOD_CH   = "com.example.tirtle_ml/headphone_tracker_method"
    }

    private var poseAnalyzer:    PoseAnalyzer?         = null
    private val nativeCamera     by lazy { NativeCameraCapture(applicationContext) }
    private val fgAppMonitor     by lazy { ForegroundAppMonitor(applicationContext) }
    private val phoneMonitor     by lazy { PhoneStateMonitor(applicationContext) }
    private val headphoneTracker by lazy { HeadphoneHeadTracker(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 오버레이 채널 ─────────────────────────────────────────
        val overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
        overlayChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start"     -> {
                    startService(Intent(this, OverlayService::class.java))
                    result.success(null)
                }
                "update"    -> {
                    val label = call.argument<String>("label") ?: "정상"
                    val color = call.argument<String>("color") ?: "#00C896"
                    OverlayService.updateState(label, color)
                    result.success(null)
                }
                "updateSplit" -> {
                    val modeLabel = call.argument<String>("modeLabel") ?: "대기"
                    val modeColor = call.argument<String>("modeColor") ?: "#9E9E9E"
                    val riskLabel = call.argument<String>("riskLabel")
                    val riskColor = call.argument<String>("riskColor")
                    val showCalibrateBtn = call.argument<Boolean>("showCalibrateBtn") ?: false
                    val calibrateBtnText = call.argument<String>("calibrateBtnText")
                    OverlayService.updateSplitState(
                        modeLabel, modeColor, riskLabel, riskColor,
                        showCalibrateBtn, calibrateBtnText)
                    result.success(null)
                }
                "stop"      -> {
                    stopService(Intent(this, OverlayService::class.java))
                    result.success(null)
                }
                "isRunning" -> result.success(OverlayService.isRunning())
                else        -> result.notImplemented()
            }
        }

        // 오버레이 측정 버튼 탭 → Flutter에 전달
        OverlayService.onCalibrateTapped = {
            runOnUiThread {
                overlayChannel.invokeMethod("onCalibrateTapped", null)
            }
        }

        // ── 자세 분석 채널 (온디바이스 MediaPipe) ──────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POSE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        // 코루틴 대신 스레드 사용 (의존성 불필요)
                        Thread {
                            try {
                                if (poseAnalyzer == null) {
                                    poseAnalyzer = PoseAnalyzer(applicationContext)
                                    poseAnalyzer!!.initialize()
                                }
                                runOnUiThread { result.success(null) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("INIT_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "analyze" -> {
                        val imageData = call.argument<ByteArray>("imageData")
                        if (imageData == null) {
                            result.error("NO_DATA", "imageData가 없습니다", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val analyzer = poseAnalyzer
                                if (analyzer == null) {
                                    runOnUiThread {
                                        result.error("NOT_INIT", "초기화가 필요합니다", null)
                                    }
                                    return@Thread
                                }
                                val scores = analyzer.analyze(imageData)
                                runOnUiThread { result.success(scores) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("ANALYZE_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }
                    "close" -> {
                        poseAnalyzer?.close()
                        poseAnalyzer = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 카메라 백그라운드 서비스 채널 ──────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startService(Intent(this, CameraBackgroundService::class.java))
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, CameraBackgroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 네이티브 Camera2 캡처 채널 ────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CAM_CH)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureImage" -> {
                        Thread {
                            nativeCamera.captureImage { bytes ->
                                runOnUiThread {
                                    if (bytes != null) result.success(bytes)
                                    else result.error("CAPTURE_FAILED", "촬영 실패", null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 포그라운드 앱 감지 (EventChannel + MethodChannel) ──────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, FG_APP_EVENT_CH)
            .setStreamHandler(fgAppMonitor)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FG_APP_METHOD_CH)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(fgAppMonitor.hasPermission())
                    "openSettings"  -> { fgAppMonitor.openSettings(); result.success(null) }
                    else -> result.notImplemented()
                }
            }

        // ── 폰 상태 (화면 + 통화) EventChannel ──────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PHONE_EVENT_CH)
            .setStreamHandler(phoneMonitor)

        // ── 이어폰 헤드 트래커 (실험) ───────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HP_EVENT_CH)
            .setStreamHandler(headphoneTracker)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HP_METHOD_CH)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkSupport" -> result.success(headphoneTracker.checkSupport())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        poseAnalyzer?.close()
        nativeCamera.release()
        super.onDestroy()
    }
}
