# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**dollarBox** — project is in initial setup; update this file once the stack and structure are established.

# CLAUDE.md

## Project Overview

Build a macOS Widget application that displays the real-time USD/KRW exchange rate.

The project should run locally on macOS through Xcode without any deployment requirements.

The widget must appear in the macOS Widget Center and automatically refresh exchange rate data at regular intervals.

---

## Goals

* Display current USD → KRW exchange rate
* Show last updated timestamp
* Support automatic background refresh
* Work entirely on local development environment
* Follow native macOS design guidelines

---

## Tech Stack

### Language

Swift 5+

### UI Framework

SwiftUI

### Widget Framework

WidgetKit

### Networking

URLSession

### Data Storage

UserDefaults with App Groups

### IDE

Xcode

### Platform

macOS

---

## Architecture

Project Structure:

ExchangeRateWidget/
├── ExchangeRateApp/
│   ├── Views/
│   ├── Models/
│   ├── Services/
│   └── App.swift
│
├── ExchangeRateWidgetExtension/
│   ├── Provider/
│   ├── Timeline/
│   ├── WidgetView/
│   └── Widget.swift
│
└── Shared/
├── ExchangeRateModel.swift
└── ExchangeRateService.swift

---

## Features

### Main App

* Fetch USD/KRW exchange rate
* Save latest exchange rate into shared storage
* Display current exchange rate
* Manual refresh button

### Widget

* Read latest exchange rate from shared storage
* Display:

  * USD/KRW rate
  * Last updated time
* Support Small widget size
* Support Medium widget size

### Refresh Behavior

* Widget refresh every 15–30 minutes
* Fetch latest data using TimelineProvider

---

## Exchange Rate API

Use a free public API.

Preferred:

https://api.frankfurter.app/latest?from=USD&to=KRW

Expected Response:

{
"amount": 1.0,
"base": "USD",
"date": "2026-01-01",
"rates": {
"KRW": 1385.42
}
}

---

## UI Requirements

Widget Layout:

Large Text:
"1 USD = 1385.42 KRW"

Secondary Text:
"Updated 14:25"

Design:

* Native Apple style
* Clean typography
* Minimal layout
* Dark mode support
* Light mode support

---

## Data Model

struct ExchangeRate: Codable {
let rate: Double
let updatedAt: Date
}

---

## Networking Requirements

Create ExchangeRateService:

Functions:

* fetchLatestRate()
* saveRate()
* loadRate()

Use async/await where possible.

Handle:

* Network failure
* API timeout
* Invalid response

---

## Widget Timeline

Timeline refresh interval:

15 minutes

Generate placeholder data when network is unavailable.

---

## Development Constraints

* No third-party libraries
* No Firebase
* No backend server
* No deployment configuration
* Local execution only

Use only:

* SwiftUI
* WidgetKit
* Foundation
* URLSession

---

## Expected Result

When the widget is added to macOS Widget Center, it should display:

1 USD = 1385.42 KRW

Updated 14:25

and automatically refresh throughout the day.

---

## 향후 주식 기능 추가 시 리팩토링 계획

현재 차트/지표 코드는 환율 전용으로 ContentView에 통합되어 있음.
주식 API를 붙일 때 아래 작업이 필요하다는 걸 기억할 것.

### 지금 재사용 가능한 것 (건드리지 말 것)
- `RateDataPoint` — date + rate 구조, 주식에도 그대로 사용 가능
- `PatternMatchView` — `[RateDataPoint]` 입력, 범용
- `HeatmapView` — `[RateDataPoint]` 입력, 범용
- MA / BB / RSI / 예측선 계산 수학 — 공식 자체는 종목 무관

### 주식 추가 시 리팩토링해야 할 것
1. **차트 UI 분리** — ContentView에 박힌 차트를 독립 `ChartView` 컴포넌트로 추출
2. **서비스 레이어 프로토콜화** — `ExchangeRateService`를 `PriceDataService` 프로토콜로 추상화, FX/주식 각각 구현
3. **InvestView KRW 의존성 제거** — `CurrencyPair` 대신 범용 `Asset` 타입으로 교체
4. **`ExchangeRate` 모델 분리** — FX 전용 필드(previousClose, changePercent)를 범용 모델과 분리

### 판단 근거
기능 추가가 계속되는 지금 단계에서 추상화하면 복잡도만 높아짐.
주식 기능을 실제로 붙이기 직전에 이 섹션을 보고 리팩토링 후 진행할 것.
