# Transfer Progress Screen & Saved Selections — Implementation Plan

## Overview
Two parallel features:

1. **Transfer Progress Screen** — A dedicated full-screen view that opens immediately when the user initiates a send, showing real-time per-file progress with pause/resume/cancel controls.  Works on Android, iOS, macOS, Windows, Linux.

2. **Save Selection Feature** — Lets users name and persist a set of files as a "selection preset" so the same collection can be re-loaded and sent again without re-picking files every time.

---

## Feature 1 — Transfer Progress Screen

### Current state (gap analysis)
| What exists | What is missing |
|---|---|
| `TransferModel` with full progress fields | No dedicated progress *screen* — progress shown only in a floating bottom sheet (`ActiveTransfersSheet`) |
| `activeTransfersProvider` (live state) | Sheet is barely visible, easily dismissed, no per-file detail |
| `TransferController.sendFiles()` | Navigation to progress screen after send is triggered |
| Pause / resume / cancel in `TransferService` | No elapsed-time timer, no ETA calculation in UI |

### Architecture
```
SendScreen._executeSend()
  └─► TransferController.sendFiles()         ← existing
  └─► context.push('/transfer-progress', extra: TransferProgressArgs(...))

/transfer-progress  (GoRoute, non-shell, full-screen)
  └─► TransferProgressScreen (ConsumerStatefulWidget)
        ├─ watches activeTransfersProvider
        ├─ _TransferProgressCard per file (animated progress bar, speed, ETA)
        ├─ Pause / Resume / Cancel per item
        ├─ "All done" summary state with Done button
        └─ WillPopScope — warns if transfers still active
```

### Files to create / modify
| File | Action |
|---|---|
| `lib/features/send/presentation/screens/transfer_progress_screen.dart` | **CREATE** |
| `lib/core/router/app_router.dart` | Add `/transfer-progress` non-shell GoRoute |
| `lib/features/send/presentation/screens/send_screen.dart` | Navigate to progress screen in `_executeSend` and `_broadcastSend` |
| `lib/shared/providers/transfer_provider.dart` | Add `transferSessionIdsProvider` — tracks the IDs sent in *this* session |

### Screen states
- **Active** — spinning indicator, animated LinearProgressIndicator per file, speed (KB/s or MB/s), ETA
- **All complete** — green checkmark summary, total transferred, elapsed time, "Done" and "Send More" buttons
- **Mixed (some failed)** — red badge on failed items; retry button per item
- **Cancelled** — immediate pop back with snackbar

### Platform notes
No platform-specific code needed — `TransferModel` fields already carry all data.  The screen is pure Flutter and works identically on all 5 platforms.

---

## Feature 2 — Save Selection

### Current state (gap analysis)
| What exists | What is missing |
|---|---|
| `selectedFilesProvider` (in-memory, reset after send) | No way to persist a named preset |
| `FilePicker` integration | No "Save this selection" button |
| Hive already initialised for other boxes | No Hive box for saved selections |

### Architecture
```
lib/features/send/
  data/
    saved_selection_repository.dart    ← Hive read/write
  domain/
    saved_selection_model.dart         ← immutable model
  presentation/
    widgets/
      saved_selections_sheet.dart      ← bottom-sheet list UI
      save_selection_dialog.dart       ← dialog to name a preset
lib/shared/providers/
    saved_selections_provider.dart     ← StateNotifier + Hive persistence
```

### SavedSelectionModel
```dart
class SavedSelectionModel {
  final String id;          // uuid
  final String name;        // user-defined label e.g. "Work Docs"
  final List<String> paths; // absolute file paths
  final DateTime savedAt;
}
```
Stored in Hive box `'saved_selections'` as JSON maps.

### User flow
1. User picks files → `selectedFilesProvider` populated.
2. User taps **"Save Selection"** button (new button in `_SelectedFilesPreview` toolbar).
3. `SaveSelectionDialog` prompts for a name → taps Save.
4. Selection persisted to Hive via `SavedSelectionsNotifier.add()`.
5. Later: User taps **"Saved"** icon in `SendScreen` AppBar → `SavedSelectionsSheet` opens.
6. User taps a preset → `selectedFilesProvider` re-loaded (files that still exist on disk).
7. Missing files shown with a warning badge; user can remove stale entries.

### Files to create / modify
| File | Action |
|---|---|
| `lib/features/send/domain/saved_selection_model.dart` | **CREATE** |
| `lib/features/send/data/saved_selection_repository.dart` | **CREATE** |
| `lib/shared/providers/saved_selections_provider.dart` | **CREATE** |
| `lib/features/send/presentation/widgets/save_selection_dialog.dart` | **CREATE** |
| `lib/features/send/presentation/widgets/saved_selections_sheet.dart` | **CREATE** |
| `lib/features/send/presentation/screens/send_screen.dart` | Add Save & Load buttons |
| `lib/main.dart` | Open `saved_selections` Hive box on startup |
| `lib/core/constants/app_constants.dart` | Add `savedSelectionsBox` constant |

---

## Implementation Order
1. `SavedSelectionModel` + `AppConstants` box name
2. `SavedSelectionsProvider` (Hive persistence)
3. `SaveSelectionDialog` widget
4. `SavedSelectionsSheet` widget
5. Wire into `SendScreen`
6. `TransferProgressScreen` (standalone screen)
7. Route + navigation wiring in `SendScreen`

## Testing checklist
- [ ] Save a selection, restart app, verify it reloads
- [ ] Load a selection where one file was deleted → warning shown, others load fine
- [ ] Delete a saved selection
- [ ] Progress screen appears after send
- [ ] Pause/resume/cancel works on progress screen
- [ ] All-complete state shows after last file finishes
- [ ] Back navigation warns if transfer still in progress
- [ ] Broadcast send (multiple devices) shows all transfers in progress screen
