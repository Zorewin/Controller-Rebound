# Controller Rebound for WoW Forever

Controller Rebound adds a conditional spell or macro to each controller face button (A, B, X, Y) without replacing Forever's native controller layers.

- A bare face press runs its Controller Rebound spell or macro only when that slot's rule matches.
- When the rule does not match, the face button keeps Forever's normal action.
- LT, RT, LT+RT, LB, RB, and LB+RB always use Forever's native layer, including during combat.
- Slots show the assigned action's GCD and cooldowns.

## Install

Copy the `ControllerRebound` folder into `Interface/AddOns`, then reload the UI. Drag spells or macros onto the visible A/B/X/Y buttons. Use a gear icon to set its condition. Macro assignments automatically resync their text, name, and icon when the source macro is edited out of combat; a combat-time edit is applied when combat ends. Settings are stored per character. This rebrand starts a fresh Controller Rebound profile.

## Version 1.4.0-beta

- Per-character face-slot profiles, with the first character retaining the legacy profile during migration.
- Macro assignments resync safely after edits outside combat.
- Spell cooldowns, resource availability, and clear red out-of-range feedback on supported direct spells.
- A custom Controller Rebound AddOn-list icon.

## Commands

- `/controllerrebound help` shows this quick usage reminder.
- `/controllerrebound status` reports how many conditional spell slots are active.
- `/controllerrebound test` runs the addon's non-mutating diagnostics.
- `/cr` is a short alias for `/controllerrebound`.

## Tester notes

Test each configured face button bare, with LT, RT, LT+RT, LB, RB, and LB+RB both outside and inside combat. Check that gear icons are clickable but remain below bags and other dialogs. Check cooldown sweeps for spells and simple cast macros. Report the game build, controller type, class, and exact failing combination.

<img width="422" height="623" alt="image" src="https://github.com/user-attachments/assets/f8e9ecc2-2729-4eb6-b805-2c423d367cd0" />
