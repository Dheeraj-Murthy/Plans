# Plans

A cross-platform offline-first task manager with Google Drive sync. Built with Flutter + Rust.

## Features

- **Offline-first**: Local SQLite via Rust, sync is optional
- **Google Drive sync**: Snapshot-based, compressed (gzip) + encrypted (AES-256-GCM)
- **NLP task input**: Type `buy groceries tomorrow at 3pm p1 @work` — parser extracts priority, project, date/time
- **Dark theme**: Always-on dark mode
- **Cross-platform**: macOS, Windows, Linux, Android, iOS

## Download

Get the latest build from [Releases](https://github.com/Dheeraj-Murthy/Plans/releases).

| Platform | File |
|----------|------|
| Android | `app-release.apk` |
| macOS | `Plans.zip` (unsigned — right-click → Open) |
| Linux | `plans-linux.tar.gz` |
| Windows | `plans-windows.zip` |

## Development

See [AGENTS.md](AGENTS.md) for full setup guide. Quick start:

```bash
cd Plans
flutter pub get
flutter run -d macos   # or android, ios, linux, windows
```

For Rust changes, rebuild the native library:

```bash
cd Plans/rust
bash build_macos.sh    # macOS
bash build_android.sh  # Android (requires cargo-ndk + NDK)
cargo build --release  # Linux / Windows
```

## Tech Stack

- **Frontend**: Flutter 3.x, Riverpod, go_router
- **Backend**: Rust (rusqlite, flutter_rust_bridge)
- **Sync**: Google Drive API (appData folder), AES-256-GCM, gzip
- **Auth**: google_sign_in (drive.appdata scope only)
