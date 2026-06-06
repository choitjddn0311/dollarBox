# dollarBox

실시간 USD/KRW 환율을 표시하는 macOS 네이티브 앱 + 위젯

---

## 소개

dollarBox는 달러-원 환율을 빠르게 확인하기 위해 만든 macOS 앱입니다.  
메인 앱에서 환율과 차트를 보거나, 위젯으로 등록해두면 데스크탑에서 항상 확인할 수 있습니다.

---

## 주요 기능

### 메인 앱

- 실시간 USD/KRW 환율 표시
- 1주일 / 1개월 / 1년 기간별 환율 차트
- 차트 위 드래그로 특정 날짜 환율 확인
- 최고/최저 환율 포인트 표시
- 수동 새로고침 버튼
- 테마 모드 3가지 — 라이트 / 다크 / 시스템 따름

### macOS 위젯

- Widget Center에서 추가 가능
- Small: 현재 환율 + 스파크라인
- Medium: 환율 + 주간 차트
- Large: 환율 + 풀 차트
- 15분마다 자동 갱신

---

## 스크린샷

> 앱 실행 후 캡처 예정

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Widget | WidgetKit |
| Chart | Swift Charts |
| Networking | URLSession (async/await) |
| Storage | UserDefaults |
| Platform | macOS 14.0+ |
| IDE | Xcode 15+ |
| Project Gen | xcodegen |

외부 라이브러리 없음 — 모두 Apple 네이티브 프레임워크만 사용

---

## 환율 데이터

Yahoo Finance 비공식 API 사용 (무료, API 키 불필요)

```
https://query1.finance.yahoo.com/v8/finance/chart/USDKRW=X
```

- 현재 환율: `range=1d&interval=1m` → `meta.regularMarketPrice`
- 차트 히스토리: `range=5d|1mo|1y&interval=1d` → `timestamps + closes`
- 캐시 TTL: 30분

---

## 프로젝트 구조

```
dollarBox/
├── ExchangeRateApp/
│   ├── ExchangeRateApp.swift       # 앱 진입점
│   └── ContentView.swift           # 메인 화면 (차트, 드래그, 테마)
│
├── ExchangeRateWidgetExtension/
│   ├── ExchangeRateWidget.swift    # 위젯 등록 (Small/Medium/Large)
│   ├── ExchangeRateProvider.swift  # TimelineProvider (15분 갱신)
│   └── ExchangeRateWidgetView.swift # 위젯 UI
│
├── Shared/
│   ├── ExchangeRate.swift          # 현재 환율 데이터 모델
│   ├── RateDataPoint.swift         # 차트 포인트 + RatePeriod 열거형
│   └── ExchangeRateService.swift   # API 호출, 캐싱, UserDefaults 저장
│
└── project.yml                     # xcodegen 프로젝트 스펙
```

---

## 실행 방법

**요구사항**

- macOS 14.0 이상
- Xcode 15 이상
- [xcodegen](https://github.com/yonaskolb/XcodeGen) 설치

```bash
brew install xcodegen
```

**빌드**

```bash
git clone <repo-url>
cd dollarBox

# Xcode 프로젝트 생성
xcodegen generate

# Xcode 열기
open ExchangeRateWidget.xcodeproj
```

Xcode에서:
1. Signing & Capabilities → Team을 본인 Apple ID로 설정 (App + Widget Extension 둘 다)
2. 상단 Scheme을 `dollarBox`로 선택
3. `Cmd+R` 실행

**위젯 추가**

앱을 한 번 실행한 뒤 → 데스크탑 우클릭 → Edit Widgets → dollarBox 검색 → 추가

---

## 아키텍처

```
ContentView
  └── ExchangeRateService.shared
        ├── fetchLatestRate()    → Yahoo Finance (1d/1m)
        ├── fetchHistory()       → Yahoo Finance (5d|1mo|1y / 1d)
        ├── saveRate()           → UserDefaults
        └── loadRate()           → UserDefaults

ExchangeRateProvider (Widget)
  └── getTimeline()
        └── fetchHistory(week)   → entry 생성 → 15분 후 갱신 예약
```

---

## 주요 구현 포인트

**차트 드래그 스크러빙**

`chartOverlay` + `DragGesture(minimumDistance: 0)` + `ChartProxy.value(atX:)` 조합으로 드래그 위치에 가장 가까운 데이터 포인트를 실시간으로 하이라이트.

**AreaMark 기준선**

`AreaMark(yStart: yDomain.lowerBound, yEnd: rate)` 패턴으로 y=0 기준선 대신 데이터 최솟값을 기준으로 설정 — 환율처럼 0 근처가 아닌 데이터에서 그래디언트가 자연스럽게 표시됨.

**테마 모드**

`@AppStorage("themeMode")`로 선택값을 영구 저장하고 `.preferredColorScheme()`으로 적용. 앱 재실행 후에도 마지막 테마 유지.

**위젯 데이터 공유**

App Group 없이 위젯이 직접 Yahoo Finance API를 호출. 서명 복잡도 없이 동일한 데이터 확보.

---

## 라이선스

MIT
