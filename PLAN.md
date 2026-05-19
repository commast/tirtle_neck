# 포스처가드 (Tirtle ML) — 프로젝트 문서

---

## 1. 앱 개요

거북목·자세 불량을 감지해 사용자에게 알리는 모바일/데스크톱 앱.

| 항목 | 내용 |
|---|---|
| 프론트엔드 | Flutter 3.x / Dart 3.11.x |
| 백엔드 | Python FastAPI + MediaPipe (카메라 분석) |
| 네이티브 | Android Kotlin (시스템 오버레이, 포그라운드 서비스) |
| 상태관리 | StatefulWidget + setState (외부 라이브러리 없음) |

---

## 2. 파일 구조

```
tirtle_ml/
├── server/server.py                      # Python 분석 서버
├── assets/posture_model.tflite           # 센서 자세 분류 TFLite 모델
├── lib/
│   ├── main.dart                         # 앱 진입점
│   ├── constants.dart                    # 색상, URL, 포트 상수
│   ├── models/
│   │   ├── posture_state.dart            # WebSocket JSON → 객체 변환
│   │   ├── posture_snapshot.dart         # 2분 캡처 스냅샷 모델
│   │   └── sensor_posture.dart           # 센서 자세 Enum (6가지 + 색상/아이콘)
│   ├── services/
│   │   ├── sensor_classifier.dart        # 가속도/자이로 기반 TFLite 분류
│   │   └── overlay_channel.dart          # Flutter → Kotlin MethodChannel 래퍼
│   ├── painters/
│   │   ├── arc_gauge_painter.dart        # 원형 게이지 (270도 호)
│   │   └── area_line_painter.dart        # 면적 채움 선 그래프
│   └── screens/
│       ├── main_screen.dart              # 핵심 — WebSocket/카메라/서비스 중추
│       ├── home_tab.dart                 # 점수 카드, 그래프, 이슈 카드
│       ├── report_tab.dart               # 원형 게이지, 시간대별 그래프, 각도 분석
│       ├── camera_tab.dart               # 촬영 상태, 카운트다운, 이력
│       ├── reward_tab.dart               # 토큰/보상 센터 (UI 스켈레톤)
│       └── profile_tab.dart              # 서버 IP 설정, 오버레이 시작 버튼
└── android/app/src/main/
    ├── kotlin/com/example/tirtle_ml/
    │   ├── MainActivity.kt               # MethodChannel 등록
    │   └── OverlayService.kt             # 네이티브 시스템 오버레이
    └── AndroidManifest.xml
```

---

## 3. 전체 데이터 흐름

```
[폰 카메라]  2분마다 자동 촬영 (즉시 1회 + Timer.periodic)
     ↓ JPEG → base64
[main_screen.dart _captureOnce()]
     ↓ WebSocket send  {"type":"frame", "frame":"..."}
[server.py MobileSession.process()]
     ├─ MediaPipe PoseLandmarker  → 어깨/귀 관절 위치
     ├─ MediaPipe FaceLandmarker  → 얼굴 3D 각도 (solvePnP)
     └─ 점수 계산 → JSON 응답
     ↓
[main_screen.dart WebSocket listen()]
     ├─ PostureState 파싱
     ├─ 점수 히스토리 누적
     └─ PostureSnapshot 저장 (리포트용)
     ↓
[하위 탭 렌더링]  HomeTab / ReportTab / CameraTab

[가속도계 + 자이로]  50Hz 상시 수집 (SensorClassifier)
     ↓ 40프레임 윈도우
[TFLite 추론]  5개 자세 분류
     ↓ turtleNeck 감지 + 60초 쿨다운
[자동 카메라 촬영]  startCapture() 또는 _captureOnce()
     ↓
[OverlayService]  상태 변경 시 WindowManager View 업데이트
```

---

## 4. Flutter ↔ Kotlin 브릿지 패턴

Flutter에서 Android 네이티브 기능을 호출하는 공식 방법.
**채널 이름이 양쪽에서 동일하면 자동 연결**된다.

### 구조

```
Dart (lib/services/overlay_channel.dart)
    MethodChannel('com.example.tirtle_ml/overlay').invokeMethod('update', {...})
              ↕  [채널 이름 일치]
Kotlin (android/.../MainActivity.kt)
    MethodChannel(..., 'com.example.tirtle_ml/overlay').setMethodCallHandler { call, result →
        when (call.method) { "update" → OverlayService.updateState(...) }
    }
```

### 빌드 과정

```
flutter run
  ├─ Dart 컴파일  (Flutter SDK)
  └─ Android 빌드  (Gradle Wrapper가 처리)
       ├─ android/gradlew → Gradle 자동 다운로드 (최초 1회)
       ├─ Kotlin 플러그인 → JetBrains 서버에서 자동 다운로드
       └─ .kt 파일 컴파일 → APK에 포함
```

**PC에 Kotlin/Gradle 별도 설치 불필요.**
`flutter run` 한 번으로 Dart + Kotlin이 자동으로 합쳐진 APK가 생성된다.

### 이 방식으로 연결 가능한 것들

- Android 전용 라이브러리 (`build.gradle.kts`에 `implementation(...)` 추가)
- WindowManager (시스템 오버레이)
- AccessibilityService (다른 앱 화면 읽기)
- 하드웨어 직접 제어 (NFC, BLE 세밀 제어 등)
- pub.dev 패키지가 없거나 부족한 모든 Android 기능

---

## 5. 네이티브 오버레이 작동 방식

다른 앱·홈화면 위에 자세 상태를 표시하는 핵심 기능.

### 왜 Kotlin으로 직접 구현했나

`flutter_overlay_window 0.5.0` 라이브러리의 Java 코드가:
```java
startForeground(NOTIFICATION_ID, notification);  // 타입 파라미터 없음
```
Android 14는 `foregroundServiceType` 명시를 강제 → `validateForegroundServiceType` 예외 → 서비스 시작 불가.

Kotlin에서 직접:
```kotlin
startForeground(5001, notification,
    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)  // Android 14 필수
```

### OverlayService.kt 핵심 코드

```kotlin
// 앱과 무관한 시스템 레이어에 View 부착
val type = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
val params = WindowManager.LayoutParams(
    WRAP_CONTENT, WRAP_CONTENT, type,
    FLAG_NOT_FOCUSABLE,     // 터치가 아래 앱으로 통과
    PixelFormat.TRANSLUCENT
)
params.gravity = Gravity.TOP or Gravity.END  // 우측 상단
windowManager.addView(overlayView, params)

// 상태 업데이트 (메인 스레드 보장)
fun applyState(label: String, colorHex: String) {
    Handler(Looper.getMainLooper()).post {
        tvLabel.text = label
        (overlayView.background as GradientDrawable).setColor(Color.parseColor(colorHex))
    }
}
```

### 필요한 권한 (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>

<service android:name=".OverlayService"
         android:foregroundServiceType="specialUse">
    <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
              android:value="센서 자세 상태를 다른 앱 위에 표시"/>
</service>
```

---

## 6. Python 서버 (server.py)

### 점수 계산 알고리즘

```python
# 4가지 지표를 가중 평균
score = (s_pitch*0.40 + s_eye*0.30 + s_vis*0.15 + s_z*0.15) * 100

# 각 지표 계산
s_pitch = 1 - (현재_pitch - golden_pitch) / 12°           # 목 기울기
s_eye   = (현재_eye_ratio / golden_eye_ratio - 0.7) / 0.3  # 눈-어깨 비율
s_vis   = 1 - (golden_ear_vis - 현재_ear_vis) / 0.15       # 귀 가시성
s_z     = 1 - (현재_z - golden_z) / 0.25                   # 전후 깊이 차이
```

### 캘리브레이션

- 첫 프레임 수신 시 현재 자세를 `golden` 기준값으로 저장
- 이후 모든 점수는 golden과의 **편차** 기반
- 캘리브레이션 실패(golden=0) 방어: 현재 프레임 값으로 즉시 보정

### WebSocket 응답 형식

```json
{
  "status": "calibrating|ok|warning|no_person",
  "score": 85,
  "is_fhp": false,
  "countdown": 0,
  "scores": {"pitch": 0.9, "eye": 0.8, "vis": 1.0, "z": 0.7}
}
```

---

## 7. 센서 기반 자세 분류 (SensorClassifier)

### TFLite 모델

- 입력: 40프레임 × 8특징 `[accX, accY, accZ, gyrX, gyrY, gyrZ, pitch, roll]`
- 출력: 5개 클래스 확률 `[normal, turtleNeck, desk, sideLying, lying]`
- 샘플링: `SensorInterval.gameInterval` (~50Hz)

### 2단계 추론 전략

```
1차: TFLite 모델 (정상 경로)
     40프레임 채워지면 → 추론 → 5개 확률 중 argmax

2차: 임계치 fallback (모델 로드 실패 시 자동 전환)
     평균 pitch > 30° OR 평균 Z가속 < 5.0 → turtleNeck
     그 외 → normal
```

### 거북목 감지 → 자동 촬영

```
turtleNeck 감지 + 60초 쿨다운 통과
    ├─ 측정 중 아님 → startCapture() (포그라운드 서비스 포함 전체 플로우)
    └─ 측정 중     → _captureOnce()  (즉시 추가 촬영)
```

---

## 8. 주요 버그 수정 이력

### WebSocket 경쟁 조건 (Race Condition)

- **문제**: `_connect()`에서 `_channel.sink.close()` → `onDone` → `_onDisconnect()` → 재연결 무한루프
- **해결**: `_channel = null` 먼저, `old?.sink.close()` 나중 (순서 중요)

### 점수 85점 고정 버그

- **원인**: 캘리브레이션 5초 수집 구간을 건너뛰어 `golden` 값이 전부 0
  - s_pitch, s_eye → 조건 실패로 1.0 강제
  - s_z → `(curr_z - 0) / 0.25` → 항상 0
  - 결과: `(0.40 + 0.30 + 0.15 + 0) × 100 = 85`
- **해결**: 캘리브레이션 데이터 수집을 `elapsed` 체크보다 먼저 실행 + z 임계값 0.1→0.25 완화 + golden=0 런타임 보정

### Android 14 포그라운드 서비스 크래시

- **문제**: `foregroundServiceType` 파라미터 없이 `startForeground()` 호출
- **해결**: `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` 명시 (API 29+)

### 재연결 루프 불안정

- **해결**: `_isConnecting` 플래그로 중복 연결 방지 + 지수적 백오프 (2→4→8→최대 30초)

---

## 9. 플랫폼별 동작 차이

| 기능 | Windows | Android |
|---|---|---|
| WebSocket 서버 | 자동 시작/종료 | 수동 실행 필요 |
| 카메라 | PC 웹캠 | 전면 카메라 |
| 센서 | 없음 | 가속도/자이로 |
| TFLite 분류 | 없음 | 5가지 자세 |
| 시스템 오버레이 | 없음 | 우측 상단 플로팅 칩 |
| 포그라운드 서비스 | 없음 | 센서 + 촬영 백그라운드 유지 |
| 서버 IP | 고정 (localhost) | 프로필 탭에서 입력 |

---

## 10. 주요 의존성

```yaml
web_socket_channel: ^3.0.1       # WebSocket 통신
camera: ^0.11.0+2                # 카메라 촬영
permission_handler: ^11.3.1      # 런타임 권한 요청
wakelock_plus: ^1.3.4            # 백그라운드 화면 유지
flutter_foreground_task: ^8.0.2  # 포그라운드 서비스
sensors_plus: ^6.1.0             # 가속도/자이로 센서
tflite_flutter: ^0.11.0          # TFLite 추론 (FFI 기반)
flutter_overlay_window: ^0.5.0   # 현재 미사용 (네이티브 방식으로 대체)
```

### build.gradle.kts 필수 설정

```kotlin
aaptOptions {
    noCompress("tflite")  // .tflite 파일 압축 안 함 (메모리 매핑 필수)
}
```

---

## 11. 센서 자세 상태 색상표

| 상태 | 라벨 | 색상 |
|---|---|---|
| inactive | 사용안함 | `#9E9E9E` 회색 |
| normal | 정상 | `#00C896` 초록 |
| turtleNeck | 거북목 | `#FF9800` 주황 |
| desk | 책상 자세 | `#2196F3` 파랑 |
| sideLying | 옆으로 누움 | `#00838F` 청록 |
| lying | 누움 | `#9C27B0` 보라 |
