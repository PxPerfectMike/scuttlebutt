# Spike results (WoW Forever 1.60.1)

First run: 11/09/2026, one client (Alliance, level 9).

| Check | Result | Decision |
|---|---|---|
| Custom channel | `JoinTemporaryChannel("ScuttlebuttNet")` joined, `GetChannelName` = 1. | Keep the hidden channel. |
| Addon prefix | `RegisterAddonMessagePrefix` returns 0 (success enum). | As built. |
| Send to channel | 255-byte, 256-byte and high-byte (UTF-8) sends all return 0 (success). | `MSG_MAX` stays 255 until a receiver confirms the limit. |
| Own echo | **No `CHAT_MSG_ADDON` came back for any of our channel sends.** | Delivery is unconfirmed. Needs a second client. Sync already ignores its own echo, so nothing depends on it. |
| Throttle | 10 sends succeed in a burst; the 11th onward return 3 (`AddonMessageThrottle`). | Scuttlebutt stays well under it: `SEND_BUDGET = 5`, `SEND_REFILL = 0.5` per second (the limit may be shared with other addons; refill rate unmeasured). A throttled send is re-queued and dropped after `SEND_TRIES`. |
| `issecretvalue` | Exists. | Guards as built. |
| Tooltip | `TooltipDataProcessor` exists; the user saw the lines. | As built. |
| Right-click menu | `Menu.ModifyMenu` exists and fired for `MENU_UNIT_PLAYER`; `UnitPopup_ShowMenu` doesn't exist. | As built. |
| Settings | `Settings.RegisterCanvasLayoutCategory` exists. | As built. |
| Group finder | `C_LFGList` exists, but no `LFGListFrame`/`PVEFrame`; `LFGBrowseFrame` exists (Classic-style group browser), `C_LFGBrowse` doesn't. The retail hooks find nothing. | Second check `/sbspike lfg2` maps LFGBrowse; until then the group finder option shows disabled. |
| Nameplates | No plates were visible during the check. | Retest with players nearby. |
| Faction split | Not testable with one client. | Two-client test. |

The real addon on the same client: no errors; a like, a tag and a private note were saved.
Bug found: two changes in the same second kept only the first (test "two changes in the same
second both apply"), fixed.
