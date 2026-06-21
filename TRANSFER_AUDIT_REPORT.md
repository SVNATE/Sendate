# Transfer / Receive Audit Report
_Sendate — Full codebase audit of the file transfer and receive pipeline_

---

## Executive Summary

The transfer model has **13 confirmed bugs** ranging from critical data-loss issues to
subtle race conditions and missing integration points. The most severe are:

| Severity | Count |
|----------|-------|
| 🔴 Critical (data loss / silent drops) | 5 |
| 🟠 High (broken feature / hang risk)   | 4 |
| 🟡 Medium (incorrect behaviour)        | 4 |

---

## 🔴 Critical Bugs

---

### BUG-01 — Multi-file send is fully sequential; a single rejection/failure blocks ALL remaining files

**File:** `lib/services/transfer/transfer_service.dart` — `_processQueue()` / `sendFile()`  
**File:** `lib/shared/providers/transfer_service_provider.dart` — `TransferController.sendFiles()`

**Root cause:**  
`TransferController.sendFiles()` calls `_service.sendFile()` with `await` in a plain `for` loop.
`sendFile` itself blocks until the file completes (including all retries, up to ~2 min per file).
If the receiver **rejects** the first file, that awaited `sendFile` returns a `cancelled` result,
but the loop continues trying to send the remaining files using the same connection attempt —
each of which will **also** time out on connect because the other side already closed the session.

Additionally, when files are enqueued via `enqueueFiles()` / `_processQueue()`, the queue is also
fully sequential — only one file flies at a time regardless of `maxParallelTransfers = 3`.

**Impact:** In a 10-file transfer, if file #3 fails, files #4-10 each wait 30 s (transferTimeout)
for a connection that will never be accepted, causing the UI to appear stuck for minutes.

---

### BUG-02 — Receiver data reassembly is broken for large / fragmented TCP streams

**File:** `lib/services/transfer/transfer_service.dart` — `_handleIncoming()`

**Root cause:**  
```dart
// ❌ WRONG – waits for only the first 4 bytes, then breaks
await for (final data in dataStream) {
  allData.addAll(data);
  if (allData.length >= 4) break;   // ← breaks on first chunk ≥ 4 bytes
}
// ❌ WRONG – waits one chunk at a time, no loop until complete
while (allData.length < 4 + headerLength) {
  final data = await dataStream.first;  // ← .first throws if stream already done
  allData.addAll(data);
}
```

TCP is a stream protocol — a single `await for` iteration can deliver anywhere from 1 byte to
the entire file. The current code:
1. Breaks the header-read loop as soon as it has **any** 4+ bytes, even if those 4 bytes aren't
   the complete length prefix (possible on very slow links).
2. Uses `dataStream.first` (which cancels the subscription after one event) inside a `while`
   loop — after the second call, `dataStream.first` throws `StateError: Stream already listened`.
3. After the header is parsed, the "overflow" bytes (data that arrived with the header) are
   handled correctly — but the encrypted receive loop re-uses the same `dataStream` that was
   already consumed, causing it to immediately see EOF for large files.

**Impact:** Any transfer of a file > the first TCP segment (typically > 64 KB on mobile, > 1 MB on desktop) will silently corrupt or truncate the received file.

---

### BUG-03 — Encrypted send sends chunk length TWICE

**File:** `lib/services/transfer/transfer_service.dart` — `sendFile()`

**Root cause:**  
```dart
// sender — encrypted path
final encrypted = await _encryptionService.encryptChunk(...);
socket.add(_intToBytes(encrypted.length));   // ← length prefix #1
dataToSend = encrypted;
// ...
socket.add(dataToSend);                       // ← sends encrypted bytes (which ALSO start with length)
```

`encryptChunk()` in `EncryptionService` already packs its output as:
`[4-byte nonce len][nonce][4-byte mac len][mac][ciphertext]`

The receiver reads:
```dart
final chunkLen = _bytesToInt(buffer.sublist(0, 4));  // reads first 4 bytes as "length"
final encryptedChunk = buffer.sublist(4, 4 + chunkLen);
```

But the first 4 bytes the receiver actually sees are the *explicit* `_intToBytes(encrypted.length)`
prefix added by the sender BEFORE the packed chunk. So `chunkLen` is the total packed-chunk size,
which is correct — but then `_intToBytes` is sent, followed by the full packed chunk (which itself
starts with `[4-byte nonce len]`). This means the receiver interprets the nonce-length field as
the **second** chunk-length prefix, desynchronising the frame stream after the very first chunk.
Every subsequent chunk will be misread, producing garbage or a MAC-auth failure.

**Impact:** Every encrypted multi-chunk file (> ~64 KB with AES-GCM overhead) will fail to decrypt
correctly on the receiver, either producing corrupted data or a hard exception.

---

### BUG-04 — `asBroadcastStream()` is called AFTER `await for` — stream is already consumed

**File:** `lib/services/transfer/transfer_service.dart` — `_handleIncoming()`

**Root cause:**
```dart
final allData = <int>[];
final dataStream = socket.asBroadcastStream();     // creates broadcast WRAPPER

await for (final data in dataStream) {             // ← FIRST listener on broadcast
  allData.addAll(data); if (allData.length >= 4) break;
}
// ...
await for (final data in dataStream) { ... }      // later in encrypted path
```

`asBroadcastStream()` does **not** buffer past events. Any data that arrived while the first
`await for` was running (and broke early) is irrecoverably lost — it will never appear in the
second or later `await for`. This is the root cause of why overflow data is sometimes missing
even though the code attempts to track it in `overflow`.

**Impact:** On fast LANs where the sender pushes data faster than the receiver processes headers,
entire chunks of file data are silently dropped.

---

### BUG-05 — Browser receiver loads entire upload body into RAM (OOM on large files)

**File:** `lib/services/browser_receiver/browser_receiver_service.dart` — `_handleUpload()`

**Root cause:**
```dart
final bodyBytes = <int>[];
await for (final chunk in request) {
  bodyBytes.addAll(chunk);  // ← entire multipart body buffered in heap
  if (bodyBytes.length > maxBodyBytes) { ... }
}
// then: transformer.bind(Stream.value(bodyBytes))  ← also copies to new List
final parts = await transformer.bind(...).toList();  // ← parts[i].data also copied
```

A 500 MB upload creates **at least 3 copies** of the body in memory simultaneously:
`bodyBytes` + the stream passed to transformer + the `MimeMultipart.data` list.
On Android (256 MB heap limit) this reliably triggers an OOM kill mid-transfer.

**Impact:** Any file > ~150 MB sent from a browser will crash the app before saving.

---

## 🟠 High Bugs

---

### BUG-06 — `pauseTransfer` sets a flag but does NOT emit a state update

**File:** `lib/services/transfer/transfer_service.dart` — `pauseTransfer()`

**Root cause:**
```dart
void pauseTransfer(String id) => _sessions[id]?.isPaused = true;
```

Setting the flag does pause the chunk loop (correctly), but no `TransferModel` state update
is emitted. The UI is driven exclusively by `transferStream` events — so pressing Pause shows
no visual feedback; the card stays in `TransferState.sending` until the chunk loop happens to
check `isPaused` and re-emits the model itself. On a slow device or a large chunk, that can
take seconds.

---

### BUG-07 — Retry on send creates a new `_TransferSession` under the original `transferId`

**File:** `lib/services/transfer/transfer_service.dart` — `sendFile()` retry path

**Root cause:**
```dart
// In the catch block:
return sendFile(filePath: filePath, target: target, retryCount: retryCount + 1);
```

`sendFile` is called recursively. Inside, `_sessions[transferId] = session` **overwrites** the
previous (now-cancelled) session. But the retry also re-creates a brand new `TransferModel` with
`id: transferId` (same UUID). If the first attempt's `_finishTransfer` call is still in-flight
(async gap), it can call `_activeTransfers.remove(transferId)` and `_emit(t)` AFTER the retry
has already registered the new session and started emitting progress for it — removing the active
transfer prematurely.

---

### BUG-08 — Bluetooth `BluetoothTransferService` is completely disconnected from the main transfer pipeline

**File:** `lib/services/bluetooth/bluetooth_transfer_service.dart`  
**File:** `lib/shared/providers/transfer_service_provider.dart`

**Root cause:**  
`BluetoothTransferService` has its own `_transferController` stream that nobody subscribes to.
`transferServiceProvider` only wires `TransferService.transferStream` to `activeTransfersProvider`.
Bluetooth transfers never appear in the UI, never show progress, never reach history, and
`onFileReceived` (notification) is never called for BT-received files.

---

### BUG-09 — `browserReceiverPort` constant collision: same port as `persistentConnectionPort`

**File:** `lib/core/constants/app_constants.dart`

**Root cause:**
```dart
static const int browserReceiverPort = 53319;       // ← WRONG
static const int persistentConnectionPort = 53322;   // correct
```

But `AppConstants.browserReceiverPort` is `53319`, which the code comments on the next line say
is the "HTTP browser receiver" — however the comment block shows:
```
// Port 53319: distinct from transfer (53318), clipboard (53320), notification (53321)
```
in `persistent_connection_service.dart`, where it claims port 53319 IS the persistent-connection
port. In reality both services attempt to bind `53319` → the second one to start will always fail
silently, and the browser receiver snackbar will say "port may be in use."

---

## 🟡 Medium Bugs

---

### BUG-10 — `TransferController.sendFiles()` uses sequential `await sendFile()` but `enqueueFiles()` / `scheduleFiles()` bypass it entirely

**File:** `lib/shared/providers/transfer_service_provider.dart`

`scheduleFiles()` calls `_service.scheduleTransfer()` which calls `enqueueFiles()` which calls
`_processQueue()`. `_processQueue` runs transfers through `sendFile()` directly without going
through `TransferController.sendFiles()`. This means:
- The batch-complete notification (`showSendBatchComplete`) is never called for scheduled transfers.
- `autoConvertEnabled` is only synced in `sendFiles()`, not in `_processQueue()`.

---

### BUG-11 — `_uniquePath` is not async-safe (TOCTOU race condition)

**File:** `lib/services/transfer/transfer_service.dart` — `_uniquePath()`

```dart
String _uniquePath(String path) {
  var file = File(path);
  if (!file.existsSync()) return path;   // ← synchronous check
  // ...
}
```

Between `existsSync()` returning `false` and `file.openWrite()` being called, another
concurrent transfer receiving the same file name can create the file first. Result: two
simultaneous incoming files with the same name both get path `/foo/bar.jpg` — the second one
silently overwrites the first.

---

### BUG-12 — `TransferHistoryNotifier` uses a custom history-box schema incompatible with `BrowserReceiverService._saveToHistory()`

**File:** `lib/services/browser_receiver/browser_receiver_service.dart` — `_saveToHistory()`  
**File:** `lib/shared/providers/transfer_provider.dart` — `_loadFromHive()`

`BrowserReceiverService` saves to `historyBox` with keys like `'direction': 'receive'` and
`'status': 'completed'`, but `TransferHistoryNotifier._loadFromHive()` reads `'direction'` and
maps `'sent'` → sent, anything else → received, and looks for `'state'` (not `'status'`).
Browser-received files will appear in history with wrong/missing fields and `state` will default
to `TransferState.completed` (which happens to be correct), but `fileName`, `fileSize`,
`deviceName` will all be read from fields that don't exist (`map['fileSize']` → `null` → 0).

---

### BUG-13 — `progress` on receive is clamped but `bytesTransferred` can exceed `fileSize`

**File:** `lib/services/transfer/transfer_service.dart` — `_handleIncoming()`

```dart
transfer = transfer.copyWith(
  progress: (bytesReceived / fileSize).clamp(0.0, 1.0),  // clamped ✓
  bytesTransferred: bytesReceived,                         // NOT clamped ✗
);
```

With AES-GCM encryption, decrypted bytes always equal original bytes, but if a receiver reads
TCP framing incorrectly (BUG-02) and `bytesReceived` overshoots `fileSize`, the UI will show
"2.1 MB / 1.8 MB" which looks broken and can cause integer overflow when computing ETA.

---

## Fix Plan

### Phase 1 — Critical Data-Integrity Fixes (do first)

| # | Fix | Files |
|---|-----|-------|
| F-01 | Rewrite `_handleIncoming` TCP framing using a proper byte-accumulator loop, remove `asBroadcastStream`, collect all socket data into one `IOSink`-driven buffer | `transfer_service.dart` |
| F-02 | Remove the redundant `socket.add(_intToBytes(encrypted.length))` before the packed chunk in the sender encrypted path — the length prefix is already inside `encryptChunk()` output | `transfer_service.dart` |
| F-03 | Make multi-file send parallel (up to `maxParallelTransfers`) using `Future.wait` with a semaphore, so one rejection does not block other files | `transfer_service_provider.dart` |
| F-04 | Stream the browser upload body directly to a `File.openWrite()` sink instead of buffering in RAM; use a streaming multipart parser | `browser_receiver_service.dart` |

### Phase 2 — High Fixes

| # | Fix | Files |
|---|-----|-------|
| F-05 | Emit `TransferState.paused` immediately in `pauseTransfer()` via `_emit()` | `transfer_service.dart` |
| F-06 | Fix retry path: assign a new UUID for each retry attempt so old and new sessions don't share a `transferId` | `transfer_service.dart` |
| F-07 | Wire `BluetoothTransferService.transferStream` into `transferServiceProvider` listener so BT transfers appear in active/history | `transfer_service_provider.dart`, `bluetooth_transfer_service.dart` |
| F-08 | Fix port constant: `browserReceiverPort` should be a unique port (e.g. `53325`) that doesn't collide with any other service | `app_constants.dart`, `browser_receiver_service.dart` |

### Phase 3 — Medium Fixes

| # | Fix | Files |
|---|-----|-------|
| F-09 | Replace sync `_uniquePath` with an async version using `File.exists()` + a lock to prevent TOCTOU | `transfer_service.dart` |
| F-10 | Standardise the history record schema between `TransferHistoryNotifier` and `BrowserReceiverService` | `browser_receiver_service.dart`, `transfer_provider.dart` |
| F-11 | Add `autoConvertEnabled` sync inside `_processQueue()` for scheduled transfers; call `showSendBatchComplete` from queue path | `transfer_service.dart`, `transfer_service_provider.dart` |
| F-12 | Clamp `bytesTransferred` to `fileSize` on receive-complete | `transfer_service.dart` |

---

## Recommended Fix Order

```
F-02 → F-01 → F-03 → F-05 → F-08 → F-04 → F-06 → F-07 → F-09 → F-10 → F-11 → F-12
```

Start with F-02 (one line change) to unblock encryption, then F-01 (TCP framing rewrite) to
fix all receive bugs, then F-03 to fix the multi-file drop issue.
