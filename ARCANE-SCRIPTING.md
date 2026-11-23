# Arcane MP scripting — working notes

Facts verified against `@hogwartsmp/types` (the typed contract the docs site is generated from),
the `arcane-mp/docs` guides, and `arcane-mp/foundations`. Pin the types package to the server
release you deploy: `npm i -D @hogwartsmp/types@<server version>`.

## Resource anatomy

Discovery is **one level deep**: every directory directly under `resources/` holding a
`package.json` is a resource. `resources/my-gamemode/package.json` is found;
`resources/[group]/my-gamemode/` is **not**. Name the directory the same as the manifest `name` —
console commands use the manifest name, while logs attribute errors by directory.

```
resources/my-gamemode/
├── package.json      # manifest
├── server/main.js    # Node.js, never shipped to clients
└── client/main.js    # sandboxed V8 on each player
```

Manifest keys live under a top-level `mafiahub` object: `clientScripts`, `serverScripts`,
`sharedScripts` (run first, both sides), `files` (shipped, not executed; globs allowed),
`exports`, `resourceDependencies`, `errorBehavior` (`stop` | `restart` | `continue`).

- A manifest with no `mafiahub` block runs nothing; npm `main` is **not** an entry point.
- Load order comes from `resourceDependencies` (topologically sorted). `priority` is accepted but
  ignored on current releases — do not rely on it.
- Legacy singular `client` / `server` string keys still work, which is why the sample-resources
  repo looks different.

## The things this project needs, and what backs them

| Requirement | API |
|---|---|
| Floo / fast travel | `player.fastTravel(name)`, `setFastTravelUnlocked(ids, unlocked)`, `getFastTravelUnlocked()`, `travelToMap`, `travelToPlace`; events `playerFastTravelRequest` (**return `false` to refuse**), `playerFastTravelUnlocked`, `playerFastTravelComplete` |
| Press-F sit / interact | `player.startActivity(id, variant)` / `getActivity()` / `finishActivity()`; `WorldObject.create()` options carry `promptText`, `promptHeight`, `promptRange`; client `Hud.showPrompt(key, label, x, y, z)` |
| Inventory | `player.inventory`, server-side `InventoryCatalog`; events `playerInventoryChanged`, `playerInventoryUpdated` (with revision), `playerInventoryConsumed` |
| Economy / crafting | No built-in currency — ours. Gathering via `Lootables`, `LootSpots`, `Herbology`, `Brewing`; `lootableTaken` / `lootSpotTaken` events |
| Clubs + Room of Requirement | `Sanctuary` namespace, `playerSanctuaryEnter` / `playerSanctuaryLeave` / `sanctuaryChanged`; instancing via `setVirtualWorld(world)` on players and entities |
| Priority queue | `playerConnecting(connection)` fires **before a slot is held**: `connection.reject(reason)`, `connection.update(message)` to show queue status, and returning a promise delays admission |
| Identity | `PendingConnection` exposes `steamId`, `epicId`, **`discordId`**, `discordName`, `hardwareId`, `ip` |
| Spells / teaching | `Spells` (server); client `SpellLearning`, `Talents`, `Progression`; `playerSpellCast(player, spell, cast)` |
| House points | `HousePoints` namespace; `housePointsChange`, `housePointsRequest` (**`false` refuses**) |
| Houses | `player.house` is writable: `"Gryffindor" | "Hufflepuff" | "Ravenclaw" | "Slytherin" | "Unaffiliated"`; also `player.commonRooms[]` |

## Traps that will cost hours if missed

**There is no persistence.** The old `Storage` / `player.getData` / `player.setData` API was
**removed in 1.3.0** and appears nowhere in the current types. The official `sample-resources`
repo still calls it, so copying those samples produces code that throws. Use `entity.state` /
`World.state` (`StateBag`) for session state only — it is replicated, not durable — and an
external store for anything that must survive a restart.

**The RPC payload rule is asymmetric.** Server → client: `player.emit(name, JSON.stringify(obj))`
takes a **JSON string**. Client → server: `Events.emitServer(name, obj)` serializes for you, and
the server handler receives `(player, parsedObject)` — **player first**. `Events.emitAllClients`
also serializes for you. Client events land on a separate subscription table: `Events.onClient`,
not `Events.on`.

**Taking over `chatMessage` silences chat.** The server relays ordinary chat itself *until* any
resource listens for `chatMessage` — after that your handler is responsible for sending it on, or
nobody sees anything. There is no built-in rate limiting.

**Commands are not registered.** A `/` line raises `chatCommand(player, message, command, args)`;
every resource sees every command, so each must answer only its own and ignore the rest. Nothing
replies to an unknown command unless you do. Args split on whitespace with no quoting.

**No server tick event.** Use `setInterval` (server timers return a `Timeout`; client timers
return a `number`).

**`console` is limited.** Only `log/info/warn/error/debug` — `console.table` and friends *throw*.
Errors print as `{}` (log `error.stack`) and arrays print as `[Array(3)]` (`JSON.stringify` them).

**No readable `player.health`.** `maxHealth` is readable; current health is write-only via
`setHealth`. `teleport()` returns a request id, with completion arriving as
`playerTeleportComplete`.

**Client payloads are untrusted.** Validate shape, ownership, permission, rate and server state
before mutating anything authoritative.

## Runtime

CommonJS on both sides (`require`, `module.exports`, `__dirname`). Server scripts may use npm
packages; the client sandbox's `require()` only loads your own relative files, so client code must
be bundled (esbuild) and `node_modules/` is never shipped. Resources are reloaded live from the
console with `ensure <resource>` — **AMP's console does this for us**, since the template runs the
server with a writable STDIO console. Note `playerConnect` does **not** re-fire for players already
online when a resource restarts, so initialise from `PlayerManager.getAll()` on `resourceStart`.
Entities a resource created are destroyed when it stops.
