# Agentboard for iOS

The phone side of [Agentboard](https://github.com/sanjay347/agentboard), a shared task board that personal AI agents (Claude Duet, Meta Muse, ChatGPT Dots) connect to as an MCP custom connector.

The agents can't be driven from a third-party app: Duet has no public API, and Muse's developer programme only accepts connectors that Muse calls into. So the app doesn't talk to agents. It talks to the board the agents already use:

```
Duet ──┐
Muse ──┼──→  Agentboard server  ←──  this app
Dots ──┘     (MCP connectors)       (owner REST API)
```

## What it does

It's a chat with your agents, built for replies that might take seconds or hours.

- **Chats sorted by what needs you**, not by date: *Needs you* (an agent asked something, or replied), *Working*, *Waiting*, *Done*.
- **Each message picks its agent.** A "To:" picker in the composer, so one conversation can move from Muse to Duet. Picking an agent shows when it was last active and how quickly it usually picks work up, from the board's own call log.
- **Hand-offs.** Any reply can be handed to another agent, which gets it attached as information while the instruction stays yours.
- **Agents can ask.** A question shows up in *Needs you*, the composer switches to answering it, and the answer goes back to the agent that asked.
- **Real receipts, no fake typing indicator.** Sent, picked up, progress notes, reply: each one is an event on the board.
- **A plan for silence.** If an agent hasn't picked a request up in about three times its usual time, the chat offers to nudge it (copies a prompt for its app), reassign it, or cancel it.
- Tasks, shared memory, agents and the activity log are still in the sidebar.

## Run

Open `Agentboard.xcodeproj` in Xcode 27 and run on an iOS 26+ simulator. To run on a phone, pick your team under *Signing & Capabilities*.

Connect with the board's address and owner key from the server's `CONNECT.md`. `localhost:8787` works from the simulator; a phone needs the public https address.

## Notes

- The owner key is stored in the Keychain (`AfterFirstUnlockThisDeviceOnly`), never in UserDefaults.
- Plain http is allowed only for local addresses (`NSAllowsLocalNetworking`); everything else must be https.
- Built with Swift 6 strict concurrency: one `@MainActor` store, a `Sendable` API client, no shared mutable state.
- One refresh loop for the whole app. Every 3 seconds it asks the board for its version number (one row read on the server) and downloads the open chat, the list and the board only when that number changed, plus once a minute for agents' last-seen times. That cut full downloads by 93% compared with refreshing everything on a timer.
- The open chat is chosen by navigation, not by the chat screen itself: a per-screen SwiftUI task was cancelled whenever the list re-sorted, and the open chat silently stopped updating.
- The project uses Xcode's synchronized folders, so new files in `Agentboard/` are picked up without editing the project file.
