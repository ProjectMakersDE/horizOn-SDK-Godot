# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **horizOn SDK for Godot 4.5+** - a GDScript-based plugin providing integration with the horizOn Backend-as-a-Service. The SDK is distributed as a Godot addon that game developers copy into their projects.

## Architecture

### Core Structure

```
addons/horizon_sdk/
├── horizon_sdk.gd          # Main singleton (Horizon autoload)
├── horizon_plugin.gd       # Editor plugin (@tool script)
├── core/                   # Feature managers
│   ├── http_client.gd      # Networking layer with retry/rate-limiting
│   ├── auth.gd             # Authentication (email, anonymous, Google)
│   ├── leaderboard.gd      # Score submission and rankings
│   ├── cloud_save.gd       # JSON/binary save data
│   ├── remote_config.gd    # Server-side configuration
│   ├── news.gd             # In-game announcements
│   ├── gift_codes.gd       # Promotional code redemption
│   ├── feedback.gd         # Bug reports/feature requests
│   ├── user_logs.gd        # Server-side event tracking
│   └── horizon_config.gd   # Configuration resource class
├── models/                 # Data classes (user_data, leaderboard_entry, etc.)
└── utils/                  # Logger and error codes
```

### Design Patterns

- **Singleton Pattern**: `Horizon` is registered as an autoload singleton via the plugin
- **Manager Pattern**: Each feature (auth, leaderboard, etc.) is a separate manager class accessed via `Horizon.auth`, `Horizon.leaderboard`, etc.
- **Signal-based async**: All network operations are async using GDScript's `await` and emit signals for event-driven handling
- **Resource-based config**: Configuration is stored as a `.tres` resource file imported from JSON

### Key Classes

- `HorizonHttpClient`: Core HTTP layer, handles host selection via ping, automatic retries, rate limiting (429), and API key/session token headers
- `HorizonAuth`: Manages user sessions, caches tokens to `user://horizon_cache.cfg`
- `HorizonConfig`: Resource class for storing API key and backend hosts

### API Endpoints

All API calls go to `/api/v1/app/*` endpoints. With a single host, the SDK performs a health check on `/actuator/health` and connects directly. With multiple hosts, the SDK pings all hosts and connects to the lowest-latency one.

## Running the Project

Open in Godot 4.5+ and run the main scene:
```
res://addons/horizon_sdk/examples/horizon_test_scene.tscn
```

The test scene (`horizon_test_ui.gd`) provides UI for testing all SDK features.

## Configuration

The SDK requires a config JSON from the horizOn dashboard with:
```json
{
    "apiKey": "your-api-key",
    "backendUrl": "https://horizon.pm"
}
```
Both `backendUrl` (single string) and `backendDomains` (array) are accepted. With a single host, the SDK skips ping-based selection and performs only a health check. With multiple hosts, latency-based selection is used.

Import via: **Project > Tools > horizOn: Import Config...**

Config is saved to: `addons/horizon_sdk/horizon_config.tres`

## Code Conventions

- GDScript with static typing (`: Type` annotations)
- Class names prefixed with `Horizon` (e.g., `HorizonAuth`, `HorizonUserData`)
- Private members prefixed with `_`
- All async methods return `bool` for success/failure and emit signals
- Error messages come from `HorizonErrorCodes` utility class

## Git Commits & Pull Requests

**CRITICAL: No AI attribution in commits or pull requests.**

- NEVER add `Co-Authored-By` lines mentioning Claude, Anthropic, or any AI
- NEVER include "Claude", "Claude Code", "AI-generated", "AI-assisted", or similar in commit messages
- NEVER reference AI tools in pull request titles or descriptions
- Commit messages must be clean, professional, and written as if authored by a human developer
