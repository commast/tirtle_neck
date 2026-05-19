package com.example.tirtle_ml

import android.app.*
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat

class OverlayService : Service() {

    companion object {
        private var instance: OverlayService? = null

        /** Flutter → 네이티브: 자세 상태 업데이트 */
        fun updateState(label: String, colorHex: String) {
            instance?.applyState(label, colorHex)
        }

        fun isRunning() = instance != null
    }

    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: LinearLayout
    private lateinit var tvLabel: TextView
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        startForegroundNotification()
        createOverlayView()
    }

    // 사용자가 최근 앱 목록에서 앱을 스와이프해서 닫을 때 호출
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
        // ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE = 1073741824
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(5001, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(5001, notification)
        }
    }

    private fun createOverlayView() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // 칩 배경 (둥근 모서리)
        val bg = GradientDrawable().apply {
            cornerRadius = 50f
            setColor(Color.parseColor("#00C896"))
        }

        tvLabel = TextView(this).apply {
            text = "정상"
            textSize = 12f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(28, 12, 28, 12)
        }

        overlayView = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            background = bg
            elevation = 8f
            addView(tvLabel)
        }

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 20
            y = 120
        }

        windowManager.addView(overlayView, params)
    }

    private fun applyState(label: String, colorHex: String) {
        handler.post {
            try {
                tvLabel.text = label
                (overlayView.background as? GradientDrawable)
                    ?.setColor(Color.parseColor(colorHex))
            } catch (_: Exception) {}
        }
    }
}
