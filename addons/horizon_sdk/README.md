# horizOn SDK for Godot 4.5+

Official Godot SDK for **horizOn** Backend-as-a-Service by ProjectMakers.

## Features

- **Authentication**: Email, anonymous, Google, and Apple sign-in/sign-up
- **Leaderboards**: Submit scores, get rankings, view top players
- **Cloud Saves**: Save and load player progress (JSON or binary)
- **Remote Config**: Server-side configuration values
- **Localization**: Server-side translations in 15 languages
- **News**: In-game news and announcements
- **Gift Codes**: Validate and redeem promotional codes, unlock cosmetics
- **Player Profile**: Avatar, frame and badges per player, shown on leaderboards
- **Validated Actions**: Server-checked runs: single-use tickets, server seed, rule checks before a score is written
- **Feedback**: Submit bug reports and feature requests
- **User Logs**: Server-side player event tracking
- **Crash Reporting**: Automatic crash capture, exception tracking, breadcrumbs
- **Email Sending**: Send transactional emails to players with templates and scheduling

## Installation

1. Copy the `addons/horizon_sdk` folder to your project's `addons` directory
2. Enable the plugin in **Project > Project Settings > Plugins**
3. Import your config JSON: **Project > Tools > horizOn: Import Config...**
4. The `Horizon` singleton will be automatically available

## Configuration

### Importing Config from horizOn Dashboard

1. Download your config JSON file from the horizOn dashboard
2. In Godot, go to **Project > Tools > horizOn: Import Config...**
3. Select your downloaded JSON file
4. The config will be saved to `addons/horizon_sdk/horizon_config.tres`

The config JSON should have this format:
```json
{
    "apiKey": "your-api-key-here",
    "backendUrl": "https://horizon.pm"
}
```

If you need multi-region host selection (SDK pings all hosts and picks the fastest), use `backendDomains` instead:
```json
{
    "apiKey": "your-api-key-here",
    "backendDomains": [
        "https://eu.horizon.pm",
        "https://us.horizon.pm",
        "https://as.horizon.pm"
    ]
}
```

### Managing Configuration

- **Edit Config**: Project > Tools > horizOn: Edit Config
- **Clear Cache**: Project > Tools > horizOn: Clear Cache

## Quick Start

```gdscript
extends Node

func _ready():
    # Config is loaded automatically from horizon_config.tres
    # Just connect to server
    var connected = await Horizon.connect_to_server()
    if not connected:
        print("Failed to connect!")
        return

    # Quick anonymous sign-in
    var signed_in = await Horizon.quickSignInAnonymous("Player1")
    if signed_in:
        print("Welcome, %s!" % Horizon.getCurrentUser().displayName)
```

## API Reference

### Connection

```gdscript
# Connect to the best available server (config loaded automatically)
var success: bool = await Horizon.connect_to_server()

# Check connection status
if Horizon.isConnected():
    print("Connected to: %s" % Horizon.getActiveHost())

# Check if SDK is configured
if Horizon.isInitialized():
    print("SDK ready!")

# Disconnect
Horizon.disconnect_from_server()
```

### Authentication (Horizon.auth)

```gdscript
# Sign up with email
var success = await Horizon.auth.signUpEmail("user@example.com", "password", "Username")

# Sign in with email
var success = await Horizon.auth.signInEmail("user@example.com", "password")

# Anonymous authentication
# The server issues the anonymous token: signUpAnonymous() stores it and signs in with it
var success = await Horizon.auth.signUpAnonymous("DisplayName")
var success = await Horizon.auth.signInAnonymous("cached-token")
var success = await Horizon.auth.restoreAnonymousSession()

# Check if signed in
if Horizon.isSignedIn():
    var user = Horizon.getCurrentUser()
    print("User ID: %s" % user.userId)
    print("Display Name: %s" % user.displayName)
    print("Auth Type: %s" % user.authType)

# Sign out
Horizon.auth.signOut()

# Change display name
var success = await Horizon.auth.changeName("NewName")

# Check auth status
var isValid = await Horizon.auth.checkAuth()

# Password reset flow
await Horizon.auth.forgotPassword("user@example.com")
await Horizon.auth.resetPassword("token-from-email", "newPassword")

# Email verification
await Horizon.auth.verifyEmail("verification-token")
```

### Leaderboards (Horizon.leaderboard)

```gdscript
# Submit a score
var success = await Horizon.leaderboard.submitScore(1000)

# Get top 10 players
var entries: Array[HorizonLeaderboardEntry] = await Horizon.leaderboard.getTop(10)
for entry in entries:
    print("%d. %s: %d" % [entry.position, entry.username, entry.score])

# Get your rank
var myRank: HorizonLeaderboardEntry = await Horizon.leaderboard.getRank()
print("My position: %d" % myRank.position)

# Get players around your position
var around: Array[HorizonLeaderboardEntry] = await Horizon.leaderboard.getAround(5)

# Every entry (and the rank) carries the player's profile, never null
for entry in around:
    if entry.profile.hasAvatar():
        print("%s uses %s" % [entry.username, entry.profile.avatarId])
```

### Cloud Saves (Horizon.cloudSave)

Sign in before saving or loading. JSON and binary requests carry the player session.
Binary loads POST a JSON `userId` body and request `application/octet-stream`; a missing save returns empty bytes.

```gdscript
# Save JSON string
var success = await Horizon.cloudSave.saveData('{"level": 5, "coins": 1000}')

# Load JSON string
var data: String = await Horizon.cloudSave.loadData()

# Save/load Dictionary
var success = await Horizon.cloudSave.saveObject({"level": 5, "coins": 1000})
var dict: Dictionary = await Horizon.cloudSave.loadObject()

# Save/load binary data
var bytes = "Hello World".to_utf8_buffer()
var success = await Horizon.cloudSave.saveBytes(bytes)
var loaded: PackedByteArray = await Horizon.cloudSave.loadBytes()
```

### Remote Config (Horizon.remoteConfig)

```gdscript
# Get a single config value
var value: String = await Horizon.remoteConfig.getConfig("game_version")

# Get with type conversion
var maxLevel: int = await Horizon.remoteConfig.getInt("max_level", 100)
var difficulty: float = await Horizon.remoteConfig.getFloat("difficulty", 1.0)
var maintenance: bool = await Horizon.remoteConfig.getBool("maintenance_mode", false)

# Get all configs
var configs: Dictionary = await Horizon.remoteConfig.getAllConfigs()

# Clear cache
Horizon.remoteConfig.clearCache()
```

### News (Horizon.news)

```gdscript
# Load news
var entries: Array[HorizonNewsEntry] = await Horizon.news.loadNews(20, "en")
for entry in entries:
    print("%s - %s" % [entry.title, entry.message])

# Clear cache
Horizon.news.clearCache()
```

### Gift Codes (Horizon.giftCodes)

`redeem` needs a signed-in player and sends the player session (`Authorization: Bearer`). The server only redeems codes for the player who owns that session.

```gdscript
# Validate a code
var isValid = await Horizon.giftCodes.validate("ABCD-1234")

# Redeem a code
var result: Dictionary = await Horizon.giftCodes.redeem("ABCD-1234")
if result.get("success", false):
    var giftData = result.get("giftData", "")
    print("Rewards: %s" % giftData)
    # Cosmetics unlocked by the code (`grants`), [] for codes without grants.
    # The cached player profile is dropped, the next getProfile() shows them.
    print("Unlocked: %s" % result.get("grantedUnlocks", []))
```

### Player Profile (Horizon.playerProfile)

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

### Validated Actions (Horizon.validatedActions)

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

### Feedback (Horizon.feedback)

```gdscript
# Submit feedback
var success = await Horizon.feedback.submit(
    "Bug Report",
    "Found a bug in level 3",
    "BUG",                    # Category: GENERAL, BUG, FEATURE
    "user@example.com",       # Optional contact email
    true                      # Include device info
)

# Convenience methods
await Horizon.feedback.submitBugReport("Title", "Description")
await Horizon.feedback.submitFeatureRequest("Title", "Description")
```

### User Logs (Horizon.userLogs)

```gdscript
# Create log entries
await Horizon.userLogs.info("Player completed tutorial")
await Horizon.userLogs.warn("Low memory detected")
await Horizon.userLogs.error("Failed to load asset", "ERR_ASSET_001")

# Log custom events
await Horizon.userLogs.logEvent("level_complete", "Level 5 completed")
```

## Signals

### SDK Lifecycle
```gdscript
Horizon.sdk_initialized.connect(func(): print("SDK initialized"))
Horizon.sdk_connected.connect(func(host): print("Connected to: %s" % host))
Horizon.sdk_connection_failed.connect(func(error): print("Failed: %s" % error))
Horizon.sdk_disconnected.connect(func(): print("Disconnected"))
```

### Authentication
```gdscript
Horizon.auth.signup_completed.connect(func(user): print("Signed up: %s" % user.userId))
Horizon.auth.signup_failed.connect(func(error): print("Signup failed: %s" % error))
Horizon.auth.signin_completed.connect(func(user): print("Signed in: %s" % user.userId))
Horizon.auth.signin_failed.connect(func(error): print("Signin failed: %s" % error))
Horizon.auth.signout_completed.connect(func(): print("Signed out"))
```

### Leaderboard
```gdscript
Horizon.leaderboard.score_submitted.connect(func(score): print("Score: %d" % score))
Horizon.leaderboard.top_entries_loaded.connect(func(entries): print("Loaded top"))
Horizon.leaderboard.rank_loaded.connect(func(entry): print("Rank: %d" % entry.position))
```

### Player Profile
```gdscript
Horizon.playerProfile.profile_loaded.connect(func(profile): print("Profile: %s" % profile["profile"]))
Horizon.playerProfile.profile_load_failed.connect(func(error, code): print("Load failed [%s]: %s" % [code, error]))
Horizon.playerProfile.profile_updated.connect(func(profile): print("Saved: %s" % profile["profile"]))
Horizon.playerProfile.profile_update_failed.connect(func(error, code): print("Save failed [%s]: %s" % [code, error]))
```

### Validated Actions
```gdscript
Horizon.validatedActions.run_started.connect(func(run): print("Run %s, seed %d" % [run["runId"], run["seed"]]))
Horizon.validatedActions.run_start_failed.connect(func(error, code): print("Start failed [%s]: %s" % [code, error]))
Horizon.validatedActions.run_submitted.connect(func(result): print("Accepted, rank %d" % result["rank"]))
Horizon.validatedActions.run_submit_failed.connect(func(error, code): print("Rejected [%s]: %s" % [code, error]))
Horizon.validatedActions.state_loaded.connect(func(state): print("Values: %d" % state["values"].size()))
Horizon.validatedActions.state_load_failed.connect(func(error, code): print("State failed [%s]: %s" % [code, error]))
Horizon.validatedActions.evidence_uploaded.connect(func(run_id): print("Evidence uploaded: %s" % run_id))
Horizon.validatedActions.evidence_upload_failed.connect(func(run_id, error, code): print("Evidence failed [%s]: %s" % [code, error]))
```

### Cloud Save
```gdscript
Horizon.cloudSave.data_saved.connect(func(size): print("Saved %d bytes" % size))
Horizon.cloudSave.data_loaded.connect(func(data): print("Loaded: %s" % data))
```

## Examples

### Hello horizOn

The fastest first run. `hello_horizon` connects, signs in
anonymously, submits a leaderboard score, and shows the result on
screen. Start in 3 steps:

1. Copy the `addons/horizon_sdk` folder into your project and enable the plugin in Project > Project Settings > Plugins.
2. Import your app key: Project > Tools > horizOn: Import Config.
3. Open and run `res://addons/horizon_sdk/examples/hello_horizon/hello_horizon.tscn`.

See `examples/hello_horizon/README.md` for details.

### Per-feature examples

`examples/features/` holds one small, runnable script per feature
(`auth_example.gd`, `leaderboard_example.gd`, `cloud_save_example.gd`,
`crash_reporting_example.gd`, `user_logs_example.gd`,
`remote_config_example.gd`, `news_example.gd`,
`email_sending_example.gd`, `gift_codes_example.gd`,
`feedback_example.gd`, `player_profile_example.gd`,
`validated_actions_example.gd`, `validated_state_example.gd`). Each shows the minimal flow for that feature
with error handling. Attach a script to a `Node` and run the scene to
try it. See `examples/features/README.md` for the run steps.

### Full test UI

Open the example scene to exercise every SDK endpoint from one UI:
`res://addons/horizon_sdk/examples/horizon_test_scene.tscn`

## Project Settings

You can configure the SDK via exported properties on the Horizon autoload node, or programmatically:

```gdscript
# Set log level
Horizon.setLogLevel(HorizonLogger.LogLevel.DEBUG)

# Available levels: DEBUG, INFO, WARNING, ERROR, NONE
```

## Error Handling

All async methods return success/failure indicators. Use signals for event-driven error handling:

```gdscript
Horizon.auth.signin_failed.connect(_on_signin_failed)

func _on_signin_failed(error: String):
    print("Sign in failed: %s" % error)
    # Show error to user
```

## Data Models

### HorizonUserData
```gdscript
var user = Horizon.getCurrentUser()
user.userId        # Unique user ID
user.email         # Email (empty for anonymous)
user.displayName   # Display name
user.authType      # "ANONYMOUS", "EMAIL", or "GOOGLE"
user.accessToken   # Session token
user.isAnonymous   # True if anonymous user
```

### HorizonLeaderboardEntry
```gdscript
entry.position     # Rank (1-indexed)
entry.username     # Player name
entry.score        # Score value
entry.profile      # HorizonPlayerProfileData, never null
```

### HorizonPlayerProfileData
```gdscript
profile.avatarId     # Avatar ID ("" = not set)
profile.frameId      # Frame ID ("" = not set)
profile.badges       # Array[String], 0 to 3, order kept
profile.hasAvatar()  # True if avatarId is set
profile.hasFrame()   # True if frameId is set
```

### Validated Actions models
`Horizon.validatedActions` returns Dictionaries built by these null safe models
(JSON `null` becomes "", 0 or an empty object):
```gdscript
HorizonValidatedRun           # runId, ticket, seed, leaderboardKey ("" = unbound), issuedAt, expiresAt, expiresInSeconds
HorizonValidatedSubmitResult  # accepted, runId, leaderboardKey, score, bestScore, isNewHighScore, rank, durationSeconds, state, evidence
HorizonValidatedPlayerState   # userId, day, values, getBalance(key), getValue(key), isFullyCredited(key), isPresent()
HorizonValidatedEvidenceRequest # required, runId, uploadBefore, maxBytes (filled from Part 3 on)
```

### HorizonNewsEntry
```gdscript
entry.id           # News ID
entry.title        # Title
entry.message      # Content
entry.releaseDate  # ISO 8601 date
entry.languageCode # e.g., "en"
```

## Requirements

- Godot 4.5+
- horizOn API key (get one at https://horizon.pm)

## Support

- Documentation: https://horizon.pm/quickstart
- Discord: https://discord.gg/projectmakers
- Issues: https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues

## License

MIT License - Copyright (c) ProjectMakers
