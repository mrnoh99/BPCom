# BP Companion of Jaisung NOH

혈압(BP)을 기록하는 iOS 앱입니다. SwiftUI + SwiftData + Swift Charts, 오렌지 색상 테마, iCloud(CloudKit) 동기화.

![icon](BPCompanion/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)

## 화면 구성

| 탭 | 내용 |
|---|---|
| **Home** | 제목 *BP companion of Jaisung NOH*. `LAST 10 READINGS` (SYSTOLIC / DIASTOLIC / HR / MAP / WEIGHT 의 MAX·MIN·AVG), `YOUR LAST READINGS`. 우상단 **+** 로 입력 |
| **History** | 월별 섹션(접기/펼치기), 날짜 아이콘, 수축기/이완기(단계별 색상), 맥박, MAP, 시간, 체중, 약 복용(💊) 표시. 연필 버튼 = 편집/삭제 모드, 행을 누르면 수정 |
| **Reports** | 좌우 스와이프로 4페이지: **Summary**(MAX/MIN/AVG 표) · **Trend**(BP/HR/Weight 꺾은선 + 평균 점선) · **Range**(구간별 횟수·비율) · **Statistics**(Max/Avg/Min 막대). 상단 From/To 와 ‹ › 로 기간 이동, 하단 **D / W / M / Y / Custom**, **All / AM / PM** 필터, 📷 버튼 = 현재 페이지 이미지로 공유 |
| **Settings** | 1. **Export (CSV)** 2. **Import (CSV)** 3. **iCloud Sync** 켜기/끄기, 이름 변경, 전체 삭제 |
| **+ Add Entry** | Basic(혈압/맥박 휠 ↔ 날짜·시간 휠, Drug 스위치) · Weight(저울 눈금 + kg 휠) · Note(메모 + ★) |

혈압 색상 기준: 수축기 <90 저혈압(파랑) · 90–119 정상(초록) · 120–139 주의(주황) · ≥140 고혈압(빨강) / 이완기 <60 · 60–79 · 80–89 · ≥90.
MAP = 이완기 + (수축기 − 이완기) / 3.

## 빌드 방법

요구사항: **Xcode 16 이상**, iOS 17 이상 기기/시뮬레이터.

1. `BPCompanion.xcodeproj` 를 Xcode로 엽니다.
2. Target **BPCompanion › Signing & Capabilities** 에서 **Team** 을 선택합니다.
   필요하면 Bundle Identifier(`com.jaisungnoh.BPCompanion`)를 본인 것으로 바꿉니다.
3. iCloud 동기화를 쓰려면 같은 화면의 **iCloud** 항목에서 CloudKit 컨테이너
   `iCloud.com.jaisungnoh.BPCompanion` 를 체크(또는 + 로 생성)합니다. Bundle ID를 바꿨다면 컨테이너 이름도 `iCloud.<bundle id>` 로 맞춰 주세요.
   (Background Modes › Remote notifications, Push Notifications 는 이미 설정되어 있습니다.)
4. ▶︎ Run.

iCloud 설정이 없거나 iCloud에 로그인되어 있지 않으면 앱은 자동으로 기기 내 저장소만 사용합니다.
Settings 의 iCloud Sync 스위치 변경은 앱을 다시 실행해야 적용됩니다.
App Store 배포 시에는 CloudKit Console에서 스키마를 Production 으로 Deploy 해야 합니다.

## CSV 형식

```
date,systolic,diastolic,pulse,weight,drug,note,starred
2026-11-19 06:54,141,95,66,84.5,1,,0
```

가져오기 시 `date, systolic, diastolic` 열은 필수이며, 같은 시각·같은 값의 중복 기록은 건너뜁니다.

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
