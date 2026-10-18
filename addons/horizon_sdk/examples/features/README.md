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
| Localization | `localization_example.gd` |
| News | `news_example.gd` |
| Email Sending | `email_sending_example.gd` |
| Gift Codes | `gift_codes_example.gd` |
| Feedback | `feedback_example.gd` |
| Player Profile | `player_profile_example.gd` |
| Player Values | `player_values_example.gd` (configure energy-pack; persists uncertain purchase intent) |
| Statistics | `statistics_example.gd` (configure kills/sum and best_score/max first) |
| Inbox | `inbox_example.gd` (explicit refresh/claim; persists the authorized original entry ID) |
| Items | `items_example.gd` (explicit item offer/purchase, inventory, equip/adjust/discard) |
| Achievements | `achievements_example.gd` (progress, atomic permanent-key unlock, legacy reward-status helpers) |
| Validated Actions | `validated_actions_example.gd` |
| Validated Actions: server-owned player state | `validated_state_example.gd` |
| Validated Actions: evidence upload | `validated_evidence_example.gd` |

## How to run an example

1. Enable the horizOn SDK plugin and import your config via Project > Tools > horizOn: Import Config.
2. Create a new scene with a single `Node` root and attach the example script you want to try.
3. Run the scene. Output goes to the Godot Output panel.

Each script's header comment lists what it does and the expected output.
Some examples need values from your Dashboard, the email, gift code,
player profile, validated state and validated evidence scripts say what to set up or replace.

For a guided first run that connects, signs in, and submits a score,
see `../hello_horizon/`.

Groups: `groups_example.gd` provides explicit authenticated create/update, one member
page and all fourteen caller-confirmed actions. Preserve reviewed revisions and
request UUIDs after uncertainty; reconcile with an explicit read. The actual sample
is executed by the two-player Groups HTTP fixture; it neither polls nor replaces
a guest identity. Transfer leadership before leaving; private data stays member-only.

Items: attach `items_example.gd` to a Node and call its methods from explicit UI
buttons after signing in. Configure an active item template and Player Values item
offer first. `review_offer` displays fresh terms; `purchase_reviewed_offer` checks
them again, persists the original operation ID and then sends. Call
`retry_pending_purchase` after uncertainty; a confirmed purchase with a failed
inventory refresh resumes GET only. Pending action files preserve exact instance
and revision until explicit fresh-read reconciliation. Do not delete an expired or
corrupt guard to create another operation. The sample does not run any purchase,
property delta or discard from `_ready`, `_process` or a polling loop. Each discard
needs its own explicit destructive confirmation. NUL-containing property strings
use the lossless ItemStringData wrapper documented in the SDK README.
