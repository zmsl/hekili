# VirtualState kick-off prompt (Phase 1 session)

You are starting Phase 1 of VirtualState in Hekili: the module that carries the game state forward from plain
observations on WoW Forever and answers the reads that are secret in combat, so that Hekili can recommend
again. The design is final and written down; your job is to plan it and build it.

## Repository and branches

- Repository: `~/src/hekili`, the user's own fork of Hekili. Work and git happen in WSL.
- `forever`: the Forever branch, at fc61b6d9 when this prompt was written (Checkpoint B: a clean load on
  Forever, every game read through `Libs/VirtualGameAPI-1.0`).
- `virtualstate-design`: the planning documents listed below, one branch off `forever`.
- `classic`: the Classic Era branch. Leave it alone.

Branch `virtualstate-phase1` from `forever` if `virtualstate-design` has been merged into it; otherwise branch from `virtualstate-design`. Never push to `forever` or `classic`.

Work in a git worktree under `~/src/hekili/.claude/worktrees/virtualstate-phase1`, commit there, and push the
branch `virtualstate-phase1` to `origin` when a checkpoint is green.

## Read first, in this order

1. `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md`: the Phase 1 spec. It is the source of
   truth; §5 (applying through the spec), §10 (Hekili edits outside the module), §11 (testing and the exit
   criterion) and §12 (risks) carry the most weight.
2. `docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md`: the Phase 2 plan. Deferred; read
   it so Phase 1 leaves no obstacle to it.
3. `docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md`: the Phase 3 outline. Deferred; its §10
   names which Phase 1 edits a later event bus retires.
4. The four research inputs the spec cites, under `docs/research/2026-10-14-virtualstate-inputs/`:
   `tdf-state-patterns.md`, `tdf-port-mapping.md`, `hekili-integration-points.md`, `library-design-draft.md`
   (the first design draft; its shape is superseded, its content carries over as the spec says).
5. `docs/forever-facade-notes.md`: the facade inventory and the stub call sites.
6. `docs/forever-cleanup.md`: §5 open questions Q1-Q16 (the spec's "cleanup Qn") and "How to verify", which
   names the tool paths for busted, luacheck and LuaLS.

The spec inlines every fact it takes from outside the repository. Its `TDF src/TacoDogForever/<path>:<lines>`
and `TDF tests/<path>:<lines>` cites are Taco Dog Forever (TDF), the user's other repository, at main 7bef7b5;
it is the repository that holds the feasibility doc the spec cites,
`~/src/TacoDogForever/docs/research/2026-10-14-hekili-virtual-state-feasibility.md`. Read TDF to port its
mechanics; never write to it.

## How to proceed

Brainstorming is done; do not re-run it. Feed the spec to `writing-plans`, then execute with `subagent-driven-development`.

The plan goes under `docs/superpowers/plans/` on `virtualstate-phase1`. Phases 2 and 3 are not part of this
session: do not start them.

## Standing rules

- **Subagents never run on Fable.** Use opus for implementation, review and planning subagents, and sonnet for
  research subagents.
- **Clean-room direction.** Hekili code never flows into TDF. TDF mechanics may be ported into Hekili, with
  credit in the file header (spec §13).
- **No LICENSE or README changes**, in any repository.
- **Verification** before every commit: luacheck, LuaLS and busted, from the repository root, with the
  commands of `docs/forever-cleanup.md` "How to verify" as the spec updates them (spec §7.7, §9, §11); then
  an in-game `/reload`.
- **The user runs the game.** You never start the client. In-game checks, `/reload`, `/run` lines and probes
  (the probe addon is `~/src/ForeverProbe`) are run by the user; you write the exact lines and read the
  results the user returns.
- **Git:** worktree plus branch `virtualstate-phase1`, push that branch, never push to `forever` or `classic`,
  and never merge into them without the user's approval.

## The Phase 1 exit criterion (spec §11)

Phase 1 is complete when the user confirms this checkpoint in game:

> **In-game checkpoint (the Phase 1 exit criterion).** Warrior on Forever:
> - `/reload` gives no Lua error and no popup.
> - Out of combat, `/run print(Hekili.VirtualState.Snapshot())` shows class WARRIOR, the talent ranks, and
>   rage with basis `default` at est 0.
> - After 60 s on a dummy:
>   - rage alternates between `pinned` and `modelled`, its interval is 15 wide or less, and it contains the
>     rage bar's value;
>   - the main-hand swing basis is `observed`, with speed equal to the weapon speed ±0.01;
>   - Rend's believed expiry is within 0.2 s of the debuff timer;
>   - Hekili recommends spenders.
