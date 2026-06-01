# Enumeration & Change Tracking Plan

Tracking doc for fleshing out FileProvider enumeration end-to-end: real sync anchors, `enumerateChanges`, working-set enumeration, and Agent-side polling for remote changes. Designed to span multiple PRs and multiple AI sessions.

## Goal

Today `SSHadow/ExtensionKit/Enumerator.swift` only implements `enumerateItems` for ordinary directories. The sync anchor is a constant, `enumerateChanges` is a no-op, and `.workingSet` enumeration returns nothing. We want macOS to learn
about remote changes (new files, deletes, mtime bumps) without the user having to manually re-navigate into a directory.

## Architectural decisions

- **`ItemModel` becomes the persisted twin of `Item`.** Same fields (`kind`, `size`, `permissions`, `accessTime`, `modifyTime`, `createTime`) stored as SwiftData columns, not via a separate `ItemSnapshot` table. The 1:1 cardinality makes a side-table pure overhead. `Item` stays the XPC/boundary type — they can't be _one_ type because `Item` is a Codable struct shared with the extension while `@Model` requires a class in `AgentKit` with associated-value enum flattening. A bridge (`ItemModel.init(from: Item)` + `ItemModel.toItem()`) keeps the field shapes in sync. This migration lands first (steps 1 + 2) because every downstream piece reads or writes these fields.
- **Create RPCs return `Item`, not take `itemId`.** `createDirectory(parentId:, name:, mode:)`, `createSymlink(parentId:, name:, target:)`, `upload(parentId:, name:, file:, mode:, progress:)` each do the SFTP op, stat the result, insert a fully-populated `ItemModel`, and return the `Item`. Atomic on the success path; nothing written on failure. This eliminates the "reservation `ItemModel`" lifecycle (allocated by the extension before the file exists, orphaned on create failure) and lets snapshot fields be non-optional.
- **Virtual containers (`.rootContainer`, `.workingSet`, `.sshadowContainer`, `.trashContainer`)** keep a sentinel `kind = .folder` with other snapshot fields `nil`. Polling filters them by id.
- **Pull-style change delivery.** Agent writes change records to `DomainDB` and pokes the extension via `NSFileProviderManager.signalEnumerator(for:)`. The extension calls `enumerateChanges` on its own schedule and reads the journal. No long-lived XPC stream. Open question: how fast does macOS actually spin the extension up after a signal? Measure during step 7.
- **Anchors are per-domain monotonic `UInt64`**, persisted in `DomainDB`, serialized into `NSFileProviderSyncAnchor` as big-endian `Data`.
- **Journal is append-only.** Add pruning in step 8; unbounded for v1.
- **Working-set membership is materialization-driven.** Any item the extension has handed to macOS via `list`/`fetchContents` is in the working set until evicted. Tracked via a `workingSet: Bool` column on `ItemModel`.

## Concrete pieces

Each step is intended to be one PR. Mark `[x]` and include the PR number once merged so future sessions can `git log` for context. Steps 1 and 2 are the prerequisite migration and could land as a single PR if small.

### Step 0 — Rename `PathNode` → `ItemModel`

Mechanical rename, kept as its own PR so the step 1/2 diffs stay focused.

- [x] Rename `SSHadow/AgentKit/PathNode.swift` → `ItemModel.swift` and the `PathNode` class → `ItemModel`.
- [x] Rename `SSHadow/AgentKitTests/PathNodeTests.swift` → `ItemModelTests.swift`.
- [x] Update all call sites (24 references across `DomainDB`, tests, and `CLAUDE.md`).

### Step 1 — Create RPCs return `Item`

Pure protocol + lifecycle refactor; no schema change. Establishes the
invariant "every `ItemModel` row is server-confirmed," which step 2 relies on.

- [x] Change RPC signatures in `Common/AgentProtocol.swift` and `Common/AgentClient.swift` from `(itemId, …)` to `(parentId, name, …) -> Item`: `createDirectory`, `createSymlink`, `upload`.
- [x] In `Session`, each operation: resolve parent path → run SFTP op → stat → insert `ItemModel(id: UUID, parentId, name)` → return `Item`.
- [x] Update `Extension.createItem` (Extension.swift:202-278): drop the upfront `agent.child(...)`, call the new RPC, return the resulting `Item` directly. The trailing `item(for: itemIdentifier)` lookup goes away.
- [x] Leave `Session.list()`'s `child(of:path:)` call (Session.swift:127) alone — it has full metadata at hand and writes a real `ItemModel`.
- [x] Tests: failed create leaves zero new rows; successful create leaves exactly one row matching the returned `Item.id`.
- [x] Migrate existing tests that use `child(...,.create)` to fabricate ids for files they then create — they should use the new RPCs.

**Follow-up (separate PR):** With the create RPCs owning row insertion, `AgentClient.child`'s `ifNotExists: .create` mode is no longer needed by production callers. The only remaining caller is `Extension.setAttributes` (Extension.swift:450), and by the time it runs the row always exists. `Session.list` still upserts by name internally via `db.child`, which is unaffected. Plan:

- [x] Drop `ifNotExists` from `AgentClient.child` / `ChildRequest` (always `.fail`); rename to something like `lookup` if a clearer name helps.
  - [x] Drop ifNotExists from ChildRequest in AgentProtocol.swift
  - [x] Drop ifNotExists from AgentClient.child
  - [x] Update Agent.child handler to drop ifNotExists
  - [x] Drop ifNotExists from Session.child; update Session.list to use db.child
- [x] Migrate test scaffolding that currently fabricates ids via `agent.child(path: ...)` to either `agent.list(for: parentId)` + pick-by-name, or to the create RPCs when the test itself is creating the file.
  - [x] Migrate SessionTests scaffolding
  - [x] Migrate AgentClientTests scaffolding
  - [x] Migrate ExtensionTests scaffolding
  - [x] Migrate EnumeratorTests scaffolding

**Acceptance:** failing a create leaves no row in `ItemModel`; a successful create leaves exactly one row with `(id, parentId, name)` populated. Snapshot fields land in step 2.

### Step 2 — Snapshot file metadata on `ItemModel`

- [x] Add fields to `ItemModel`: `kind` (non-optional), `size`, `permissions`, `accessTime`, `modifyTime`, `createTime` (optionality matching `Item`).
- [x] In `DomainDB.configure()` (DomainDB.swift:39-68), give the four virtual containers `kind = .folder` and leave the rest `nil`.
- [x] Wire snapshot writes:
  - [x] `Session.list()` (Session.swift:127) — upsert each child's snapshot after building the `Item`. (Currently this metadata is thrown away.)
  - [x] `Session.item(for:)` (Session.swift:90) — refresh the snapshot.
  - [x] The step-1 commit path already populates on insert.
  - [x] `Session.move()` (Session.swift:238) — no snapshot work; next `list`/poll catches any mtime bump.
- [x] SwiftData lightweight migration with defaults for existing rows.
- [x] Tests: snapshot populated after `list`; virtual containers carry their sentinel.

**Acceptance:** every non-virtual `ItemModel` carries the same `size`/`modifyTime` as the corresponding `Item`.

### Step 3 — Serve `list` and `item` from DB cache

Prerequisite: step 2 (snapshot fields populated). After this step, SFTP is only contacted on a cold cache; correctness relies on the polling loop (step 7) to keep stale data from accumulating indefinitely.

- [ ] Add `enumeratedAt: Date?` to `ItemModel` so an empty-but-enumerated directory is distinguishable from a never-enumerated one (without this, a folder with zero children would always look like a cache miss). The timestamp also gives step 7's polling loop a natural "last refreshed" signal. Folder-only in intent; stays `nil` on file/symlink rows.
- [x] Make symlink targets non-nullable: change `Item.Kind.symlink(target: String?)` → `symlink(target: String)` and the matching `ItemModel.Kind` case. Today, every symlink returned from `list` triggers a follow-up `stat` to resolve the target — by resolving proactively during the SFTP round-trip and caching the result on `ItemModel.symlinkTarget`, we eliminate that second hop. The invariant "if `kind == .symlink`, target is populated" lets callers stop branching on nil.
- [ ] `Session.list(for:)` — check `DomainDB` for children of the item. On cache hit (item's `enumeratedAt` is non-nil), return `ItemModel.toItem()` for each child without an SFTP round-trip. On cache miss, fetch from SFTP, resolve any symlink children's targets in the same pass, populate children, and stamp `enumeratedAt` on the item in the same transaction.
- [ ] `Session.item(for:)` — check `DomainDB` for the item's snapshot. On cache hit (row exists), return from DB. On cache miss, stat over SFTP (resolving the symlink target if applicable) and refresh the snapshot.
- [ ] Tests: assert no SFTP calls occur when the cache is warm (including the empty-directory case and symlink reads); assert SFTP is called and DB is populated — with the symlink target resolved — when the cache is cold.

**Acceptance:** a directory listed once is served from DB on subsequent `list` calls with no SFTP round-trip; `item(for:)` likewise for items already snapshotted.

### Step 4 — Real sync anchors + change journal in `DomainDB`

- [ ] Persist a `currentAnchor: UInt64` per domain in `DomainDB`.
- [ ] Add a `ChangeRecord` `@Model` with `anchor: UInt64`, `itemId: String`, `kind: ChangeKind` (`.updated` / `.deleted`), indexed on `anchor`.
- [ ] `DomainDB` helpers:
  - [ ] `bumpAnchor() -> UInt64`
  - [ ] `appendChanges(_ records: [(itemId, kind)])` — batches; bumps the anchor atomically.
  - [ ] `changes(since: UInt64) -> (records: [ChangeRecord], upTo: UInt64)`
- [ ] `NSFileProviderSyncAnchor` ↔ `UInt64` encoding helpers.
- [ ] Replace the hardcoded `"an anchor"` in `SSHadow/ExtensionKit/Enumerator.swift` with the real anchor (new `agent.currentSyncAnchor(domainId:)` or piggyback on `list`).
- [ ] Tests cover bump, append, `changes(since:)` including "no changes" and "anchor from the future."

**Acceptance:** unit tests pass; logs show the anchor advancing in `currentSyncAnchor` after wiring a bump into one write op as a smoke test.

### Step 5 — `enumerateChanges` reads the journal

- [ ] Add `ChangesRequest(domainId, since: Data) → ChangesResponse(items: [Item], deletedIds: [String], upTo: Data, moreComing: Bool)` to `Common/AgentProtocol.swift`.
- [ ] Agent side: query `DomainDB.changes(since:)`, hydrate `.updated` via `ItemModel` (snapshot is authoritative after step 2), pass raw ids for `.deleted`.
- [ ] Wire `Enumerator.enumerateChanges` to feed `observer.didUpdate` / `observer.didDeleteItem`.
- [ ] Every mutating agent op appends to the journal so we can validate end-to-end before any polling exists.
- [ ] Integration check in the running app: write a file via Finder, confirm the change reaches the extension and re-renders.

**Acceptance:** local mutations produce `enumerateChanges` events without needing a directory re-list.

### Step 6 — Working-set membership tracking

- [ ] Add `workingSet: Bool` to `ItemModel`.
- [ ] Set the flag when the agent returns an item from `list` or `download`/`stream`. Revisit `fetchContents`-only later.
- [ ] Add `agent.listWorkingSet(domainId:) -> [Item]` and implement `enumerateItems(.workingSet)` in `Enumerator.swift`.
- [ ] Tests for both the flag and the new enumeration path.

**Acceptance:** Finder's working-set view shows the items that have been materialized.

### Step 7 — Polling loop in `Session`

- [ ] Opt-in polling task that on each interval:

      1. Collects "interesting" directories: parents of every working-set `ItemModel` plus any directory currently being enumerated (small in-memory set updated from `list`).
      2. Re-lists each over SFTP.
      3. Diffs against the snapshot on `ItemModel`: added, missing, or `(size, modifyTime)`-changed children.
      4. Batches the deltas into `appendChanges` and updates snapshots in the same transaction.
      5. Pokes the extension via `NSFileProviderManager.signalEnumerator( for: .workingSet)`. Signal path: a one-way XPC message to a long-lived extension callback (fire-and-forget, not a stream).

- [ ] Interval + jitter behind a constant; start at 30s.
- [ ] "Always poll while the domain is mounted" is fine for v1; revisit pausing on inactivity later.
- [ ] Integration test against the local sshd: create a file out-of-band, run a poll cycle, assert the journal grew.
- [ ] **Instrument latency** between `signalEnumerator` and the resulting `enumerateChanges` — log both with timestamps to answer the spin-up question.

**Acceptance:** create a file via plain `ssh` on the test server; within one poll interval Finder reflects it.

### Step 8 — Tighten and observe

- [ ] Confirm per-directory `enumerateChanges` can stay a thin no-op (macOS only polls the working-set enumerator in practice).
- [ ] Journal pruning: drop records below the minimum anchor seen in the last hour.
- [ ] Document the anchor + polling story in `CLAUDE.md` under "Key Patterns."

## Open questions (revisit during/after step 7)

- How fast does macOS invoke `enumerateChanges` after `signalEnumerator`?
- Coalesce/debounce signals if many changes land in one poll?
- Poll directories outside the working set (e.g. "recent locations")?
- Pruning policy once the journal has run for days.
