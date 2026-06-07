# dollarBox

실시간 USD/KRW 환율을 표시하는 macOS 네이티브 앱 + 위젯

---

## 소개

dollarBox는 달러-원 환율을 빠르게 확인하기 위해 만든 macOS 앱입니다.  
메인 앱에서 환율과 차트를 보거나, 위젯으로 등록해두면 데스크탑에서 항상 확인할 수 있습니다.

---

## 주요 기능

### 메인 앱

- 실시간 환율 표시 — USD/KRW, EUR/KRW, JPY/KRW (100엔 기준)
- 전일 대비 등락폭 및 등락률 표시 (▲/▼)
- 1W / 1M / 1Y / 5Y 기간별 환율 차트
- 차트 위 드래그로 특정 날짜 환율 확인
- 최고/최저 환율 포인트 및 가격 레이블 표시
- 52주 고저 게이지 — 현재 환율의 연간 범위 내 위치 표시
- 수동 새로고침 버튼
- 테마 모드 3가지 — 라이트 / 다크 / 시스템 따름

**차트 기술 지표 (설정에서 켜고 끄기 가능)**

| 지표 | 설명 | 지원 기간 |
|------|------|-----------|
| MA 7일 | 7일 단순 이동평균 | 1M, 1Y, 5Y |
| MA 30일 | 30일 단순 이동평균 | 1Y, 5Y |
| 볼린저 밴드 | 20일 기준, 상단·중앙·하단 밴드 (±2σ) | 1M, 1Y, 5Y |
| RSI (14) | 14일 Wilder 스무딩, 0-100 스케일 | 1M, 1Y, 5Y |
| 예측선 | 최근 30일 선형 회귀 기반 단기 추세 연장 | 1M, 1Y, 5Y |
| 52W 게이지 | 52주 최고/최저 범위 내 현재 위치 | 전체 |

**환산 탭**

- 외화 입력 → 원화 자동 계산 (USD/EUR/JPY 선택)
- 원화 입력 → 외화 자동 계산
- 실시간 환율 기준으로 즉시 환산

**환전 일지 탭**

- 환전 기록 추가 — 통화쌍, 날짜, 환전 환율, 금액, 메모 입력
- 환율 필드에 현재 환율 자동 입력
- 기록 탭하면 수정, 우클릭 → 삭제
- 각 기록에 현재 환율 기준 수익률(%) 및 KRW 손익 표시
- JSON 파일로 로컬 영구 저장 (`~/Application Support/dollarBox/journal.json`)

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
| Platform | macOS 26.0+ |
| IDE | Xcode 16+ |
| Project Gen | xcodegen |

외부 라이브러리 없음 — 모두 Apple 네이티브 프레임워크만 사용

---

## 환율 데이터

Yahoo Finance 비공식 API 사용 (무료, API 키 불필요)

```
https://query1.finance.yahoo.com/v8/finance/chart/USDKRW=X
```

- 현재 환율: `range=1d&interval=1m` → `meta.regularMarketPrice`
- 전일 종가: `meta.chartPreviousClose` → 등락폭 계산에 사용
- 차트 히스토리: `range=5d|1mo|1y|5y&interval=1d|1wk` → `timestamps + closes`
- 캐시 TTL: 30분
- `updatedAt`: `timestamp` 배열 마지막 값 사용 → 요청 시각이 아닌 실제 마지막 데이터 시각 표시 (주말·공휴일 등 시장 마감 시 정직한 시각 반영)

---

## 프로젝트 구조

```
dollarBox/
├── ExchangeRateApp/
│   ├── ExchangeRateApp.swift         # 앱 진입점
│   ├── ContentView.swift             # 메인 화면 (차트, 환산, 일지, 지표, 테마)
│   ├── MenuBarView.swift             # 메뉴바 팝오버 UI
│   ├── RateMonitor.swift             # @Observable 환율 상태 관리
│   ├── SettingsView.swift            # 차트 지표 on/off 설정 화면
│   ├── JournalView.swift             # 환전 일지 탭 UI
│   ├── TradeEntry.swift              # 일지 항목 모델
│   └── TradeJournalService.swift     # 일지 CRUD + JSON 파일 저장
│
├── ExchangeRateWidgetExtension/
│   ├── ExchangeRateWidget.swift      # 위젯 등록 (Small/Medium/Large)
│   ├── ExchangeRateProvider.swift    # TimelineProvider (15분 갱신)
│   └── ExchangeRateWidgetView.swift  # 위젯 UI
│
├── Shared/
│   ├── ExchangeRate.swift            # 현재 환율 + 전일비 계산 모델
│   ├── RateDataPoint.swift           # 차트 포인트 + CurrencyPair + RatePeriod
│   └── ExchangeRateService.swift     # API 호출, 캐싱, UserDefaults 저장
│
└── project.yml                       # xcodegen 프로젝트 스펙
```

---

## 실행 방법

**요구사항**

- macOS 26.0 이상
- Xcode 16 이상
- [xcodegen](https://github.com/yonaskolb/XcodeGen) 설치

```bash
brew install xcodegen
```

**빌드**

```bash
git clone https://github.com/choitjddn0311/dollarBox.git
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
  ├── ExchangeRateService.shared
  │     ├── fetchLatestRate()    → Yahoo Finance (1d/1m) → rate + previousClose
  │     ├── fetchHistory()       → Yahoo Finance (5d|1mo|1y / 1d) → [RateDataPoint]
  │     ├── saveRate()           → UserDefaults
  │     └── loadRate()           → UserDefaults
  │
  └── 지표 계산 (ContentView 내부, 순수 Swift)
        ├── movingAverage(period:)   → MA7, MA30
        ├── bbPoints                 → 볼린저 밴드 (20일, ±2σ)
        └── rsiPoints                → RSI (14일, Wilder EMA)

ExchangeRateProvider (Widget)
  └── getTimeline()
        └── fetchHistory(week)   → entry 생성 → 15분 후 갱신 예약
```

---

## 주요 구현 포인트

**Liquid Glass 디자인 (macOS 26)**

macOS 26에서 새로 공개된 `.glassEffect(in:)` API를 활용해 패널과 버튼에 반투명 유리 효과를 적용.  
차트 내 annotation에서는 `.glassEffect`가 렌더링되지 않아 `.background(.ultraThinMaterial, in:)` 으로 대체.

**Swift Charts 멀티 시리즈 색상**

Swift Charts는 `series:` 파라미터 없이 여러 `LineMark`를 쓰면 단일 시리즈로 묶어 색상을 통일해버린다.  
MA7/MA30/BB 각 계열에 `series: .value("S", "ma7")` 형태로 고유 키를 지정해 색상 분리.

**볼린저 밴드 계산**

```swift
// 20일 표준편차 기반
let avg = slice.reduce(0, +) / Double(p)
let std = sqrt(slice.map { pow($0 - avg, 2) }.reduce(0, +) / Double(p))
upper = avg + 2 * std
lower = avg - 2 * std
```

**RSI 계산 (Wilder EMA)**

```swift
// Wilder 스무딩: 단순 이동평균 초기화 → EMA 방식으로 갱신
avgG = (avgG * Double(p - 1) + gains[i]) / Double(p)
avgL = (avgL * Double(p - 1) + losses[i]) / Double(p)
rsi  = 100 - (100 / (1 + avgG / avgL))
```

**차트 드래그 스크러빙**

`chartOverlay` + `DragGesture(minimumDistance: 0)` + `ChartProxy.value(atX:)` 조합으로  
드래그 위치에 가장 가까운 데이터 포인트를 실시간으로 하이라이트.  
RSI 서브차트도 메인 차트의 `selectedPoint`를 공유해 연동.

**테마 모드**

`@AppStorage("themeMode")`로 선택값을 영구 저장하고 `.preferredColorScheme()`으로 적용.  
앱 재실행 후에도 마지막 테마 유지.

**환산 탭 포커스 처리**

`@FocusState`로 현재 입력 필드를 추적해 `onChange`에서 역방향 갱신을 방지.  
USD 입력 중에는 KRW 필드 변경이 USD onChange를 트리거하지 않아 무한 루프 없음.

---

## 라이선스

MIT License

Copyright (c) 2026 choitjddn0311

이 소프트웨어와 관련 문서 파일(이하 "소프트웨어")을 취득하는 모든 사람에게, 소프트웨어를 제한 없이 사용할 수 있는 권한을 무료로 부여합니다.  
여기에는 소프트웨어를 사용, 복사, 수정, 병합, 출판, 배포, 서브라이선스 부여, 판매할 권리와 이를 받은 사람에게 동일한 권리를 허용할 권리가 포함됩니다.

**단, 다음 조건을 반드시 준수해야 합니다:**

> 위의 저작권 표시와 이 허가 통지는 소프트웨어의 모든 복사본 또는 상당 부분에 포함되어야 합니다.

**보증 부인:**

소프트웨어는 "있는 그대로(AS IS)" 제공되며, 명시적이든 묵시적이든 어떠한 종류의 보증도 하지 않습니다.  
여기에는 상품성, 특정 목적에 대한 적합성, 비침해에 관한 보증이 포함되나 이에 한정되지 않습니다.  
어떠한 경우에도 저자 또는 저작권 보유자는 소프트웨어나 소프트웨어의 사용 또는 기타 거래로 인해 발생하는 계약, 불법행위 또는 기타 사유로 인한 손해배상 책임을 지지 않습니다.

---

이 프로젝트는 Yahoo Finance의 비공식 API를 사용합니다. API는 공식 지원이 아니므로 서비스 구조 변경 시 데이터 수신이 중단될 수 있습니다. 상업적 목적의 활용 시에는 공식 데이터 제공 서비스를 사용하는 것을 권장합니다.
