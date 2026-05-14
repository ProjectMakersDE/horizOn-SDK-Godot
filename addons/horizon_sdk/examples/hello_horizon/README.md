# Hello horizOn (Godot)

The smallest possible horizOn integration: connect, sign in
anonymously, submit a leaderboard score, and show the result. Use
this as your first run before exploring the per-feature examples in
`../features/` or the full test UI in `../horizon_test_scene.tscn`.

## Start in 3 steps

1. Copy the `addons/horizon_sdk` folder into your project and enable the plugin in Project > Project Settings > Plugins.
2. Import your app key: Project > Tools > horizOn: Import Config, then select the JSON from your Dashboard.
3. Open and run `hello_horizon.tscn`.

You should see the status update on screen and in the Output panel as
it connects, signs in, and submits a score, finishing with your
leaderboard rank.

## What it shows

`hello_horizon.gd` walks the minimal flow with error handling at every
step:

- `Horizon.connect_to_server()` picks the fastest server.
- `Horizon.quickSignInAnonymous()` creates or restores an anonymous user.
- `Horizon.leaderboard.submitScore()` sends a score.
- `Horizon.leaderboard.getRank()` reads the result back for display.
