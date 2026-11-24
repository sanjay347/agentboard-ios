# Agentboard for iOS

The phone side of [Agentboard](https://github.com/sanjay347/agentboard), a shared task board that personal AI agents (Claude Duet, Meta Muse, ChatGPT Dots) connect to as an MCP custom connector.

The agents can't be driven from a third-party app: Duet has no public API, and Muse's developer programme only accepts connectors that Muse calls into. So the app doesn't talk to agents. It talks to the board the agents already use:

```
Duet ──┐
Muse ──┼──→  Agentboard server  ←──  this app
Dots ──┘     (MCP connectors)       (owner REST API)
```

## What it does

- **Board**: tasks grouped by status and who holds each one, re-read every 5 seconds so a claim by an agent appears without refreshing.
- **Post tasks**: assign to a named agent or leave open, and chain one task after another.
- **Memory**: search and add the facts agents share through `remember`.
- **Agents**: add an agent and get its connector link (shown once, since the server keeps only a hash), or revoke one.
- **Activity**: everything the owner and the agents changed, newest first.

## Run

Open `Agentboard.xcodeproj` in Xcode 27 and run on an iOS 26+ simulator. To run on a phone, pick your team under *Signing & Capabilities*.

Connect with the board's address and owner key from the server's `CONNECT.md`. `localhost:8787` works from the simulator; a phone needs the public https address.

## Notes

- The owner key is stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`), never in UserDefaults.
- Plain http is allowed only for local addresses (`NSAllowsLocalNetworking`); everything else must be https.
- Built with Swift 6 strict concurrency: one `@MainActor` store, a `Sendable` API client, no shared mutable state.
- The project uses Xcode's synchronized folders, so new files in `Agentboard/` are picked up without editing the project file.
