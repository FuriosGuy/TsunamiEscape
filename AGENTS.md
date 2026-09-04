# AGENTS.md

You are an elite Roblox architect. Your #1 job is to **never write duplicated code**.

## File Naming Convention

- `.server.luau` — server scripts
- `.client.luau` — local scripts
- `.luau` — ModuleScripts (shared or server-only modules)

## Rule #0 — Project-Wide Strictness

- Never use `--!nonstrict` or `--!nocheck` in new code
- For legacy scripts: add `--!nonstrict` only temporarily; migrate to strict ASAP
- Use latest Luau type solver features (read-only tables, refinements, etc.)

## Rule #1 — Modularity Is Non-Negotiable

Before writing **any** logic, you must:

1. Search the codebase for existing ModuleScripts that already handle this
2. If one exists → `require()` it and use it
3. If multiple exist → pick the most appropriate and reuse
4. Only create a new module if nothing exists (place it in `ReplicatedStorage/Modules/`)

## Rule #2 — Automatic Detection Behavior

When the user asks for something (e.g. "make a debounce", "add recoil", "damage system"):

- First response: `"Checking existing modules..."`
- Then: `"Found existing solution in [path/to/Module.luau] — reusing it"`
- Or: `"No existing module found → creating new one in ReplicatedStorage/Modules/"`

## Rule #3 — Strict Code Quality

- Every script starts with `--!strict`
- Full Luau typing everywhere (type annotations, `type ModuleName`, etc.)
- No deprecated APIs — never use `wait()`, `spawn()`, `delay()`, `fireclickdetector`, etc.
- Cache all services and references at the top (`game:GetService("Players")`, etc.)
- Prefer the `task` library: `task.spawn`, `task.delay`, `task.defer`, `task.wait`, `task.synchronize`
- Use Attributes for configuration where appropriate
- Use CollectionService for tagging and querying
- Debounce **all** input events (UserInputService, proximity prompts, tools, etc.)
- Parent objects only **after** full configuration — never before setting properties

## Rule #3.5 — Robust Error Handling

- Use `assert()` for programmer invariants and critical preconditions
- Use `warn()` for non-fatal issues that should be visible in output
- Wrap risky operations in `pcall` when appropriate (e.g. RemoteEvent:FireServer, table access)
- Never swallow errors silently — always log or propagate meaningfully

## Rule #3.6 — Prefer Immutability

- Avoid mutating tables passed as arguments unless explicitly intended
- Return new tables instead of modifying in-place when transforming data
- Use `table.clone()` for defensive copies when needed

## Rule #3.7 — Bound All Loops & Resources

- Every loop must have a guaranteed exit (counters, timeouts, table limits — no infinite loops)
- Disconnect all connections (RunService, events, etc.) when the owning scope ends
- Clean up instances, tweens, and coroutines when the owning object or system is torn down
- Never assume Roblox will clean up connections automatically — always do it explicitly

## Rule #3.8 — Consistent Style & Readability

- Follow the Roblox Lua Style Guide (spaces around operators, one statement per line, etc.)
- Naming: `PascalCase` for modules/types/instances, `camelCase` for locals/functions, `SCREAMING_SNAKE_CASE` for constants
- Keep functions short (<60 lines ideal); split large ones into helpers
- Comment complex logic; use meaningful variable names over abbreviations

## Rule #3.9 — Performance Awareness

- Avoid expensive operations in `Heartbeat`/`RenderStepped` — prefer `Stepped` or fixed intervals
- Cache frequently accessed instances and services
- Use CollectionService over `:GetChildren()` loops when possible
- Profile with MicroProfiler before optimizing prematurely

## Rule #3.10 — Zombie Code Prevention

Scripts in Roblox do not automatically stop when destroyed. You must explicitly
guard against all five sources of immortal code:

**1. `task.wait()` trap**
- A script destroyed mid-wait will wake up and continue executing
- Always bind waits to a lifetime variable:
```lua
local alive = true
task.spawn(function()
    while alive do
        task.wait(1)
        -- do work
    end
end)
-- on cleanup:
alive = false
```

**2. `while` loops**
- Loops do not check if their script still exists
- Never use `while true do` — always use a bounded condition:
```lua
-- BAD
while true do task.wait(1) end

-- GOOD
while alive and object.Parent do task.wait(1) end
```

**3. ModuleScript references**
- Required modules stay in memory even if their Instance is destroyed
- Never store mutable per-lifetime state inside a ModuleScript's upvalues
- Always pass state explicitly as arguments or use a Maid/cleanup pattern
- This applies to any bounded lifetime: character, player, tool, UI, NPC, effect

**4. External table references (OOP)**
- Tables referenced by any live script will not be garbage collected
- Always nil out table entries when the associated object or scope is done:
```lua
-- on any cleanup, not just PlayerRemoving:
myTable[key] = nil
```
- Applies to: player removal, character removal, tool unequip,
  UI close, NPC death, effect end, round reset, or any other
  scope boundary

**5. Thread spawning (`task.spawn` / coroutine)**
- Threads spawned just before destruction continue running independently
- Always cancel spawned threads when the owning scope ends:
```lua
local thread = task.spawn(myFunction)
-- on any cleanup:
task.cancel(thread)
```

**General rule:** Every `task.spawn`, `task.delay`, `task.defer`, and
`RunService` connection must have a corresponding cancel or disconnect
path that is guaranteed to run when the owning scope ends — this includes
character removal, player removal, script destruction, tool unequip,
UI teardown, NPC cleanup, round resets, effect expiry, and any other
bounded lifetime event. If you cannot point to the exact line of code
that cleans it up, it is a bug.

## Rule #3.11 — Replication Boundaries

- Never put server-only logic, secrets, or authority code in `ReplicatedStorage`
- Store server-only modules and assets in `ServerStorage` or `ServerScriptService`
- Only replicate data and instances that clients actually need
- Do not require large shared modules on the client unless they are truly needed at runtime
- Prefer narrow-purpose remotes over giant "do everything" remotes
- Never trust replicated client state for damage, currency, progression, or anti-cheat decisions

## Rule #3.12 — Remote Safety & Networking

- All `RemoteEvent` and `RemoteFunction` inputs must be validated on the server
- Validate:
  - player authority
  - argument types
  - argument count
  - allowed ranges
  - object ownership / ancestry
  - action cooldowns
- Never trust client-sent numbers for damage, prices, rewards, position correction, or timers
- Rate-limit every remote per player
- Reject oversized tables, deep tables, or unexpected instance references from clients
- Prefer enums / string literals / tagged ids over arbitrary freeform payloads
- `RemoteFunction` should only be used when a real request/response is required
- Never yield indefinitely inside `OnServerInvoke`

## Rule #3.13 — Event-Driven > Polling

- Prefer `.Changed`, `GetAttributeChangedSignal`, `ChildAdded`, `ChildRemoved`, and domain events over polling loops
- Never poll for state that can be observed with an event
- Avoid `while task.wait()` watchers for UI, characters, tools, or round state unless there is no event-based alternative
- If polling is unavoidable:
  - use the lowest safe frequency
  - bind it to a clear lifetime
  - document why an event-based solution was not possible

## Rule #3.14 — Character / Player Lifecycle Discipline

- Treat `Player`, `Character`, `Humanoid`, `Backpack`, and `PlayerGui` as separate lifetimes
- Never mix character-lifetime state into player-lifetime tables without cleanup boundaries
- Every `CharacterAdded` setup must have a matching teardown for:
  - character removing
  - humanoid death
  - player removing
  - respawn replacement
- Never assume the old character is gone before the new one exists
- Guard all character references with ancestry / identity checks before reusing them
- Connections created for one character must never survive into the next respawn

## Rule #3.15 — Instance Creation & Reuse

- Do not repeatedly create and destroy the same effect objects if they can be pooled or reused
- Reuse attachments, beams, highlights, sounds, and cosmetic instances where practical
- Avoid rebuilding welds / constraints / motors if a valid instance can be updated in place
- Cache templates and clone only from known, preconfigured sources
- For frequently toggled systems, prefer enable/disable over destroy/recreate when safe

## Rule #3.16 — CollectionService & Lookup Strategy

- Use `CollectionService` tags for dynamic groups instead of scanning large hierarchies repeatedly
- Do not call `workspace:GetDescendants()` or similar broad scans in hot paths
- Convert repeated name-based searches into cached references
- If a lookup may become stale, define when and how the cache is refreshed
- Tags must have a clear ownership meaning, not just be used as random labels

## Rule #3.17 — Attributes, State, and Source of Truth

- Use Attributes for lightweight replicated state that benefits from engine replication and change signals
- Do not duplicate the same state across Attributes, ValueObjects, and Lua tables unless one is explicitly derived
- Every system must have one clear source of truth
- Derived state should be recomputed from authoritative state, not manually synchronized in multiple places
- Avoid ValueObjects for high-frequency state when Attributes or plain Luau state are cleaner

## Rule #3.18 — Hot Path Rules

- Hot paths include:
  - `Heartbeat`
  - `RenderStepped`
  - `Stepped`
  - high-frequency input callbacks
  - remote handlers that fire often
- In hot paths:
  - no `GetDescendants()`
  - no repeated `FindFirstChild` chains if refs can be cached
  - no large table allocations each tick
  - no string formatting / concatenation spam
  - no cloning / destroying instances unless absolutely necessary
- Measure first, then optimize the worst offender

## Rule #3.19 — Logging & Debug Gates

- Expensive debug logging must be behind a debug flag
- Never spam output in hot paths or per-player loops
- Warnings should include enough context to debug:
  - system name
  - player / object
  - failure reason
- Remove temporary spam logs before finalizing a feature

## Rule #3.20 — APIs, Contracts, and Single Responsibility

- Every ModuleScript must expose a small, intentional API
- Do not let unrelated systems reach into another module's private tables
- Shared modules should define clear contracts:
  - input types
  - return types
  - ownership expectations
  - cleanup expectations
- One module should own one domain; avoid "god modules"
- If a module requires call-order assumptions, document them at the top

## Rule #3.21 — Deterministic Cleanup Pattern

- Any system that creates instances, connections, threads, or cached references must expose a cleanup path
- Preferred patterns:
  - `Destroy()`
  - `Disconnect()`
  - `Cleanup()`
  - `Stop()`
- Cleanup functions must be idempotent
- After cleanup:
  - all connections disconnected
  - all threads cancelled or allowed to exit
  - all table references nilled if lifetime-bound
  - all owned instances destroyed or returned to pool
- Never rely on garbage collection as the primary cleanup strategy

## Rule #3.22 — Server Authority by Default

- The server decides:
  - damage
  - health changes
  - inventory changes
  - currencies
  - unlocks
  - rewards
  - spawning authority
- The client may request actions, but never finalize them
- Cosmetic-only systems may be client-authoritative if failure is harmless
- When in doubt, treat the client as presentation and the server as authority

## Rule #3.23 — Parallel / Deferred Work Discipline

- Use `task.defer` for non-urgent follow-up work when immediate execution is unnecessary
- Use `task.spawn` sparingly; spawned work must still have a cancellation story
- Break large batches across frames when processing many instances or players
- Do not block critical threads with avoidable heavy work
- If work can be amortized, batch it

## Rule #3.24 — No Hidden Rebuild Churn

- Do not destroy and recreate whole systems when only one field changed
- Prefer reconciliation:
  - validate existing instance
  - update changed properties
  - create only missing parts
  - remove only invalid parts
- Rebuilds are allowed only when simpler and proven cheap
- Frequent equip/unequip, respawn, and UI open/close flows must be designed to reconcile, not churn

## Rule #3.25 — self and Method Calls

- self is the reference to the table the method is being called on
- self is not a special global and not true class syntax
- self is just the first parameter of a function by convention
- when using : to define or call a method, Lua automatically passes the table as the first argument
- this means self lets a function read from and write to the current object's state without manually passing that table every time

How it works:
- defining a function with . means all parameters must be declared manually
- defining a function with : means the table is automatically inserted as the first parameter, usually named self
- calling a function with . does not pass the table automatically
- calling a function with : does pass the table automatically
- because of this, : on definition and : on call are meant to match each other
- if they do not match, arguments shift into the wrong parameter positions and bugs happen

Behavior rules:
- use : for methods that operate on instance state
- use . for utility functions, constructors, or helpers that do not need instance state
- self should be used when the function needs to access fields stored on the current table
- self makes object-style code possible in ModuleScripts by letting returned tables behave like reusable objects

Important notes:
- self only exists inside functions where it is explicitly received as a parameter
- using : is just shorthand syntax for passing the table as the first argument
- self can technically be named something else, but self is the standard and should always be used for readability
- ModuleScripts do not automatically create self
- self only appears when you structure the returned table to use method-style functions

Common mistake to avoid:
- do not define with : and call with .
- do not define with . and expect self to exist unless you manually declare and pass it
- mismatching . and : causes nil errors or incorrect argument order

Architecture rule:
- if a module represents an object with changing state, prefer : methods so self clearly points to that object's data
- if a module function is stateless and only transforms input, prefer . functions
- this keeps APIs predictable, avoids hidden argument bugs, and makes strict typed Luau easier to reason about