# Croissante

Croissante is an iOS app for learning French vocabulary through spaced repetition, multilingual support, and a more tactile, thoughtful study experience.

## Features

- Spaced repetition system (SRS) for daily review
- CEFR-based word levels from A1 to C2
- Conjugation-aware search
- French example sentences with English, Chinese, and Hindi support
- Home Screen widget for daily word practice
- Spotlight integration for faster lookup
- iCloud sync for learning progress
- Premium pronunciation powered by OpenAI TTS
- Multiple app icon styles and personalization options

## Why I Built This

Most vocabulary apps feel mechanical.  
Croissante is an attempt to make French learning feel calmer, more visual, and easier to stick with every day.

## Tech Stack

- SwiftUI
- WidgetKit
- StoreKit 2
- iCloud Key-Value Sync
- OpenAI Audio / TTS API
- Teenybase + Cloudflare Workers (backend)

## Project Structure

- `Croissante/` – core app models, services, and views
- `CroissanteApp/` – app entry and assets
- `CroissanteWidget/` – widget extension
- `backend/` – optional backend services

## Running Locally

1. Open `Croissante.xcodeproj` in Xcode.
2. Select the `Croissante` scheme.
3. Run on an iPhone simulator or physical device.
4. If you want to test premium pronunciation, add your own `OpenAIAPIKey` locally and do not commit it.
5. If needed, run the optional backend from `backend/`.

## Roadmap

- Improve onboarding and gesture guidance
- Expand the French word dataset
- Refine progress tracking and sync behavior
- Continue polishing the app’s visual design

## Status

Croissante is actively under development.

## License

All rights reserved.
This repository is shared for reference only.
