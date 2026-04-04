# Nudge 🔔
> Never miss a deadline again.

Nudge is a smart task manager built for students. Share a WhatsApp message, paste text, or type it yourself — Nudge extracts the task, figures out the deadline, and keeps you on track.

Built for how students actually communicate. Plain English, Hinglish, Marathi — vague deadlines and all.

---

## The Problem

Academic deadlines arrive from everywhere — WhatsApp groups, Google Classroom, college portals, verbal announcements. It's unstructured, scattered, and easy to forget. Assignments get missed. Submissions happen at 11:59 PM.

## The Solution

Share any message directly to Nudge. It reads the text, extracts the task, resolves the deadline — and saves it. No copy-pasting. No manual formatting. Just tap Share → Nudge → Save.

---

## Features

- **Share to App** — share text from WhatsApp, Classroom, Notes directly into Nudge
- **Smart Parser** — extracts task name and deadline from natural language
- **Hinglish + Marathi support**
  - `"kal submit karna hai"` → Due: Tomorrow
  - `"udya report dena ahe"` → Due: Tomorrow
  - `"submit by next Monday"` → Due: Next Monday
  - `"3 din mein assignment"` → Due: In 3 days
- **Offline-first** — works without internet, always
- **Local SQLite storage** — your data stays on your device
- **Clean minimal UI** — built for speed, not clutter

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Local Database | SQLite via `sqflite` |
| NLP Parser | Rule-based with Hinglish/Marathi support |
| Share Integration | Android native intent (`ACTION_SEND`) |
| Platform | Android (iOS ready) |

---

## Roadmap

- [x] Phase 1 — Project setup and local SQLite storage
- [x] Phase 2 — Manual task input with deadline picker
- [x] Phase 3 — Share intent from WhatsApp, Classroom, Notes
- [x] Phase 4 — Hinglish + Marathi parser and date resolver
- [ ] Phase 5 — OCR from screenshots
- [ ] Phase 6 — Local push notifications
- [ ] Phase 7 — Cloud sync (optional)

---

## Getting Started

### Prerequisites
- Flutter SDK 3.x or above
- Android Studio with Android SDK
- Android device or emulator (API 21+)

### Run locally
```bash
git clone https://github.com/sahiljo14/nudge-app.git
cd nudge-app
flutter pub get
flutter run
```

### Test Share Intent (via ADB)
```bash
adb shell am start \
  -a android.intent.action.SEND \
  -t text/plain \
  --es android.intent.extra.TEXT "kal tak DSA assignment submit karna hai" \
  com.nudgeapp.nudge/.MainActivity
```

---

## Project Structure
```
nudge-app/
├── android/
│   └── app/src/main/
│       ├── kotlin/com/nudgeapp/nudge/
│       │   └── MainActivity.kt        # Share intent handler
│       └── AndroidManifest.xml        # Intent filters
├── lib/
│   ├── database/
│   │   └── db_helper.dart             # SQLite CRUD
│   ├── models/
│   │   └── task.dart                  # Task model
│   ├── parser/
│   │   ├── date_resolver.dart         # Natural language date parser
│   │   ├── rule_parser.dart           # Task + deadline extractor
│   │   └── share_handler.dart         # Platform channel for share intent
│   ├── screens/
│   │   ├── home_screen.dart           # Task list
│   │   └── add_task_screen.dart       # Add/parse task
│   ├── widgets/
│   │   └── task_card.dart             # Task UI component
│   └── main.dart                      # App entry + share intent router
└── pubspec.yaml
```

---

## License

MIT License — free to use, modify, and distribute.

---

*Built by students, for students.*
