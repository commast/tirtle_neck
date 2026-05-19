package com.example.tirtle_ml

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import kotlin.math.*

/**
 * Python server.py의 MobileSession 로직을 그대로 포팅한 온디바이스 자세 분석기.
 * MediaPipe PoseLandmarker + FaceLandmarker 를 사용한다.
 */
class PoseAnalyzer(private val context: Context) {

    companion object {
        private const val TAG              = "PoseAnalyzer"
        private const val CALIB_SECONDS    = 5f
        private const val PITCH_DANGER_DEG = 12f
    }

    private var poseLandmarker: PoseLandmarker? = null
    private var faceLandmarker: FaceLandmarker? = null

    // 캘리브레이션 누적 버퍼
    private val calibEarVis   = mutableListOf<Float>()
    private val calibZDiff    = mutableListOf<Float>()
    private val calibPitch    = mutableListOf<Float>()
    private val calibEyeRatio = mutableListOf<Float>()

    // 기준값 (캘리브레이션 완료 후 고정)
    private var goldenEarVis   = 0f
    private var goldenZDiff    = 0f
    private var goldenPitch    = 0f
    private var goldenEyeRatio = 0f
    private var calibrated     = false
    private val startTime      = System.currentTimeMillis()

    // ── 초기화 ──────────────────────────────────────────────────────
    fun initialize() {
        // Options는 PoseLandmarker/FaceLandmarker의 중첩 클래스 (별도 import 없음)
        val poseOpts = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(
                BaseOptions.builder().setModelAssetPath("pose_landmarker.task").build()
            )
            .setRunningMode(RunningMode.IMAGE)
            .build()
        poseLandmarker = PoseLandmarker.createFromOptions(context, poseOpts)

        val faceOpts = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(
                BaseOptions.builder().setModelAssetPath("face_landmarker.task").build()
            )
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .setOutputFacialTransformationMatrixes(true)
            .build()
        faceLandmarker = FaceLandmarker.createFromOptions(context, faceOpts)

        Log.d(TAG, "초기화 완료")
    }

    // ── 프레임 분석 (Python MobileSession.process() 동일 로직) ──────
    fun analyze(imageBytes: ByteArray): Map<String, Any> {
        // JPEG 디코딩
        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: return noPersonResult()

        // 전면 카메라 좌우 반전 (Python: cv2.flip(frame, 1))
        val flipMat = Matrix().apply { preScale(-1f, 1f) }
        bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, flipMat, false)

        val mpImage = BitmapImageBuilder(bitmap).build()

        val poseResult = try {
            poseLandmarker?.detect(mpImage)
        } catch (e: Exception) {
            Log.e(TAG, "Pose detect 오류: $e")
            null
        } ?: return noPersonResult()

        if (poseResult.landmarks().isEmpty()) return noPersonResult()

        val faceResult = try {
            faceLandmarker?.detect(mpImage)
        } catch (e: Exception) {
            Log.e(TAG, "Face detect 오류: $e")
            null
        }

        val poseLm = poseResult.landmarks()[0]

        // 어깨 너비 (랜드마크 11, 12)
        val shoulderW = dist(poseLm[11], poseLm[12])
        if (shoulderW == 0f) return noPersonResult()

        val elapsed = (System.currentTimeMillis() - startTime) / 1000f

        // ── 캘리브레이션 ────────────────────────────────────────────
        if (!calibrated) {
            // 현재 프레임을 먼저 수집 (elapsed 체크 전에 — Python 버그 수정 반영)
            val earVis = earVisibility(poseLm)
            val zDiff  = zDifference(poseLm)
            calibEarVis.add(earVis)
            calibZDiff.add(zDiff)

            faceResult?.let { fr ->
                if (fr.faceLandmarks().isNotEmpty()) {
                    getFacePitch(fr)?.let { calibPitch.add(it) }
                    getEyeRatio(fr.faceLandmarks()[0], poseLm, shoulderW)
                        ?.let { calibEyeRatio.add(it) }
                }
            }

            if (elapsed < CALIB_SECONDS) {
                val cd = (CALIB_SECONDS - elapsed).toInt().coerceAtLeast(0)
                return mapOf(
                    "status"    to "calibrating",
                    "countdown" to cd,
                    "score"     to 0,
                    "is_fhp"   to false,
                    "scores"    to mapOf("pitch" to 1.0, "eye" to 1.0, "vis" to 1.0, "z" to 1.0)
                )
            } else {
                // 캘리브레이션 완료
                goldenEarVis   = calibEarVis.average(0f)
                goldenZDiff    = calibZDiff.average(0f)
                goldenPitch    = calibPitch.average(0f)
                goldenEyeRatio = calibEyeRatio.average(0f)
                calibrated     = true
                Log.d(TAG, "캘리브레이션 완료 pitch=${goldenPitch}° z=${goldenZDiff}")
            }
        }

        // ── 점수 계산 ────────────────────────────────────────────────
        val earVis = earVisibility(poseLm)
        val zDiff  = zDifference(poseLm)

        // golden이 0이면 현재 프레임으로 보정 (85점 고정 버그 방지)
        val gEarVis = if (goldenEarVis == 0f) earVis else goldenEarVis
        val gZDiff  = if (goldenZDiff  == 0f && zDiff != 0f) zDiff else goldenZDiff

        val sVis = (1f - (gEarVis - earVis) / 0.15f).coerceIn(0f, 1f)
        val sZ   = (1f - (zDiff - gZDiff)  / 0.25f).coerceIn(0f, 1f)
        var sPitch = 1f
        var sEye   = 1f

        faceResult?.let { fr ->
            if (fr.faceLandmarks().isNotEmpty()) {
                getFacePitch(fr)?.let { pitch ->
                    if (goldenPitch != 0f) {
                        sPitch = (1f - (pitch - goldenPitch) / PITCH_DANGER_DEG).coerceIn(0f, 1f)
                    }
                }
                getEyeRatio(fr.faceLandmarks()[0], poseLm, shoulderW)?.let { ratio ->
                    if (goldenEyeRatio > 0f) {
                        sEye = ((ratio / goldenEyeRatio - 0.7f) / 0.3f).coerceIn(0f, 1f)
                    }
                }
            }
        }

        val score  = ((sPitch * 0.40f + sEye * 0.30f + sVis * 0.15f + sZ * 0.15f) * 100f)
            .toInt().coerceIn(0, 100)
        val isFhp  = score < 80

        Log.d(TAG, "점수=$score sPitch=$sPitch sEye=$sEye sVis=$sVis sZ=$sZ")

        return mapOf(
            "status"    to if (isFhp) "warning" else "ok",
            "score"     to score,
            "is_fhp"    to isFhp,
            "countdown" to 0,
            "scores"    to mapOf(
                "pitch" to sPitch.toDouble(),
                "eye"   to sEye.toDouble(),
                "vis"   to sVis.toDouble(),
                "z"     to sZ.toDouble()
            )
        )
    }

    // ── 헬퍼 함수들 ──────────────────────────────────────────────────

    /** MediaPipe 4×4 변환행렬(열우선)에서 얼굴 피치 추출
     *  facialTransformationMatrixes() → Optional<List<FloatArray>>
     *  FloatArray = 16개 float (4×4 열우선)
     *  Python: atan2(rmat[2][1], rmat[2][2])
     *  열우선 index: row r, col c → c*4 + r
     *  rmat[2][1] → 1*4+2 = 6 / rmat[2][2] → 2*4+2 = 10 */
    private fun getFacePitch(result: FaceLandmarkerResult): Float? {
        val opt = result.facialTransformationMatrixes()
        if (!opt.isPresent || opt.get().isEmpty()) return null
        val m = opt.get()[0]   // FloatArray (16개, 4×4 열우선) — .data() 없음
        return Math.toDegrees(atan2(m[6].toDouble(), m[10].toDouble())).toFloat()
    }

    /** 눈-어깨 비율 (Python get_eye_ratio) */
    private fun getEyeRatio(
        faceLm: List<NormalizedLandmark>,
        poseLm: List<NormalizedLandmark>,
        shoulderW: Float
    ): Float? {
        val eyeY      = (faceLm[33].y() + faceLm[133].y() + faceLm[263].y() + faceLm[362].y()) / 4f
        val shoulderY = (poseLm[11].y() + poseLm[12].y()) / 2f
        return abs(eyeY - shoulderY) / shoulderW
    }

    private fun earVisibility(lm: List<NormalizedLandmark>) =
        (lm[7].visibility().orElse(0f) + lm[8].visibility().orElse(0f)) / 2f

    private fun zDifference(lm: List<NormalizedLandmark>) =
        (lm[11].z() + lm[12].z()) / 2f - (lm[7].z() + lm[8].z()) / 2f

    private fun dist(a: NormalizedLandmark, b: NormalizedLandmark): Float {
        val dx = a.x() - b.x(); val dy = a.y() - b.y()
        return sqrt(dx * dx + dy * dy)
    }

    private fun List<Float>.average(default: Float): Float =
        if (isEmpty()) default else (sum() / size)

    private fun noPersonResult(): Map<String, Any> = mapOf(
        "status"    to "no_person",
        "score"     to 0,
        "is_fhp"    to false,
        "countdown" to 0,
        "scores"    to mapOf("pitch" to 1.0, "eye" to 1.0, "vis" to 1.0, "z" to 1.0)
    )

    fun close() {
        poseLandmarker?.close()
        faceLandmarker?.close()
        Log.d(TAG, "종료")
    }
}
