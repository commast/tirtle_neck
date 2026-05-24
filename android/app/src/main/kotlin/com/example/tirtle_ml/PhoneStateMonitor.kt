package com.example.tirtle_ml

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * 화면 ON/OFF + 통화 상태를 Flutter에 스트림으로 전달.
 * 화면은 BroadcastReceiver, 통화는 TelephonyCallback(API 31+) / PhoneStateListener.
 */
class PhoneStateMonitor(private val ctx: Context) : EventChannel.StreamHandler {

    companion object { private const val TAG = "PhoneState" }

    private var sink: EventChannel.EventSink? = null
    private val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

    private var screenOn = pm.isInteractive
    private var inCall   = false

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            screenOn = when (intent?.action) {
                Intent.ACTION_SCREEN_ON  -> true
                Intent.ACTION_SCREEN_OFF -> false
                else -> screenOn
            }
            emit()
        }
    }

    private var phoneCallback: TelephonyCallback? = null
    @Suppress("DEPRECATION")
    private var legacyListener: PhoneStateListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        // 화면 상태 수신
        ctx.registerReceiver(screenReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        })
        // 통화 상태 수신 (권한 있을 때만)
        if (hasPhonePermission()) startCallListener() else Log.w(TAG, "READ_PHONE_STATE 권한 없음 — 통화 감지 스킵")
        emit() // 초기 상태 전송
    }

    override fun onCancel(arguments: Any?) {
        try { ctx.unregisterReceiver(screenReceiver) } catch (_: Exception) {}
        stopCallListener()
        sink = null
    }

    private fun hasPhonePermission() = ctx.checkSelfPermission(
        android.Manifest.permission.READ_PHONE_STATE
    ) == PackageManager.PERMISSION_GRANTED

    private fun startCallListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    inCall = state != TelephonyManager.CALL_STATE_IDLE
                    emit()
                }
            }
            tm.registerTelephonyCallback(ctx.mainExecutor, cb)
            phoneCallback = cb
        } else {
            @Suppress("DEPRECATION")
            val ll = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    inCall = state != TelephonyManager.CALL_STATE_IDLE
                    emit()
                }
            }
            @Suppress("DEPRECATION")
            tm.listen(ll, PhoneStateListener.LISTEN_CALL_STATE)
            legacyListener = ll
        }
    }

    private fun stopCallListener() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                phoneCallback?.let { tm.unregisterTelephonyCallback(it) }
            } else {
                @Suppress("DEPRECATION")
                legacyListener?.let { tm.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (_: Exception) {}
        phoneCallback = null
        legacyListener = null
    }

    private fun emit() {
        sink?.success(mapOf("screenOn" to screenOn, "inCall" to inCall))
    }
}
