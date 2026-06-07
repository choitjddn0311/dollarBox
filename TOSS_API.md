# Toss Invest Open API 검토 노트

> 작성일: 2026-06-07
> 상태: 출시 전 (사전 신청 대기 중)
> 목적: dollarBox 주식 기능 통합 참고용

---

## 기본 스펙

| 항목 | 내용 |
|------|------|
| Base URL | `https://openapi.tossinvest.com` |
| 인증 방식 | OAuth2 `client_credentials` |
| 프로토콜 | REST + WebSocket |
| 계정 헤더 | `X-Tossinvest-Account: {accountSeq}` |

---

## 확인된 엔드포인트

```
POST /oauth2/token           → 액세스 토큰 발급
GET  /api/v1/accounts        → 계좌 목록 조회
POST /api/v1/orders          → 주문 (BUY/SELL, LIMIT/MARKET)
GET  /v1/holdings            → 보유 종목 + 수익률
```

### 토큰 발급 예시
```python
token = requests.post(
    "https://openapi.tossinvest.com/oauth2/token",
    data={
        "grant_type": "client_credentials",
        "client_id": os.environ["TOSS_CLIENT_ID"],
        "client_secret": os.environ["TOSS_CLIENT_SECRET"],
    },
).json()["access_token"]
```

### 보유 종목 조회 응답 예시
```json
{
  "items": [
    {
      "name": "종목명",
      "quantity": 10,
      "profitLoss": {
        "rate": 0.0523
      }
    }
  ]
}
```

### 주문 예시
```python
requests.post(
    "https://openapi.tossinvest.com/api/v1/orders",
    headers={
        "Authorization": f"Bearer {token}",
        "X-Tossinvest-Account": str(account_seq)
    },
    json={
        "clientOrderId": "dca-AAPL-20260607",
        "symbol": "AAPL",
        "side": "BUY",
        "orderType": "MARKET",
        "quantity": "1",
    },
)
```

---

## 이용 제약 사항

### 결정적 제약
- **외부 배포 및 상업적 사용 금지** — 본인 매매 목적으로만 사용 가능. dollarBox를 공개 배포하거나 App Store에 올릴 경우 이 API 사용 불가.
- **입출금·환전 불가** — USD/KRW 환율 소스로 사용 불가. 기존 Frankfurter API 유지 필요.
- **만 19세 미만 사용 불가**

### 운영 리스크
- API 호출 한도는 사전 고지 없이 변경될 수 있음
- 시세 데이터는 지연 또는 오차 가능
- 시스템 점검·장애 시 응답 지연/중단 가능

### API Key 관리
- 본인만 사용, 제3자 노출 금지
- Key 유출로 인한 손실은 본인 책임
- **macOS Keychain에 저장 필수** (앱 번들 하드코딩 절대 금지)

---

## 사전 신청 절차

1. 토스증권 계좌 보유 필수
2. 사전 신청 후 순차 대기 (신청 순서대로 열림)
3. 순서 도래 시 알림톡으로 안내
4. API Key 발급은 **토스증권 PC**에서만 가능
5. 신청 시점과 Key 발급 시점은 다를 수 있음

---

## dollarBox 통합 계획

### 추가 가능한 기능

| 기능 | 엔드포인트 | 비고 |
|------|-----------|------|
| 보유 주식 목록 + 수익률 표시 | `GET /v1/holdings` | 메뉴바/위젯에 표시 |
| 보유 해외주식 KRW 환산 | holdings × 환율 | Frankfurter 환율 활용 |
| 계좌 잔고 표시 | `GET /api/v1/accounts` | |
| 메뉴바 빠른 주문 | `POST /api/v1/orders` | |

### 불가능한 것
- USD/KRW 환율 소스 교체 (환율 전용 엔드포인트 없음)
- 앱 공개 배포 상태에서 API 사용

---

## 목표 아키텍처

```
Main App
├── KeychainService          ← client_id, client_secret, API Key 저장
├── TossAuthService          ← 토큰 발급/갱신 (@Observable)
├── TossPortfolioService     ← holdings, accounts 조회
├── ExchangeRateService      ← 기존 Frankfurter 유지
└── App Group UserDefaults
         ↓ 읽기 전용
Widget Extension
```

**핵심 원칙:**
- 토큰 발급/갱신은 Main App에서만
- Widget Extension은 UserDefaults에서 캐시된 데이터만 읽음
- 인증 정보는 반드시 Keychain 경유

---

## 개발 순서 (API Key 발급 전 준비 가능)

1. `KeychainService` 구현
2. `TossAuthService` mock 구현 (토큰 발급 흐름)
3. `TossPortfolioService` mock 데이터로 UI 개발
4. 포트폴리오 뷰 SwiftUI 구현
5. API Key 발급 후 실제 엔드포인트 연결
