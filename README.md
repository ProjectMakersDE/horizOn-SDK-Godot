<p align="center">
  <a href="https://horizon.pm">
    <img src="https://horizon.pm/media/images/og-image.png" alt="horizOn - Game Backend & Live-Ops Dashboard" />
  </a>
</p>

# horizOn SDK for Godot

[![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.8.0-orange)](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases)

Official Godot SDK for **horizOn** Backend-as-a-Service by [ProjectMakers](https://projectmakers.de).

## Features

| Feature | Description |
|---------|-------------|
| 🔐 **Authentication** | Email, anonymous, Google, and Apple sign-in/sign-up |
| 🏆 **Leaderboards** | Submit scores, get rankings, view top players |
| ☁️ **Cloud Saves** | Save and load player progress (JSON or binary) |
| 🔄 **Realtime** | Optional Cloud invalidations for inbox, friends, groups, matches and chat; HTTP content reload |
| ⚙️ **Remote Config** | Server-side configuration values |
| 🌐 **Localization** | Server-side translations in 15 languages |
| 📰 **News** | In-game news and announcements |
| 🎁 **Gift Codes** | Validate and redeem promotional codes, unlock cosmetics |
| 🧑 **Player Profile** | Avatar, frame and badges per player, shown on leaderboards |
| 📈 **Statistics** | One session batch for sum/max/min/last counters with optional UTC daily/weekly resets |
| 📬 **Inbox** | Bounded personal/project notifications, read/remove and atomic Player Values claims |
| 👥 **Friends** | Exact public lookup, explicit request actions and private own-player relationships |
| 🛡️ **Groups** | Explicit guild/team membership, roles, private data and bounded member pages |
| ✅ **Validated Actions** | Server-checked runs: single-use tickets, server seed, rule checks before a score is written |
| 💬 **Feedback** | Submit bug reports and feature requests |
| 📊 **User Logs** | Server-side player event tracking |
| 💥 **Crash Reporting** | Automatic crash capture, exception tracking, breadcrumbs |
| ✉️ **Email Sending** | Send transactional emails to players with templates and scheduling |

## Requirements

- Godot 4.5 or later
- horizOn API key ([Get one at horizon.pm](https://horizon.pm))

## Installation

### Option 1: GitHub Release ZIP (Recommended)

1. Download `horizOn-SDK-vX.Y.Z.zip` from the [latest release](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases/latest)
2. Unzip it and move the `horizon_sdk` folder into your project's `addons` directory, so the plugin lives at `res://addons/horizon_sdk/`
3. Enable the plugin in **Project > Project Settings > Plugins**

### Option 2: Manual Copy from the Repository

1. Clone or download this repository
2. Copy the `addons/horizon_sdk` folder to your project's `addons` directory
3. Enable the plugin in **Project > Project Settings > Plugins**

### Godot Asset Library

The SDK is not listed in the Godot Asset Library at the moment. Install it with one of the options above.

## Quick Start

> **[Quickstart Guide on horizon.pm](https://horizon.pm/quickstart#godot)** - Interactive setup guide with step-by-step instructions.

### 1. Import Configuration

Download your config JSON from the [horizOn Dashboard](https://horizon.pm) and import it:

**Project > Tools > horizOn: Import Config...**

### 2. Connect and Authenticate

```gdscript
extends Node

func _ready():
    # Connect to the best available server
    var connected = await Horizon.connect_to_server()
    if not connected:
        print("Failed to connect!")
        return

    # Quick anonymous sign-in
    var signed_in = await Horizon.quickSignInAnonymous("Player1")
    if signed_in:
        print("Welcome, %s!" % Horizon.getCurrentUser().displayName)
```

### 3. Use SDK Features

```gdscript
# Submit a score
await Horizon.leaderboard.submitScore(1000)

# Get top 10 players
var top_players = await Horizon.leaderboard.getTop(10)

# Save game data
await Horizon.cloudSave.saveObject({"level": 5, "coins": 1000})

# Load game data
var save_data = await Horizon.cloudSave.loadObject()
```

## API Reference

### Connection

```gdscript
# Connect to server
var success: bool = await Horizon.connect_to_server()

# Check status
Horizon.isConnected()      # Returns true if connected
Horizon.isInitialized()    # Returns true if configured
Horizon.getActiveHost()    # Returns current server URL

# Disconnect
Horizon.disconnect_from_server()
```

### Authentication

`quickSignInAnonymous()` restores an existing stored identity and returns `false` if that
restore fails; it creates a player only when no anonymous identity is stored. Reading a
cached token never deletes it, including unusable legacy tokens longer than 32 characters.
Those fail restore locally and remain available for reconciliation. Only an explicit game
decision to clear the identity may permit a new account; network/validation failures do not.

```gdscript
# Email authentication
await Horizon.auth.signUpEmail("user@example.com", "password", "Username")
await Horizon.auth.signInEmail("user@example.com", "password")

# Anonymous authentication
# The server issues the anonymous token: signUpAnonymous() stores it and signs in with it
await Horizon.auth.signUpAnonymous("DisplayName")
await Horizon.auth.restoreAnonymousSession()

# Apple Sign-In - low-level (game already has the identity token)
await Horizon.auth.signUpApple(identity_token, "Jane", "Doe")
await Horizon.auth.signInApple(identity_token)

# Apple Sign-In - convenience flow
# - iOS: opens the native ASAuthorizationController sheet via the bundled
#        classic .gdip plugin (addons/horizon_sdk/ios/HorizonAppleSignIn/)
# - Other platforms: opens the system browser to the customer Services ID OAuth URL
await Horizon.auth.sign_in_with_apple("com.customer.web")

# Get current user
if Horizon.isSignedIn():
    var user = Horizon.getCurrentUser()
    print(user.userId, user.displayName, user.authType)
    # Apple users expose `apple_user_id` and `is_private_relay_email`
    if user.authType == "APPLE":
        print(user.apple_user_id, user.is_private_relay_email)

# Sign out
Horizon.auth.signOut()
```

### Leaderboards

```gdscript
# Submit score
await Horizon.leaderboard.submitScore(1000)

# Get rankings
var top: Array[HorizonLeaderboardEntry] = await Horizon.leaderboard.getTop(10)
var myRank: HorizonLeaderboardEntry = await Horizon.leaderboard.getRank()
var around: Array[HorizonLeaderboardEntry] = await Horizon.leaderboard.getAround(5)

# Every entry (and the rank) carries the player's profile, never null
for entry in top:
    if entry.profile.hasAvatar():
        print("%s uses %s" % [entry.username, entry.profile.avatarId])
```

### Cloud Saves

Sign in before saving or loading. JSON and binary requests carry the player session.
Binary loads POST a JSON `userId` body and request `application/octet-stream`; a missing save returns empty bytes.

```gdscript
# Dictionary (recommended)
await Horizon.cloudSave.saveObject({"level": 5, "coins": 1000})
var data: Dictionary = await Horizon.cloudSave.loadObject()

# JSON string
await Horizon.cloudSave.saveData('{"level": 5}')
var json: String = await Horizon.cloudSave.loadData()

# Binary data
await Horizon.cloudSave.saveBytes(my_bytes)
var bytes: PackedByteArray = await Horizon.cloudSave.loadBytes()
```

**Saving from several devices.** The plain save methods overwrite whatever is stored. When a player plays on more than one device, load a snapshot with its revision and save against that revision. The server writes only while the save is still at that revision. Otherwise it answers HTTP 409, nothing is written and the result is `STATUS_CONFLICT`. The SDK never retries or overwrites a conflict: load again, merge or let the player choose, then save with the new revision.

```gdscript
var snapshot: Dictionary = await Horizon.cloudSave.loadSnapshot()  # or loadBytesSnapshot()
if snapshot["success"]:
	# Build new_json from snapshot["data"]: only the snapshot's data belongs to its revision.
	var result: Dictionary = await Horizon.cloudSave.saveDataAtRevision(new_json, snapshot["revision"])  # or saveBytesAtRevision()
	if result["conflict"]:
		pass  # another device saved first: load a new snapshot and decide
	elif result["success"]:
		var next_revision: int = result["revision"]  # pass it to the next save
```

`revision` is `0` for an empty slot. It is `HorizonCloudSave.REVISION_UNKNOWN` (`-1`) when the server sends no revision, for example a self-hosted simpleServer: the state is then unknown, not empty, and the server does not detect conflicts.

### Remote Config

```gdscript
# Get typed values
var version: String = await Horizon.remoteConfig.getConfig("game_version")
var maxLevel: int = await Horizon.remoteConfig.getInt("max_level", 100)
var difficulty: float = await Horizon.remoteConfig.getFloat("difficulty", 1.0)
var maintenance: bool = await Horizon.remoteConfig.getBool("maintenance_mode", false)

# Get all configs
var all: Dictionary = await Horizon.remoteConfig.getAllConfigs()
```

### Localization

```gdscript
# Defaults to the OS language (one of 15 supported), otherwise "en".
# Switch the active language at any time (clears the cache).
Horizon.localization.setLanguage("de")

# Get a single translation (uses the active language)
var greeting: String = await Horizon.localization.getLocalization("greeting")

# Override the language per call
var greeting_en: String = await Horizon.localization.getLocalization("greeting", "en")

# Get all translations for the active language
var all: Dictionary = await Horizon.localization.getAllLocalizations()

# List the languages available on the server
var languages: Array = await Horizon.localization.getAvailableLanguages()
```

### News

```gdscript
var news: Array[HorizonNewsEntry] = await Horizon.news.loadNews(20, "en")
for entry in news:
    print("%s: %s" % [entry.title, entry.message])
```

### Gift Codes

Prepare once, durably persist the complete scoped intent, then send it. The feature example provides separate explicit redeem/retry actions and a guarded file store.

```gdscript
var intent: Dictionary = await Horizon.giftCodes.prepareRedemption("ABCD-1234")
# Persist all intent fields for this project/player BEFORE sending.
var result: Dictionary = await Horizon.giftCodes.redeemPrepared(intent)
# After uncertainty/restart: load and resend the same intent; never prepare a replacement automatically.
```

Counts/revisions are canonical Int64 decimal strings. Replay has `alreadyApplied/replayed=true`, current Player Values, null giftData and empty grants. Replace current balances, never add grants. V1 `redeem(code[, id])` returns `UPGRADE_REQUIRED`; protected `MIGRATION_REQUIRED`, `COUNT_AHEAD`, `CAMPAIGN_CHANGED`, `COUNTER_EXHAUSTED` and domain errors require reconciliation. An intent cannot move to another player/project or a reused visible code. `redeemPreparedParsed` only parses fresh opaque giftData and never turns it into authoritative balances.

### Player Profile

Avatar, frame and up to three badges per player, shown on every leaderboard entry. Each project keeps a cosmetic catalog in the Dashboard; locked cosmetics need an unlock (granted by a gift code with `grants` or in the Dashboard). The server stores only IDs, your game maps them to its assets. Both calls need a signed-in player and send the player session (`Authorization: Bearer`).

```gdscript
# One call: profile, unlocks, catalog (with `available`) and limits
var result: Dictionary = await Horizon.playerProfile.getProfile()
var profile: Dictionary = result.get("profile", {})   # avatarId, frameId ("" = not set), badges
var avatars: Array = Horizon.playerProfile.getCosmetics("avatar")
var canUseGold: bool = Horizon.playerProfile.isAvailable("frame.gold")

# PUT replaces the whole profile: pass current values for slots you keep.
# "" clears a slot, [] clears the badges (max 3).
var updated: Dictionary = await Horizon.playerProfile.setProfile(
    "avatar.zombie_07", profile.get("frameId", ""), ["badge.supporter"])
if updated.is_empty():
    print(Horizon.playerProfile.getLastErrorCode())  # e.g. COSMETIC_LOCKED

# Last successful result ({} before the first call and after sign-out)
var cached: Dictionary = Horizon.playerProfile.getCurrentProfile()
```

Error codes from `getLastErrorCode()` and the `*_failed` signals: `SESSION_REQUIRED` (no session, checked locally), `INVALID_BADGES`, `INVALID_COSMETIC_ID` (also checked locally), `COSMETIC_NOT_FOUND`, `COSMETIC_TYPE_MISMATCH`, `COSMETIC_LOCKED`, `SESSION_FORBIDDEN`, `PLAYER_NOT_FOUND`. Without a server code the SDK error name is used (for example `API_RATE_LIMITED`, `NETWORK_ERROR`).

### Validated Actions

Server-checked runs for competitive leaderboards. `startRun()` returns a single-use ticket with a server seed; your game seeds its deterministic randomness with it and records an input log. `submitValidated()` sends the score and the SHA-256 of the log; the server checks the ticket and the rules of your API key (score limits, minimum duration, score per second, stages) before anything is written. The rules live on the server only and never appear in responses. Every call needs a signed-in player and sends the player session (`Authorization: Bearer`). Cloud only: the self-hosted simpleServer does not support it (`NOT_SUPPORTED`).

```gdscript
# 1. Get a ticket ("" for a run without leaderboard)
var run: Dictionary = await Horizon.validatedActions.startRun("weekly")
if run.is_empty():
    print(Horizon.validatedActions.getLastErrorCode())  # e.g. RUN_RATE_LIMITED
var rng := RandomNumberGenerator.new()
rng.seed = run["seed"]

# 2. Play and record the inputs as bytes (input_log: PackedByteArray)

# 3. Submit: the SDK hashes the log (SHA-256) and sends the current ticket.
#    Optional: stage, leaderboard key ("" = the ticket's board), earned values (Part 2)
var result: Dictionary = await Horizon.validatedActions.submitValidated(18250, input_log, "wave_3")
if result.is_empty():
    print(Horizon.validatedActions.getLastErrorCode())  # e.g. DURATION_TOO_SHORT
else:
    print("Rank %d, best %d" % [result["rank"], result["bestScore"]])

# With a ready hash (64 hex characters) instead of the log bytes
var hash_hex := HorizonValidatedActions.computeInputLogHash(input_log)
# await Horizon.validatedActions.submitValidatedWithHash(18250, hash_hex)

Horizon.validatedActions.hasActiveRun()   # a run waits for its submit
Horizon.validatedActions.getCurrentRun()  # the run, {} when none
Horizon.validatedActions.discardRun()     # drop it without submitting
```

A ticket is single use. After an accepted run, a `422` rejection (ticket and rule codes) and `403 SCORE_LIMIT_REACHED` the current run is cleared. `LEADERBOARD_MISMATCH` (`422`), `LEADERBOARD_NOT_FOUND` (`404`), `SCORE_REQUIRED` and `PLAYER_NAME_REQUIRED` (`400`) are checked before the server consumes the ticket, so the run stays and you may fix the request and submit again with the same ticket. After network errors, `401`, `429` and `503` it stays as well, and after `403 PLAYER_BANNED` (checked before the ticket is used; call `discardRun()` to give the run up). A new ticket needs a new `startRun()`. Sign-out also clears the run. After an accepted board run the leaderboard cache is cleared.

Error codes from `getLastErrorCode()` and the `*_failed` signals: local `SESSION_REQUIRED`, `NO_ACTIVE_RUN`, `INVALID_INPUT_LOG_HASH`, `INVALID_CONTENT_DIGEST`; run start context `INITIAL_STATE_INVALID_ENCODING` (`400`), `INITIAL_STATE_TOO_LARGE` (`413`); ticket `TICKET_INVALID`, `TICKET_EXPIRED`, `TICKET_FOREIGN`, `TICKET_CONSUMED`, `LEADERBOARD_MISMATCH`; rules `STAGE_REQUIRED`, `STAGE_UNKNOWN`, `SCORE_ABOVE_MAX`, `SCORE_BELOW_MIN`, `STAGE_SCORE_ABOVE_MAX`, `STAGE_SCORE_BELOW_MIN`, `DURATION_TOO_SHORT`, `SCORE_RATE_TOO_HIGH`; values `UNKNOWN_VALUE_KEY`, `DUPLICATE_VALUE_KEY`, `EARNED_ABOVE_MAX`, `EARNED_BELOW_MIN`, `INSUFFICIENT_BALANCE`; others `SCORE_REQUIRED`, `PLAYER_NAME_REQUIRED`, `SCORE_LIMIT_REACHED`, `SESSION_FORBIDDEN`, `PLAYER_NOT_FOUND`, `LEADERBOARD_NOT_FOUND`, `RUN_RATE_LIMITED` and `RUN_CAPACITY_REACHED` (`429`, not retried automatically, the wait can be an hour), `VALIDATED_ACTIONS_UNAVAILABLE`, `PLAYER_BANNED` (`403`, the account banned the player from the board), `NOT_SUPPORTED`. Without a server code the SDK error name is used (for example `NETWORK_ERROR`).

A leaderboard with **Validated submissions only** (`validatedOnly: true` in `listBoards()`) refuses `submitScore()`: it returns `false` and `Horizon.leaderboard.getLastErrorCode()` is `VALIDATED_SUBMIT_REQUIRED`. A player the account banned from a board gets `PLAYER_BANNED` from `submitScore()` and from the validated submit; neither is retried.

#### Run start context and sus runs

`startRun()` takes an optional context Dictionary: what the run starts from. Every key is optional; empty values are not sent, and without any value the request stays the old one.

```gdscript
var context := {
    "game_version": "1.4.2",                 # at most 64 printable ASCII characters
    "content_version": "levels-7",
    "simulation_version": "sim-3",
    "replay_format_version": "inputs-v1",
    "content_digest": HorizonValidatedActions.computeInputLogHash(level_bytes),  # SHA-256, 64 hex
    "initial_state": initial_state_bytes,    # PackedByteArray, sent as base64
}
var run: Dictionary = await Horizon.validatedActions.startRun("weekly", context)

# Or set the versions once; used whenever startRun() gets no context (no merge with a passed one)
Horizon.validatedActions.default_run_context = {"game_version": "1.4.2"}
```

The keys map to the JSON fields `gameVersion`, `contentVersion`, `simulationVersion`, `replayFormatVersion`, `contentDigest` and `initialState`. The server binds the context to the run together with what it fixes itself (rule version, cloud save, server-owned values, seed, start time). A `content_digest` that is not 64 hex characters fails locally with `INVALID_CONTENT_DIGEST`; the server answers `INITIAL_STATE_TOO_LARGE` (`413`, above the game's evidence size limit) or `INITIAL_STATE_INVALID_ENCODING` (`400`).

`result["sus"]` is `true` when an accepted run crossed a soft threshold of the rules. The score counts; the server keeps the run with its start context for a review and requests the input log through `result["evidence"]`, which the SDK uploads on its own after `submitValidated()`, like a top N record. The reasons stay on the server. Older servers do not send the field (`false`).

#### Server-owned player state

Currency, loot and other counters (int64) that only the server writes. Define the values in the Dashboard under Validated Actions (per value `maxPerRun`, optional `minPerRun` below 0 for spending, `dailyCap`, `maxBalance`). A run reports what it earned or spent with `earned`; the server checks every entry before it writes anything and then credits it, clamped by the daily cap and the maximum balance. There is no call that sets a balance.

```gdscript
# Read the values (every key of the rules, sorted, balance 0 when never earned)
var state: Dictionary = await Horizon.validatedActions.getState()
print(Horizon.validatedActions.getBalance("gold"))   # from the cached state
# state["values"][i]: {key, balance, earnedToday, dailyCap (0 = no cap)}; a submit result adds requested and credited to the values its run touched

# Earn 250 gold and spend one chest key in a run (negative amount = spend)
var result: Dictionary = await Horizon.validatedActions.submitValidated(0, input_log, "", "", [
    {"key": "gold", "amount": 250},
    {"key": "chest.key", "amount": -1}
])
if not result.is_empty():
    var run_state := HorizonValidatedPlayerState.fromDict(result["state"])
    print(run_state.getValue("gold"))  # credited < requested: daily cap or max balance clamped it
    if run_state.isFullyCredited("chest.key"):
        open_chest()  # grant a purchase only when credited == requested
```

`getCurrentState()` returns the last known state (from `getState()` or the latest accepted run with a state, without `requested` and `credited`), `{}` before the first load; sign-out and a sign-in of another player clear it. A result `state` of `{day: "", values: []}` means the server sent `null` (the rules define no values); the cache then stays as it is. All numbers are at most 9,007,199,254,740,991 (2^53 - 1) and arrive as `int`. Send `earned` only when the rules define values: every rejected entry uses up the ticket (`422`: `UNKNOWN_VALUE_KEY`, `DUPLICATE_VALUE_KEY`, `EARNED_ABOVE_MAX`, `EARNED_BELOW_MIN`, `INSUFFICIENT_BALANCE`). The SDK sends whole numbers only and drops malformed entries with a warning; at most 64 entries per run.

**Cloud save as a mirror.** The cloud save stays a blob your game writes, so it may only hold a copy:
1. After every accepted run, copy `result["state"]["values"]` (or `getCurrentState()`) into your save, for display and offline start.
2. On start, call `getState()` and overwrite the copy with it, never the other way round.
3. Never send a value from the save back as a balance; balances change only through `earned`.
4. Values earned offline go into `earned` of the next validated run, where the per run and daily limits apply as usual.

See `examples/features/validated_state_example.gd`.

#### Evidence (input log upload)

The server may ask for the input log of an accepted run, so the account can replay it in the Dashboard: when the run became the player's entry on a board and lands in the top `evidenceTopN` of that board, or carries a soft rule flag. The result then has `evidence` = `{required: true, runId, uploadBefore (24 h), maxBytes (32,768)}`; otherwise `required` is `false`.

```gdscript
Horizon.validatedActions.evidence_uploaded.connect(func(run_id): print("Evidence stored for %s" % run_id))
Horizon.validatedActions.evidence_upload_failed.connect(func(run_id, error, code): print("Evidence [%s]: %s" % [code, error]))

# submitValidated() knows the bytes: the SDK uploads them in the background
var result: Dictionary = await Horizon.validatedActions.submitValidated(18250, input_log)

# submitValidatedWithHash() does not: upload the same bytes yourself
result = await Horizon.validatedActions.submitValidatedWithHash(18250, hash_hex)
if not result.is_empty() and result["evidence"]["required"]:
    var ok: bool = await Horizon.validatedActions.uploadEvidence(result["evidence"]["runId"], input_log)
    if not ok and HorizonValidatedActions.isEvidenceRetryable(Horizon.validatedActions.getLastErrorCode()):
        pass  # wrong bytes or network error: try again before result["evidence"]["uploadBefore"]
```

- The automatic upload (`auto_upload_evidence`, default `true`) starts after an accepted `submitValidated()` whose result requests evidence. It is not awaited: `submitValidated()` returns the result right away, and the upload reports only through `evidence_uploaded(run_id)` and `evidence_upload_failed(run_id, error, code)`. It never changes the submit result or `getLastErrorCode()`. Set `auto_upload_evidence = false` to upload yourself.
- `uploadEvidence(run_id, input_log)` sends `PUT /api/v1/app/validated-actions/runs/{runId}/evidence` with `{userId, log}` (standard base64 of the bytes) and the player session, and returns `true` when stored. It sets `getLastErrorCode()`. `getLastEvidenceErrorCode()` holds the code of the last upload of either kind.
- The bytes must be exactly those whose SHA-256 was submitted. Codes: local `SESSION_REQUIRED`, `INVALID_RUN_ID`, `EMPTY_INPUT_LOG`, and `EVIDENCE_TOO_LARGE` when the automatic upload sees a log above `maxBytes` (nothing is sent); server `EVIDENCE_HASH_MISMATCH` (`422`, the request stays open), `EVIDENCE_INVALID_ENCODING` (`400`), `EVIDENCE_NOT_REQUESTED` (`404`), `EVIDENCE_ALREADY_UPLOADED` (`409`), `EVIDENCE_EXPIRED` (`410`, the 24 h window passed), `EVIDENCE_TOO_LARGE` (`413`).
- Retry only after `EVIDENCE_HASH_MISMATCH` (with the correct bytes) or `NETWORK_ERROR`: `HorizonValidatedActions.isEvidenceRetryable(code)`. Every other code is final. An upload failure never affects the accepted score.

See `examples/features/validated_evidence_example.gd`.

### Inbox

After signing in, load notifications explicitly when opening the inbox or returning to the
game. The SDK does not start a poll loop. Respect `pollAfterSeconds` before a later lifecycle
refresh; optional realtime events only invalidate this cache, then HTTP reloads the contents.

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var cached: Dictionary = Horizon.inbox.getCurrentInbox()
var result: Dictionary = await Horizon.inbox.getInbox(user_id, cached.get("cursor", ""))
if result.success:
    render_entries(result.data.entries) # complete entries, including unchanged=true

# On an explicit player action, persist the selected entry ID before HTTP.
var claimed: Dictionary = await Horizon.inbox.claim(user_id, selected_entry_id)
if claimed.success:
    render_balances(claimed.data.playerValues.values) # authoritative replacement, never add deltas
```

| Method | Result |
|---|---|
| `getInbox(user_id, since="")` | GET snapshot; opaque cursor is used only when its full cache is available |
| `markRead(user_id, entry_id)` | POST `/inbox/read`; idempotent snapshot |
| `remove(user_id, entry_id)` | POST `/inbox/remove`; protects unclaimed rewards |
| `claim(user_id, entry_id)` | POST `/inbox/claim`; `{entryId,replayed,inbox,playerValues}` |
| `getCurrentInbox()`, `clearCache()` | Defensive cache copy; invalidation also fences in-flight replies |
| `getLastErrorCode()` | Last local/server error code |

All four async methods return `{success,data,errorCode,error}`. The current player's signed
session and project key are required. Signals are `inbox_loaded(snapshot)`,
`inbox_updated(snapshot)`, `entry_claimed(result)` and `inbox_failed(error,code)`.
Snapshots include `userId`, `cursor`, `revision`, `broadcastRevision`, `serverTime`,
`pollAfterSeconds`, `unchanged`, complete `entries`, `counts` and effective `limits`.
An `unchanged` wire response contains no entries; the SDK materializes the complete cached
entries. Expiry may change the cursor with the same revision. Overdue unclaimed reward
entries stay visible and count toward capacity, as determined by the server.

Requests serialize, including necessary follow-up reads. Mutations invalidate the old cache;
session, player, host or project changes fence old/queued responses. Independent revision and
server-time watermarks survive cache invalidation. JSON integer tokens are checked before
conversion, preserving safe 64-bit values through 9,007,199,254,740,991.

After an uncertain claim, retry **the same entry ID**. There is no caller-selected amount,
recipient or new operation ID. The SDK adopts the complete `playerValues` snapshot; it never
adds attachment values to a local balance. `STATE_CONFLICT` and network errors remain
explicit; there is no automatic replacement booking. Admin broadcast/support routes stay
in the Dashboard/MCP, outside the app SDK. See `examples/features/inbox_example.gd`.

The Player Values purchase example stores pending intents by **project key + player**.
Configured legacy regional-host files migrate with the original ID/payload; conflicting IDs
or an unrecognised old-host intent block and retain the files for reconciliation.

### Statistics

Define `kills` (sum) and `best_score` (max) for the project in the Dashboard. Sign in, then
load a snapshot explicitly when the game needs its values/catalog; sign-in never fetches it.

```gdscript
var snapshot: Dictionary = await Horizon.statistics.getStatistics()
if snapshot.is_empty():
    return
var operation: String = Horizon.statistics.createOperationId() # once, persist with the batch
var updates: Array = [{"key":"kills","value":3}, {"key":"best_score","value":250}]
var result: Dictionary = await Horizon.statistics.updateStatistics(updates, operation)
if result.is_empty():
    push_warning(Horizon.statistics.getLastErrorCode())
```

| Method | Result |
|---|---|
| `getStatistics()` | Snapshot Dictionary or `{}`; GET `/api/v1/app/statistics?userId=` |
| `getDefinitions()` | `{definitionVersion,definitions}` or `{}`; GET `/statistics/definitions` |
| `updateStatistics(updates, operation_id)` | Atomic snapshot plus original ID/replayed; POST `/statistics` |
| `createOperationId()` | Timestamp:UUID, corrected by the last snapshot's server time |
| `getCurrentStatistics()`, `getCurrentDefinitions()` | Copies of the accepted caches |
| `getLastErrorCode()`, `getLastSubmittedOperationId()` | Stable code and original submitted ID |
| `clearCache()` | Clears data and invalidates pending conditional reads |

Signals: `statistics_loaded`, `statistics_updated`, `definitions_loaded`, and
`statistics_failed(message, code)`. Every request uses the matching current player's Bearer
session. Caches clear on session/project/host change; late replies cannot overwrite a newer
revision or UTC projection, even after catalog changes. Conditional catalog reads are folded
from cache. Snapshots expose `values` (`key`, integer `value`, `hasValue`, `period`), revision,
definition version, operation window and `newlyUnlocked` for achievement integration.

Request values must be Godot `int`, within ±9,007,199,254,740,991; floats/strings and duplicate
keys fail before sending. JSON response integers are normalized back to exact `int` values.
Unset counters are zero with `hasValue:false`. An optional positive `maxPerUpdate` bounds the
absolute reported value. Daily/weekly resets use UTC midnight/ISO Monday without player jobs.

Persist the ID and original batch before sending. After timeout, inspect a snapshot and retry
the same ID; the SDK never invents another. Retained IDs replay the current snapshot; another
payload returns `OPERATION_CONFLICT`. Only eight receipts are retained. Unknown IDs must be
within 24 hours, at most 30 seconds ahead and newer than a persistent eviction floor; delayed
or out-of-order IDs can expire sooner with `OPERATION_EXPIRED`. Reconcile an uncertain expired
intent instead of reporting the session again. `STATE_CONFLICT` requests a fresh snapshot and
retry of the original ID; other codes include `UPDATE_ABOVE_LIMIT`, `VALUE_OVERFLOW`,
`UNKNOWN_STATISTIC`, session errors and `RATE_LIMITED`.

`examples/features/statistics_example.gd` preserves pending batches with binary Variant
storage, retaining `int64` types across restart. JSON.parse_string loads JSON numbers as
floats, so convert and validate them explicitly before constructing a fresh report. The same
app API is supported by simpleServer with SQL-configured definitions.

### Feedback

```gdscript
await Horizon.feedback.submitBugReport("Title", "Description")
await Horizon.feedback.submitFeatureRequest("Title", "Description")
await Horizon.feedback.submit("Title", "Message", "GENERAL", "email@example.com", true)
```

### User Logs

```gdscript
await Horizon.userLogs.info("Player completed tutorial")
await Horizon.userLogs.warn("Low memory detected")
await Horizon.userLogs.error("Failed to load asset", "ERR_001")
await Horizon.userLogs.logEvent("level_complete", "Level 5")
```

### Crash Reporting

Track crashes, non-fatal exceptions, and breadcrumbs to monitor game stability.

```gdscript
# Register crash session (call once on game start)
await Horizon.crashes.register_session()

# Record breadcrumbs for context leading up to issues
Horizon.crashes.record_breadcrumb("navigation", "Entered level 5")
Horizon.crashes.record_breadcrumb("user_action", "Opened inventory")
Horizon.crashes.log("Player picked up item")

# Set custom metadata included in all reports
Horizon.crashes.set_custom_key("level", "5")
Horizon.crashes.set_custom_key("build", "1.2.3")

# Override user ID (defaults to authenticated user)
Horizon.crashes.set_user_id(user_id)

# Report a fatal crash
await Horizon.crashes.report_crash("Unexpected null reference", stack_trace)

# Record a non-fatal exception with optional extra keys
await Horizon.crashes.record_exception(
    "Failed to load texture",
    stack_trace,
    {"texture_name": "player_sprite.png"}
)
```

#### Breadcrumb Types

Use built-in constants for consistent breadcrumb categorization:

| Constant | Value | Use Case |
|----------|-------|----------|
| `BREADCRUMB_NAVIGATION` | `"navigation"` | Scene/screen transitions |
| `BREADCRUMB_USER_ACTION` | `"user_action"` | Button presses, interactions |
| `BREADCRUMB_LOG` | `"log"` | General log messages |
| `BREADCRUMB_ERROR` | `"error"` | Error conditions |
| `BREADCRUMB_STATE` | `"state"` | Game state changes |

#### Limits

| Parameter | Limit |
|-----------|-------|
| Reports per minute | 5 |
| Reports per session | 20 |
| Breadcrumbs (ring buffer) | 50 |
| Custom keys | 10 |

### Email Sending

**Email Sending** lets your game send transactional emails to registered players. Create multi-language HTML templates with variable placeholders in the horizOn Dashboard, then trigger immediate or scheduled email delivery from your game using the SDK. Emails are sent through your own SMTP server -- horizOn handles the queue, rendering, and scheduling while you keep full control over branding and deliverability.

```gdscript
# Send immediate email
var response = await Horizon.email_sending.send_email(
    "user-uuid", "welcome", {"username": "John"}, "en"
)
print("Email queued: ", response.get("id", ""))

# Schedule email for later
var scheduled = await Horizon.email_sending.send_email(
    "user-uuid", "reminder", {"eventName": "Tournament"}, "en",
    "2026-04-12T09:00:00Z"
)

# Check status
var status = await Horizon.email_sending.get_email_status(response.get("id", ""))
print("Status: ", status.get("status", ""))

# Cancel a scheduled email
var cancel = await Horizon.email_sending.cancel_email(scheduled.get("id", ""))
print(cancel.get("message", ""))
```

## Signals

All operations emit signals for event-driven programming:

```gdscript
# SDK lifecycle
Horizon.sdk_initialized.connect(func(): print("Ready"))
Horizon.sdk_connected.connect(func(host): print("Connected to %s" % host))
Horizon.sdk_disconnected.connect(func(): print("Disconnected"))

# Authentication
Horizon.auth.signin_completed.connect(func(user): print("Signed in: %s" % user.userId))
Horizon.auth.signin_failed.connect(func(error): print("Error: %s" % error))

# Leaderboard
Horizon.leaderboard.score_submitted.connect(func(score): print("Score: %d" % score))

# Player Profile
Horizon.playerProfile.profile_loaded.connect(func(profile): print("Profile: %s" % profile["profile"]))
Horizon.playerProfile.profile_updated.connect(func(profile): print("Saved: %s" % profile["profile"]))
Horizon.playerProfile.profile_update_failed.connect(func(error, code): print("Failed [%s]: %s" % [code, error]))

# Validated Actions
Horizon.validatedActions.run_started.connect(func(run): print("Run %s, seed %d" % [run["runId"], run["seed"]]))
Horizon.validatedActions.run_start_failed.connect(func(error, code): print("Start failed [%s]: %s" % [code, error]))
Horizon.validatedActions.run_submitted.connect(func(result): print("Accepted, rank %d" % result["rank"]))
Horizon.validatedActions.run_submit_failed.connect(func(error, code): print("Rejected [%s]: %s" % [code, error]))
Horizon.validatedActions.state_loaded.connect(func(state): print("Values: %d" % state["values"].size()))
Horizon.validatedActions.state_load_failed.connect(func(error, code): print("State failed [%s]: %s" % [code, error]))
Horizon.validatedActions.evidence_uploaded.connect(func(run_id): print("Evidence uploaded: %s" % run_id))
Horizon.validatedActions.evidence_upload_failed.connect(func(run_id, error, code): print("Evidence failed [%s]: %s" % [code, error]))

# Cloud Save
Horizon.cloudSave.data_saved.connect(func(size): print("Saved %d bytes" % size))
Horizon.cloudSave.data_loaded.connect(func(data): print("Loaded"))
Horizon.cloudSave.save_conflict.connect(func(error): print("Conflict: %s" % error))

# Crash Reporting
Horizon.crashes.crash_reported.connect(func(fingerprint): print("Crash reported: %s" % fingerprint))
Horizon.crashes.crash_report_failed.connect(func(error): print("Report failed: %s" % error))
Horizon.crashes.session_registered.connect(func(session_id): print("Session: %s" % session_id))

# Email Sending
Horizon.email_sending.email_sent.connect(func(response): print("Email sent: %s" % response.get("id", "")))
Horizon.email_sending.email_send_failed.connect(func(error): print("Send failed: %s" % error))
Horizon.email_sending.email_cancelled.connect(func(id): print("Cancelled: %s" % id))
Horizon.email_sending.email_status_received.connect(func(response): print("Status: %s" % response.get("status", "")))
```

## Configuration Options

Edit your config resource at `addons/horizon_sdk/horizon_config.tres`:

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | - | Your horizOn API key |
| `hosts` | `["https://horizon.pm"]` | Backend server URL(s). Single host skips ping; multiple hosts use latency-based selection. |
| `connection_timeout_seconds` | 10 | HTTP request timeout |
| `max_retry_attempts` | 3 | Retry count for failed requests |
| `retry_delay_seconds` | 1.0 | Delay between retries |
| `log_level` | INFO | DEBUG, INFO, WARNING, ERROR, NONE |

## Rate Limiting

**Limit**: counted per account, shared by all players of all your games. On the Free plan the soft limit is 10 and the hard limit 100 requests per minute. Paid plans have higher limits, see [horizon.pm/pricing](https://horizon.pm/pricing).

| Do | Don't |
|----|-------|
| Load all configs at startup | Fetch configs repeatedly |
| Cache leaderboard data | Refresh every frame |
| Save on level complete | Save on every action |
| Submit scores on improvement | Submit every score |
| Register one crash session per launch | Register sessions repeatedly |

### Efficient Startup Pattern

```gdscript
func _ready():
    var connected = await Horizon.connect_to_server()
    if not connected:
        return

    await Horizon.quickSignInAnonymous("Player1")

    # Startup loads (3 requests)
    await Horizon.remoteConfig.getAllConfigs()
    await Horizon.news.loadNews()
    await Horizon.crashes.register_session()

    # The per-minute limit counts for your whole account, not per player
```

## Error Handling

```gdscript
# Check return values
var success = await Horizon.auth.signInEmail(email, password)
if not success:
    print("Sign-in failed")

# Cloud save with fallback
var data = await Horizon.cloudSave.loadObject()
if data.is_empty():
    data = {"level": 1, "coins": 0}
```

### Common HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 400 | Bad Request | Check parameters |
| 401 | Unauthorized | Re-authenticate |
| 403 | Forbidden | Check tier/permissions |
| 429 | Rate Limited | Wait and retry |

## Self-Hosted Option

The horizOn SDKs work with both the **managed horizOn BaaS** and the **free, open-source [horizOn Simple Server](https://github.com/ProjectMakersDE/horizOn-simpleServer)**.

Simple Server is a lightweight PHP backend with no dependencies — perfect as a starting point if you want full control over your infrastructure. It supports core features like leaderboards, cloud saves, remote config, news, gift codes, feedback, and crash reporting.

To connect to your own server, set the `hosts` configuration to your server URL:

```gdscript
# In your HorizonConfig resource
hosts = ["https://your-server.example.com"]
```

> **Note:** Simple Server is a starting point, not a full replacement. For the complete experience with dashboard, user authentication, multi-region deployment, and more, use [horizOn BaaS](https://horizon.pm).

## Project Structure

```
addons/horizon_sdk/
├── core/
│   ├── horizon.gd          # Main SDK singleton
│   ├── auth.gd             # Authentication
│   ├── leaderboard.gd      # Leaderboards
│   ├── cloud_save.gd       # Cloud saves
│   ├── remote_config.gd    # Remote config
│   ├── localization.gd     # Localization
│   ├── news.gd             # News
│   ├── gift_codes.gd       # Gift codes
│   ├── player_profile.gd   # Player profile (avatar, frame, badges)
│   ├── validated_actions.gd # Validated runs (tickets, submit, hash helper, player state, evidence)
│   ├── feedback.gd         # Feedback
│   ├── user_logs.gd        # User logs
│   ├── crashes.gd          # Crash reporting
│   └── email_sending.gd    # Email sending
├── examples/
│   └── horizon_test_scene.tscn
└── horizon_config.tres      # Configuration resource
```

## Documentation

- **[Quickstart Guide](https://horizon.pm/quickstart#godot)** - Interactive setup
- **[API Reference](https://horizon.pm/docs)** - Full API documentation
- **[Example Scene](addons/horizon_sdk/examples/horizon_test_scene.tscn)** - Interactive demo of all features

## Support

- 📖 **Documentation**: [horizon.pm/quickstart](https://horizon.pm/quickstart)
- 💬 **Discord**: [discord.gg/JFmaXtguku](https://discord.gg/JFmaXtguku)
- 🐛 **Issues**: [GitHub Issues](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues)

## License

MIT License - Copyright (c) [ProjectMakers](https://projectmakers.de)

See [LICENSE](LICENSE) for details.

## Realtime invalidations (Cloud)

After sign-in call `Horizon.realtime.subscribe("inbox:" + Horizon.auth.getCurrentUser().userId)`. Connect `resync_required` and `event_received` to the feature HTTP reload. `polling_required` requests an HTTP fallback after at least `pollAfterSeconds`; chat never polls. Call `unsubscribe(topic)` when no longer needed.

Reconnect uses jitter and reauthorizes subscriptions. Events contain IDs and revisions only. Sign-out clears subscriptions; same-user token refresh reconnects automatically. simpleServer reports `NOT_SUPPORTED`; realtime is Cloud only.

## Player values

`Horizon.playerValues` exposes `getState(user_id)`, `getOffers(user_id)`, `purchase(user_id,offer_key,operation_id)`, `adjust(user_id,key,amount,reason,operation_id)` and `createOperationId()`. All calls require a matching signed-in session. State/mutation results are `{success,state,errorCode,error}`; offers use `data` instead of `state`. Business failures can include current balances.

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var loaded: Dictionary = await Horizon.playerValues.getState(user_id)
if not loaded.success:
    return
var operation_id: String = Horizon.playerValues.createOperationId() # persist with the purchase intent
var result: Dictionary = await Horizon.playerValues.purchase(user_id, "energy-pack", operation_id)
if not result.state.is_empty():
    print(result.state.values)
if not result.success:
    push_error(result.errorCode)
```

Retain the same operation ID and payload for retries after a timeout. Never generate another ID automatically after `OPERATION_EXPIRED`; refresh and reconcile first. IDs use learned server time plus monotonic elapsed time; local UTC is the fallback before loading state/offers (`hasServerClock() == false`). Amounts must be Godot `int` values within +/-9,007,199,254,740,991; float inputs and unsafe numeric response tokens are rejected. Values/costs/deltas return as int64 and nullable daily caps remain null (zero is a real cap). Cache getters return deep copies, revision/time watermarks survive catalogue invalidation and `clearCache()` rejects earlier in-flight requests. Session/project/host changes discard old state. Realtime is optional: refresh HTTP state after a validated run or another balance mutation. No automatic purchase/poll loop exists.

Current server configuration is authoritative; the SDK does not clamp balance or
offer lists to tariff defaults. Existing balances and earned totals remain readable
after a daily cap is lowered. Compact purchase replay returns the current snapshot
and original operation ID with `replayed:true`, `applied:[]` and `items:[]`; replace
cached balances rather than reconstructing historical deltas or item grants.
Offer-day quotas are absent (`purchasesPerDay` may be omitted/null). Keep the exact
original operation ID for uncertain retries and explicitly refresh inventory after
confirmation. No local debit, grant or replacement purchase is inferred from replay.

### Statistics sample recovery

The minimal `examples/features/statistics_example.gd` keeps its original binary
Variant batch under a project/player SHA-256 filename, independent of host or
access token. The sample validates the exact user, operation ID, keys and safe
integer payload before sending. Old user-only files cannot be safely assigned to
a project: they remain untouched and block a replacement until reconciled.
Atomic directory locks protect intent creation/completion across processes; stale
locks and interrupted writes require manual reconciliation. A successful delayed
response cannot delete another intent. Snapshot reads and expired/unknown results
never release or regenerate a pending operation.

Before guest signup/restore, a durable identity marker prevents a lost signup
response or missing cache from creating another guest on restart. Recover the
original identity rather than deleting this guard. Corrupt caches and unusable
tokens fail closed. This changes only the executable sample and its tests.

### Rate-limit retries (TASK-996)

For HTTP 429 without a nonempty machine-readable `code`, JSON requests wait the
server's `Retry-After` plus independent random jitter from 0 to 20% before the next
allowed attempt. Never retry earlier than the server minimum. Missing/invalid
hints use a finite fallback of at least one second. Any feature code, including
new codes unknown to this SDK, returns immediately with its status/code/header.
The configured attempt budget, immutable original body/ID and host/project/session
generation remain unchanged; a context change or ABA during backoff cancels the retry.
Signup and legacy redemption still have one transport attempt because they lack
a caller-owned replay identity. No background loop, extra HTTP call, database work
or server resource allocation is added. The private jitter RNG never consumes
the game's global RNG. Native tests use isolated loopback port 20096; inherited fixtures
may overlap other engine test ports and are run serially when sharing a host.

The Inbox example persists one original claim entry ID per project/player before
HTTP. A new intent requires that exact entry in the current authorized snapshot,
unclaimed and with nonempty value attachments. An existing identical intent may
be retried after timeout even when the entry is already claimed or absent. Another
pending entry blocks a new claim; corrupt/interrupted storage stays blocked for
explicit recovery. A regional host change retains the original slot. Only a
successful authoritative claim confirms and removes its exact stored intent.
This sample protection adds no server reads, polling or reward calculation.

Gift V2 transport retries reuse the original campaign/count/revision strings. Legacy arbitrary-ID calls are closed with `UPGRADE_REQUIRED` and never authorize a new operation.

### Achievements (TASK-1008, Develop)

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var snapshot: Dictionary = await Horizon.achievements.getAchievements(user_id)
var unlocked: Dictionary = await Horizon.achievements.unlock(user_id, "manual_hidden")
var delivered: Dictionary = await Horizon.achievements.deliverRewards(user_id, ["manual_hidden"])
```

All three methods return `{success, data, errorCode, error}`. Snapshot `data` holds
`userId`, `revision`, opaque player-specific `definitionVersion`, materialized
`definitions`, `progress`, `limits` and `serverTime`. Unlock data holds `achievements`,
`newlyUnlocked`, `replayed` and `deliveryResults`; delivery data holds `achievements`
and `results`. `getAchievements(user_id, definition_version = "")` sends a conditional
version only when this manager owns the matching metadata cache. `null` retains
that cache; `[]` replaces it. Hidden metadata becomes visible only after unlock.
Session/project/host generations and explicit invalidation fence old responses.
Reads and mutations serialize; lower progress/time cannot replace newer state.

Retain the same manual key on timeout; the permanent server guard survives catalogue
edits and archival. Drain 1–8 unique pending keys explicitly. `INBOX_FULL` keeps the
original `pendingReward.issuedAt/values`; current catalogue rewards never replace
that accepted intent. A delivered result invalidates the local Inbox cache without
fetching it. Explicitly refresh Inbox and claim its original entry to replace the
complete Player Values state; never add reward amounts locally.

Statistics `newlyUnlocked` invalidates cached achievement metadata without adding
an HTTP request. The minimal `achievements_example.gd` shows an explicit follow-up
refresh, manual unlock, pending drain and the shared durable Inbox claim flow.
There are no background polls, automatic signup, client reward evaluation or new
server reads beyond the three explicitly requested API operations. Native HTTP
tests use dedicated Godot port 20108; inherited engine fixtures remain serialized.


### Friends (TASK-1009, Develop)

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var result: Dictionary = await Horizon.friends.getFriends(user_id)
if result.success:
    # Render this full snapshot. Keep its revision and the selected request UUID.
    var snapshot: Dictionary = result.data
    print(snapshot.friendCode)

# In the explicit Accept button handler, pass the selected rendered request:
func confirm_incoming(user_id: String, target: String, revision: int, request_id: String) -> Dictionary:
    return await Horizon.friends.acceptRequest(user_id, target, revision, request_id)
```

Every operation returns `{success, data, errorCode, error}`. The reserved methods are
`getFriends(user_id)`, `findPlayer(user_id, query)`, `sendRequest`, `removeFriend`,
`blockPlayer`, `unblockPlayer` with `(user_id, target_user_id, expected_revision)`, and
`acceptRequest`, `declineRequest`, `cancelRequest` with the same arguments plus the original
`request_id`. Revisions must be explicit integer Variants in 0…9,007,199,254,740,991;
strings, floats, missing UUIDs and self actions fail locally without HTTP.

Lookup accepts one exact player UUID or canonical public `H-` friend code. Its data contains
only `{userId, friendCode, display:{name,profile:{avatarId,frameId,badges}}}`. It never returns
email, tokens, activity or another player's private blocklist. Successful reads and mutations
replace the complete own-player snapshot: `{userId,revision,friendCode,friends,incoming,
outgoing,blocked,limits,serverTime}`. Nullable display fields remain null; `lastActiveAt:null`
means no retained login is known. A login timestamp is never an online/offline indicator.
Retained friends above the current tier remain readable after a downgrade. Returned dictionaries
are copies; local edits do not modify the retained snapshot.

All seven mutations use exactly one transport attempt, including global 429, 503 and timeout.
They have no permanent command receipt. After an uncertain result or 409, explicitly refresh
and let the player reconcile the intended action. Never replace a revision/request UUID and
silently repeat a newer action; an old Inbox notice cannot authorize accepting a new request.
Commands invalidate their old local snapshot, preserve original arguments while queued and
suppress late host/project/session/epoch responses, including A→B→A changes. No signup,
background polling, extra profile lookup or hidden recovery request is added. A successful
mutation is one HTTP POST; lookup/snapshot each use one logical GET with the existing bounded
read retry policy. All relationship writes, notification atomicity and block policy stay on the server.

The executable `examples/features/friends_example.gd` supplies explicit refresh, exact lookup
and confirmed actions for all routes. Optional Cloud topic `friends:<userId>` is metadata only:
connect `Horizon.realtime.event_received` and `resync_required` to cache invalidation followed
by an explicit `getFriends` refresh, coalescing repeated UI refreshes. The manager creates no
polling timer or automatic subscription. simpleServer has REST parity; realtime remains Cloud only.

`tests/run_transport_tests.sh` keeps the existing transport/health gates and adds 17 real
loopback HTTP requests through the actual sample and manager. They cover all nine endpoints,
64-bit revisions, unchanged request UUIDs, private/public projection, two player sessions,
full-snapshot replacement and single 429/503/timeout attempts. Separate policy cases cover
wire integer/duplicate-name rejection, retained downgrade lists, crossed requests, stale
revision/time floors, serialization and context/queue/completion-callback races. These local
fixtures verify SDK transport and cache behavior; backend transactions and real Cloud realtime
are separate acceptance evidence.


## Groups: explicit reviewed player commands

`Horizon.groups` returns dictionaries `{success,data,errorCode,error}` and emits
`groups_loaded`, `groups_updated`, `group_loaded`, `members_loaded`, `pending_loaded`
and `groups_failed(error,code)`. Read methods are `getGroups(user_id)`,
`getGroup(user_id,group_id)`, `getMembers(user_id,group_id,after_user_id="",limit=50)`
and `getPending(user_id,group_id)`. A page is one bounded HTTP request, with its own
revision and explicit cursor; there is no automatic page drain or polling. Restart
explicitly if a later page has another group revision. Public member displays keep
nullable names/profile IDs and exclude credentials, private profiles and activity.

```gdscript
var own: Dictionary = await Horizon.groups.getGroups(user_id)
if own.success:
    # Capture this original revision when the player confirms creation.
    var created: Dictionary = await Horizon.groups.createGroup(
        user_id, own.data.revision, "Guild", "Description", "open", {"region": "EU"})
    if created.success:
        var group: Dictionary = created.data.group
        var page: Dictionary = await Horizon.groups.getMembers(user_id, group.id)
        # Render/confirm later actions using this reviewed group revision.
        print(group.id, group.revision, page.data if page.success else page.errorCode)
```

`createGroup(user,expected_player_revision,name,description="",join_mode="open",data={})`
accepts no caller group ID. `updateGroup(user,group,expected_revision,name,description,join_mode,data)`
replaces every metadata field. Both use JSON objects (including empty `{}`), finite
numbers, depth16 and at most2048 serialized UTF-8 bytes; names120/description1024
UTF-8 bytes. Dotted, empty and dollar-prefixed data keys and decimal data fields
remain legal. `GroupView.data` is a `HorizonGroupJsonData` value containing original
JSON text, including large integers and high-precision number lexemes; only
insignificant whitespace outside string values is removed. Pass that
value unchanged to `updateGroup` when editing other metadata. `getJson()` is
lossless; `getPreview()` creates a fresh display dictionary using Godot numbers and
may round values, so never use that preview for an unchanged roundtrip. Create/update
accept either a new Dictionary (serialized once at full engine precision) or
`HorizonGroupJsonData.fromJson(original_json)`. The wrapper has no public mutation
method; invalid JSON/duplicate keys/size/depth/nonfinite values are rejected. Protocol revisions/counts require exact safe integer wire lexemes.

All fourteen actions begin `(user_id,group_id,expected_revision)`:

| Method | Additional arguments |
|---|---|
| `joinGroup`, `requestJoin`, `leaveGroup`, `deleteGroup` | none |
| `invitePlayer`, `removeMember`, `transferLeadership` | `target_user_id` |
| `acceptInvite`, `declineInvite`, `cancelRequest` | original `request_id` |
| `cancelInvite`, `acceptRequest`, `declineRequest` | `target_user_id`, original `request_id` |
| `setMemberRole` | `target_user_id`, `role` (`officer`/`member`) |

Every command uses exactly one transport attempt, including PUT, code-free429,
503 and timeout. It never refreshes revisions, replaces request UUIDs or creates a
new guest after failure. Read state and ask for a new explicit decision after an
uncertain result. Mutations return `{groups:MyGroupsView,group:GroupView|null}`;
`groups` is the acting player's complete replacement snapshot, never the target's.
`getCurrentGroups()` gives a deep copy and is a cached view, not authorization.
Private data is exposed only with the current session's member role; pending
metadata always strips it. Invalid or partial responses never replace the cache or
advance freshness floors. Project/host/session ABA, queued work, signout and
synchronous callbacks fence old responses. Detail freshness memory is bounded48
records; own-player revision/server-time floors survive explicit cache clears.

Global retained maxima500 members/5 memberships and20 invitations/requests remain
readable after a smaller tier is applied. Server limits and role/block checks are
authoritative. A full Inbox error stays atomic at the server and is returned for an
explicit UI decision. Sole-leader deletion cannot dismantle a nonempty group;
transfer leadership before leaving. No group currency, hidden reads or admin write
impersonation is added. Optional hosted `groups:<groupId>` realtime is only an
invalidation hint; subscribe explicitly after membership and reload HTTP after
reconnect. simpleServer supports the same REST contract and no realtime transport.

The runnable `examples/features/groups_example.gd` contains explicit create/read,
one member page, all confirmed actions and no identity/revision fallback. Native
policy and exact real loopback HTTP fixtures execute that actual sample with two
players, all20 routes, role/transfer/leave, full-Inbox refusal and uncertain command
reconciliation. These transport tests are distinct from hosted/database acceptance.
A mutation is one HTTP request; bounded read retries follow the shared transport
policy. Group/player CAS, block/profile projections and Inbox delivery are server
costs; the SDK does not multiply them through polling or automatic page loops.

## Items: unique instances and explicit inventory actions

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var inventory: Dictionary = await Horizon.items.getInventory(user_id)
var catalog: Dictionary = await Horizon.items.getCatalog(user_id) # One page, at most50 templates.
if inventory.success and not inventory.data.instances.is_empty():
    var selected: Dictionary = inventory.data.instances[0]
    # In a later explicit Equip confirmation, retain this instance/revision:
    var equipped: Dictionary = await Horizon.items.setEquipped(
        user_id, selected.instanceId, inventory.data.revision, true)
```

The five methods return `{success,data,errorCode,error}`:
`getInventory(user_id)`, `getCatalog(user_id,after_key="",limit=50,catalog_revision=null)`,
`adjustProperties(user_id,instance_id,expected_revision,changes)`,
`setEquipped(user_id,instance_id,expected_revision,equipped)`, and
`discardItem(user_id,instance_id,expected_revision)`. Adjustment entries use
`{key,amount}`, at most8 distinct nonzero integer deltas. Every expected revision
and numeric property is an exact integer within ±9,007,199,254,740,991; revisions
are nonnegative. Floats, exponent/string coercion and duplicate decoded JSON names
are rejected. Only catalog-permitted existing numeric properties can change;
post-change properties remain bounded to256 canonical UTF-8 bytes. Catalog pages
have `revision,definitions,nextAfterKey,total,limits,serverTime`; inventory has
`userId,revision,instances,limits,serverTime`. Instances contain
`instanceId,itemKey,properties,equipped,createdAt`. Current snapshots are copied,
replace complete state, and retain over-limit historical instances after downgrade.

`limits.catalog`, `limits.inventory` and `limits.receipts` are positive Int32 values from current Admin System Config. The old5000/150/50 defaults are not parser ceilings. Existing instances and catalog totals stay readable after lowering a quota, including more instances than the current inventory limit. Catalog totals retain the physical65,536 lifetime template-slot bound. The five-field instance JSON, original expectedRevision and property deltas are unchanged; compact basis versions stay server internals. Godot retains its independent raw-JSON safety frame (default1MiB, maximum2MiB).

Each of the three mutations sends exactly once, including429/503/timeout. Keep the
original instance/revision and explicitly read/reconcile an uncertain outcome.
Never silently replace a revision or repeat a delta. Catalog pagination is one
explicit page per call, bound to the supplied catalog revision; no automatic page
loop or polling. Host/project/session generations, ABA, cache clears, queues and
synchronous completion callbacks fence late responses. The manager retains only
one own inventory and one catalog page. `getCurrentInventory()` and
`getCurrentCatalogPage()` return copies; `clearCache()` preserves same-player
freshness floors. Signals are `inventory_loaded`, `inventory_updated`,
`catalog_loaded` and `items_failed(error,code)`. Items creates no realtime topic.

Ordinary property strings remain Godot `String`. Godot itself cannot represent
U+0000 and would replace it with U+FFFD. Those valid property/name strings instead
use immutable `HorizonItemStringData`: `getOriginalJson()` gives the original JSON
string token, `getJson()` gives its exact canonical JSON, and
`getDisplayPreview()` visibly spells each NUL as `\u0000`. That preview is for
rendering, never an unchanged write. Other properties/items remain available.
`HorizonItemModels.canonical(properties)` preserves these lossless values and
canonical byte limits, including Unicode/slash/control escapes. No invalid native
NUL decode or silent replacement is used by Item HTTP responses.

Player Values offers add `itemRewards:[{itemKey,quantity}]`; operation receipts add
`items:[{instanceId,itemKey}]`. Both default to[] for older servers/receipts. A
purchase retains the same durably saved original `unixMillis:UUID` and unchanged
offer key across retries. It replaces the complete authoritative Player Values
state and invalidates the inventory cache without fetching or synthesizing items.
Explicitly fetch inventory after success. Compact replay has empty historical `applied`/`items` and current balances; never
buy again or recreate discarded/transferred items to repair a missing refresh.
The server-only GrantProvider owns creation and the atomic balance/inventory/
receipt transaction; the SDK exposes no grant endpoint. Quantities are distinct
item keys with total1..4. Countable currency stays in Player Values; cosmetics
stay in Player Profile, while Items represent individually identified instances.

The executable `examples/features/items_example.gd` supplies UI-called catalog,
review/purchase, inventory, equip, adjust and explicitly destructive discard.
It refreshes terms before a NEW purchase and requires another confirmation if
terms changed. Project+player owns the durable pending slot across regional hosts;
atomic locks/compare-and-swap guard concurrent samples, interrupted writes and late
responses. Confirmed purchase recovery persists an inventory-only phase so a failed
GET or restart never buys again. Expired/uncertain/corrupt intents remain blocked.
Inventory actions persist their exact original selection before the one send and
require an explicit fresh snapshot plus acknowledgement after uncertainty. No
identity signup fallback or background action is introduced. The actual sample is
executed by the native HTTP and storage/policy tests on Godot-only port20111, with
inherited engine fixtures kept serial. These local fixtures prove SDK behavior;
backend transactions and hosted performance require their separate acceptance.

A successful mutation is one HTTP POST; catalog/inventory are one logical GET
with the existing bounded read retry policy. Purchase uses the existing replay-safe
Player Values transport, followed by the caller's explicit inventory GET. The SDK
adds no server queries, grants, polling timers or hidden recovery requests.
simpleServer supports these REST shapes; its catalog administration uses the local
CLI. Realtime and validated actions remain hosted-only.

## Shared Objects: opaque bytes and explicit world-map pages

`Horizon.sharedObjects` exposes the seven player REST operations. Every call uses
the current project's API key and the matching player's Bearer session; no admin
credential belongs in a game. Results contain `success,data,errorCode,error`.
Success additionally returns an opaque local `identity` for `getCached(identity)`.
Cache access never performs network IO or authorizes a write.

```gdscript
var user_id: String = Horizon.auth.getCurrentUser().userId
var catalog: Dictionary = await Horizon.sharedObjects.getCollections(user_id)
var usage: Dictionary = await Horizon.sharedObjects.getUsage(user_id, "world")
# Render the reviewed usage first; invoke creation only from an explicit player action.
if usage.success:
    var created: Dictionary = await Horizon.sharedObjects.createObject(
        user_id, "world", usage.data.revision, PackedByteArray([0, 255, 1]),
        {"power": 100}, {"x": 4, "y": 8})
    if created.success:
        var object: Dictionary = created.data.object
        print(object.id, object.revision, object.data) # PackedByteArray, never parsed as game JSON.

var page: Dictionary = await Horizon.sharedObjects.queryObjects(user_id, "world", {
    "mode": "rectangle", "minX": 0, "maxX": 10, "minY": 0, "maxY": 10, "limit": 20})
# An empty page with nextCursor is valid. Request the next page explicitly with the
# unchanged query and that exact cursor; there is no automatic traversal or timer.
```

Signatures (all async calls return `Dictionary`):

- `getCollections(user_id, after_key="", limit=50, catalog_revision=null)`
- `getUsage(user_id, collection)`
- `getObject(user_id, collection, object_id)`
- `queryObjects(user_id, collection, query:Dictionary)`
- `createObject(user_id, collection, expected_usage_revision, data:PackedByteArray, search:Dictionary, position=null, group_id="")`
- `updateObject(user_id, collection, object_id, expected_revision, data:PackedByteArray, search:Dictionary, position=null)`
- `deleteObject(user_id, collection, object_id, expected_revision)`

Collections use one permanent read/write schema. Configure collections through the
Dashboard/Account Key or self-hosted CLI. Returned definitions and existing objects
can exceed a downgraded current tier; the SDK preserves them within the global
64KiB object bound. Bytes remain exact, including empty data/NUL/high-bit values.
Every object preserves `dataBase64` and adds decoded `data:PackedByteArray`.
`groupId`, `position` and `expiresAt` remain null when absent, and empty `search`
remains `{}`. Collection catalog pages keep the original revision across explicit
pages. No implicit catalog load, grant or new identity is performed.

All revisions/positions/integer search values use exact JSON integer tokens within
±9007199254740991. Floats, exponents, quoted integers, duplicate decoded fields,
unpaired Unicode and noncanonical Base64 fail before state replacement. Native
Godot strings cannot represent U+0000. Such metadata strings use the existing
immutable `HorizonItemStringData` wrapper, with `getOriginalJson()`, canonical
`getJson()`, `getUtf8ByteCount()` and visibly escaped `getDisplayPreview()`. Other
strings remain ordinary `String`. Pass the original wrapper back in `search` to
preserve every code point; a display preview is never an unchanged write value.
`HorizonSharedObjectModels.parse()` can construct a lossless metadata dictionary
from original JSON text. Payload bytes require no string conversion.

Queries support one owner/group partition and `list`, `owner`, `field` equality or
range, `rectangle`, and integer-field `random` modes. Random results are varied,
nonuniform and have no next cursor. One result page contains at most50 objects and
1MiB decoded data. Refresh uses returned `pollAfterSeconds` (normally120); explicit
next pages may proceed immediately subject to ordinary rate limits. An early repeat
returns local `REFRESH_NOT_DUE` with `retryAfterSeconds`;
`getRefreshDelaySeconds(identity)` reports the remaining interval. The sample
uses explicit `getRecoveryUsage` and own-player `queryRecoveryObjects` reads only
to reconcile a pending write; these bypass refresh cadence without retrying writes.
Query POST is
read-only and may use bounded read retries with the frozen original body. Create,
update and delete each use one transport attempt and the exact original If-Match:
usage revision for create, object revision for update/delete. A timeout requires
explicit state recovery; never silently refresh a revision or create again to
recover a lost ID. Repeated deletion can correctly return OBJECT_NOT_FOUND.

Host/project/player/session generations, including A→B→A changes and callback
invalidations, fence queued/late responses. Cache versions/times never move backward
within the retained resource window. Local caching is bounded to8 responses and512
revision/time/deletion fences; it adds no server calls. Signals are
`objects_loaded(kind,data)`, `objects_changed(kind,data)` and
`shared_objects_failed(error,code)`. Realtime/chat and background polling are absent.

The executable `examples/features/shared_objects_example.gd` supplies explicit
collection/usage reads, owned-marker create/read/update, rectangle pages and reviewed
deletion. It durably saves the complete original body, IDs and revision before a
single write. The project/player namespace excludes regional host and credentials.
Uncertain/failed writes block further writes across sample instances and restart;
there is deliberately no uncertain-create replay function. `inspect_pending()`
reads stable owner usage and one owner page; explicitly continue its cursor until
complete. Only an explicit `acknowledge_reconciliation()` after reviewing the full
owner state can release the guard, and a changed monotone revision fences late old
CAS writes. Unchanged usage/target revisions remain unconfirmed. Corrupt state,
interrupted files, stale locks and save/ack failures block new work and require
reconciliation with the original state. No automatic file deletion or new ID.

For asynchronous PvP, store opaque defense bytes with numeric `power` and call
`sample_opponents()` for a bounded range. `begin_defense_run(selected_defense, leaderboard_key)` passes the frozen bytes and
SHA-256 digest to the existing Cloud-only Validated Actions start route. The game
plays those bytes with the returned seed, records its actual input log, then calls
`submit_defense_run(score,input_log)`. Known terminal start/submit rejections release the sample binding. An explicit SDK
discard releases a known run only if no submit was sent. An uncertain start or
submit keeps the guard; use the original VA lifecycle rather than replacing it. This
adds one logical start and one submit (plus existing optional requested evidence);
it never infers a winner or validates a battle. Durable ordinary defender Inbox
notice delivery runs only on the trusted backend (the scoped hosted route or the
simpleServer backend-only recipe), with a frozen defense/run binding, original
UUID and finite expiry. Never ship its Account Key in a client. Normal Shared
Objects REST works on simpleServer; Validated Actions and realtime retain their
Cloud-only boundaries.

`tests/run_transport_tests.sh` includes strict/lossless/byte/page/retention policy
checks and an actual loopback HTTP sample chain covering all seven routes,
original headers, restart/read-only recovery, explicit cursors, frozen read retry,
malformed/stale/ABA replies, Cloud VA defense start/submit, and exactly
one503/429/timeout Shared Objects mutation attempt. Each normal feature call adds
one logical HTTP request (read retries are bounded); one explicit pending recovery
page adds two usage reads and one owner query. No recovery pages run automatically. Native
engine, exact-source CI and backend/runtime proof are recorded separately.


## Matches: explicit asynchronous turns and result consensus

`Horizon.matches` uses the currently signed-in player session. All methods return
`{success, data, errorCode, error}`. Pass exact integer revisions from the state the
player actually reviewed. There are four reads and ten one-attempt commands:

| Method | Arguments after `user_id` |
| --- | --- |
| `getMatches` | `recovery = false` |
| `getLimits` | none |
| `findOpenMatches` | `minimum_strength, maximum_strength, limit = 20, cursor = ""` |
| `getMatch` | `match_id, recovery = false` |
| `createMatch` | `expected_player_revision, options` |
| `joinMatch`, `declineInvite`, `advanceTimeout`, `leaveMatch`, `cancelMatch` | `match_id, expected_revision` |
| `startMatch` | `match_id, expected_revision, turn_order` |
| `submitTurn` | `match_id, expected_revision, state: PackedByteArray, finish = false` |
| `reportResult` | `match_id, final_state_revision, result: PackedByteArray, winner_ids` |
| `startRankedRun` | `match_id, final_state_revision` |

UUID arguments are normalized to their canonical lowercase representation before
sending or comparing effects; uppercase invitees cannot turn a committed create
into an apparent failure. Create options use the exact fields `name`, `capacity`, `visibility`, `strength`,
`turnSeconds`, `timeoutPolicy`, `ranked`, `dataBase64`, `inviteeIds`. Use
`Horizon.matches.encodeState(bytes)` for canonical Base64. Views retain wire
`dataBase64` and add `data: PackedByteArray`; invite-only metadata has both null.
Reports similarly expose exact `resultBase64` and `result: PackedByteArray`. Safe
integer lexemes, nullable deadlines, false and empty byte arrays survive parsing.
A name containing U+0000 is a lossless `HorizonItemStringData`: use `getJson()` for
exact serialization and its marked display preview for UI. No game JSON decoding
or client-authored rewards occur. An active match can appear in `recent` after the
current player forfeits while other players continue.

The executable [`matches_example.gd`](addons/horizon_sdk/examples/features/matches_example.gd)
uses a separate signed-in client for each of two players: read ledger, persist
create with original ledger revision, invite/accept/start, alternate byte-state
turns, finish, then collect both immutable result reports. A missing report leaves
an unconfirmed result; disagreement remains visible as disputed. Explicit timeout
advancement applies the configured skip/forfeit policy. `notificationPending=true`
means the move succeeded while its original Inbox notice awaits room. Do not send
another move to deliver it. Realtime only invalidates: subscribe to an authorized
`matches:<id>` through the existing realtime manager and explicitly reread after
reconnect. There is no background polling or automatic timeout, report or paging.

Every sample write is saved before HTTP under project/player/feature identity.
Host, session and monotone generation fence responses without selecting a new
pending file. Storage errors, restarts, callbacks, context changes and uncertain
responses retain the original. A busy or unresolved earlier action blocks new
writes. `inspect_pending()` only reads. After displaying recovered state,
`acknowledge_reconciliation()` requires an explicit decision and a higher monotone
ledger/match revision, which prevents a still-late original CAS from applying.
404 alone proves no outcome. Lost decline/lobby-leave acknowledgements use the
complete player ledger: absence of the original match removes membership/invite
authority, while a retained match requires a higher original revision. Explicit
`RUN_EXPIRED`/`RUN_ALREADY_USED` responses allow a separate terminal acknowledgement
of the original ranked intent; they never start a replacement run. An immutable report/ranked request may instead use
`retry_original_report_or_run()` with the original final revision and bytes.
Never silently replace a revision, create ID or result after timeout.

Ordinary reads obey `pollAfterSeconds`; `recovery=true` is an explicit recovery
read, and exact next-cursor pages can be requested immediately. No automatic page
traversal occurs, including empty consumed pages with a cursor. Eight response
cache entries and bounded revision/time histories are scoped to host/project/
player/session generation, including ABA; signal callbacks cannot adopt old data.

Optional Cloud-only ranked starts require a confirmed match and its original final
revision. The response enters `Horizon.validatedActions` with the original run ID,
seed, ticket and expiry, so existing submit/evidence flows apply. General and
match starts share an owned in-flight lease held through callbacks. A foreign
active run blocks match start; an adopted match run blocks general start until
explicit discard or submission. Original recovery may reseal the same ticket;
it cannot create another run after expiry/consumption. The sample submits the
game's actual score/input log for a short post-match rule check. This does not
retrospectively simulate the asynchronous game or establish an anti-cheat claim.
PHP ordinary REST is supported; capability flags disable ranked/realtime and
`501 FEATURE_NOT_SUPPORTED` remains visible.

Each explicit command sends one HTTP request; bounded GET retries preserve the
same request context. Existing authentication/rate-limit work is additional. No
SDK calls or timers generate hidden traffic. The native fixture exercises all14
routes with two sessions, original durable CAS, opaque bytes, full-Inbox pending,
reports, one-attempt faults, recovery and common VA start/submit ownership; these
are local contract proofs, separate from hosted capacity measurements.

### Chat: HTTP commands and push snapshots

`Horizon.chat` returns `{success, data, errorCode, error}` for all six REST methods.
Every method starts with the current signed-in `user_id`; identifiers must be
canonical lowercase UUIDs and timestamps must contain exactly three UTC milliseconds.

| Method | Arguments after `user_id` |
| --- | --- |
| `getLimits` | none |
| `openChannel` | `kind, peer_id = "", group_id = ""` |
| `syncChannel` | `channel_id` |
| `sendMessage` | `channel_id, operation_id, issued_at, text` |
| `getOperation` | `operation_id` |
| `reportMessage` | `channel_id, message_id, reason` |

Open direct channels only for mutual friends, group channels for current members,
or `project` with neither peer nor group ID. After opening, call
`watchChannel(user_id, channel_id)`. The manager subscribes through
`Horizon.realtime`, waits for the current socket's authorization and resync,
then loads the first snapshot. `channel_changed(channel_id, snapshot)` supplies
the complete ordered feed, including an empty channel. A later metadata event
loads only unknown text using the complete cached epoch/ID set. Each channel has
at most one sync in flight plus one dirty bit. Eight watched channels is a local
memory bound; another watch fails instead of silently dropping an existing feed.
`stopWatching(channel_id)` explicitly unsubscribes.
Multiple views can pass a stable optional `owner` string to `watchChannel` and
`stopWatching`; up to32 owners share one channel subscription. Releasing a view
does not unsubscribe another owner. The demo creates its own owner and releases
it on scene exit; a newly opened view immediately receives the authorized cache.

`getCached(channel_id)` returns an isolated copy. Disconnect, permission resync,
authorization denial, project/player/session/host generation changes and local
expiry hide text. Fresh authorized subscription and complete sync are required
before restoring it. Missing/duplicate/foreign payloads never become a partial
success. Revisions and retired channel epochs cannot restore an older feed.
`channel_hidden` lets a UI clear its display immediately. There is no periodic
poll, disconnected HTTP fallback, automatic page traversal or background send.
Explicit `syncChannel` also requires an acknowledged current subscription.

Open, send and report perform exactly one transport attempt, including503 and429.
Only read-only sync and GET use the existing bounded frozen-request retry policy.
Retain the original send UUID, canonical `issued_at`, channel and exact UTF-8 text
after any uncertain result; never replace them to retry. `getServerTime()` gives
the latest accepted server time plus elapsed monotonic time for a new intent.
Receipt responses contain metadata, not text. A missing or expired operation
does not prove that the original never committed. Reports retain their original
channel/message/reason. Reports deduplicate only while the server retains the shared report.
Local history alone cannot establish a missing server message for a report. Plain text permits LF/TAB,
at most500 Unicode scalars/2000 UTF-8 bytes, and rejects other control characters.
Render it as plain text with markup disabled. PHP surfaces501 `NOT_SUPPORTED`.

The runnable [`chat_demo.tscn`](addons/horizon_sdk/examples/features/chat_demo.tscn)
uses the existing signed-in session and offers project/direct/group selection,
plain-text feed, explicit send/status/original retry and report controls. Its
[`chat_example.gd`](addons/horizon_sdk/examples/features/chat_example.gd) saves
the original intent before HTTP under project/player/feature identity; host and
session only fence callbacks. The bounded checksummed journal uses an exclusive
lock and atomic replacement. Partial, corrupt or abandoned-lock storage blocks
new sends. A successful original receipt is persisted before freeing its slot;
a late ACK cannot free a newer original. Restart recovery reads the original
operation first and never automatically generates another identity or send.
The game must separately handle any blocked journal through explicit recovery.

Native fixtures use actual HTTP and WebSocket connections for first-message push,
20-ID incremental snapshots, permissions/reconnect, one-attempt faults and original
lost-ACK recovery. These local proofs are distinct from hosted two-player,
fanout/CPU/storage measurements and official game integration.


Chat also exposes `await Horizon.chat.requestChannelSnapshot(user_id, channel_id, epoch = "", known_message_ids = [])`
for one explicit raw REST snapshot, including disconnected `NOT_SUPPORTED` checks. Empty epoch
encodes null; known IDs refer only to the caller's complete snapshot under that original epoch.
The typed `{success,data,errorCode,error}` result contains the raw incremental envelope. It
never merges into the managed feed, owns no watch, updates no feed clock and schedules no retry
or polling. Host/project/session generation changes reject late replies. Keep `watchChannel`
and acknowledged `syncChannel` for interactive managed feeds.
Current authenticated401 still clears private feeds; channel denials affect only the captured current watch, so explicit raw reads cannot retain revoked content.


### Device Chat history

Hosted Chat is available in every tier, including Free. The server holds at most
20 project/global messages for seven days, or 15 direct/group transport messages
for 30 seconds. Private buffers do not promise offline delivery. `knownMessageIds`
contains at most 20 IDs from the live window, never IDs from the device archive.
A new operation must be later than the player's accepted issued-at floor and
server time minus 30 seconds, with at most 60 seconds future tolerance. Operation
lookup/replay uses the original message while it remains buffered. There is no
personal server receipt history. Missing operations remain uncertain. No send is
retried automatically, including after a local storage failure.

`Horizon.chat.readLocalHistory(channel_id, cursor = "", limit = 50)` returns
`{success,messages,nextCursor}` or a local `errorCode`. `clearLocalHistory(channel_id)`
and `clearAllLocalHistory()` explicitly erase only the current identity's device
copies. Listen to `local_history_changed(channel_id)` and
`local_history_failed(channel_id, code)`. The sample offers separate live and device
views plus read/older/clear controls and an optional channel UUID for offline reads.

The archive stores received immutable text and confirmed original send input. Its
scope hashes the API key and player, with one append-only UTF-8 JSONL log and one
append-only ID/hash/offset index per channel. No key or session token is stored in
plaintext. Only the small ID index is loaded on first use, then its appended tail.
Text reads are bounded per record (16 KiB) and page (at most 100 messages). Byte
cursors follow local delivery order, newest delivery first within every page.
An interrupted complete log append can repair its missing final index entry.
The lock publishes a PID/token owner atomically. A killed owner can be recovered without
removing another live owner. Desktop recovery uses a local PID probe. On mobile/Web,
an unrelated owner whose liveness cannot be established stays `LOCAL_HISTORY_BUSY`;
no stale lock is blindly deleted. Desktop native tests do not prove mobile recovery.
Damaged/locked/unwritable storage reports a local error and never resends a message.

Server eviction, expiry, moderation, epoch changes and revoked membership retain
already delivered device copies. The active feed still hides immediately. Same-identity
authenticated offline reads are allowed. Logout and project/player changes remove
access in memory. Captured request identity and persistent clear generations fence
late replies. Clear invalidates prior page cursors. A new device has no old archive,
and the SDK neither uploads it nor uses Cloud Save. There is no implicit local cap.
