# horizOn SDK for Godot 4.5+

Official Godot SDK for **horizOn** Backend-as-a-Service by ProjectMakers.

## Features

- **Authentication**: Email, anonymous, and Google sign-in/sign-up
- **Leaderboards**: Submit scores, get rankings, view top players
- **Cloud Saves**: Save and load player progress (JSON or binary)
- **Remote Config**: Server-side configuration values
- **News**: In-game news and announcements
- **Gift Codes**: Validate and redeem promotional codes
- **Feedback**: Submit bug reports and feature requests
- **User Logs**: Server-side player event tracking

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
```

### Cloud Saves (Horizon.cloudSave)

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

```gdscript
# Validate a code
var isValid = await Horizon.giftCodes.validate("ABCD-1234")

# Redeem a code
var result: Dictionary = await Horizon.giftCodes.redeem("ABCD-1234")
if result.get("success", false):
    var giftData = result.get("giftData", "")
    print("Rewards: %s" % giftData)
```

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

### Cloud Save
```gdscript
Horizon.cloudSave.data_saved.connect(func(size): print("Saved %d bytes" % size))
Horizon.cloudSave.data_loaded.connect(func(data): print("Loaded: %s" % data))
```

## Example Scene

Open the example scene to test all SDK features:
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

- Documentation: https://docs.horizon.pm
- Discord: https://discord.gg/projectmakers
- Issues: https://github.com/projectmakers/horizon-godot-sdk/issues

## License

MIT License - Copyright (c) ProjectMakers
