# Shooter project instructions

Use this file as the shared guide for coding agents working in this repository. Keep machine-specific setup and credentials outside the repository. Follow the user's task, then use the checked-in project conventions and references below to make implementation decisions.

## Shared development setup

- Open the repository root containing `project.godot`. Use Godot 4.7.2 stable (standard build), GDScript, Forward+, and Jolt. Coordinate engine, addon, and export-template upgrades through the release process.
- Use `project.godot`, `export_presets.cfg`, and the checked-in scripts as the shared configuration. Keep personal IDE settings, Godot import caches, locally licensed assets, and build outputs out of Git. Put scratch scenes and unused demos under ignored `archive/` with a `.gdignore` file.
- Keep Godot `.uid` and relevant `.import` files with their resources. When moving a scene or asset, update resource references and verify it loads from a clean checkout. Optional local assets must follow the documented fallback or setup procedure.
- Start with [README](README.md) for controls and player-facing behavior and [Development](docs/development.md) for module boundaries, entry points, and test commands.

## Implementation patterns

- Put match lifecycle and scoring in `game/match/`, player and bot behavior in `game/actors/`, weapon and damage logic in `game/combat/`, map construction in `game/maps/`, networking in `game/network/`, and interface code in `game/ui/`. Keep version selection and update installation in `game/release/`.
- Reuse the existing scene and gameplay entry points. Add shared tuning to the existing balance definitions in `game/combat/combat_balance.gd` when it belongs there. Keep presentation and audio outside authoritative gameplay decisions.
- Keep hit resolution, damage, inventory changes, and bot decisions on the host or dedicated server. For an RPC change, check sender authority, state validation, reliability, and protocol compatibility. Verify offline, LAN, or dedicated-server paths as relevant to the change.
- Follow surrounding GDScript style. Use descriptive names and explicit types where they clarify contracts or prevent ambiguous inference. Use comments for non-obvious reasons and invariants.
- Keep new UI text consistent with the existing Russian interface and reuse the project's menu and HUD components. Use the configured input actions and preserve rebinding and saved settings.
- Follow [Maps](docs/maps.md) and the [map layout decision](docs/adr/001-map-content-layout.md) when adding content. Check player spawns, bot navigation, collision, and available map sizes together.

## Documentation and verification

| Change | Update or consult |
| --- | --- |
| Controls or player-facing behavior | [README](README.md), [HUD](docs/hud.md) |
| Architecture or gameplay rules | [Development](docs/development.md), [decision records](docs/adr/) |
| Maps, models, textures, audio, or third-party addons | [Maps](docs/maps.md), [Asset sources and licenses](docs/assets.md), nearby credits and licenses |
| Network behavior or deployment | [Networking](docs/networking.md), [Server deployment](docs/server-deployment.md) |
| Graphics or performance | [Performance](docs/performance.md), with reproducible hardware, settings, and test conditions |
| Versioning, packaging, or updates | [Releases](docs/releases.md), [Changelog](CHANGELOG.md) |

- Run `git diff --check` and the smallest relevant existing test from `tests/`. Import new assets before testing. For combat changes, start with `godot --headless --path . --script res://tests/combat_balance_test.gd`.
- Verify scene and UI changes in a playtest, including the final screen after the action. Check network behavior with separate host and client processes when it affects synchronization. Record which scenarios ran and any meaningful gaps.
- Before sending changes to `main`, run `python3 scripts/check-release.py --base origin/main HEAD` against an up-to-date remote reference. Gameplay, asset, and export changes require the version, matching changelog entry, and relevant documentation. Documentation-only and other non-release changes follow the exceptions in [Releases](docs/releases.md).
- Use the documented build and publishing commands. Keep private signing keys, SFTP credentials, and machine-specific paths out of commits. Publish builds and change servers only when the task authorizes it.

## Godot MCP

Use the project's configured MCP servers for editor inspection, diagnosis, and playtests.

| Server | Use |
| --- | --- |
| `godot-mcp-toolkit` | Inspect the open editor, scenes, scripts, and resources. Run playtests and collect diagnostics. |
| `godot-cli` | Launch the project, capture output, and check the engine version or basic project state. |

- Open this project in the Godot editor before using Toolkit. If it is unavailable, check the editor Output panel for `[MCPServer] listening`. For CLI setup, see [Godot MCP setup](docs/mcp.md).
- Start with read-only inspection. Use `GODOT_MCP_READ_ONLY=1` for inspection-only sessions. Confirm the target before edits. Prefer Toolkit for scene and resource edits that benefit from editor Undo. Small GDScript changes can be made in the source file.
- Use code execution, deletion, or project-setting changes only when the task requires them. Keep secrets, session tokens, and user data out of tool inputs and logs.
- After changing GDScript, use Toolkit diagnostics or run a relevant test. After editing an interface or scene, confirm the resulting behavior in a playtest.
- Keep pinned MCP package versions synchronized in `.mcp.json` and `.codex/config.toml`. When upgrading Toolkit, replace the vendor directory with the complete new release so obsolete files and UID sidecars do not remain. Restart the MCP client or open a new session after configuration changes.
