package com.example.tirtle_ml

import android.app.*
import android.content.Intent
import android.os.*
import androidx.core.app.NotificationCompat

/**
 * 백그라운드 카메라 접근을 위한 최소 포그라운드 서비스.
 * Android 11+ 에서 foregroundServiceType="camera" 가 있어야
 * 앱이 백그라운드에 있을 때도 카메라를 사용할 수 있다.
 * startCapture() 시 시작, stopCapture() 시 종료.
 */
class CameraBackgroundService : Service() {

    companion object {
        private const val CHANNEL_ID       = "camera_bg_channel"
        private const val NOTIFICATION_ID  = 5002
    }

    override fun onBind(intent: Intent?) = null

    override fun onCreate() {
        super.onCreate()
        startForegroundWithCameraType()
    }

    private fun startForegroundWithCameraType() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID, "카메라 백그라운드",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(ch)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("포스처가드")
            .setContentText("자세 촬영 중")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID, notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 14+ ForegroundServiceStartNotAllowedException 등 방어
            // foreground 선언 실패해도 카메라 캡처(MainActivity 컨텍스트)는 계속 동작
            android.util.Log.w("CameraBgSvc", "startForeground 실패 (무시): ${e.message}")
            stopSelf()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
