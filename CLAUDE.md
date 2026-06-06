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
