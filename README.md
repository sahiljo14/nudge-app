# Nudge

> Never miss a deadline again.

Nudge is a smart task manager built for students. Share a message, paste a screenshot, or type it yourself — Nudge extracts the task, figures out the deadline, and reminds you before it's too late.

It works with how students actually communicate. Plain English, Hinglish, Marathi in English script, vague deadlines — Nudge handles all of it.

## The Problem

Students get academic information from everywhere — messages, screenshots, PDFs, college portals. It's unstructured, easy to lose, and hard to act on. Deadlines get missed. Assignments get forgotten.

## The Solution

Nudge turns any unstructured input into a clean, organized task with a deadline and a reminder. No manual formatting. No extra effort.

## Features

- Input from messages, screenshots, or manual entry
- Auto-extracts task name, deadline, and priority
- Understands natural language including Hinglish and Marathi in English
  - "kal submit karna hai" → Due: Tomorrow
  - "udya report dena ahe" → Due: Tomorrow
  - "submit by next Monday" → Due: Next Monday
- Offline-first — works without internet
- Local reminders before every deadline
- Clean, fast, minimal UI built for students

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) |
| Local Database | SQLite via sqflite |
| OCR | Google ML Kit |
| NLP Parser | Rule-based + AI fallback |
| Platform | Android (iOS ready) |

## Roadmap

- [x] Phase 1 — Project setup and local SQLite storage
- [x] Phase 2 — Manual task input with deadline picker
- [x] Phase 3 — Share intent and message input
- [x] Phase 4 — Smart Hinglish parser and date resolver
- [ ] Phase 5 — OCR from screenshots
- [ ] Phase 6 — Local push notifications
- [ ] Phase 7 — Cloud sync (optional)

## Getting Started

### Prerequisites

- Flutter SDK 3.x or above
- Android Studio (for Android SDK and emulator)
- Android device or emulator running API 21+

### Run locally
```bash
git clone https://github.com/yourusername/nudge-app.git
cd nudge-app
flutter pub get
flutter run
```

## License

MIT License — free to use, modify, and distribute.

---

Built by a student, for students.
>>>>>>> add7baaee39c81038b481f2c0f18f56b11d12f16
