# Raycast quick-add

`plans-quick-add.sh` is a Raycast script command that adds a task to Plans
without opening the app, the same way Todoist's quick-add works.

## Setup

1. Launch the Plans macOS app at least once (this generates the auth token
   at `~/.plans_app/quickadd_token`).
2. In Raycast: **Extensions → Script Commands → Add Script Directory**, and
   point it at this `raycast/` directory.
3. Run "Quick Add to Plans" from Raycast, type a task, hit Enter.

The task text accepts the same grammar as the in-app composer —
`Buy milk tomorrow p1 @Groceries`.

## How it works

The app runs a tiny local HTTP server (`lib/shared/quickadd/quickadd_server.dart`)
bound to `127.0.0.1:51793` only — it is never reachable from another machine.
Every request must carry the bearer token from `~/.plans_app/quickadd_token`
(file permissions `600`); the only unauthenticated route is `GET /health`.

The server keeps running even after you close the Plans window (it only
stops when you fully quit the app), so quick-add works without the window
popping up.

This is a local-machine convenience feature, not a sync/remote API — don't
expose port 51793 beyond loopback.
