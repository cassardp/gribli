# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gribli is a timed match-3 puzzle game (iOS, iPhone only) built with Swift/SwiftUI. No external dependencies — uses only URLSession and CryptoKit. Backend is a Cloudflare Worker (TypeScript) with D1 SQLite for the leaderboard.

## Build & Run

- Open `Gribli.xcodeproj` in Xcode and run on simulator or device
- **Do not compile from CLI** (xcodebuild/swift build) — too slow, the developer reports errors manually
- Deployment target: iOS 17.6+, portrait only
- Requires `Gribli/Secrets.swift` (gitignored) containing the HMAC key for API signing

## Backend (gribli-api/)

- Cloudflare Workers + D1, deployed via `wrangler deploy`
- `cd gribli-api && npm install` for local setup
- Single file: `src/index.ts` with all endpoints (GET/POST /scores, PUT /profile)

## Architecture

**MVVM with @Observable (iOS 17+ observation):**

- `GameViewModel` — single source of truth for all game state, timer, scoring, haptics. Persists best score and player info to UserDefaults.
- `GridEngine` — pure game logic: 8×8 grid, match detection, gravity, bomb expansion, hint finding. No UI dependencies.
- Views: `SplashView` (interactive intro with demo swipe-to-match) → `GameView` (main screen + grid + gestures) → `TileView` (individual tile rendering/animation) → `LeaderboardView` (scores, profile editing, about tab)

**Game loop:** User tap/swipe → `trySwap()` → `processCascade()` (find matches → expand bombs → apply gravity → spawn tiles → repeat until stable) → check for valid moves (shuffle if none)

**Key models:** `Tile` (id, type, row, col, isMatched, isBomb), `TileType` (6 colored circles: olive, red, orange, blue, silver, taupe), `ScoreEntry` (leaderboard row)

## Color System

All colors live in `Palette.swift` using hex initializers. Dieter Rams / Braun-inspired palette. Dark/light mode handled via `Palette.background(for:)` and `Palette.text(for:)`. Never use hardcoded colors — always go through `Palette`.

## API Integration

- `API.swift` handles all network calls with async/await
- Write operations (POST/PUT) are HMAC-SHA256 signed (body → `X-Signature` header)
- GET /scores is unsigned (public read)
- Backend validates: timestamp within ±2min, rate limits per device (30s) and per IP (10s), player name XSS filtering, score ≤ 1M

## Conventions

- `DeviceId.swift` provides a stable UUID per install (UserDefaults-persisted)
