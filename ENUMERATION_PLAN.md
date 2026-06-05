# Enumeration & Change Tracking Plan

Tracking doc for fleshing out FileProvider enumeration end-to-end: polling for remote changes, `enumerateChanges`, working-set enumeration, and sync anchors. Designed to span multiple PRs and multiple AI sessions.

## Goal

Today `SSHadow/ExtensionKit/Enumerator.swift` only implements `enumerateItems` for ordinary directories. The sync anchor is a constant, `enumerateChanges` is a no-op, and `.workingSet` enumeration returns nothing. We want macOS to learn about remote changes (new files, deletes, mtime bumps) without the user having to manually re-navigate into a directory.

## Architectural decisions

- **`ItemModel` is the persisted twin of `Item`.** Same fields (`kind`, `size`, `permissions`, `accessTime`, `modifyTime`, `createTime`) stored as SwiftData columns. `Item` is the XPC/boundary Codable struct; `ItemModel` is the `@Model` class. A bridge (`ItemModel.init(from: Item)` + `ItemModel.toItem()`) keeps them in sync.
- **Virtual containers** (`.rootContainer`, `.workingSet`, `.sshadowContainer`, `.trashContainer`) carry a sentinel `kind = .folder` with other snapshot fields `nil`. Polling skips them by id.
- **Pull-style change delivery.** Agent identifies changes, signals the extension via `NSFileProviderManager.signalEnumerator(for: .workingSet)`, and the extension calls `enumerateChanges` on its own schedule.
- **Anchors are per-domain monotonic `Int`s**, encoded into `NSFileProviderSyncAnchor`. The agent owns the anchor; the extension treats it as opaque.
- **In-memory first.** The first end-to-end implementation keeps the anchor and the pending change list in memory on the `Session`. When the agent restarts, the anchor resets and `enumerateChanges` reports the anchor as expired so macOS re-enumerates from scratch. Persistence lands once the polling/signaling loop is proven.

## Concrete pieces

Each step is intended to be one PR. Mark `[x]` and include the PR number once merged so future sessions can `git log` for context.

### Step 0 — Rename `PathNode` → `ItemModel`

- [x] Rename `SSHadow/AgentKit/PathNode.swift` → `ItemModel.swift` and the class.
- [x] Rename `SSHadow/AgentKitTests/PathNodeTests.swift` → `ItemModelTests.swift`.
- [x] Update all call sites.

### Step 1 — Create RPCs return `Item`

- [x] Change RPC signatures from `(itemId, …)` to `(parentId, name, …) -> Item`: `createDirectory`, `createSymlink`, `upload`.
- [x] In `Session`, each operation: resolve parent path → run SFTP op → stat → insert `ItemModel(id: UUID, parentId, name)` → return `Item`.
- [x] Update `Extension.createItem`: drop the upfront `agent.child(...)`, call the new RPC, return the resulting `Item` directly.
- [x] Drop `ifNotExists` from `AgentClient.child` / `ChildRequest`.
- [x] Migrate test scaffolding off `agent.child(...,.create)`.

### Step 2 — Snapshot file metadata on `ItemModel`

- [x] Add fields: `kind` (non-optional), `size`, `permissions`, `accessTime`, `modifyTime`, `createTime`.
- [x] Virtual containers carry `kind = .folder` and `nil` for the rest.
- [x] `Session.list()` and `Session.item(for:)` upsert snapshots.
- [x] SwiftData lightweight migration with defaults for existing rows.

### Step 3 — Serve `list` and `item` from DB cache

- [x] Add `enumeratedAt: Date?` to `ItemModel` so empty-but-enumerated folders are distinguishable from never-enumerated ones.
- [x] Make symlink targets non-nullable: `Item.Kind.symlink(target: String)` and `ItemModel.Kind` to match; resolve the target during the SFTP listing pass and cache it.
- [x] `Session.list(for:)` — on cache hit (item's `enumeratedAt` is non-nil) return children from DB; on miss, fetch over SFTP, populate children, stamp `enumeratedAt`.
- [x] `Session.item(for:)` — on cache hit return from DB; on miss, stat over SFTP and refresh.

### Step 4 — In-memory polling, signaling, and `enumerateChanges`

The full end-to-end loop, with all state held on the `Session`. No new schema. The point of this step is to prove the FileProvider contract works end-to-end — `signalEnumerator` reaches the extension, `enumerateChanges` is invoked with the right anchor, `syncAnchorExpired` actually triggers a re-enumeration — before investing in persistence.

- [ ] On `Session`, add in-memory state:
  - `anchor: Int` — starts at 0 on session create; bumped per poll cycle that produced any change.
  - `pendingUpdates: [String: Item]` — keyed by item id; later changes overwrite earlier ones for the same id.
  - `pendingDeletes: Set<String>` — item ids deleted.
- [ ] **Working set == every non-virtual `ItemModel` in the DB for v1.** No separate set on `Session`. Since `ItemModel` rows only exist because macOS resolved an id through `list` / `child(of:)`, "everything in the DB" is already a close approximation of "everything macOS knows about." Slight over-reporting through `.workingSet` is harmless; Step 6 introduces an explicit membership column.
- [ ] Polling task on `Session` (start at 30s interval, behind a constant):
  1. Pick the set of directories to re-list: every `ItemModel` with `enumeratedAt != nil`, minus virtual containers.
  2. Re-list each over SFTP.
  3. Diff against current `ItemModel` snapshots: added, removed, or `(size, modifyTime)`-changed children.
  4. Apply: upsert/insert `ItemModel` rows, delete missing rows, update snapshots.
  5. Merge deltas into `pendingUpdates` / `pendingDeletes`.
  6. If anything changed, bump `anchor` by 1 and call `NSFileProviderManager.signalEnumerator(for: .workingSet)`.
- [ ] Add `ChangesRequest(domainId, since: Data) → ChangesResponse(items: [Item], deletedIds: [String], anchor: Data, expired: Bool)` to `Common/AgentProtocol.swift` and `AgentClient`.
- [ ] Agent handler:
  - Decode `since` as `Int`. If `since > anchor` (agent restarted, extension is ahead) or `since < earliestKnownAnchor` (we only keep "everything since session start"; any older anchor is expired), return `expired = true` with the current `anchor`. macOS treats this as a signal to re-enumerate.
  - Otherwise return the current `pendingUpdates.values` and `pendingDeletes`, plus the current `anchor`.
  - **Open: when to clear pending state.** Simplest v1: clear `pendingUpdates`/`pendingDeletes` on every successful `enumerateChanges` response. Risk: if there's ever more than one observer per session, the second observer misses events. We only have `.workingSet` as an observer today, so this is fine for now — revisit in step 6.
- [ ] `Enumerator.swift`:
  - `currentSyncAnchor` calls `agent.currentSyncAnchor(domainId:)` (returns the encoded `Int`).
  - `enumerateChanges(for: anchor, observer:)` calls `agent.changes(domainId:, since:)`, feeds `observer.didUpdate`/`observer.didDeleteItem`, and either calls `finishEnumeratingChanges(upTo:moreComing:)` or — when `expired = true` — `finishEnumeratingWithError(NSFileProviderError(.syncAnchorExpired))`.
  - `enumerateItems(.workingSet, …)` calls a new `agent.listWorkingSet(domainId:) -> [Item]` that returns every non-virtual `ItemModel` in the DB.
- [ ] Add `currentSyncAnchor` and `listWorkingSet` RPCs to `AgentProtocol`/`AgentClient`.
- [ ] Log timestamps at the `signalEnumerator` call site and at `enumerateChanges` entry so we have rough visibility into wake-up lag while tuning the poll interval.
- [ ] Integration test against the local sshd: create a file out-of-band, run one poll cycle, assert `pendingUpdates` grew and the anchor bumped.
- [ ] Manual check in the running app: write a file via plain `ssh` on the test server; within one poll interval Finder reflects it.

**Acceptance:** out-of-band remote changes appear in Finder within one poll interval, without persisting anchors or a change journal.

### Step 5 — Persist anchor and change journal

Now that polling/signaling is proven, move the in-memory state into `DomainDB` so agent restarts don't force a full re-enumeration.

- [ ] Persist `currentAnchor: Int` per domain in `DomainDB`.
- [ ] Add a `ChangeRecord` `@Model` with `anchor: Int`, `itemId: String`, `kind: ChangeKind` (`.updated` / `.deleted`), indexed on `anchor`.
- [ ] `DomainDB` helpers: `bumpAnchor() -> Int`, `appendChanges([(itemId, kind)])` (atomic with the snapshot writes from polling), `changes(since: Int) -> (records: [ChangeRecord], upTo: Int, expired: Bool)`.
- [ ] Replace the `Session` in-memory `anchor` / `pendingUpdates` / `pendingDeletes` with these helpers.
- [ ] `expired` semantics: `since < oldestAnchor` (after pruning) returns `expired = true`.
- [ ] Tests cover bump, append, `changes(since:)` including "no changes," "anchor from the future," and "anchor below floor."

**Acceptance:** restart the agent mid-session; pending changes survive and the extension consumes them on next `enumerateChanges`.

### Step 6 — Working-set membership column + multi-observer support

- [ ] Add `workingSet: Bool` to `ItemModel`, replacing the v1 "everything in the DB" approximation.
- [ ] Set the flag in `Session.list`, `Session.download`, `Session.stream`.
- [ ] `agent.listWorkingSet` queries by column.
- [ ] Drop the "clear pending on read" hack from step 4: per-observer progress is now tracked purely by anchor — observers ask for "everything `> their last anchor`" and the journal serves them independently.

**Acceptance:** Finder's working-set view shows the items the agent has materialized; multiple enumerators can safely consume the journal.

### Step 7 — Tighten and observe

- [ ] Confirm per-directory `enumerateChanges` can stay a thin no-op (macOS only polls the working-set enumerator in practice).
- [ ] Journal pruning: drop records below the minimum anchor seen in the last hour.
- [ ] Tune polling interval + jitter; consider pausing on inactivity.
- [ ] Document the anchor + polling story in `CLAUDE.md` under "Key Patterns."

## Open questions

- Does macOS reliably invoke `enumerateChanges` after `signalEnumerator`, and is the wake-up lag small enough that the poll interval is the dominant factor in user-perceived latency? (Observe during step 4.)
- Coalesce/debounce signals if many changes land in one poll?
- Poll directories outside the working set (e.g. "recent locations")?
- Pruning policy once the journal has run for days.
