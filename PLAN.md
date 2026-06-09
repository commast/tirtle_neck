# 포스처가드 (Tirtle ML) — 프로젝트 문서

---

## 1. 앱 개요

거북목·자세 불량을 감지해 사용자에게 알리는 모바일/데스크톱 앱.
IMU 센서 기반 위험도(정상/주의/위험) 3단계 + 포그라운드 앱 컨텍스트 감지를 결합한다.
앱별 사용시간/주의 횟수를 누적해 리포트로 시각화한다.

| 항목 | 내용 |
|---|---|
| 프론트엔드 | Flutter 3.x / Dart 3.11.x |
| 백엔드 | Python FastAPI + MediaPipe (선택적, 카메라 분석) |
| 온디바이스 분석 | Android Kotlin MediaPipe (기본 모드) |
| 네이티브 | Android Kotlin (오버레이, 포그라운드 서비스, UsageStats, 전화 상태) |
| 상태관리 | StatefulWidget + setState + ValueNotifier + ChangeNotifier 싱글톤 |
| 차트 | fl_chart (도넛/스택바/라인) |
| 알람 | flutter_ringtone_player (시스템 알림음) + HapticFeedback (진동) |

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
│   │   ├── neck_risk.dart                    # NeckRiskLevel(정상/주의/위험) + 점수 분해
│   │   └── app_usage_record.dart             # 앱별/카테고리별 일일 누적 (리포트 데이터)
│   ├── services/
│   │   ├── sensor_classifier.dart            # IMU → 자세 분류 + 위험도 계산 (핵심)
│   │   ├── context_detector.dart             # 포그라운드앱+폰상태 → DetectedContext
│   │   ├── foreground_app_channel.dart       # 네이티브 UsageStats 채널 래퍼
│   │   ├── phone_state_channel.dart          # 네이티브 화면·통화 채널 래퍼
│   │   ├── app_category_classifier.dart      # 패키지명/시스템 카테고리 → AppCategory
│   │   ├── camera_mode_settings.dart         # 게임·영상 모드 카메라 옵트인 (SharedPrefs)
│   │   ├── alert_settings.dart               # 진동/소리 ON-OFF + 세기 (싱글톤 ChangeNotifier)
│   │   ├── usage_tracker_service.dart        # 포그라운드 앱 사용시간/주의횟수 누적 (싱글톤)
│   │   ├── posture_calibration.dart          # 모드별 baseline tilt 저장/로드
│   │   ├── background_calibration_runner.dart# 5초 백그라운드 캘리브레이션 샘플러
│   │   ├── overlay_channel.dart              # 분할 오버레이 (모드 칩 + 위험 칩)
│   │   ├── native_camera_channel.dart        # Kotlin Camera2 캡처 채널
│   │   ├── pose_analyzer_channel.dart        # 온디바이스 MediaPipe 분석 채널
│   │   └── headphone_head_tracker.dart       # (UI 제거됨, 파일만 잔존)
│   ├── painters/
│   │   ├── arc_gauge_painter.dart
│   │   └── area_line_painter.dart
│   └── screens/
│       ├── main_screen.dart                  # 중추 — 위험도·컨텍스트·캡처·오버레이·알람사이클
│       ├── home_tab.dart                     # 톱 사용 앱 카드 + 카테고리 라인 차트
│       ├── report_tab.dart                   # 오늘 도넛 / 주간 스택바 / 월간 라인 (fl_chart)
│       ├── camera_tab.dart                   # 캡처 히스토리 (FAB 경로 없어졌고 거의 미사용)
│       └── profile_tab.dart                  # 오버레이/카메라 옵트인/측정설정·알람 ExpansionTile
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

┌─ UsageTrackerService  앱별 사용량 누적 ──────────────────┐
│   ContextDetector.snapshot 구독 → 앱 전환 시 이전 앱에   │
│   초 단위 누적. 알람 발사 시 warningCount + hourly 버킷. │
│   SharedPrefs 'usage_history_v1' 에 일자별 JSON 영속화.  │
│   리포트 탭이 이 데이터를 도넛/스택바/라인으로 시각화.   │
└──────────────────────────────────────────────────────────┘

┌─ MainScreen  통합 + UI + 알람 듀티 사이클 ───────────────┐
│                                                          │
│   onRiskChanged ─→ _updateOverlay()                       │
│     OverlayChannel.updateSplit(mode, risk, score?)       │
│        → Kotlin OverlayService 두 칩 갱신                │
│     ※ _shouldShowOverlay==false 면 오버레이 stop+알람차단│
│                                                          │
│   normal → caution/risk ─→ _fireAlertIfDue()              │
│     ├─ AlertSettings.triggerAlert (진동+소리)            │
│     ├─ UsageTrackerService.recordWarning()               │
│     └─ alerting(3s) → cooldown(10s) → 재평가 사이클       │
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

| 컨텍스트 | 신호 | pitch 임계 | 모드 색 | 라벨 | 오버레이 |
|---|---|---|---|---|---|
| `onPhoneCall` | TelephonyManager.callState ≠ IDLE | 비활성 | #795548 | 통화 중 | **숨김** |
| `watchingVideo` | 포그라운드 = CATEGORY_VIDEO | 22° | #9C27B0 보라 | 영상 모드 | 표시 |
| `gaming` | 포그라운드 = CATEGORY_GAME | 22° | #2196F3 파랑 | 게임 모드 | 표시 |
| `social` | 포그라운드 = CATEGORY_SOCIAL | 22° | #03A9F4 하늘 | 소셜 모드 | 표시 |
| `studying` | 포그라운드 = CATEGORY_PRODUCTIVITY | 25° | #4CAF50 초록 | 학습 모드 | 표시 |
| `desk` | SensorPosture.desk + 위 모두 무관 | 22° | #607D8B 회청 | 책상 모드 | **숨김** |
| `normal` | 그 외 (런처/일반 앱) | 30° | #9E9E9E 회색 | 대기 | **숨김** |

### 오버레이 가시성 정책

`MainScreen._shouldShowOverlay` getter — 컨텍스트가 **video / game / social / study** 중 하나일 때만 오버레이를 표시하고 알람을 발사한다. 그 외(런처, 분류 안 된 앱, 통화 중, 책상 모드)에서는 `OverlayChannel.stop()` 호출 + 진행 중 알람 사이클 취소.

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
- 컨텍스트가 video/game/social/study **이외**면 오버레이 전체 hide
- 알람 쿨다운 중에는 risk 칩을 일시적으로 normal 로 마스킹
- API: `OverlayChannel.updateSplit({mode, risk, score?})`, `OverlayChannel.start()/stop()`

---

## 7. 알람 듀티 사이클

[main_screen.dart](lib/screens/main_screen.dart) — `_AlertPhase` {idle, alerting, cooldown}.

```
[idle]  센서 normal→non-normal + _shouldShowOverlay
   ↓ 알람 1회 (소리+진동) + UsageTrackerService.recordWarning()
[alerting]  3초 (오버레이 실제 risk 칩 표시)
   ↓
[cooldown]  10초 (오버레이 정상 칩 마스킹, 소리/진동 무음)
   ↓ 만료 시 현재 _riskState 확인
   ├─ non-normal → [alerting] 재진입 (재알람)
   └─ normal     → [idle]
```

- 자세를 바로잡아 normal 복귀해도 쿨다운은 끝까지 유지.
- `_stopSensorMonitoring()` / `dispose()` 에서 타이머 정리.
- 알람 자체 ON/OFF, 진동/소리 세기는 `AlertSettings` 싱글톤 (SharedPrefs 영속).

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

⚠️ `ForegroundAppChannel.stream` 의 `EventChannel.receiveBroadcastStream()` 은 Android에서 **활성 핸들러 1개만** 허용. `ContextDetector` 가 단독 구독하고 `UsageTrackerService` 는 그 `snapshot` ValueNotifier 를 구독해야 충돌 안 남.

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
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions"/>
```

### 런타임 권한 요청 순서

| 권한 | 요청 방식 | 시점 |
|---|---|---|
| `READ_PHONE_STATE` | `Permission.phone.request()` | 앱 시작 (initState) |
| `CAMERA` | `Permission.camera.request()` | 사용자가 카메라 탭에서 수동 시작 시만 |
| `PACKAGE_USAGE_STATS` | **보호된 권한 — 시스템 설정으로 안내** | 미허용 시 사용량 추적 안 됨 |
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
shared_preferences: ^2.5.5      # 카메라 옵트인/캘리브레이션/사용량/알람 설정 저장
fl_chart: ^0.69.0               # 리포트 도넛/스택바/라인 차트
flutter_ringtone_player: ^4.0.0+3  # 안드로이드 시스템 알림음 (SystemSound.alert 가 no-op)
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

## 11. 화면 구성

### HomeTab
- 인사 + 앱 이름 (상태 인디케이터 제거됨)
- **오늘 가장 많이 쓴 앱 카드** (앱명, 카테고리 칩, 사용시간, 주의·위험 총횟수, 시간당 발생률)
- **카테고리별 경고·위험 추이 라인 차트** — 일별(24h) / 주별(월~일) 토글, 4 카테고리 색별 라인
- 데이터 없는 미래 시각은 라인 미연결

### ReportTab — 오늘/주간/월간 토글
- 오늘: **도넛 차트** (4 카테고리 사용시간 비율, 사용 안 한 카테고리는 슬라이스 없음)
- 주간: **스택 막대** (월~일 7개, 각 막대를 4 카테고리 사용시간 비율로 스택, 영역 안에 주의·경고 횟수 텍스트)
- 월간: **4 라인 차트** (카테고리별 일별 주의 추이, 데이터 없는 날 끊김)
- 하단: 카테고리 카드 Expandable 리스트 (앱별 사용시간/주의횟수 드릴다운)
- fl_chart 사용

### ProfileTab
- 아바타 + 사용자 + 이메일 (장식)
- 자세 오버레이 시작 카드 (SYSTEM_ALERT_WINDOW 허용)
- 모드별 카메라 사용 옵트인 카드 (게임/영상)
- 하단 ListTile:
  - **알람 설정** (ExpansionTile) — 진동/소리 토글 + 각 세기 슬라이더
  - **측정 설정** (ExpansionTile) — 모드별 자세 기준 (캘리브레이션), `(N/5 측정됨)` 부제목
  - 도움말 / 앱 정보 — 비활성 placeholder

### CameraTab
- 캡처 히스토리. FAB 변경으로 진입 경로 없어졌고 거의 미사용.

### FAB — 센서 토글
- 가운데 FloatingActionButton (centerDocked)
- 아이콘: `sensors_rounded` (꺼짐, 초록) / `sensors_off_rounded` (켜짐, 빨강)
- 탭 → `_toggleSensor()` 로 SensorClassifier + 포그라운드 서비스 + 오버레이 토글
- 앱 시작 시 OFF (사용자가 명시적으로 켜야 감지 시작)

---

## 12. Logcat 주요 태그

```
[Risk] 정상/주의/위험 점수=… (pitch=, gyro=, dur=, still보너스=, …)
[Sensor] 컨텍스트 → (모드)  (pitch임계=…°)
[Context] 포그라운드: (앱이름) (패키지명) sys=(카테고리) → (분류)
[TFLite] (자세)  N=0.x T=0.x D=0.x SL=0.x L=0.x
[Alert] 알림음 재생 실패: …  (폴백 동작 시)
[UsageTracker] FgApp/저장/로드 관련 에러
D/FgApp: 포그라운드 앱 변경: (앱이름) (패키지명) category=(...)
D/PhoneState: ...
```

---

## 13. 주요 버그 수정 이력

### Android 14 포그라운드 서비스 크래시
- 문제: `foregroundServiceType` 파라미터 없이 `startForeground()` 호출
- 해결: `ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE` / `CAMERA` / `DATA_SYNC` 명시

### Android 11+ 패키지 가시성 제약
- 문제: `getApplicationInfo()` 실패 → 라벨이 패키지명, 카테고리 항상 `undefined`
- 해결: AndroidManifest `<queries>`에 LAUNCHER intent 선언

### UsageStatsManager 백그라운드 폴링 누락
- 문제: `Handler(Looper.getMainLooper())`로 폴링 시 메인 스레드 throttle로 백그라운드에서 안 돌아감
- 해결: 별도 `HandlerThread` 사용 + `queryUsageStats(INTERVAL_DAILY)` → `queryEvents()`

### 컨텍스트 전환 시 위험 타이머 누수
- 해결: `SensorClassifier.updateContext()`에서 무조건 `_cancelTurtleNeckTimers()`

### 카메라 권한 다이얼로그 침입
- 해결: 센서 트리거에서는 `Permission.camera.status`만 조회, 미허용 시 조용히 스킵

### 캘리브레이션 캡처가 점수 히스토리에 섞임
- 해결: `_captureOnce({fromTurtleNeck})` 플래그로 트리거 캡처만 히스토리 기록

### ForegroundApp EventChannel 다중 구독 충돌
- 문제: `UsageTrackerService` 가 `ForegroundAppChannel.stream` 을 별도 listen하면서 `ContextDetector` 의 listen을 덮어씌워 컨텍스트 갱신이 멈춤 → 오버레이/모드 칩 안 뜸
- 해결: `UsageTrackerService.init(ContextDetector)` 가 EventChannel 직접 구독 대신 `ContextDetector.snapshot` ValueNotifier 를 구독

### SystemSound.alert 가 안드로이드에서 무음
- 문제: Flutter 공식 문서 — iOS 전용
- 해결: `flutter_ringtone_player` 도입 → `playNotification(volume:)` 호출

### 알람이 엣지 1회만 발사
- 문제: normal→non-normal 엣지에서만 발사라 자세 계속 나빠도 재알람 없음
- 해결: `_AlertPhase` 듀티 사이클 (3초 알람 / 10초 쿨다운 / 반복) — 섹션 7 참조

### 시간대 막대 차트 색이 데이터 적을 때 모두 빨강
- 문제: `ratio > 0.7` 휴리스틱이 한두 데이터에서 무조건 1.0이 됨
- 해결: 막대 차트 자체를 도넛/스택바/라인으로 교체 (fl_chart), 색은 카테고리 고정색만

---

## 14. 제거된 기능 (한때 있었으나 사용 안 함)

| 기능 | 제거 이유 |
|---|---|
| `DetectedContext.lyingDown` | 영상·게임 모드와 겹쳐 오감지 잦음 |
| `DetectedContext.sleeping` | 시간대+STILL+화면OFF 조건이 너무 제한적 |
| `DetectedContext.exercising` | ActivityRecognition 신뢰도가 낮고 헬스장 등 못 잡음 |
| `flutter_activity_recognition` 패키지 | 위 두 컨텍스트 제거로 불필요 |
| `ACTIVITY_RECOGNITION` 권한 | 위와 같음 |
| `flutter_overlay_window` 패키지 | Android 14 호환 안 됨, 네이티브 OverlayService로 대체 |
| 서버 IP 설정 카드 | 온디바이스 모드 기본화로 불필요 |
| 이어폰 헤드 트래커 UI 카드 | 99% 기기에서 동작 안 함 (서비스 파일은 잔존, 인스턴스화 안 함) |
| ProfileTab 컨텍스트 디버그 카드 | 사용자 노출 불필요, 개발용 — Logcat 으로 대체 |
| ProfileTab 상단 stat 3개 (측정일/평균점수/토큰) | 더미 데이터, 의미 없음 |
| HomeTab 연결됨/연결 중 인디케이터 | 의미가 모호해 제거 |
| 자세 점수 게이지 / 점수 추이 라인 | 카테고리·앱 중심 리포트로 전환 |
| FAB 카메라 탭 진입 경로 | FAB 가 센서 토글로 용도 변경 |

---

## 15. 단계별 동작 예시

| 시나리오 | 오버레이 표시 | 알람 | 카메라 발사 |
|---|---|---|---|
| 폰 홈 화면(런처) | 숨김 | X | X |
| 시계/날씨 등 분류 안 된 앱 | 숨김 | X | X |
| 통화 수신 | 숨김 | X | X |
| 책상 모드 (폰 엎어둠) | 숨김 | X | X |
| 유튜브, 자세 좋음 | 영상 모드 보라 | X | X |
| 유튜브, 약간 숙임 1분 | 영상 모드 + 주의 (3초) → 마스킹(10초) → … | 진동+소리 13초 주기 | X |
| 유튜브 3분간 안 움직임 | 영상 모드 + 위험 | 위험 사이클 | 옵트인 ON일 때만 |
| 카카오톡 + 자세 나쁨 5분 | 소셜 모드 + 주의 | 사이클 | X (소셜은 카메라 비대상) |
| 게임 중 자세 나쁨 5초+ | 게임 모드 + 위험 | 사이클 | 옵트인 ON일 때만 |

---

## 16. 캘리브레이션 (PostureCalibration)

각 모드(영상/게임/소셜/학습/책상) 별로 "평상시 자세" 의 baseline tilt 를 저장.
이후 위험도 계산 시 절대 각도 대신 **baseline 대비 편차**로 점수 매김.
사람마다 폰 잡는 자세가 달라 발생하는 오감지 줄임.

| 파일 | 역할 |
|------|------|
| `lib/services/posture_calibration.dart` | baseline tilt 저장/로드 (ChangeNotifier) |
| `lib/services/background_calibration_runner.dart` | 5초 백그라운드 측정 샘플러 |
| `lib/services/sensor_classifier.dart` | `_computeRisk()` 안에서 baseline 있으면 편차 기반 점수 |
| `lib/screens/profile_tab.dart` `_measurementExpandable()` | 측정 설정 ExpansionTile UI |
| `OverlayService.kt` | 오버레이에 "🎯 측정" 버튼 — 측정 가능 모드 + 미측정 시 표시 |

측정 흐름: 오버레이 측정 버튼 탭 → `_handleOverlayCalibrateTapped()` → `BackgroundCalibrationRunner.sample()` (5초 카운트다운) → `PostureCalibration.saveFor(mode, tilt)`. 측정된 모드는 측정 설정 카드에 각도와 함께 표시되고 X 로 개별 초기화 가능.
