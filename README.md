# BP Companion of Jaisung NOH

혈압(BP)을 기록하는 iOS 앱입니다. SwiftUI + SwiftData + Swift Charts, 오렌지 색상 테마, iCloud(CloudKit) 동기화.

![icon](BPCompanion/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)

## 화면 구성

| 탭 | 내용 |
|---|---|
| **Home** | 제목 *BP companion of Jaisung NOH*. `LAST 10 READINGS` (SYSTOLIC / DIASTOLIC / HR / MAP / WEIGHT 의 MAX·MIN·AVG), `YOUR LAST READINGS`. 우상단 **+** 로 입력 |
| **History** | 위쪽에서 **Blood Pressure / Weight** 전환. Weight = 건강 앱(YUNMAI)의 측정 기록을 월별로(체중·직전 대비 ▲▼, BMI·등급, 체지방률, 제지방량, 시간, 출처 앱; 읽기 전용). Blood Pressure = 월별 섹션(접기/펼치기), 날짜 아이콘, 수축기/이완기(단계별 색상), 맥박, MAP, 시간, 약 복용(💊) 표시. 연필 버튼 = 편집/삭제 모드, 행을 누르면 수정 |
| **Reports** | 좌우 스와이프로 4페이지: **Summary**(MAX/MIN/AVG 표) · **Trend**(BP/HR 꺾은선 + 평균 점선) · **Range**(구간별 횟수·비율) · **Statistics**(Max/Avg/Min 막대). 상단 From/To 와 ‹ › 로 기간 이동, 하단 **D / W / M / Y / Custom**, **All / AM / PM** 필터, 📷 버튼 = 현재 페이지 이미지로 공유 |
| **Settings** | 1. **Export (CSV)** 2. **Import (CSV)** (아래 Info 는 평소 접힘, 가져오기/내보내기 후 결과와 함께 펼쳐짐) 3. **iCloud Sync** 4. **Apple Health** 쓰기, 이름 변경 |
| **Body** | 건강 앱에서 체중계 앱(YUNMAI 등)의 **체중·BMI·체지방률·제지방량·신장**을 읽어 혈압과 별도로 분석: 최근값 카드(BMI 등급, 신장), 기간별 MAX/MIN/AVG/변화 표, 항목별 추이 그래프(평균선), 변화 분석(체지방 감소·제지방 유지 등). 기간 선택(AM/PM 구분 없음), 앱별 출처 필터, 당겨서 새로고침 |
| **+ Add Entry** | Basic(혈압/맥박 휠 ↔ 날짜·시간 휠, Drug 스위치) · Note(메모 + ★). 체중은 입력하지 않음 → Body 탭 |

혈압 색상 기준: 수축기 <90 저혈압(파랑) · 90–119 정상(초록) · 120–139 주의(주황) · ≥140 고혈압(빨강) / 이완기 <60 · 60–79 · 80–89 · ≥90.
MAP = 이완기 + (수축기 − 이완기) / 3.

## 빌드 방법

요구사항: **Xcode 16 이상**, iOS/iPadOS 17 이상 **iPhone · iPad** (유니버설 앱). iPhone은 세로 고정, iPad는 모든 방향 회전과 Split View/Slide Over를 지원하며 표와 목록은 넓은 화면에서 가운데 정렬됩니다.

1. `BPCompanion.xcodeproj` 를 Xcode로 엽니다.
2. Target **BPCompanion › Signing & Capabilities** 에서 **Team** 을 선택합니다.
   필요하면 Bundle Identifier(`com.jaisungnoh.BPCompanion`)를 본인 것으로 바꿉니다.
3. iCloud 동기화를 쓰려면 같은 화면의 **iCloud** 항목에서 CloudKit 컨테이너
   `iCloud.com.jaisungnoh.BPCompanion` 를 체크(또는 + 로 생성)합니다. Bundle ID를 바꿨다면 컨테이너 이름도 `iCloud.<bundle id>` 로 맞춰 주세요.
   (Background Modes › Remote notifications, Push Notifications 는 이미 설정되어 있습니다.)
4. ▶︎ Run.

iCloud 설정이 없거나 iCloud에 로그인되어 있지 않으면 앱은 자동으로 기기 내 저장소만 사용합니다.
Settings 의 iCloud Sync 스위치 변경은 앱을 다시 실행해야 적용됩니다.

## Apple 건강(Health) 앱 연동

- **Settings › Apple Health › Write to Health** 를 켜면 권한을 요청한 뒤 기존 기록 전체를 건강 앱에 저장합니다.
  - 혈압(수축기/이완기)과 심박수를 기록 시각 그대로 저장합니다(체중은 쓰지 않음). (약 복용·메모는 건강 앱에 해당 항목이 없어 저장하지 않습니다.)
- 켜 둔 동안 새로 추가·수정·삭제·가져오기 한 기록은 건강 앱에도 자동 반영됩니다.
  다른 기기에서 iCloud로 넘어온 기록은 **Send All Readings to Health** 로 보낼 수 있습니다(중복되지 않음 — 기록마다 고유 동기화 ID 사용).
- **체성분 읽기 (YUNMAI 등)**: Settings › Apple Health › **Read Body Data** (기본 켜짐). YUNMAI 앱이 건강 앱에 넣은 체중·BMI·체지방률·제지방량·신장을 읽어 **Body 탭**에서 혈압과 따로 분석합니다. 혈압 기록에 체중을 붙이거나 앱에서 체중을 입력하지 않습니다.
  - YUNMAI 앱에서 건강 앱 연동을 켜야 합니다(Me › Connect to Health).
  - 앱이 열려 있는 동안 새 측정값이 들어오면 자동으로 다시 읽습니다. Home의 "YOUR LAST READINGS"에는 최근 체중이 함께 표시됩니다.
  - BP Companion이 직접 쓴 체중(예전 버전에서 저장한 것)은 읽을 때 제외합니다. Settings › Apple Health › **Delete BP Companion Weights in Health** 로 건강 앱에서도 지울 수 있습니다(YUNMAI 자료는 지워지지 않음).
  - BMI 등급은 대한비만학회 기준(정상 18.5–22.9, 과체중 23–24.9, 비만 25 이상)입니다.
- 기본으로 켜져 있어 **iPhone/iPad에서 처음 실행할 때 건강 권한 창**이 뜹니다. 권한을 한 번 요청해야
  건강 앱 › 공유 › 앱 및 각 항목의 **데이터 소스**에 BP Companion 이 나타납니다.
- Settings › Apple Health › Health Access 에서 상태(Allowed / Not allowed / Not asked yet)와 오류를 볼 수 있습니다.
  "Missing com.apple.developer.healthkit entitlement" 오류가 보이면 Xcode › Signing & Capabilities 에 HealthKit 을 추가하고 다시 설치하세요.
- 건강 앱이 없는 Mac(Designed for iPad)에서는 이 항목이 보이지 않습니다.
- Xcode: Signing & Capabilities 에 **HealthKit** 이 표시되는지 확인하세요(entitlements 에 이미 포함). 없으면 + Capability › HealthKit 추가.

## iCloud 동기화

- 기록은 SwiftData + CloudKit 으로 사용자의 **개인(private) iCloud 데이터베이스**에 저장되어,
  같은 Apple ID로 로그인한 모든 iPhone/iPad에 자동으로 동기화됩니다. (서버 비용 없음, 다른 사람은 볼 수 없음)
- 이미 기기에 있던 기록은 동기화를 켜면 iCloud로 업로드됩니다.
- **Settings › iCloud** 에서 계정 상태, 동기화 상태(Syncing… / Up to date / 오류), 마지막 동기화 시각을 볼 수 있습니다.
  iCloud 기능이 설정되지 않은 빌드면 "iCloud unavailable – saved on this device"와 원인이 표시됩니다.

### 확인 순서
1. 위 빌드 방법 2–3단계(Team, iCloud 컨테이너 체크)를 완료합니다.
2. 두 기기(또는 기기 + 시뮬레이터)에 같은 Apple ID로 iCloud 로그인 후 앱을 설치합니다.
   시뮬레이터는 설정 앱에서 iCloud 로그인이 필요합니다.
3. 한 기기에서 기록을 추가하면 다른 기기에 보통 수십 초 안에 나타납니다. 안 보이면 앱을 백그라운드로 보냈다가 다시 열어 보세요.
4. 개발 중 데이터는 CloudKit **Development** 환경에 저장됩니다. TestFlight/App Store 배포 전에는
   [CloudKit Console](https://icloud.developer.apple.com) 에서 스키마를 **Deploy Schema Changes → Production** 해야 합니다.

## CSV 형식

기존 앱의 `BloodPressure_Data_YYYYMMDD.csv` 와 **같은 형식**으로 내보내고 가져옵니다.

```
"Date Time","Period","Systolic (mmHg)","Diastolic (mmHg)","MAP (mmHg)","Heart Rate (bpm)","Weight (kg)","Drug","Note"
"2026. 11. 19. 06:54","Morning","141","95","110","66","84.5","YES",""
"2026. 11. 18. 21:12","Evening","149","91","110","70","84.5","YES",""
```

- 모든 칸을 따옴표로 감싸고, 최신 기록이 맨 위, UTF-8, 파일 이름 `BloodPressure_Data_20261119.csv`
- Period: Morning 04:00–11:59 · Day 12:00–17:59 · Evening 18:00–03:59
- MAP = 이완기 + (수축기 − 이완기)/3 반올림, Drug = `YES`/`NO`. Weight 칸은 형식 호환을 위해 남겨 두며, 가져온 CSV의 체중 값을 그대로 보관했다가 내보낼 때 다시 씁니다(앱 화면에는 표시하지 않음)
- 가져오기: `Date Time`, `Systolic`, `Diastolic` 열은 필수. `Period`, `MAP` 은 다시 계산하므로 무시합니다.
  같은 시각(분)·같은 혈압·맥박의 기록은 중복으로 보고 건너뜁니다. 이전 형식(`date,systolic,...`)도 읽을 수 있습니다.
- ★(starred) 표시는 이 형식에 칸이 없어 내보내지 않습니다.

### 가져오는 방법
1. **Settings › Import (CSV)** 에서 파일 선택
2. 또는 Files·메일·카카오톡 등에서 `.csv` 파일을 탭/공유 → **BP Companion** 선택 → "Import" 확인
   (가져온 뒤 History 탭으로 이동). UTF-8, UTF-16, CP949(한글 Excel) 인코딩을 읽을 수 있습니다.

## 폴더 구조

```
BPCompanion/
  BPCompanionApp.swift      앱 진입점, SwiftData + CloudKit 컨테이너
  Models/Reading.swift      기록 모델, 혈압 단계
  Utilities/                Theme(오렌지 색상), Stats, CSV
  Views/                    Home, History, AddEntry, Settings, StatsTable
  Views/Reports/            Reports(기간·필터), Trend, Range, Statistics
  Assets.xcassets/          AppIcon(1024), AccentColor
Config/                     Info.plist(추가 키), entitlements(iCloud)
docs/                       원본 사양서(docx)와 참고 스크린샷
tools/make_icon.py          앱 아이콘 생성 스크립트 (Pillow)
```
