# Crash Reporting — Godot SDK Implementation Plan

**Date**: 2026-02-22
**Status**: Implemented
**SDK Version**: 1.2.0
**Language**: GDScript (Godot 4.5+)
**Related**: `ansible-horizon/docs/plans/2026-02-22-crash-reporting-sdk-logic.md` (universal spec)

---

## 1. Overview

Documents the existing HorizonCrashes manager implementation in the horizOn Godot SDK. The crashes manager captures non-fatal exceptions and fatal errors, collects contextual data (breadcrumbs, device info, custom keys), and sends structured crash reports to the horizOn backend.

**File location**: `addons/horizon_sdk/core/crashes.gd`

---

## 2. Architecture

### 2.1 Class Structure

```
RefCounted (GDScript)
    └── HorizonCrashes
```

HorizonCrashes is a plain GDScript class (not Node/AutoLoad), instantiated by the main `Horizon` autoload during SDK initialization.

### 2.2 Dependencies

| Dependency | Purpose |
|-----------|---------|
| `HorizonHttpClient` | HTTP requests (injected via `initialize()`) |
| `HorizonLogger` | SDK logging (injected via `initialize()`) |
| `HorizonAuth` | User ID fallback (optional, injected via `initialize()`) |

### 2.3 Signals

```gdscript
signal crash_reported(fingerprint: String)
signal crash_report_failed(error: String)
signal session_registered(session_id: String)
```

---

## 3. Crash Capture

### 3.1 No Automatic Capture

Godot does not provide a global unhandled exception hook equivalent to Unity's `Application.logMessageReceived`. Crash capture is **manual**:

- `report_crash(message, stack_trace?)` → submits CRASH type
- `record_exception(message, stack_trace?, extra_keys?)` → submits NON_FATAL type

Developers must wrap risky code in try/catch and call these methods explicitly.

### 3.2 Crash Types

```gdscript
enum CrashType {
    CRASH,
    NON_FATAL,
    ANR
}
```

---

## 4. Fingerprint Generation

### 4.1 Algorithm

1. If stack trace is empty → hash `"no_stack_trace"`
2. Split by newlines into frame lines
3. Normalize each frame via `_normalize_frame()`
4. Collect up to 5 non-empty normalized frames
5. Join with newlines
6. SHA-256 hash via `HashingContext`

### 4.2 Normalization Steps

| Step | What It Does |
|------|-------------|
| Strip `res://` | Remove Godot resource path prefix |
| Strip `user://` | Remove user data path prefix |
| Strip `0x[0-9a-fA-F]+` | Remove memory addresses (regex) |
| Strip `:\d+` | Remove colon-style line numbers |
| Strip `line \d+` | Remove word-style line numbers |
| Strip `at ` prefix | Remove leading "at " |
| Collapse whitespace | Replace multiple spaces with single space |

### 4.3 Hash Function

```gdscript
var ctx := HashingContext.new()
ctx.start(HashingContext.HASH_SHA256)
ctx.update(input.to_utf8_buffer())
return ctx.finish().hex_encode()
```

---

## 5. Breadcrumb Ring Buffer

### 5.1 Implementation

```gdscript
var _breadcrumbs: Array[Dictionary] = []  # Pre-allocated to 50 slots
var _breadcrumbIndex: int = 0              # Write position
var _breadcrumbCount: int = 0              # Total ever added
```

- Pre-allocated with 50 empty dictionaries at init
- Circular write: `index = (index + 1) % 50`
- Count is unbounded (tracks total, not current buffer size)

### 5.2 Breadcrumb Types

```gdscript
const BREADCRUMB_NAVIGATION := "navigation"
const BREADCRUMB_USER_ACTION := "user_action"
const BREADCRUMB_LOG := "log"
const BREADCRUMB_ERROR := "error"
const BREADCRUMB_STATE := "state"
```

### 5.3 Retrieval Logic

- If `count <= 50`: Read linearly from index 0
- If `count > 50`: Start from `_breadcrumbIndex` (oldest after wrap) and iterate circularly
- All entries `.duplicate()`'d to avoid reference issues
- Returns chronological order (oldest first)

### 5.4 Timestamps

```gdscript
Time.get_datetime_string_from_system(true, true)  # UTC, ISO 8601
```

### 5.5 Public API

- `record_breadcrumb(type, message)` — Generic
- `log(message)` — Shorthand for `BREADCRUMB_LOG` type

---

## 6. Rate Limiting

### 6.1 Configuration

```gdscript
const TOKENS_PER_MINUTE := 5
const MAX_SESSION_REPORTS := 20
const TOKEN_REFILL_INTERVAL_SEC := 60.0
```

### 6.2 Token Bucket

- Uses `Time.get_unix_time_from_system()` for timing
- Refills in discrete 60-second intervals (not continuous)
- Multiple intervals: If 120s elapsed, adds `2 * 5 = 10` tokens
- Capped at `TOKENS_PER_MINUTE` (5) via `mini()`

### 6.3 Enforcement

Two checks before submission:
1. `_tokenCount <= 0` → emit `crash_report_failed`, return false
2. `_sessionReportCount >= MAX_SESSION_REPORTS` → emit `crash_report_failed`, return false

---

## 7. Device Info

### 7.1 Cached at Init

```gdscript
_cachedDeviceInfo = {
    "os": OS.get_name(),
    "osVersion": OS.get_version(),
    "model": OS.get_model_name(),
    "locale": OS.get_locale(),
    "processorName": OS.get_processor_name(),
    "processorCount": OS.get_processor_count(),
    "godotVersion": "{major}.{minor}.{patch}",
    "renderer": RenderingServer.get_video_adapter_name(),
    "platform": OS.get_name(),
    "staticMemoryMB": int(OS.get_static_memory_usage() / 1048576)
}
```

### 7.2 Conditional Fields

Screen dimensions only added if not in headless mode:
```gdscript
if DisplayServer.get_name() != "headless":
    _cachedDeviceInfo["screenWidth"] = screen_size.x
    _cachedDeviceInfo["screenHeight"] = screen_size.y
```

---

## 8. Session Registration

### 8.1 Session ID

```gdscript
# 16 random bytes → 32-char hex string
var bytes := PackedByteArray()
for i in 16:
    bytes.append(randi() % 256)
return bytes.hex_encode()
```

### 8.2 Registration Request

- Endpoint: `POST /api/v1/app/crash-reporting/session`
- Body: `{ sessionId, userId, deviceInfo, sdkVersion: "godot-1.0.0", timestamp }`
- Called manually by developer (not automatic)
- Signal `session_registered` emitted on success

---

## 9. Custom Keys

- `Dictionary` storage, max 10 entries
- `set_custom_key(key, value)` — values auto-converted to string via `str(value)`
- New key rejected if limit reached, existing keys always updatable
- Merged into report: persistent keys + per-report extra keys (extra overrides persistent)

---

## 10. User ID Resolution

Three-level priority:
1. `_userId` (explicit override via `set_user_id()`)
2. `_auth.getCurrentUser().userId` (if signed in)
3. `"anonymous"` (fallback)

---

## 11. Report Submission

### 11.1 Request Body

```json
{
  "sessionId": "32-char-hex",
  "userId": "uuid-or-anonymous",
  "type": "CRASH",
  "message": "Error description",
  "fingerprint": "sha256-hash",
  "deviceInfo": { ... },
  "breadcrumbs": [ ... ],
  "timestamp": "ISO-8601",
  "stackTrace": "optional",
  "customKeys": { "key": "value" }
}
```

### 11.2 Endpoint

`POST /api/v1/app/crash-reporting/report`

### 11.3 Conditional Fields

- `stackTrace` only included if not empty
- `customKeys` only included if there are keys to send
- Empty strings and nulls excluded by `_toJsonExcludeEmpty()` in HTTP client

---

## 12. Differences from Universal Spec

| Aspect | Universal Spec | Godot Implementation |
|--------|---------------|---------------------|
| **Crash capture** | Automatic hooks | Manual only (no global hook in Godot) |
| **Endpoint path** | `/api/v1/app/crash-reports/*` | `/api/v1/app/crash-reporting/*` (slightly different) |
| **Device info** | 4 required fields | 12 fields (extended with engine-specific data) |
| **SDK version** | `"1.0.0"` | `"godot-1.0.0"` (platform-prefixed) |
| **Token refill** | Continuous (per-second) | Discrete (per-60s interval) |
| **Breadcrumb types** | 9 types | 5 types (navigation, user_action, log, error, state) |
| **Session registration** | Automatic (fire-and-forget) | Manual (developer calls `register_session()`) |

---

## 13. Not Implemented

- **Automatic crash capture**: Godot lacks a global unhandled exception hook
- **Offline persistence**: Failed reports are dropped (not queued locally)
- **ANR detection**: CrashType.ANR exists in enum but no detection logic
- **Auto-breadcrumbs from other managers**: Not yet wired
- **Network request breadcrumbs**: HTTP client doesn't auto-record breadcrumbs
