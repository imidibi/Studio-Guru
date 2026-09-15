# Dante as a Bidirectional Connection — Design & Porting Spec

**Status:** IMPLEMENTED in Studio Guru 1 (builds clean) — user testing pending
**Last updated:** 2026-09-14
**Purpose:** This document specifies how Dante must be modeled as a connection
protocol. It is written to be implementation-agnostic so it can be handed to
Studio Guru 2 (which shares the same defect) once the changes are implemented
and tested in Studio Guru 1. Appendix A maps the spec onto Studio Guru 1's
actual code; the SG2 implementer should map the same requirements onto SG2's
schema.

> **Maintenance note:** Update the Status line and the Changelog (bottom) as
> work progresses. Anything discovered during SG1 implementation/testing that
> changes the spec must be recorded here so SG2 inherits the corrected design.

---

## 1. Problem statement

Both apps model Dante as two separate one-way ports per device — a
"Dante In (Ethernet)" input port and a "Dante Out (Ethernet)" output port —
each with 64 channels. Consequences:

1. The canvas implies **two cables** between a Dante device and a computer,
   when physically there is exactly **one** Ethernet cable.
2. Fully documenting one real cable requires the user to draw **two edges**
   (one into "Dante In", one out of "Dante Out").
3. Connection validation only permits Dante-port ↔ computer-Ethernet edges,
   forbidding legitimate **device-to-device** Dante wiring (console ↔
   stagebox, device ↔ switch).

## 2. Validated domain facts (do not re-litigate in SG2)

Verified 2026-09-14 against Audinate documentation and product specs:

- **The physical link is always ONE bidirectional Ethernet connection.**
  A single RJ45 carries audio, clocking, and control traffic in both
  directions. There is never a separate "in" cable and "out" cable.
- **Audio capability is NOT always bidirectional.** Audinate models each
  device as having independent **transmit (Tx)** and **receive (Rx)** channel
  counts, and either may be zero:
  - Tx-only examples: Dante AVIO Input Adapter (2×0), Dante microphones.
  - Rx-only examples: Dante AVIO Output Adapter (0×2), Dante amplifiers.
  - Symmetric examples: consoles/interfaces at 64×64, 16×16.
  - Asymmetric both-way devices (e.g. 16×8) also exist.
- Convention: counts are written **Tx×Rx** (Audinate product naming).
- Terminology mapping to our device editor: a device's **Digital Output =
  Tx** (transmits audio to the network); **Digital Input = Rx** (receives
  audio from the network).

Sources:
- https://dev.audinate.com/GA/dante-controller/userguide/webhelp/content/device_channels.htm
- AVIO product pages (B&H, Sweetwater) confirming 2×0 / 0×2 unidirectional
  adapters.

## 3. Design decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | A device with Dante enabled (in either direction) gets **exactly one** Dante port, named "Dante (Ethernet)", representing the single physical RJ45. | One cable in reality → one port/one link on canvas. |
| D2 | The port's direction is **bidirectional**. | The link always carries traffic both ways (control/clock even on Rx-only devices). |
| D3 | The device editor keeps **independent** "Dante" toggles under Digital Inputs and Digital Outputs. Input toggle = Rx capability, Output toggle = Tx capability. No auto-sync between them (unlike MIDI-over-USB). | Matches Audinate's Tx/Rx capability model; supports Tx-only and Rx-only devices. |
| D4 | In the patching/connections UI, the single Dante port appears in the **output (source) column only if Tx is enabled** and in the **input (destination) column only if Rx is enabled**. | Capability gates patch direction; the port itself stays singular. |
| D5 | Validation allows a Dante port to connect to: (a) a **computer Ethernet interface**, or (b) **another device's Dante port**. Everything else is rejected. | Device-to-device Dante (console↔stagebox, via switches) is standard practice; the old computer-only rule was wrong. |
| D6 | Canvas rendering: Dante links use the **bidirectional style** (two arrowheads, same as computer/USB/Thunderbolt links). *(Discovered during SG1 implementation: Ethernet ports already map to the "computer" visual type, so this required no code change. Also: the canvas has no channel-count label at all — only the connection matrix shows "Nch", which counts patched channels and remains correct — so the planned "Tx×Rx" label was moved to future work, §7.)* | Communicates the true nature of the link. |
| D7 | Channel counts remain hardcoded at **64 per enabled direction** for now. | Matches current behavior; user-editable Tx/Rx counts are future work (§7). |
| D8 | Existing user data must be **migrated, not discarded**: edges pointing at the old "Dante In"/"Dante Out" ports are re-pointed to the new single port. | Orphan-cleanup would silently delete users' documented wiring. |

## 4. Data / model requirements (portable spec)

1. **Port model** must support a bidirectional direction value. (SG1 already
   has `PortDirection.bidirectional` but never used it for generated ports;
   check SG2's equivalent.)
2. **Port generation** ("build ports from device spec"):
   - If Dante is in the device's digital inputs OR digital outputs, emit ONE
     port: name `Dante (Ethernet)`, type Ethernet, direction bidirectional,
     64 channels. Do NOT emit it twice when both toggles are on.
   - The port's channel set represents the logical link; Tx/Rx capability is
     derived from the device's digital input/output sets at display and
     validation time (no schema change required).
3. **Stored device data is unchanged**: Dante continues to be recorded as a
   string in the digital-inputs and/or digital-outputs raw arrays. This keeps
   CloudKit records compatible across app versions and between SG1 and SG2.
4. **Every UI that lists ports by direction must handle bidirectional
   ports** — offering them in BOTH the input and output lists (with D4
   capability gating for Dante). In SG1 there were **two** such places, and
   SG2 should audit for the same pattern (search for filters on port
   direction == input/output):
   - the connections/patching overlay columns, and
   - the device I/O detail ("explosion") view's Inputs/Outputs sections,
     including its used/open endpoint counter. Where that view derived the
     endpoint's direction from the port's direction, it must instead take
     the direction from the list (section) the port is being shown in.
5. **Endpoint identity caution**: the same port now appears in both columns.
   Endpoint references include a direction field; an edge stores the Dante
   endpoint with direction matching its role in that edge (output when
   source, input when destination). Occupancy/conflict checks must treat
   these as distinct roles of one physical port. This mirrors how computer
   interface endpoints already behave in SG1.
6. **I/O summaries must report Dante.** Anywhere the app summarizes a
   device's I/O (canvas PDF/SVG device cards, matrix headers, spreadsheet
   export), include a `Dante <in>/<out>` part where in = 64 if Rx enabled
   else 0, out = 64 if Tx enabled else 0 (in/out ordering to match the
   app's other summaries, NOT Audinate's Tx×Rx ordering). In SG1 there were
   two such summary functions — one computed from generated ports (use the
   port's back-reference to the device for the capability split) and one
   computed from the device spec — and neither previously mentioned Dante
   at all.
7. **Connection matrix must reflect bidirectionality.** The matrix places an
   edge in the cell of its stored from→to direction. A Dante edge must ALSO
   be mirrored into the opposite cell when the reverse flow is physically
   possible: the far endpoint can transmit (computer Ethernet always can; a
   Dante port only if its device has Tx) and the near endpoint can receive
   (computer always; Dante port only with Rx). Mirror by swapping the edge's
   endpoints; restrict mirroring to edges involving a Dante port so existing
   computer-link matrix behavior is unchanged. This also makes the matrix's
   "has reverse connection" marking light up for symmetric Dante links, and
   one-way (Tx-only/Rx-only) devices correctly stay single-celled.

## 5. Validation rules (replace the old Dante rule)

Definitions:
- *Dante port*: port of type Ethernet whose name contains "dante"
  (case-insensitive). (Name-based detection is inherited from SG1; if SG2
  has or can add a first-class port subtype, prefer that — but note new enum
  cases in synced/Codable types can break older clients decoding the data.)
- *Computer Ethernet*: a computer-interface endpoint of kind Ethernet.

Rules:
1. If either endpoint of an edge is a Dante port, the other endpoint must be
   a computer Ethernet interface OR another Dante port. Otherwise reject with:
   *"Dante connections must run between a Dante (Ethernet) port and either a
   computer Ethernet interface or another device's Dante port."*
2. A Dante port may be used as a **source** only if its device has Dante in
   digital outputs (Tx), and as a **destination** only if its device has
   Dante in digital inputs (Rx). The capability-gated columns (D4) enforce
   this in the UI; validation enforces it again as a backstop, with messages:
   *"This device's Dante port is receive-only — it has no Dante transmit
   (output) channels."* / *"This device's Dante port is transmit-only — it
   has no Dante receive (input) channels."*
3. One physical Dante link between a device pair is represented by **one
   edge** (the edge is inherently bidirectional per D6). Do not require or
   create a reverse edge.

## 6. Migration (one-time, on studio load)

For each device whose ports contain the legacy `Dante In (Ethernet)` and/or
`Dante Out (Ethernet)` ports (match by **exact name** plus Ethernet port
type, so the new "Dante (Ethernet)" port is never matched):

1. Create (or reuse, for idempotence after a partial run) the new single
   `Dante (Ethernet)` bidirectional port with 64 channels.
2. For every connection edge referencing a legacy Dante port ID, re-point
   that endpoint's port ID to the new port and its channel ID to the new
   port's channel with the **same index** (both legacy ports were 64ch, so
   indices 1–64 map 1:1).
3. Delete the legacy Dante ports (explicitly, via the persistence context —
   in SwiftData, removing from the relationship array alone is not enough;
   channels cascade-delete with the port).
4. Collapse duplicate edges: after re-pointing, if two edges involving a
   migrated Dante port have the same unordered endpoint pair (device+port+
   channel on each side, **ignoring the endpoint direction field**), keep
   the first and drop the rest — they described the two directions of one
   physical link. Restrict this dedupe to edges touching a migrated Dante
   port; never dedupe unrelated edges.
5. Persist bundles, mark affected devices and the studio modified so
   CloudKit sync propagates, and save the context.

**Placement (as implemented in SG1):** the migration runs as the first step
inside the orphaned-connection cleanup routine, which every cleanup call
site already invokes after bundles are loaded. This guarantees migration
precedes orphan removal everywhere without touching call sites. It is
idempotent and cheap when there is nothing to migrate (early return).

**Import/export interplay (verified in SG1, check the same in SG2):**
- Exports must run the migration before serializing (SG1: cleanup — which
  embeds the migration — is already the first step of studio export), so
  exported files always contain the new single-port shape.
- Ports round-trip through export files by raw direction string, so
  "bidirectional" survives without schema changes.
- Importing an OLD export file (legacy Dante In/Out ports) needs no special
  import-time handling **provided** the load-time migration runs on the
  imported studio afterwards (SG1: import selects the new studio, which
  triggers load + cleanup + migration).
- Import rebuilds endpoint directions from each edge's from/to **role**, not
  from the port's direction — verify SG2 does the same, otherwise
  bidirectional ports break on import.
- Whole-database backups need nothing: restored legacy data migrates on
  next load.

**Cross-version sync caution:** a migrated studio syncing to an app version
without this change will show the new port shape. Because stored device
*specs* (digital input/output raw arrays) are unchanged, an old client that
rebuilds ports will regenerate legacy In/Out ports and its edges will match;
the new client will re-migrate on next load. This is acceptable churn, but
release notes should encourage updating all devices.

## 7. Out of scope (deliberately) — candidate future work

- **User-editable Tx/Rx channel counts** (2×0, 16×8, …). Would need two new
  count fields on the device spec plus editor UI.
- **Tx×Rx labels on canvas links / matrix cells** (e.g. "64×64"). The canvas
  currently has no channel-count label; adding one was deemed out of scope.
- **Redundant Dante (Primary + Secondary ports).** Many devices have two
  RJ45s for redundancy. Would follow the ADAT pattern of a port count.
- **Switch/network topology modeling** (Dante via network switch as a hub).

## 8. Test checklist (fill in results during SG1 testing)

- [ ] New device with Dante in both inputs and outputs → exactly one
      "Dante (Ethernet)" port, bidirectional, 64 channels.
- [ ] Dante-input-only device → port appears only in destination column.
- [ ] Dante-output-only device → port appears only in source column.
- [ ] Dante port ↔ computer Ethernet: single edge, accepted.
- [ ] Dante port ↔ another device's Dante port: accepted.
- [ ] Dante port ↔ analog/ADAT/MADI/USB endpoint: rejected with clear message.
- [ ] Canvas draws one link with two arrowheads (computer/bidirectional
      style). (Tx×Rx label is future work, §7 — matrix "Nch" counts patched
      channels and stays as-is.)
- [ ] Device I/O detail ("explosion") view: Dante port listed under Inputs
      and/or Outputs per capability; used/open counts correct.
- [ ] Legacy studio with old Dante In/Out ports + existing edges: after
      migration, edges preserved, single port, no duplicate links, nothing
      deleted by orphan cleanup.
- [ ] CloudKit round-trip of a migrated studio.
- [ ] Export (PDF/SVG) renders the single Dante link correctly (one orange
      line) and device cards show "Dante 64/64" (or 64/0, 0/64) in the I/O
      summary.
- [ ] Studio export → import round-trip preserves the Dante port
      (bidirectional) and its connections.
- [ ] Importing an OLD .studioguru export (legacy Dante In/Out ports):
      studio opens with a single Dante port and connections intact.
- [ ] Matrix view: symmetric Dante link appears in BOTH direction cells;
      Tx-only/Rx-only device appears in one cell only; matrix headers and
      spreadsheet export show the Dante I/O summary.

## Appendix A — Studio Guru 1 changes as implemented (porting map)

All changes shipped 2026-09-14 on branch `feature/freemium`. Search anchors
are given instead of line numbers (the files are large and shift):

| Concern | SG1 change |
|---|---|
| Port generation | `StudioCanvasView.swift`, `buildPorts`: both `case .dante:` arms are now no-ops; a single block after the two digital-format loops (search "Dante: one physical Ethernet link") emits one `Dante (Ethernet)` port, type `.ethernet`, direction `.bidirectional`, 64 channels, when Dante is in either format set. |
| Rebuild-detection count | `StudioCanvasView.swift`, `portConfigurationChanged`: expected port count decremented by 1 when Dante is in BOTH digital inputs and outputs (single port). Side effect: legacy devices mismatch and rebuild on next edit-save, which is fine because the load-time migration has already re-pointed edges. |
| Patch overlay columns | `Connections.swift`, `EndpointsColumnView`: direction filter is now a switch on `directionRaw` with a `"bidirectional"` case shown in both columns; Dante ports gated by `device.digitalOutputs.contains(.dante)` (source column) / `digitalInputs` (destination column). |
| Validation | `Connections.swift`, `validateEdge` (search "single bidirectional Ethernet link"): peers = computer Ethernet OR another Dante port; plus Tx/Rx capability backstop checks via device lookup. |
| Migration | `Connections.swift`, `ConnectionsStore.migrateLegacyDantePorts(studio:)`, called as the first step of `cleanupOrphanedConnections`. Implements §6 exactly. |
| Device I/O detail view | `StudioCanvasView.swift`, `DeviceExplosionDetailView`: `endpoint(for:channel:as:)` now takes the direction from the caller (section) instead of the port; `inputPorts`/`outputPorts` include bidirectional ports via `bidirectionalPortAppears(_:asInput:)` with Dante capability gating; used/open counter iterates inputs and outputs separately. |
| Canvas rendering | No change needed: `ConnectionVisualType.from(portType:)` already maps `.ethernet` → `.computer`, which triggers the existing bidirectional (two-arrowhead) rendering. |
| I/O summaries | `StudioCanvasView.swift`: the port-based `ioSummary(from:)` (used by canvas PDF + SVG device cards) computes a Dante in/out part via the port's device back-reference; the spec-based `ioSummary(for:)` in the matrix view (headers + spreadsheet export) adds "Dante 64/64" from the digital input/output toggles. |
| Matrix bidirectionality | `StudioCanvasView.swift`, matrix view `connectionMap`: `danteReverseCapable(_:)` + `reversedEdge(_:)` mirror each Dante edge into the opposite direction cell when the far end can Tx and the near end can Rx (computer Ethernet counts as both). Mirroring is restricted to Dante edges. |
| Export/import | No code change needed: export already runs cleanup (and therefore the migration) first; `ExportablePort` round-trips `directionRaw` verbatim; import rebuilds endpoint direction from edge role, not port direction; importing legacy files triggers migration via studio selection. Device-detail PDF lists all ports unfiltered, so the single port shows correctly. |
| Unchanged on purpose | Device editor Dante toggles (they now mean Tx/Rx capability, per D3); `DigitalFormat.dante` raw value; stored device spec arrays; port sort ranking (matches "dante" case-insensitively, still works with the new name); both `ioSummary` functions (never included Dante). |

Other SG1 reference points that informed the design (pre-change):
`Models.swift:29` (`PortDirection.bidirectional`, previously unused for
generated ports), `Models.swift:71` (`DigitalFormat.dante`), computer
interfaces built as single ports in `buildPorts` (search "Computer
Interfaces (USB").

## Changelog

| Date | Change |
|---|---|
| 2026-09-14 | Initial spec written. Domain facts validated (one physical link, asymmetric Tx/Rx capability). Design agreed: single bidirectional port, capability-gated columns, device-to-device connections allowed, edge-preserving migration. Implementation not yet started. |
| 2026-09-14 | Implemented in SG1; project builds clean. Discoveries folded into spec: (1) a second direction-filtered UI existed (device I/O "explosion" view) — spec §4.4 generalized to "audit every direction-filtered port list"; (2) canvas bidirectional rendering was free (Ethernet already maps to the computer visual type); (3) canvas has no channel label, so Tx×Rx labeling moved to future work; (4) migration placed at the top of orphan cleanup rather than at call sites; legacy ports deleted explicitly via the persistence context. User testing pending — checklist (§8) not yet filled in. |
| 2026-09-14 | Audited and fixed reporting/serialization paths (new spec items §4.6, §4.7, and the import/export interplay notes in §6): I/O summaries now include Dante (canvas PDF, SVG, matrix headers, spreadsheet export); matrix mirrors Dante edges into both direction cells per Tx/Rx capability. Verified with no changes needed: studio export/import (export migrates first; direction round-trips; legacy imports migrate on selection; import derives endpoint direction from edge role), whole-store backups, CloudKit port sync, device-detail PDF. Builds clean. |
