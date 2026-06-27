# Privacy Policy for Sendate

**Last Updated:** 27 June 2026

Sendate ("we", "us", or "our") respects your privacy and is committed to protecting it. Sendate is an open-source, offline-first, peer-to-peer file transfer and clipboard synchronization application. 

This Privacy Policy explains how our application operates and how your data is handled. Because of the nature of Sendate, **we do not collect, store, transmit, or share any of your personal data on any servers.**

## 1. Data Collection & Usage

Sendate operates entirely on your local device and your local network. We do not operate any backend servers, analytics services, or remote databases. Therefore, we do not collect any personal information, usage statistics, or telemetry.

## 2. Required Device Permissions

To provide its core functionality, Sendate requests specific device permissions. This data never leaves your local network:

### A. Local Network (mDNS/UDP)
- **Why it is needed:** To discover other devices running Sendate on the same Wi-Fi network.
- **How it is used:** Sendate broadcasts a local network packet containing your device's friendly name and an auto-generated unique ID. This allows devices to find each other for file transfers. This data is never sent to the internet.

### B. Bluetooth & Location (Android & iOS)
- **Why it is needed:** Used for discovering nearby devices via Bluetooth Low Energy (BLE) and establishing Wi-Fi Direct connections. On Android, the OS strictly requires Location permissions to scan for nearby Wi-Fi or Bluetooth devices.
- **How it is used:** Sendate strictly uses these permissions to detect nearby devices for local file transfers. **We do not track, store, or transmit your GPS location.**

### C. Storage / Files / Photos
- **Why it is needed:** To read the files you select to send, and to save the files you receive.
- **How it is used:** The app only accesses files when you explicitly select them. Received files are saved locally to your device's storage. We do not scan your files or upload them to any cloud storage.

### D. Clipboard
- **Why it is needed:** To power the "Clipboard Sync" feature.
- **How it is used:** When enabled, the app syncs your clipboard text with other connected devices on your local network. This data is transferred locally and encrypted peer-to-peer. It is never logged or transmitted over the internet.

### E. Biometrics (Face ID, Touch ID, Fingerprint)
- **Why it is needed:** To power the "App Lock" feature.
- **How it is used:** Authentication happens securely on your device using the operating system's native secure enclave. We do not have access to your biometric data.

## 3. Data Transfer and Security

All file and clipboard transfers occur peer-to-peer (directly between devices) over your local network (Wi-Fi, Hotspot, or Wi-Fi Direct). No data is ever routed through external servers or the internet. While data is sent directly over the local network, you should ensure you are connected to a trusted local network when transferring sensitive files.

## 4. Third-Party Services

Sendate does not integrate any third-party advertising, analytics, or tracking SDKs. We do not sell, rent, or share your data with anyone because we do not have access to it.

## 5. Children's Privacy

Because Sendate operates entirely locally and does not collect any data, it complies with the Children's Online Privacy Protection Act (COPPA). We do not knowingly collect personal information from anyone, including children under the age of 13.

## 6. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Since the app is open-source and offline, changes will primarily reflect updates to app store guidelines or new local features. The latest version will always be available in the app's official repository.

## 7. Contact Us

If you have any questions about this Privacy Policy, please contact us by opening an issue on our official GitHub repository.
