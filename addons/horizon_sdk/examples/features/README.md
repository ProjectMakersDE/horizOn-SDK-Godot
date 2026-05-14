# horizOn SDK Feature Examples (Godot)

One small, runnable script per horizOn feature. Each file shows the
minimal flow for that feature, with error handling wired through the
feature's signals and return values.

## Files

| Feature | Script |
|---|---|
| Auth (anonymous + email) | `auth_example.gd` |
| Leaderboards | `leaderboard_example.gd` |
| Cloud Save | `cloud_save_example.gd` |
| Crash Reporting | `crash_reporting_example.gd` |
| User Logs | `user_logs_example.gd` |
| Remote Config | `remote_config_example.gd` |
| News | `news_example.gd` |
| Email Sending | `email_sending_example.gd` |
| Gift Codes | `gift_codes_example.gd` |
| Feedback | `feedback_example.gd` |

## How to run an example

1. Enable the horizOn SDK plugin and import your config via Project > Tools > horizOn: Import Config.
2. Create a new scene with a single `Node` root and attach the example script you want to try.
3. Run the scene. Output goes to the Godot Output panel.

Each script's header comment lists what it does and the expected output.
Some examples need values from your Dashboard, the email and gift code
scripts say which placeholders to replace.

For a guided first run that connects, signs in, and submits a score,
see `../hello_horizon/`.
