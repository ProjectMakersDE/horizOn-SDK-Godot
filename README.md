<p align="center">
  <a href="https://horizon.pm">
    <img src="https://horizon.pm/media/images/og-image.png" alt="horizOn - Game Backend & Live-Ops Dashboard" />
  </a>
</p>

# horizOn SDK for Godot

[![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.2.3-orange)](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases)

Official Godot SDK for **horizOn** Backend-as-a-Service by [ProjectMakers](https://projectmakers.de).

## Features

| Feature | Description |
|---------|-------------|
| 🔐 **Authentication** | Email, anonymous, and Google sign-in/sign-up |
| 🏆 **Leaderboards** | Submit scores, get rankings, view top players |
| ☁️ **Cloud Saves** | Save and load player progress (JSON or binary) |
| ⚙️ **Remote Config** | Server-side configuration values |
| 📰 **News** | In-game news and announcements |
| 🎁 **Gift Codes** | Validate and redeem promotional codes |
| 💬 **Feedback** | Submit bug reports and feature requests |
| 📊 **User Logs** | Server-side player event tracking |
| 💥 **Crash Reporting** | Automatic crash capture, exception tracking, breadcrumbs |

## Requirements

- Godot 4.5 or later
- horizOn API key ([Get one at horizon.pm](https://horizon.pm))

## Installation

### Option 1: Asset Library (Recommended)

1. Open Godot and go to **AssetLib**
2. Search for "horizOn SDK"
3. Download and install
4. Enable the plugin in **Project > Project Settings > Plugins**

### Option 2: Manual Installation

1. Download the latest release from [Releases](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases)
2. Copy the `addons/horizon_sdk` folder to your project's `addons` directory
3. Enable the plugin in **Project > Project Settings > Plugins**

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

# Get current user
if Horizon.isSignedIn():
    var user = Horizon.getCurrentUser()
    print(user.userId, user.displayName, user.authType)

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

### News

```gdscript
var news: Array[HorizonNewsEntry] = await Horizon.news.loadNews(20, "en")
for entry in news:
    print("%s: %s" % [entry.title, entry.message])
```

### Gift Codes

```gdscript
var isValid = await Horizon.giftCodes.validate("ABCD-1234")
var result = await Horizon.giftCodes.redeem("ABCD-1234")
if result.get("success", false):
    var rewards = result.get("giftData", "")
```

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

# Cloud Save
Horizon.cloudSave.data_saved.connect(func(size): print("Saved %d bytes" % size))
Horizon.cloudSave.data_loaded.connect(func(data): print("Loaded"))

# Crash Reporting
Horizon.crashes.crash_reported.connect(func(fingerprint): print("Crash reported: %s" % fingerprint))
Horizon.crashes.crash_report_failed.connect(func(error): print("Report failed: %s" % error))
Horizon.crashes.session_registered.connect(func(session_id): print("Session: %s" % session_id))
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
│   ├── news.gd             # News
│   ├── gift_codes.gd       # Gift codes
│   ├── feedback.gd         # Feedback
│   ├── user_logs.gd        # User logs
│   └── crashes.gd          # Crash reporting
├── examples/
│   └── horizon_test_scene.tscn
└── horizon_config.tres      # Configuration resource
```

## Documentation

- **[Quickstart Guide](https://horizon.pm/quickstart#godot)** - Interactive setup
- **[API Reference](https://horizon.pm/docs)** - Full API documentation
- **[Example Scene](addons/horizon_sdk/examples/horizon_test_scene.tscn)** - Interactive demo of all features

## Support

- 📖 **Documentation**: [docs.horizon.pm](https://docs.horizon.pm)
- 💬 **Discord**: [discord.gg/horizOn](https://discord.gg/JFmaXtguku)
- 🐛 **Issues**: [GitHub Issues](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues)

## License

MIT License - Copyright (c) [ProjectMakers](https://projectmakers.de)

See [LICENSE](LICENSE) for details.
