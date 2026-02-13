<p align="center">
  <a href="https://horizon.pm">
    <img src="https://horizon.pm/media/images/og-image.png" alt="horizOn - Game Backend & Live-Ops Dashboard" />
  </a>
</p>

# horizOn SDK for Godot

[![Godot 4.5+](https://img.shields.io/badge/Godot-4.5%2B-blue?logo=godot-engine&logoColor=white)](https://godotengine.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-orange)](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/releases)

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
```

## Configuration Options

Edit your config resource at `addons/horizon_sdk/horizon_config.tres`:

| Option | Default | Description |
|--------|---------|-------------|
| `api_key` | - | Your horizOn API key |
| `hosts` | - | Array of backend server URLs |
| `connection_timeout_seconds` | 10 | HTTP request timeout |
| `max_retry_attempts` | 3 | Retry count for failed requests |
| `retry_delay_seconds` | 1.0 | Delay between retries |
| `log_level` | INFO | DEBUG, INFO, WARNING, ERROR, NONE |

## Example Project

The SDK includes a test scene demonstrating all features:

```
res://addons/horizon_sdk/examples/horizon_test_scene.tscn
```

## Support

- 📖 **Documentation**: [docs.horizon.pm](https://docs.horizon.pm)
- 💬 **Discord**: [discord.gg/horizOn](https://discord.gg/JFmaXtguku)
- 🐛 **Issues**: [GitHub Issues](https://github.com/ProjectMakersDE/horizOn-SDK-Godot/issues)

## License

MIT License - Copyright (c) [ProjectMakers](https://projectmakers.de)

See [LICENSE](LICENSE) for details.
