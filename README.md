# Nudge 🔔
> Never miss a deadline again.

Nudge is a smart task manager built for students. Share a WhatsApp message, paste text, or type it yourself — Nudge extracts the task, figures out the deadline, and keeps you on track.

Built for how students actually communicate. Plain English, Hinglish, Marathi — vague deadlines and all.

---

<!-- SECONDARY BADGES -->
<p>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" /></a>
  <img alt="Status" src="https://img.shields.io/badge/status-active-success?style=flat-square" />
  <img alt="Offline first" src="https://img.shields.io/badge/offline-first-111?style=flat-square&logo=protondrive&logoColor=white" />
  <img alt="On-device" src="https://img.shields.io/badge/on--device-NLP%20%2B%20OCR-purple?style=flat-square&logo=tensorflow&logoColor=white" />
  <img alt="Languages" src="https://img.shields.io/badge/languages-EN%20%7C%20Hinglish%20%7C%20Marathi-orange?style=flat-square&logo=googletranslate&logoColor=white" />
  <img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square&logo=github" />
</p>

Academic deadlines arrive from everywhere — WhatsApp groups, Google Classroom, college portals, verbal announcements. It's unstructured, scattered, and easy to forget. Assignments get missed. Submissions happen at 11:59 PM.

<!-- NAVIGATION -->
<p>
  <a href="#-demo"><b>Demo</b></a>
  &nbsp;·&nbsp;
  <a href="#-features"><b>Features</b></a>
  &nbsp;·&nbsp;
  <a href="#-tech-stack"><b>Tech stack</b></a>
  &nbsp;·&nbsp;
  <a href="#-how-it-works"><b>How it works</b></a>
  &nbsp;·&nbsp;
  <a href="#-screenshots"><b>Screenshots</b></a>
  &nbsp;·&nbsp;
  <a href="#-getting-started"><b>Get started</b></a>
  &nbsp;·&nbsp;
  <a href="#-roadmap"><b>Roadmap</b></a>
</p>

Share any message directly to Nudge. It reads the text, extracts the task, resolves the deadline — and saves it. No copy-pasting. No manual formatting. Just tap Share → Nudge → Save.

---

<br />

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

<br />

<!-- ============================================================ -->
<!--                            DEMO                              -->
<!-- ============================================================ -->

<h2 align="center">
  <img src="https://img.shields.io/badge/-DEMO-FF4081?style=for-the-badge&logo=youtube&logoColor=white" alt="Demo" />
</h2>

<p align="center"><i>A 30-second walkthrough: paste, parse, get reminded.</i></p>

<div align="center">

<!-- Replace with: docs/media/demo.gif -->
<img src="docs/media/demo.gif" alt="Nudge in action" width="280" />

<!-- Click-through video alternative
<a href="docs/media/demo.mp4">
  <img src="docs/media/demo-thumbnail.png" alt="Watch the demo" width="520" />
</a>
-->

</div>

<br />

<!-- ============================================================ -->
<!--                         WHY NUDGE                            -->
<!-- ============================================================ -->

<h2 align="center">
  <img src="https://img.shields.io/badge/-WHY%20NUDGE-7C4DFF?style=for-the-badge&logo=lightning&logoColor=white" alt="Why Nudge" />
</h2>

<table>
<tr>
<td width="55%" valign="top">

<br />

Students live inside group chats, PDFs, and screenshots. Deadlines hide in casual messages -

> *"kal submit karna hai"*
> *"udya report dena ahe"*
> *"reminder, viva on Friday 4pm"*

Most task apps make you stop, switch context, and **type it all in again**.

Nudge reads that noise the way a friend would, and quietly turns it into a task with a reminder. Forward a message. Share a screenshot. Speak a sentence. That's it.

</td>
<td width="45%" valign="top">

<!-- Replace with: docs/media/why-illustration.png -->
<img src="docs/media/why-illustration.png" alt="Why Nudge" width="100%" />

</td>
</tr>
</table>

<br />

<!-- ============================================================ -->
<!--                          FEATURES                            -->
<!-- ============================================================ -->

<h2 align="center">
  <img src="https://img.shields.io/badge/-FEATURES-00BFA5?style=for-the-badge&logo=star&logoColor=white" alt="Features" />
</h2>

<table>
  <tr>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-NLP-7C4DFF?style=for-the-badge" alt="NLP" />
      <h3>Smart parser</h3>
      <p>Understands English, Hinglish, and Marathi (English script). Extracts dates, times, and priorities from natural sentences.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Share-1E88E5?style=for-the-badge&logo=share&logoColor=white" alt="Share" />
      <h3>Share intent</h3>
      <p>Receive text or files from any app via the Android share sheet - instant, friction-free task creation.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-OCR-EF5350?style=for-the-badge&logo=googlelens&logoColor=white" alt="OCR" />
      <h3>OCR import</h3>
      <p>Pull deadlines straight from screenshots, posters, and notice boards using Google ML Kit.</p>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Voice-26A69A?style=for-the-badge&logo=googleassistant&logoColor=white" alt="Voice" />
      <h3>Voice input</h3>
      <p>Dictate tasks hands-free with on-device speech-to-text. Perfect for the walk between classes.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Calendar-FB8C00?style=for-the-badge&logo=googlecalendar&logoColor=white" alt="Calendar" />
      <h3>Calendar view</h3>
      <p>See deadlines laid out by day with priority-aware highlighting and quick reschedule.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Reminders-FFCA28?style=for-the-badge&logo=googletasks&logoColor=white" alt="Reminders" />
      <h3>Local reminders</h3>
      <p>Timezone-aware notifications scheduled on-device. No server, no missed pings.</p>
    </td>
  </tr>
  <tr>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Offline-616161?style=for-the-badge&logo=protondrive&logoColor=white" alt="Offline" />
      <h3>Offline-first</h3>
      <p>SQLite-backed local storage. Works on a flight, in a basement, anywhere.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Material_3-757575?style=for-the-badge&logo=materialdesign&logoColor=white" alt="Material 3" />
      <h3>Material 3</h3>
      <p>Modern, expressive UI with full dark-mode support and Google Fonts typography.</p>
    </td>
    <td align="center" width="33%" valign="top">
      <br />
      <img src="https://img.shields.io/badge/-Privacy-2E7D32?style=for-the-badge&logo=letsencrypt&logoColor=white" alt="Privacy" />
      <h3>Privacy by default</h3>
      <p>No account, no analytics, no data leaves the device. Period.</p>
    </td>
  </tr>
</table>

<br />

<!-- ============================================================ -->
<!--                         TECH STACK                           -->
<!-- ============================================================ -->

<h2 align="center">
  <img src="https://img.shields.io/badge/-TECH%20STACK-1976D2?style=for-the-badge&logo=stackshare&logoColor=white" alt="Tech stack" />
</h2>

<div align="center">

<a href="https://skillicons.dev">
  <img src="https://skillicons.dev/icons?i=flutter,dart,sqlite,androidstudio,gradle,kotlin,materialui,git,github,vscode&theme=dark" alt="Tech stack icons" />
</a>

<br /><br />

<table>
  <tr>
    <th align="left">Layer</th>
    <th align="left">Technology</th>
  </tr>
  <tr>
    <td>Framework</td>
    <td><b>Flutter</b> &nbsp; <code>3.x</code> &nbsp;·&nbsp; <b>Dart</b> &nbsp; <code>3.x</code></td>
  </tr>
  <tr>
    <td>Local database</td>
    <td><b>SQLite</b> via <code>sqflite</code></td>
  </tr>
  <tr>
    <td>OCR</td>
    <td><b>Google ML Kit</b> Text Recognition</td>
  </tr>
  <tr>
    <td>Speech-to-text</td>
    <td><code>speech_to_text</code> (on-device)</td>
  </tr>
  <tr>
    <td>NLP parsing</td>
    <td>Custom rule-based parser - EN / Hinglish / Marathi</td>
  </tr>
  <tr>
    <td>Notifications</td>
    <td><code>flutter_local_notifications</code> + <code>timezone</code></td>
  </tr>
  <tr>
    <td>Theming</td>
    <td><b>Material 3</b> + Google Fonts</td>
  </tr>
  <tr>
    <td>Platform</td>
    <td>Android (iOS/macOS/web/windows/linux scaffolding included)</td>
  </tr>
</table>

</div>

<br />

<!-- ============================================================ -->
<!--                       HOW IT WORKS                           -->
<!-- ============================================================ -->

<h2 align="center">
  <img src="https://img.shields.io/badge/-HOW%20IT%20WORKS-455A64?style=for-the-badge&logo=googleanalytics&logoColor=white" alt="How it works" />
</h2>

<p align="center"><i>From a casual message to a scheduled reminder, in three quiet steps.</i></p>

```mermaid
flowchart TD
    A["Text input<br/>Share sheet"]:::input --> P
    B["Screenshot<br/>OCR"]:::input --> P
    C["Voice input<br/>STT"]:::input --> P

    P["Task parser<br/><i>rule-based NLP</i><br/>EN · HI-EN · MR"]:::core --> S

    S["SQLite storage<br/><i>sqflite</i>"]:::store --> N

    N["Local notification<br/>scheduler<br/><i>timezone-aware</i>"]:::notify

    classDef input fill:#7C4DFF,stroke:#5E35B1,color:#fff,stroke-width:2px
    classDef core fill:#1E88E5,stroke:#1565C0,color:#fff,stroke-width:2px
    classDef store fill:#00897B,stroke:#00695C,color:#fff,stroke-width:2px
    classDef notify fill:#FB8C00,stroke:#EF6C00,color:#fff,stroke-width:2px
```

### Pipeline detail

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant App as Nudge UI
    participant Parser as Task parser
    participant DB as SQLite
    participant Notif as Notification scheduler

    U->>App: Share / type / scan / speak
    App->>Parser: Raw text
    Parser->>Parser: Tokenize · normalize · match locale keywords
    Parser-->>App: Task { title, dueAt, priority }
    App->>DB: Persist task
    DB-->>App: Task ID
    App->>Notif: Schedule reminder (timezone-aware)
    Notif-->>U: Notification at due time
```

### Examples

<div align="center">

| You write | Nudge schedules |
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

```bash
git clone https://github.com/sahiljo14/nudge-app.git
cd nudge-app

# 2. Fetch dependencies
flutter pub get

# 3. Sanity-check
flutter analyze
flutter test

# 4. Run on a connected device or emulator
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

<br /><br />

<a href="#nudge"><img src="https://img.shields.io/badge/%E2%86%91%20Back%20to%20top-111?style=flat-square" alt="Back to top" /></a>

*Built by students, for students.*
