package com.example.tirtle_ml

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * UsageStatsManager로 현재 포그라운드 앱 패키지명을 주기적으로 폴링.
 *
 * 안정성을 위해:
 *  - 메인 스레드가 아닌 HandlerThread에서 폴링 (Activity 백그라운드 시 throttle 회피)
 *  - queryEvents(ACTIVITY_RESUMED)로 가장 최근 전환 이벤트를 직접 추적 (집계 API보다 정확)
 *  - 폴링 결과는 메인 스레드로 다시 옮겨 EventChannel.sink에 전달
 */
class ForegroundAppMonitor(private val ctx: Context) : EventChannel.StreamHandler {

    companion object {
        private const val TAG = "FgApp"
        private const val POLL_INTERVAL_MS = 3_000L
        private const val LOOKBACK_MS      = 60_000L  // ACTIVITY_RESUMED 이벤트 캡처용
    }

    private val usm = ctx.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val workerThread = HandlerThread("FgAppPoll").apply { start() }
    private val workerHandler = Handler(workerThread.looper)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var lastPackage: String? = null
    private var lastEventTime: Long = 0L

    private val poller = object : Runnable {
        override fun run() {
            try {
                val now = System.currentTimeMillis()
                // 마지막 확인 시점 이후로 발생한 RESUMED 이벤트만 살펴봐도 되지만,
                // 안전하게 LOOKBACK_MS 범위에서 가장 늦게 발생한 RESUMED를 잡는다.
                val events = usm.queryEvents(now - LOOKBACK_MS, now)
                val ev = UsageEvents.Event()
                var bestPkg: String? = null
                var bestTime = lastEventTime
                while (events.hasNextEvent()) {
                    events.getNextEvent(ev)
                    if (ev.eventType == UsageEvents.Event.ACTIVITY_RESUMED &&
                        ev.timeStamp > bestTime) {
                        bestTime = ev.timeStamp
                        bestPkg  = ev.packageName
                    }
                }
                if (bestPkg != null && bestPkg != lastPackage) {
                    lastPackage = bestPkg
                    lastEventTime = bestTime
                    val info = resolveAppInfo(bestPkg)
                    Log.d(TAG, "포그라운드 앱 변경: ${info.label} ($bestPkg) category=${info.category}")
                    mainHandler.post {
                        sink?.success(mapOf(
                            "package"  to bestPkg,
                            "label"    to info.label,
                            "category" to info.category,
                        ))
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "폴링 오류: ${e.message}")
            }
            workerHandler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    private data class AppMeta(val label: String, val category: String)

    /**
     * 앱의 라벨과 시스템 카테고리를 함께 반환.
     * 카테고리는 매니페스트의 android:appCategory를 따른다. 미선언이면 "undefined".
     */
    private fun resolveAppInfo(pkg: String): AppMeta {
        return try {
            val pm = ctx.packageManager
            val ai = pm.getApplicationInfo(pkg, 0)
            val label = pm.getApplicationLabel(ai).toString()
            val cat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appCategoryName(ai.category)
            } else "undefined"
            AppMeta(label, cat)
        } catch (_: Exception) {
            AppMeta(pkg, "undefined")
        }
    }

    private fun appCategoryName(c: Int): String = when (c) {
        ApplicationInfo.CATEGORY_GAME         -> "game"
        ApplicationInfo.CATEGORY_AUDIO        -> "audio"
        ApplicationInfo.CATEGORY_VIDEO        -> "video"
        ApplicationInfo.CATEGORY_IMAGE        -> "image"
        ApplicationInfo.CATEGORY_SOCIAL       -> "social"
        ApplicationInfo.CATEGORY_NEWS         -> "news"
        ApplicationInfo.CATEGORY_MAPS         -> "maps"
        ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
        else -> "undefined"
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        lastPackage = null
        lastEventTime = 0L
        workerHandler.post(poller)
        Log.d(TAG, "리스닝 시작 (HandlerThread=${workerThread.name})")
    }

    override fun onCancel(arguments: Any?) {
        workerHandler.removeCallbacks(poller)
        sink = null
        Log.d(TAG, "리스닝 종료")
    }

    fun hasPermission(): Boolean {
        val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                ctx.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                ctx.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ctx.startActivity(intent)
    }
}
