# Nudge

> Your deadline brain. Never miss what matters.

Nudge is an offline-first Flutter app for students. It converts unstructured text from messages, screenshots, and shared documents into clean tasks with deadlines and reminders - all on-device.

## Highlights

- Smart parser for English, Hinglish, and Marathi (English script)
- Share intent support for text and files
- OCR-based extraction from images/screenshots (Google ML Kit)
- Calendar and task views with priority-aware reminders
- Local SQLite storage and local notifications
- Voice input and dark mode support

## Example inputs

- `kal submit karna hai` -> Due tomorrow
- `udya report dena ahe` -> Due tomorrow
- `submit by next Monday` -> Due next Monday

## Tech stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) |
| Local database | SQLite (`sqflite`) |
| OCR | Google ML Kit text recognition |
| NLP parsing | Custom rule-based parser |
| Notifications | `flutter_local_notifications` + `timezone` |
| Platform | Android (iOS/macOS/web/windows/linux scaffolding included) |

## Project status

- [x] Phase 1 - Core app setup + local database
- [x] Phase 2 - Manual task creation
- [x] Phase 3 - Share intent import
- [x] Phase 4 - Hinglish/Marathi deadline parsing
- [x] Phase 5 - OCR flow for images/screenshots
- [x] Phase 6 - Local deadline reminders
- [ ] Phase 7 - Optional cloud sync

## Getting started

### Prerequisites

- Flutter SDK 3.x+
- Android Studio (SDK + emulator) or a physical Android device

### Run locally

```bash
git clone https://github.com/sahiljo14/nudge-app.git
cd nudge-app
flutter pub get
flutter analyze
flutter test
flutter run
```

## License

MIT License.

Built by a student, for students.
