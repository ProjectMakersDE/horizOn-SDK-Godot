<p align="center">
  <a href="https://horizon.pm">
    <img src="https://horizon.pm/media/images/og-image.png" alt="horizOn - Game Backend & Live-Ops Dashboard" />
  </a>
</p>

# horizOn SDK for Godot

[![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.7.2-orange)](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases)

Official Godot SDK for **horizOn** Backend-as-a-Service by [ProjectMakers](https://projectmakers.de).

## Features

| Feature | Description |
|---------|-------------|
| 🔐 **Authentication** | Email, anonymous, Google, and Apple sign-in/sign-up |
| 🏆 **Leaderboards** | Submit scores, get rankings, view top players |
| ☁️ **Cloud Saves** | Save and load player progress (JSON or binary) |
| ⚙️ **Remote Config** | Server-side configuration values |
| 🌐 **Localization** | Server-side translations in 15 languages |
| 📰 **News** | In-game news and announcements |
| 🎁 **Gift Codes** | Validate and redeem promotional codes, unlock cosmetics |
| 🧑 **Player Profile** | Avatar, frame and badges per player, shown on leaderboards |
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

```gdscript
# Email authentication
await Horizon.auth.signUpEmail("user@example.com", "password", "Username")
await Horizon.auth.signInEmail("user@example.com", "password")

# Anonymous authentication
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

`redeem` needs a signed-in player and sends the player session (`Authorization: Bearer`). The server only redeems codes for the player who owns that session.

```gdscript
var isValid = await Horizon.giftCodes.validate("ABCD-1234")
var result = await Horizon.giftCodes.redeem("ABCD-1234")
if result.get("success", false):
    var rewards = result.get("giftData", "")
    # Cosmetics unlocked by the code (`grants`), [] for codes without grants.
    # The cached player profile is dropped, the next getProfile() shows them.
    var unlocked: Array = result.get("grantedUnlocks", [])
```

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

A ticket is single use. After an accepted run, a `422` rejection and `403 SCORE_LIMIT_REACHED` the current run is cleared; after network errors, `401`, `404`, `429` and `503` it stays so you may retry with the same ticket. A new ticket needs a new `startRun()`. Sign-out also clears the run. After an accepted board run the leaderboard cache is cleared.

Error codes from `getLastErrorCode()` and the `*_failed` signals: local `SESSION_REQUIRED`, `NO_ACTIVE_RUN`, `INVALID_INPUT_LOG_HASH`; ticket `TICKET_INVALID`, `TICKET_EXPIRED`, `TICKET_FOREIGN`, `TICKET_CONSUMED`, `LEADERBOARD_MISMATCH`; rules `STAGE_REQUIRED`, `STAGE_UNKNOWN`, `SCORE_ABOVE_MAX`, `SCORE_BELOW_MIN`, `STAGE_SCORE_ABOVE_MAX`, `STAGE_SCORE_BELOW_MIN`, `DURATION_TOO_SHORT`, `SCORE_RATE_TOO_HIGH`; others `SCORE_REQUIRED`, `PLAYER_NAME_REQUIRED`, `SCORE_LIMIT_REACHED`, `SESSION_FORBIDDEN`, `PLAYER_NOT_FOUND`, `LEADERBOARD_NOT_FOUND`, `RUN_RATE_LIMITED` and `RUN_CAPACITY_REACHED` (`429`, not retried automatically, the wait can be an hour), `VALIDATED_ACTIONS_UNAVAILABLE`, `NOT_SUPPORTED`. Without a server code the SDK error name is used (for example `NETWORK_ERROR`).

A leaderboard with **Validated submissions only** (`validatedOnly: true` in `listBoards()`) refuses `submitScore()`: it returns `false` and `Horizon.leaderboard.getLastErrorCode()` is `VALIDATED_SUBMIT_REQUIRED`.

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

# Cloud Save
Horizon.cloudSave.data_saved.connect(func(size): print("Saved %d bytes" % size))
Horizon.cloudSave.data_loaded.connect(func(data): print("Loaded"))

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

**Limit**: 10 requests per minute per client.

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

    # 7 requests remaining for gameplay
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
│   ├── validated_actions.gd # Validated runs (tickets, submit, hash helper)
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
- 💬 **Discord**: [discord.gg/horizOn](https://discord.gg/JFmaXtguku)
- 🐛 **Issues**: [GitHub Issues](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues)

## License

MIT License - Copyright (c) [ProjectMakers](https://projectmakers.de)

See [LICENSE](LICENSE) for details.
