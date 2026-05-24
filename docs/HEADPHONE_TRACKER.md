# 이어폰 헤드 트래커 (Experimental)

> 이 문서는 **코드를 다 안 보고도 이 기능을 수정할 수 있도록** 작성되었다.
> 새 작업자(또는 LLM)는 이 문서만 읽고 어디를 어떻게 고치면 되는지 알 수 있다.

---

## 1. 무엇을 하는 기능인가

블루투스 이어폰에 내장된 **헤드 트래커 센서**(`Sensor.TYPE_HEAD_TRACKER`, Android API 33+)에 접근을
시도해서, 사용자의 **머리 자체 회전 각도(pitch)** 를 얻는다. 폰 IMU 만으로 추정하던 자세를 머리에서
직접 측정할 수 있게 되면 거북목 판정이 훨씬 정확해진다.

**다만 99% 케이스는 작동 안 한다** — `TYPE_HEAD_TRACKER`는 안드로이드 정책상 시스템(공간 음향) 전용으로
설계되어 일반 앱은 보통 차단된다. Galaxy Buds·AirPods·Pixel Buds 모두 공식 데이터 공개 X.
그래서 이 기능은 **본인 기기에서 되는지 확인하는 진단용**으로만 추가했고, 위험도 계산엔 통합하지 않았다.

UI: `ProfileTab` 의 "🎧 이어폰 헤드 트래커 (실험)" 카드 하나로만 노출된다.

---

## 2. 파일 구조

| 위치 | 역할 |
|------|------|
| `android/app/src/main/kotlin/com/example/tirtle_ml/HeadphoneHeadTracker.kt` | **네이티브 본체** — 센서 등록, BT 수신, 회전 벡터→pitch 변환, Flutter로 emit |
| `android/app/src/main/kotlin/com/example/tirtle_ml/MainActivity.kt` | EventChannel + MethodChannel 등록만 함. 채널명만 여기 있음 |
| `lib/services/headphone_head_tracker.dart` | **Flutter 래퍼** — EventChannel 구독 + 상태를 `ChangeNotifier`로 노출 |
| `lib/screens/main_screen.dart` | `HeadphoneHeadTracker` 인스턴스 생성·`start()`·`dispose()` + ProfileTab 에 전달 |
| `lib/screens/profile_tab.dart` | `_headphoneCard()` 위젯 — 카드 UI |
| `android/app/src/main/AndroidManifest.xml` | `BLUETOOTH_CONNECT`, `HIGH_SAMPLING_RATE_SENSORS` 권한 선언 |
| **`docs/HEADPHONE_TRACKER.md`** | 본 문서 |

---

## 3. 데이터 흐름

```
[BT 이어폰 연결] ─┬─ ACTION_ACL_CONNECTED ─┐
[BT 이어폰 해제] ─┴─ ACTION_ACL_DISCONNECTED ─┤
                                              ↓
                       Kotlin: HeadphoneHeadTracker
                       ├─ refreshConnectedDevice()  : 장치명 갱신
                       └─ tryRegisterHeadTracker()  : sensorMgr 에 listener 등록
                                              ↓
                              SensorManager (시스템)
                              ├─ getDefaultSensor(TYPE_HEAD_TRACKER)
                              └─ getDynamicSensorList(TYPE_HEAD_TRACKER)
                                              ↓
                              ┌─ Sensor 있음 → onSensorChanged
                              │    rotation vector → pitch°
                              │    sink.success({status:"tracking", device, pitchDeg})
                              │
                              └─ Sensor 없음 → emitState(null)
                                   sink.success({status:"earphoneUnsupported", device, null})

                                              ↓ (EventChannel)
                       Flutter: HeadphoneHeadTracker
                       ├─ _onEvent() : Map → HeadphoneTrackerState
                       └─ notifyListeners()
                                              ↓ (ChangeNotifier)
                       ProfileTab._headphoneCard() : AnimatedBuilder 로 실시간 재렌더
```

---

## 4. 상태 머신

```
                  start()
                     ↓
               ┌─ unknown ─┐
               │           │
        BT 미연결          BT 연결 감지
               ↓           ↓
        noEarphone     장치명 저장 → tryRegisterHeadTracker()
            ↑              │
            │      ┌───────┴───────┐
            │      ↓               ↓
            │ Sensor 없음      Sensor 있음
            │      ↓               ↓
            │ earphoneUnsupported  tracking
            │      │               │
            │      │   onSensorChanged 매 이벤트마다
            │      │   pitchDeg 갱신, status=tracking 유지
            │      ↓               ↓
            └─── ACL_DISCONNECTED ──┘
                 (unregisterSensor + 장치명 null)
```

**enum (`HeadphoneTrackerStatus`)**:
| 값 | 언제 | UI 표시 |
|----|------|---------|
| `unknown` | 초기값 (start() 호출 전) | `⏳ 초기화 중` |
| `noEarphone` | BT audio 미연결 | `— 이어폰 미연결` |
| `earphoneUnsupported` | 연결됐는데 센서 못 찾음 (대부분) | `❌ 지원 안 됨` |
| `tracking` | 센서 이벤트 들어오는 중 | `✅ tracking` |

---

## 5. 채널 프로토콜

### EventChannel: `com.example.tirtle_ml/headphone_tracker`
**방향**: Kotlin → Flutter

**페이로드** (sink.success):
```json
{
  "status":   "noEarphone" | "earphoneUnsupported" | "tracking",
  "device":   "Galaxy Buds3 Pro" | null,
  "pitchDeg": 12.4 | null
}
```
- `pitchDeg`는 `status == "tracking"` 일 때만 값이 있음
- `device`는 BLUETOOTH_CONNECT 권한 없으면 `"(BT 권한 없음)"`

### MethodChannel: `com.example.tirtle_ml/headphone_tracker_method`
**방향**: Flutter → Kotlin

| method | 반환 | 용도 |
|--------|------|------|
| `checkSupport` | `Map<String, Any?>` — `androidSdk`, `headTrackerApiAvail`, `headTrackerSensor`, `device`, `btConnectPermission` | 진단용 (현재 미사용, 추후 디버그 화면에 노출 가능) |

---

## 6. 권한

| 권한 | 매니페스트 | 런타임 요청 | 미허용 시 동작 |
|------|----------|----------|--------------|
| `BLUETOOTH_CONNECT` (API 31+) | ✓ | **앱이 시작 시 자동 요청 안 함** (지금은). 권한 없으면 device 이름이 `"(BT 권한 없음)"`로 표시 | 기능 자체는 작동, 장치명만 안 보임 |
| `HIGH_SAMPLING_RATE_SENSORS` (API 31+) | ✓ | 자동 | 고샘플링 차단 — 일반 샘플링은 가능 |

> **TODO**: 런타임 BT 권한 요청을 카드의 버튼으로 추가하면 더 친절해짐 (`Permission.bluetoothConnect.request()`).

---

## 7. 통합 정책

**현재**: 진단/표시만. 위험도 계산엔 영향 X.

**추후 통합하려면 (코드 안 봐도 어디 고치는지 안내)**:
1. `lib/services/sensor_classifier.dart` 의 `_computeRisk()` 안 `tiltDeg` 계산부 (현재 가속도계만 씀)
2. 만약 `_headphoneTracker.state.status == tracking` 이면 그 `pitchDeg`를 우선 신호로 사용
3. baseline 계산도 헤드 트래커 기준으로 따로 저장 (`PostureCalibration` 에 필드 하나 추가)

옵트인 토글:
- `lib/services/camera_mode_settings.dart` 와 같은 패턴으로 `HeadphoneTrackerSettings`(`useForRiskCalc: bool`) 신규 클래스 만들고 ProfileTab 에 토글 추가

---

## 8. 자주 묻는 수정 시나리오

### "감지 임계를 더 자주 emit 하고 싶다"
→ `HeadphoneHeadTracker.kt` 의 `sensorMgr.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)`
   의 마지막 인자를 `SENSOR_DELAY_FASTEST` 로 변경. 단 배터리 영향 큼.

### "카드의 라벨 문구를 바꾸고 싶다"
→ `lib/screens/profile_tab.dart` 의 `_headphoneCard()` + `_statusLabel()` 함수.

### "다른 BT 프로필도 인식하고 싶다 (예: BLE Audio)"
→ `HeadphoneHeadTracker.kt` 의 `refreshConnectedDevice()` 안에서
   `BluetoothProfile.HEADSET` / `A2DP` 외에 `LE_AUDIO`(API 33+) 추가.

### "센서 lookup 경로를 더 추가하고 싶다"
→ `HeadphoneHeadTracker.kt` 의 `findHeadTrackerSensor()` 안에 fallback 추가.
   (예: `Sensor.STRING_TYPE_HEAD_TRACKER` 로 텍스트 매칭, 일부 OEM 커스텀 센서 등)

### "실험 카드 자체를 끄고 싶다"
→ `lib/screens/main_screen.dart` 의 `ProfileTab(... headphoneTracker: ...)` 에서 `null` 전달.

### "실제로 작동하는지 확인하고 싶다"
→ Logcat 필터: `HeadphoneTracker`
   ```
   D/HeadphoneTracker: BT 연결: Galaxy Buds3 Pro
   D/HeadphoneTracker: HEAD_TRACKER 센서 없음 — 시스템 차단되었거나 미지원 기기
   ```
   → "센서 없음" 이 거의 항상의 결과. 어떤 OEM/펌웨어 조합에서 가끔 잡힐 수 있음.

---

## 9. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 카드에 항상 "지원 안 됨" | Android 정책상 정상. 시스템이 차단함 | 정상 동작. 본인 기기에서 안 잡힌 것뿐 |
| 카드에 항상 "이어폰 미연결" | BT 권한 X 또는 BT off | BT 켜기, 폰 설정에서 본 앱에 BLUETOOTH_CONNECT 허용 |
| 장치명이 "(BT 권한 없음)" | 런타임 BLUETOOTH_CONNECT 권한 미허용 | 폰 설정 → 앱 → 권한 → BT 켜기 |
| `tracking` 으로 뜨는데 pitchDeg 가 항상 0 | 회전 벡터 변환에서 좌표계 오류 가능 | `rotationVectorToPitchDeg()` 의 `orient[1]` 대신 `orient[2]` (roll) 또는 다른 축 시도 |
| 카드가 사라지지 않음 | dispose 안 됨 | `main_screen.dart`의 `dispose()` 에서 `_headphoneTracker.dispose()` 호출되는지 확인 |
| 빌드 에러 "Sensor.TYPE_HEAD_TRACKER not found" | minSdk < 33 | `Build.VERSION.SDK_INT >= 33` 가드 확인. 현재 코드는 가드 됨 |

---

## 10. 미래 확장 아이디어

- **음악 앱 연동**: 음악 들으며 사용 중일 때만 헤드 트래커 활용 (집중 모드)
- **양쪽 비교**: 헤드 트래커 pitch ↔ 폰 IMU pitch 두 값 시각화 → 진짜 거북목 자세 (머리만 숙이는 자세) 판별
- **운동/스트레칭 모드**: 머리 회전 범위 측정으로 목 가동범위 체크
- **권한 다이얼로그**: 첫 실행 시 BT 권한 요청 UX 개선

---

## 11. 관련 안드로이드 공식 문서

- [Sensor.TYPE_HEAD_TRACKER (API 33+)](https://developer.android.com/reference/android/hardware/Sensor#TYPE_HEAD_TRACKER)
- [Dynamic sensors (API 24+)](https://developer.android.com/reference/android/hardware/SensorManager#getDynamicSensorList(int))
- [Spatializer API](https://developer.android.com/reference/android/media/Spatializer) — 헤드 트래커가 실제 사용되는 곳
- [BluetoothManager](https://developer.android.com/reference/android/bluetooth/BluetoothManager)
