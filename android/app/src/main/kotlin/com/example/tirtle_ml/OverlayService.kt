package com.example.tirtle_ml

import android.app.*
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.provider.Settings
import android.util.Log
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat

class OverlayService : Service() {

    companion object {
        private var instance: OverlayService? = null

        /** 오버레이 측정 버튼 탭 시 호출되는 콜백 — MainActivity가 등록. */
        var onCalibrateTapped: (() -> Unit)? = null

        /** Legacy: 단일 칩 (호환용) */
        fun updateState(label: String, colorHex: String) {
            instance?.applyState(label, colorHex, null, null, false, null)
        }

        /** 신규: 모드 칩 + 위험 칩 + (선택) 측정 버튼 */
        fun updateSplitState(
            modeLabel: String, modeColor: String,
            riskLabel: String?, riskColor: String?,
            showCalibrateBtn: Boolean,
            calibrateBtnText: String?,
        ) {
            instance?.applyState(modeLabel, modeColor, riskLabel, riskColor,
                showCalibrateBtn, calibrateBtnText)
        }

        fun isRunning() = instance != null
    }

    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: LinearLayout
    private lateinit var tvMode: TextView
    private lateinit var tvRisk: TextView
    private lateinit var tvCalibrate: TextView
    private lateinit var calSpacer: View
    private lateinit var modeBg: GradientDrawable
    private lateinit var riskBg: GradientDrawable
    private lateinit var calBg: GradientDrawable
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        // SYSTEM_ALERT_WINDOW 권한 없으면 createOverlayView()의 addView가 BadTokenException.
        // 권한 체크 후 없으면 silent 종료 (앱 자체는 살려둠).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.w("OverlayService", "SYSTEM_ALERT_WINDOW 권한 없음 — 오버레이 시작 안 함")
            stopSelf()
            return
        }
        instance = this
        startForegroundNotification()
        createOverlayView()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        instance = null
        if (::overlayView.isInitialized) {
            try { windowManager.removeView(overlayView) } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    private fun startForegroundNotification() {
        val channelId = "posture_overlay_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "자세 오버레이",
                NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(ch)
        }
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("포스처가드 오버레이")
            .setContentText("자세 감지 중")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(5001, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(5001, notification)
        }
    }

    private fun createOverlayView() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        modeBg = GradientDrawable().apply {
            cornerRadius = 50f
            setColor(Color.parseColor("#9E9E9E"))
        }
        tvMode = TextView(this).apply {
            text = "대기"
            textSize = 12f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(28, 12, 28, 12)
            background = modeBg
            elevation = 8f
        }

        riskBg = GradientDrawable().apply {
            cornerRadius = 50f
            setColor(Color.parseColor("#FFA000"))
        }
        tvRisk = TextView(this).apply {
            text = "주의"
            textSize = 12f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(28, 12, 28, 12)
            background = riskBg
            elevation = 8f
            visibility = View.GONE
        }

        // ── 측정 버튼 (모드별 캘리브레이션 트리거) ─────────────────
        calBg = GradientDrawable().apply {
            cornerRadius = 50f
            setColor(Color.parseColor("#FF6B35")) // 주황 — 측정 권유 색
        }
        tvCalibrate = TextView(this).apply {
            text = "🎯 측정"
            textSize = 11f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(24, 12, 24, 12)
            background = calBg
            elevation = 8f
            visibility = View.GONE
            setOnClickListener {
                onCalibrateTapped?.invoke()
            }
        }
        calSpacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(12, 1)
            visibility = View.GONE
        }

        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(12, 1)
        }

        overlayView = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(tvMode)
            addView(spacer)
            addView(tvRisk)
            addView(calSpacer)
            addView(tvCalibrate)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        // FLAG_NOT_TOUCH_MODAL: 오버레이 밖 터치는 아래 앱으로 통과,
        // 오버레이 내부(측정 버튼 등) 터치는 받음.
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 20
            y = 120
        }

        windowManager.addView(overlayView, params)
    }

    private fun applyState(
        modeLabel: String, modeColor: String,
        riskLabel: String?, riskColor: String?,
        showCalibrateBtn: Boolean,
        calibrateBtnText: String?,
    ) {
        handler.post {
            try {
                tvMode.text = modeLabel
                modeBg.setColor(Color.parseColor(modeColor))
                if (riskLabel != null && riskColor != null) {
                    tvRisk.text = riskLabel
                    riskBg.setColor(Color.parseColor(riskColor))
                    tvRisk.visibility = View.VISIBLE
                } else {
                    tvRisk.visibility = View.GONE
                }
                if (showCalibrateBtn) {
                    tvCalibrate.text = calibrateBtnText ?: "🎯 측정"
                    tvCalibrate.visibility = View.VISIBLE
                    calSpacer.visibility = View.VISIBLE
                } else {
                    tvCalibrate.visibility = View.GONE
                    calSpacer.visibility = View.GONE
                }
            } catch (_: Exception) {}
        }
    }
}
