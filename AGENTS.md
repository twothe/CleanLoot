# Behaviour

- CleanLoot is a standalone WoW 3.3.5a addon in this directory.
- Use native WotLK group-loot APIs and events (`START_LOOT_ROLL`, `CANCEL_LOOT_ROLL`, `GetLootRollItemInfo`, `GetLootRollItemLink`, `GetLootRollTimeLeft`, `RollOnLoot`) unless the user explicitly asks for a custom realm protocol.
- Do not depend on the separate `ServerFeatures` addon or its `RLR` addon-message protocol in this project.
- When hiding Blizzard group-loot UI, scan all available `GroupLootFrameN` frames instead of trusting `NUM_GROUP_LOOT_FRAMES`; extra native frames can sit over CleanLoot rows and steal mouse clicks on many-drop loot.
- Keep item-cache readiness separate from roll-option readiness; unknown Need/Greed/Disenchant flags must stay clickable until native APIs return explicit availability values.
- Auto-confirm BoP roll confirmations only for CleanLoot-initiated roll choices; call `ConfirmLootRoll` with the tracked `rollID/rollType` and hide the `CONFIRM_LOOT_ROLL` popup instead of clicking Blizzard's popup button. Do not globally click unrelated `LOOT_BIND` or other loot popups.
- Keep long roll lists reachable: rows should grow toward available screen space and wrap into columns instead of extending off-screen from the default bottom anchor.
- Keep runtime code and developer-facing text in English. User-facing discussion with the owner can be German.
- For release-relevant changes, update `## Version:` in `CleanLoot.toc`. The first public release version is `1.0.0`; use patch increments for fixes and minor increments for user-facing features.

# Project Overview

CleanLoot replaces the standard group-loot roll frames with a compact UI for a WoW 3.3.5a client. It shows one compact row per active roll with item icon, quality color, item details, remaining time, and native Need/Greed/Disenchant/Pass actions.

# Documentation Index

- `CleanLoot.toc`: WoW addon manifest and load order.
- `CleanLoot.lua`: Main addon implementation, UI creation, native loot-roll event handling, saved settings, and slash commands.
- `scripts/package-addon.sh`: Builds the installable release ZIP from the runtime files listed in `CleanLoot.toc`.
- `.github/workflows/release-addon.yml`: GitHub Actions workflow that publishes a release archive when the TOC version increases.

# Glossary

- `rollID`: Native WoW loot-roll identifier passed by `START_LOOT_ROLL`.
- `BoP`: Bind on pickup.
- `Need`, `Greed`, `Disenchant`, `Pass`: Native WotLK roll choices passed to `RollOnLoot`.
