<p align="center">
  <img src="assets/icons/tray_icon.png" alt="Sendate Logo" width="120" />
</p>

<h1 align="center">Sendate</h1>

<p align="center">
  <strong>Privacy-first, offline-first, cross-platform file transfer.</strong><br/>
  Transfer anything between any device — no accounts, no cloud, no tracking.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#platforms">Platforms</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a>
</p>

---

## Why Sendate?

Most file transfer apps require accounts, upload your files to the cloud, or track your activity. Sendate does none of that. It creates direct device-to-device connections over your local network — your files never leave your hands.

- **No cloud** — Files transfer directly between devices
- **No accounts** — Start sharing instantly
- **No tracking** — Zero telemetry, zero analytics
- **No internet required** — Works entirely on your local network

## Features

### Core Transfer
- 📁 **File & folder transfer** — Send any file type, any size
- ⚡ **Chunk-based transfer engine** — Fast, resumable transfers with auto-retry
- 🔄 **Transfer resume** — Pick up where you left off if connection drops
- 📊 **Real-time progress** — Live transfer status and speed indicators

### Discovery & Connectivity
- 🔍 **Auto device discovery** — Finds nearby devices via UDP/TCP/mDNS
- 📱 **QR code pairing** — Instant device pairing with QR scan
- 🌐 **Wi-Fi Direct** — Connect without a shared network
- 🔗 **Bluetooth fallback** — Works even without Wi-Fi
- 🌍 **Browser receiver** — Send files to any device with a web browser

### Security
- 🔒 **End-to-end encryption** — TLS 1.3 + AES-256 for all transfers
- ✅ **Device verification** — Trust devices with visual confirmation
- 🛡️ **Biometric lock** — Protect the app with fingerprint/face
- 🚫 **Device blocking** — Block unwanted devices permanently

### Smart Features
- 📋 **Clipboard sync** — Auto-sync clipboard across paired devices
- 💬 **Device messaging** — Send quick messages between devices
- 📂 **Folder sync** — Keep folders synchronized across devices
- 🔔 **Notification sync** — Mirror notifications across devices
- 🖥️ **System tray** — Runs quietly in the background on desktop
- ⏰ **Transfer expiry** — Auto-cleanup of received files

### User Experience
- 🎨 **Material 3 UI** — Modern, clean interface with dark mode
- 🚀 **Onboarding flow** — Get started in seconds
- 📜 **Transfer history** — Full log of past transfers
- ⚙️ **Auto-accept** — Skip approval for trusted devices

## Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ Supported |
| iOS      | ✅ Supported |
| macOS    | ✅ Supported |
| Windows  | ✅ Supported |
| Linux    | ✅ Supported |

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.11.5+)
- Dart SDK (bundled with Flutter)
- Platform-specific toolchains (Xcode for iOS/macOS, Android Studio for Android)

### Installation

```bash
# Clone the repository
git clone https://github.com/SVNATE/Sendate.git
cd Sendate

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build for Release

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release
```

## Architecture

Sendate follows **Clean Architecture** with a **Feature-First** organization and **Domain-Driven Design** principles.

```
lib/
├── core/                 # App-wide config, theme, router, shell
├── features/             # Feature modules
│   ├── connect/          # Device connection & pairing
│   ├── devices/          # Device management
│   ├── folder_sync/      # Folder synchronization
│   ├── history/          # Transfer history
│   ├── messaging/        # Device-to-device messaging
│   ├── onboarding/       # First-launch onboarding
│   ├── receive/          # File receiving
│   ├── send/             # File sending
│   └── settings/         # App settings & preferences
├── services/             # Core services
│   ├── bluetooth/        # Bluetooth connectivity
│   ├── browser_receiver/ # Browser-based file receiving
│   ├── clipboard/        # Clipboard sync engine
│   ├── conversion/       # File format conversion
│   ├── discovery/        # Device discovery (UDP/TCP/mDNS)
│   ├── network/          # Network monitoring
│   ├── security/         # E2E encryption (TLS 1.3 + AES-256)
│   ├── transfer/         # Chunk-based transfer engine
│   └── wifi_direct/      # Wi-Fi Direct connections
└── shared/               # Shared models, providers, widgets
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter |
| State Management | Riverpod |
| Routing | GoRouter |
| Local Storage | Hive |
| Encryption | TLS 1.3 + AES-256 |
| UI | Material 3 |

## Contributing

Contributions are welcome! Here's how to get involved:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- Follow [Effective Dart](https://dart.dev/effective-dart) style guidelines
- Use Clean Architecture patterns (domain → data → presentation)
- Write meaningful commit messages
- Keep PRs focused on a single feature or fix

## Roadmap

- [ ] Nearby Share / AirDrop protocol interop
- [ ] File compression before transfer
- [ ] Batch transfer queue
- [ ] Transfer scheduling
- [ ] Plugin system for extensibility

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Built with ❤️ by [SVNATE](https://github.com/SVNATE)

---

<p align="center">
  <sub>Sendate — Because your files are yours.</sub>
</p>
