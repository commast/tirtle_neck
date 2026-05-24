# 포스처가드 (Tirtle ML) — 프로젝트 문서

---

## 1. 앱 개요

거북목·자세 불량을 감지해 사용자에게 알리는 모바일/데스크톱 앱.
IMU 센서 기반 위험도(정상/주의/위험) 3단계 + 포그라운드 앱 컨텍스트 감지를 결합한다.

| 항목 | 내용 |
|---|---|
| 프론트엔드 | Flutter 3.x / Dart 3.11.x |
| 백엔드 | Python FastAPI + MediaPipe (선택적, 카메라 분석) |
| 온디바이스 분석 | Android Kotlin MediaPipe (기본 모드) |
| 네이티브 | Android Kotlin (오버레이, 포그라운드 서비스, UsageStats, 전화 상태) |
| 상태관리 | StatefulWidget + setState + ValueNotifier |

---

## 2. 파일 구조

```
tirtle_ml/
├── server/server.py                          # Python 분석 서버 (선택)
├── assets/posture_model.tflite               # 센서 자세 분류 TFLite 모델
├── lib/
│   ├── main.dart                             # 앱 진입점
│   ├── constants.dart                        # 색상, URL, 포트 상수
│   ├── models/
│   │   ├── posture_state.dart                # 카메라 분석 결과 객체
│   │   ├── posture_snapshot.dart             # 캡처 히스토리 항목
│   │   ├── sensor_posture.dart               # TFLite 출력 5분류 enum
│   │   ├── detected_context.dart             # 7가지 사용 컨텍스트 enum + 색/임계
│   │   └── neck_risk.dart                    # NeckRiskLevel(정상/주의/위험) + 점수 분해
│   ├── services/
│   │   ├── sensor_classifier.dart            # IMU → 자세 분류 + 위험도 계산 (핵심)
│   │   ├── context_detector.dart             # 포그라운드앱+폰상태 → DetectedContext
│   │   ├── foreground_app_channel.dart       # 네이티브 UsageStats 채널 래퍼
│   │   ├── phone_state_channel.dart          # 네이티브 화면·통화 채널 래퍼
│   │   ├── app_category_classifier.dart      # 패키지명/시스템 카테고리 → AppCategory
│   │   ├── camera_mode_settings.dart         # 게임·영상 모드 카메라 옵트인 (SharedPrefs)
│   │   ├── overlay_channel.dart              # 분할 오버레이 (모드 칩 + 위험 칩)
│   │   ├── native_camera_channel.dart        # Kotlin Camera2 캡처 채널
│   │   └── pose_analyzer_channel.dart        # 온디바이스 MediaPipe 분석 채널
│   ├── painters/
│   │   ├── arc_gauge_painter.dart
│   │   └── area_line_painter.dart
│   └── screens/
│       ├── main_screen.dart                  # 중추 — 위험도·컨텍스트·캡처·오버레이 통합
│       ├── home_tab.dart
│       ├── report_tab.dart
│       ├── camera_tab.dart
│       └── profile_tab.dart                  # 카메라 옵트인 설정 + 디버그 카드
└── android/app/src/main/
    ├── kotlin/com/example/tirtle_ml/
    │   ├── MainActivity.kt                   # MethodChannel·EventChannel 등록
    │   ├── OverlayService.kt                 # 분할 오버레이 (모드/위험 두 칩)
    │   ├── CameraBackgroundService.kt        # 백그라운드 카메라용 FG 서비스
    │   ├── NativeCameraCapture.kt            # Camera2 직접 캡처
    │   ├── PoseAnalyzer.kt                   # MediaPipe 온디바이스 분석
    │   ├── ForegroundAppMonitor.kt           # UsageStatsManager 폴링
    │   └── PhoneStateMonitor.kt              # 화면 ON/OFF + 통화 감지
    └── AndroidManifest.xml
```

---

## 3. 핵심 데이터 흐름

```
┌─ 가속도/자이로 50Hz (sensors_plus) ───────────────────────┐
│                  ↓                                       │
│   SensorClassifier._processFrame() — 40프레임 윈도우     │
│                  ↓                                       │
│   ┌─────────────────────────────────────────┐            │
│   │ _runInference()  자세 5분류             │            │
│   │   ├─ TFLite (있으면)                    │            │
│   │   └─ Threshold fallback (pitch 기반)   │            │
│   │                ↓                        │            │
│   │   onPostureChanged(SensorPosture)       │ → context  │
│   └─────────────────────────────────────────┘            │
│   ┌─────────────────────────────────────────┐            │
│   │ _computeRisk()  위험도 계산              │            │
│   │   ├─ pitch (0-40)                       │            │
│   │   ├─ gyro 분산 (0-20)                   │            │
│   │   ├─ 자세지속 (0-40, tilt baseline ±15°)│            │
│   │   ├─ 정지지속 보너스 (0-40, 게임/영상만)│            │
│   │   └─ × 모드 가중치                      │            │
│   │                ↓                        │            │
│   │   NeckRiskState(level, score, …)        │            │
│   │   onRiskChanged(state)                  │            │
│   └─────────────────────────────────────────┘            │
└──────────────────────────────────────────────────────────┘

┌─ ContextDetector  컨텍스트 결정 ─────────────────────────┐
│                                                          │
│   PhoneStateMonitor      ─→ screenOn / inCall            │
│   ForegroundAppMonitor   ─→ pkg + label + sysCategory    │
│   SensorPosture          ─→ desk 자세 보조신호           │
│                  ↓                                       │
│   _resolveInternal()  우선순위 체인                       │
│     onPhoneCall > {video|game|social|study} > desk > nrm │
│                  ↓                                       │
│   ValueNotifier<DetectedContext> + ContextSnapshot       │
└──────────────────────────────────────────────────────────┘

         ↓ (매 컨텍스트 변경 시)
   SensorClassifier.updateContext(ctx) — pitch 임계/가중치 갱신

┌─ MainScreen  통합 + UI ──────────────────────────────────┐
│                                                          │
│   onRiskChanged ─→ _updateOverlay()                       │
│     OverlayChannel.updateSplit(mode, risk, score?)       │
│        → Kotlin OverlayService 두 칩 갱신                │
│                                                          │
│   risk=위험 5초 지속 ─→ _onSustainedRiskDetected()        │
│     ├─ 컨텍스트가 gaming/watchingVideo ? 카메라 발사     │
│     └─ 그 외 ? 오버레이만 (카메라 안 씀)                  │
└──────────────────────────────────────────────────────────┘
```

---

## 4. 위험도 점수 알고리즘 (NeckRisk)

### 점수 구성 (max 100 — modeWeight 적용 후 clamp)

| 요소 | 만점 | 의미 |
|------|-----|------|
| pitchScore | 40 | 폰의 수평 기준 기울기 (낮은 각도일수록 높음) |
| gyroScore | 20 | 자이로 분산 (정지일수록 높음) |
| durationScore | 40 | 같은 자세 지속시간 (수직자세 >60°에선 누적 안 함) |
| stillnessBonus | 40 | 자이로 거의 0 유지 (게임·영상 모드만) |

### 단계 경계

```
0  ─ 50 : 정상 (NeckRiskLevel.normal)
51 ─ 70 : 주의 (caution)
71 ─    : 위험 (risk)
```

### 모드 가중치 (`DetectedContext.riskWeight`)

```
소셜 1.2, 학습 1.1, 게임 1.0, 영상 0.9, 기타 1.0
```

### 자세 지속 추적 — tilt baseline ±15°

자이로 분산이 아니라 **smoothed pitch baseline** 으로 자세 변경을 감지.
손떨림이나 일시 동작에 끊기지 않고, baseline은 EMA로 천천히 추종 (`α=0.01`).

### 정지 지속 보너스 — 게임/영상 한정

```dart
gVar < 0.02 → _stillStartTime 유지 (스크롤·터치도 안 함)
gVar ≥ 0.02 → 리셋

if (gaming || watchingVideo) {
  stillSec > 300 → +40   // 5분+
  stillSec > 180 → +28   // 3~5분
  stillSec > 60  → +15   // 1~3분
}
```

---

## 5. 컨텍스트 분류 (DetectedContext)

7가지. 우선순위 체인 위 → 아래.

| 컨텍스트 | 신호 | pitch 임계 | 모드 색 | 라벨 |
|---|---|---|---|---|
| `onPhoneCall` | TelephonyManager.callState ≠ IDLE | 비활성 | #795548 | 통화 중 |
| `watchingVideo` | 포그라운드 = CATEGORY_VIDEO | 22° | #9C27B0 보라 | 영상 모드 |
| `gaming` | 포그라운드 = CATEGORY_GAME | 22° | #2196F3 파랑 | 게임 모드 |
| `social` | 포그라운드 = CATEGORY_SOCIAL | 22° | #03A9F4 하늘 | 소셜 모드 |
| `studying` | 포그라운드 = CATEGORY_PRODUCTIVITY | 25° | #4CAF50 초록 | 학습 모드 |
| `desk` | SensorPosture.desk + 위 모두 무관 | 22° | #607D8B 회청 | 책상 모드 |
| `normal` | 그 외 | 30° | #9E9E9E 회색 | (오버레이 숨김) |

### 포그라운드 앱 식별 (Android 11+ 주의)

`AndroidManifest.xml`에 LAUNCHER `<queries>` 선언 필수.
없으면 `PackageManager.getApplicationInfo()` 실패 → 라벨이 패키지명으로 표시되고
`ApplicationInfo.category`도 못 읽음.

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent>
</queries>
```

`AppCategoryClassifier.classify(pkg, systemCategory)`:
1. systemCategory가 game/video/audio/social/productivity → 그대로 사용
2. undefined면 패키지명 키워드 휴리스틱 폴백 (`youtube`, `kakao`, `notion`, …)

---

## 6. 오버레이 — 분할 칩 레이아웃

`OverlayService.kt`의 LinearLayout에 두 TextView를 가로 배치.

```
[ 게임 모드 ]   [ 주의 ]
  modeColor    riskColor
```

- 위험 레벨이 `normal`이면 오른쪽 칩 `View.GONE`
- 모드가 `normal`이면 왼쪽 칩 "대기" 회색
- API: `OverlayChannel.updateSplit({mode, risk, score?})`

---

## 7. 카메라 트리거 정책

위험 단계가 5초 지속 (`_onSustainedRiskDetected`)되면:

1. 컨텍스트가 `gaming` 또는 `watchingVideo` 이어야 함
2. `CameraModeSettings`에서 그 모드 카메라 옵트인이 켜져 있어야 함
3. 둘 다 만족하면 → `_captureOnce(fromTurtleNeck: true)` 실행
4. 그 외 모드 (학습/소셜/통화/일반/책상) → 카메라 발사 안 함, 오버레이 위험 표시만

권한 처리:
- 센서 트리거 캡처: `Permission.camera.status`만 확인 (다이얼로그 X, 다른 앱 사용 중 방해 방지)
- 수동 캡처 시작 (카메라 탭 버튼): `Permission.camera.request()` (다이얼로그 정상 표시)

### 캡처 히스토리 정책

`_captureOnce({bool fromTurtleNeck=false})`:
- `fromTurtleNeck: true` (센서 트리거)  → `_snapshots.add()` + `_saveHistory()`
- `false` (캘리브레이션, 수동 시작 직후 2회) → UI 점수만 표시, 히스토리 미기록

---

## 8. 네이티브 → Flutter 채널 맵

| 채널명 | 종류 | 방향 | 용도 |
|---|---|---|---|
| `…/overlay` | MethodChannel | Flutter→Kotlin | 오버레이 표시/숨김/`updateSplit` |
| `…/camera_bg` | MethodChannel | Flutter→Kotlin | CameraBackgroundService 시작/종료 |
| `…/native_camera` | MethodChannel | Flutter→Kotlin | Camera2 직접 캡처 |
| `…/pose_analyzer` | MethodChannel | Flutter→Kotlin | 온디바이스 MediaPipe 분석 |
| `…/foreground_app` | MethodChannel | Flutter→Kotlin | UsageStats 권한 체크/설정 열기 |
| `…/foreground_app_events` | EventChannel | Kotlin→Flutter | 포그라운드 앱 변경 스트림 |
| `…/phone_state_events` | EventChannel | Kotlin→Flutter | 화면 ON/OFF + 통화 상태 스트림 |

---

## 9. 권한

### AndroidManifest.xml 핵심

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.READ_PHONE_STATE"/>
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions"/>
```

### 런타임 권한 요청 순서

| 권한 | 요청 방식 | 시점 |
|---|---|---|
| `READ_PHONE_STATE` | `Permission.phone.request()` | 앱 시작 (initState) |
| `CAMERA` | `Permission.camera.request()` | 사용자가 카메라 탭에서 수동 시작 시만 |
| `PACKAGE_USAGE_STATS` | **보호된 권한 — 시스템 설정으로 안내** | 프로필 탭 "설정 열기" 버튼 |
| `SYSTEM_ALERT_WINDOW` | 오버레이 시작 시도 시 시스템 다이얼로그 | 사용자가 오버레이 시작 시 |

---

## 10. 주요 의존성

```yaml
web_socket_channel: ^3.0.1
camera: ^0.11.0+2
permission_handler: ^11.3.1
wakelock_plus: ^1.3.4
flutter_foreground_task: ^8.0.2
sensors_plus: ^6.1.0
tflite_flutter: ^0.11.0
shared_preferences: ^2.5.5      # 카메라 모드 옵트인 저장
```

`flutter_overlay_window`, `flutter_activity_recognition`은 사용 안 함 (네이티브로 대체 / 제거됨).

```kotlin
// build.gradle.kts
aaptOptions {
    noCompress("tflite")   // TFLite 메모리 매핑 위해 비압축
    noCompress("task")     // MediaPipe .task 모델도 동일
}
dependencies {
    implementation("com.google.mediapipe:tasks-vision:0.10.14")
}
```

---

## 11. 디버그 / 검증

### ProfileTab 컨텍스트 디버그 카드

실시간으로 보이는 항목:
- 사용 정보 접근 권한 상태 + "설정 열기" 버튼
- 현재 포그라운드 앱 이름 + 패키지명 + 분류 카테고리
- 현재 컨텍스트 + pitch 임계 + 위험 가중치
- 화면 ON/OFF, 통화 여부, 자세 (TFLite)

### Logcat 주요 태그

```
[Risk] 정상/주의/위험 점수=… (pitch=, gyro=, dur=, still보너스=, …)
[Sensor] 컨텍스트 → (모드)  (pitch임계=…°)
[Context] 포그라운드: (앱이름) (패키지명) sys=(카테고리) → (분류)
[TFLite] (자세)  N=0.x T=0.x D=0.x SL=0.x L=0.x
D/FgApp: 포그라운드 앱 변경: (앱이름) (패키지명) category=(...)
D/PhoneState: ...
```

---

## 12. 주요 버그 수정 이력

### Android 14 포그라운드 서비스 크래시
- 문제: `foregroundServiceType` 파라미터 없이 `startForeground()` 호출
- 해결: `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` / `CAMERA` / `DATA_SYNC` 명시

### Android 11+ 패키지 가시성 제약
- 문제: `getApplicationInfo()` 실패 → 라벨이 패키지명, 카테고리 항상 `undefined`
- 해결: AndroidManifest `<queries>`에 LAUNCHER intent 선언

### UsageStatsManager 백그라운드 폴링 누락
- 문제: `Handler(Looper.getMainLooper())`로 폴링 시 메인 스레드 throttle로 백그라운드에서 안 돌아감
- 해결: 별도 `HandlerThread` 사용 + `queryUsageStats(INTERVAL_DAILY)` → `queryEvents()` (ACTIVITY_RESUMED 이벤트 직접 추적)

### 컨텍스트 전환 시 위험 타이머 누수
- 문제: 이전 모드 임계로 카운트 중이던 타이머가 새 모드로 넘어가 즉시 트리거
- 해결: `SensorClassifier.updateContext()`에서 무조건 `_cancelTurtleNeckTimers()`

### 카메라 권한 다이얼로그 침입
- 문제: 센서 트리거에서 `Permission.camera.request()`가 다른 앱 사용 중 다이얼로그 띄움
- 해결: 센서 트리거에서는 `Permission.camera.status`만 조회, 미허용 시 조용히 스킵

### 점수가 정상 상태에서도 기록되던 문제
- 문제: 캘리브레이션 캡처(시작 직후 2회)에서도 `_snapshots.add()`
- 해결: `_captureOnce({fromTurtleNeck})` 플래그로 트리거 캡처만 히스토리 기록

---

## 13. 제거된 기능 (한때 있었으나 사용 안 함)

| 기능 | 제거 이유 |
|---|---|
| `DetectedContext.lyingDown` | 영상·게임 모드와 겹쳐 오감지 잦음 |
| `DetectedContext.sleeping` | 시간대+STILL+화면OFF 조건이 너무 제한적 |
| `DetectedContext.exercising` | ActivityRecognition 신뢰도가 낮고 헬스장 등 못 잡음 |
| `flutter_activity_recognition` 패키지 | 위 두 컨텍스트 제거로 불필요 |
| `ACTIVITY_RECOGNITION` 권한 | 위와 같음 |
| `flutter_overlay_window` 패키지 | Android 14 호환 안 됨, 네이티브 OverlayService로 대체 |

---

## 14. 단계별 동작 예시

| 시나리오 | 오버레이 표시 | 카메라 발사 |
|---|---|---|
| 폰 가만히 책상 위 (수직) | `대기` 회색 만 | X |
| 유튜브 켰음, 자세 좋음 | `영상 모드` 보라 만 | X |
| 유튜브 보는데 약간 숙임 1분 | `영상 모드` 보라 + `주의` 주황 | X |
| 유튜브 3분간 안 움직임 | `영상 모드` 보라 + `위험` 빨강 | 영상 옵트인 ON일 때만 |
| 카카오톡 사용 + 보통 자세 5분 | `소셜 모드` 하늘 + `주의` | X (소셜은 카메라 비대상) |
| 게임 중 자세 나쁨 5초+ | `게임 모드` 파랑 + `위험` | 게임 옵트인 ON일 때만 |
| 통화 수신 | `통화 중` 갈색 만 | X (감지 비활성) |

---

## 15. 실험적 기능

격리된 별도 파일에 작성된 베타 기능들. 본체 기능에 영향 주지 않는다.

### 이어폰 헤드 트래커 (`Sensor.TYPE_HEAD_TRACKER`, API 33+)

BT 이어폰 내장 헤드 트래커로 머리 회전 각도를 직접 측정하는 실험 기능.
**99% 케이스에서 안 작동** (안드로이드 정책상 시스템 전용 센서) — 본인 기기 지원 여부 확인용.

| 파일 | 역할 |
|------|------|
| `android/app/src/main/kotlin/com/example/tirtle_ml/HeadphoneHeadTracker.kt` | 네이티브 본체 |
| `lib/services/headphone_head_tracker.dart` | Flutter 래퍼 (ChangeNotifier) |
| `lib/screens/profile_tab.dart` `_headphoneCard()` | UI 카드 |
| **[`docs/HEADPHONE_TRACKER.md`](docs/HEADPHONE_TRACKER.md)** | **전용 상세 문서 (구조도·상태머신·채널 프로토콜·트러블슈팅 포함)** |

상세 동작·수정 방법·통합 정책 등은 위 전용 문서 참고.

### 캘리브레이션 (`PostureCalibration`)

첫 실행 시 5초간 "편한 자세" 측정 → SharedPreferences 저장 → 위험도 계산 시 절대 각도 대신
**baseline 대비 편차**로 점수 매김. 사람마다 폰 잡는 자세가 달라 발생하는 오감지 줄임.

| 파일 | 역할 |
|------|------|
| `lib/services/posture_calibration.dart` | baseline tilt 저장/로드 (ChangeNotifier) |
| `lib/screens/calibration_dialog.dart` | 5초 측정 다이얼로그 |
| `lib/services/sensor_classifier.dart` | `_computeRisk()` 안에서 baseline 있으면 편차 기반 점수 |
| `lib/screens/profile_tab.dart` `_calibrationCard()` | 재측정 UI |
