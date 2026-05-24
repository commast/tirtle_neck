package com.example.tirtle_ml

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.hardware.camera2.*
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import java.io.ByteArrayOutputStream

/**
 * Activity lifecycle과 독립적인 Camera2 기반 캡처.
 * capturing 플래그로 동시 캡처 재진입을 방지한다.
 */
class NativeCameraCapture(private val context: Context) {

    companion object {
        private const val TAG           = "NativeCam"
        private const val TARGET_WIDTH  = 640
        private const val TARGET_HEIGHT = 480
    }

    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val thread = HandlerThread("NativeCamThread").apply { start() }
    private val handler = Handler(thread.looper)
    @Volatile private var capturing = false

    @SuppressLint("MissingPermission")
    fun captureImage(callback: (ByteArray?) -> Unit) {
        if (capturing) {
            Log.w(TAG, "이전 캡처 진행 중 — 요청 무시")
            callback(null)
            return
        }
        capturing = true

        val cameraId = getFrontCameraId()
        if (cameraId == null) {
            Log.e(TAG, "전면 카메라를 찾을 수 없음")
            capturing = false
            callback(null)
            return
        }

        val sensorOrientation =
            cameraManager.getCameraCharacteristics(cameraId)
                .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 270

        val size   = getBestSize(cameraId)
        val reader = ImageReader.newInstance(size.width, size.height, ImageFormat.JPEG, 2)
        Log.d(TAG, "캡처 시작 — ${size.width}×${size.height} sensorOrientation=$sensorOrientation")

        // 모든 종료 경로에서 capturing = false 보장
        fun done(bytes: ByteArray?) {
            capturing = false
            callback(bytes)
        }

        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage()
            if (image == null) {
                reader.close()
                done(null)
                return@setOnImageAvailableListener
            }

            val buffer = image.planes[0].buffer
            val raw    = ByteArray(buffer.remaining())
            buffer.get(raw)
            image.close()

            val correctedBytes = applyRotation(raw, sensorOrientation)
            Log.d(TAG, "캡처 완료 (${correctedBytes.size} bytes, 회전 ${sensorOrientation}°)")
            reader.close()
            done(correctedBytes)
        }, handler)

        cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
            override fun onOpened(camera: CameraDevice) {
                camera.createCaptureSession(
                    listOf(reader.surface),
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            val request = camera.createCaptureRequest(
                                CameraDevice.TEMPLATE_STILL_CAPTURE
                            ).apply {
                                addTarget(reader.surface)
                                set(CaptureRequest.JPEG_QUALITY, 85.toByte())
                                set(CaptureRequest.CONTROL_AF_MODE,
                                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                                set(CaptureRequest.CONTROL_AE_MODE,
                                    CaptureRequest.CONTROL_AE_MODE_ON)
                            }.build()

                            session.capture(request,
                                object : CameraCaptureSession.CaptureCallback() {
                                    override fun onCaptureCompleted(
                                        s: CameraCaptureSession,
                                        r: CaptureRequest,
                                        result: TotalCaptureResult
                                    ) {
                                        s.close(); camera.close()
                                        // done()은 ImageReader 콜백에서 호출됨
                                    }
                                    override fun onCaptureFailed(
                                        s: CameraCaptureSession,
                                        r: CaptureRequest,
                                        failure: CaptureFailure
                                    ) {
                                        Log.e(TAG, "캡처 실패: ${failure.reason}")
                                        s.close(); camera.close()
                                        reader.close(); done(null)
                                    }
                                }, handler)
                        }
                        override fun onConfigureFailed(session: CameraCaptureSession) {
                            Log.e(TAG, "세션 구성 실패")
                            camera.close(); reader.close(); done(null)
                        }
                    }, handler)
            }
            override fun onDisconnected(camera: CameraDevice) {
                camera.close(); reader.close(); done(null)
            }
            override fun onError(camera: CameraDevice, error: Int) {
                Log.e(TAG, "카메라 오류: $error")
                camera.close(); reader.close(); done(null)
            }
        }, handler)
    }

    private fun applyRotation(jpeg: ByteArray, degrees: Int): ByteArray {
        if (degrees == 0) return jpeg
        val bmp = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return jpeg
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
        bmp.recycle()
        val out = ByteArrayOutputStream()
        rotated.compress(Bitmap.CompressFormat.JPEG, 85, out)
        rotated.recycle()
        return out.toByteArray()
    }

    private fun getFrontCameraId(): String? =
        cameraManager.cameraIdList.firstOrNull { id ->
            cameraManager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
        }

    private fun getBestSize(cameraId: String): Size {
        val map = cameraManager.getCameraCharacteristics(cameraId)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val sizes = map?.getOutputSizes(ImageFormat.JPEG) ?: return Size(TARGET_WIDTH, TARGET_HEIGHT)
        return sizes.minByOrNull {
            Math.abs(it.width - TARGET_WIDTH) + Math.abs(it.height - TARGET_HEIGHT)
        } ?: sizes.last()
    }

    fun release() {
        thread.quitSafely()
    }
}
