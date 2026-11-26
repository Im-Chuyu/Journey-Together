# Companion field guide

[Project home](README.md) · [简体中文](../player-guide.md)

## Installation and controls

Enable Journey Together under **Server Mods**. For a source install, extract the mod folder into the game's `mods/` directory. Opening that folder should take you straight to `modinfo.lua` and `modmain.lua`. The host and clients need the same version. Dedicated servers need the mod enabled on both the forest and cave shards.

Your first companion is Wendy, usually near the Florid Postern or another world entrance. An existing world restores its saved companion. You can choose a vanilla character or one supplied by another loaded mod. Compatibility depends on the character's custom inventory, equipment and actions.

Press `Alt+R` for the wheel and right-click a slot to change its command. Alt + right-click the companion for the inventory panel. Both interfaces support optional function keys and HUD buttons. Chat keywords use the selected companion language. Chinese has custom voice lines, while English and Russian use native character sounds.

## Friendship and orders

Affinity is personal to each player. It usually starts at 20 and grows through company, gifts and feeding. Attacking your companion lowers it. Following takes **at least 25** and work orders take **more than 50**. Within a priority tier, the latest valid follow request gets the lead. A request from someone at 90 or above has priority. Taking items, renaming and swapping characters or bodies have additional checks.

Use the companion's current name and a keyword in the same message. “Wendy, plant trees” uses seeds she carries around the spot where **she** received the order. “Wendy, this is home” marks the spot where **you** are standing. Wheel and chat orders have the same requirements. When she asks about rock fruit, Jellybeans or pickup permission, answer the question directly, without her name.

To end a fishing order, add **Stop Fishing** to a wheel slot and use it while your companion is fishing.

## Disconnecting during a body exchange

After a body exchange, you play the companion’s character while the AI plays yours. Reconnect with the same account within **15 real-time minutes** to continue the exchange. The host can set the grace period to 5, 15, 30 or 60 minutes. A running deadline survives a world save and restart.

Once time expires and the AI finishes its current busy action, the companion returns and another player can exchange with it. If you borrowed Wendy as Wilson, Wendy keeps what she carried after the game processed your logout. When you return, you receive what AI Wilson actually carried at handover. Items the game dropped on logout stay on the ground. Death stays with the body.

Travel between the forest and caves and character selection at the portal preserve the exchange. If the two bodies are on different shards when time expires, both servers must be connected to finish the handover.

## Life at camp

A base covers a radius of 48 units. Your companion remembers nearby cookpots, ice boxes, salt boxes and chests. Marking camp lets you carry on travelling together. Once off duty she may rest on a free chair.

- **Equipment.** At a player-designated base, a companion short of protection can use accessible materials to make a Football Helmet and Ham Bat, or try a Log Suit and Spear. Normal crafting requirements apply.
- **Food and weather.** A hungry companion looks for food their character can eat and can collect a finished dish when safe. Warly can cook at low hunger if he has no suitable carried food. Below 65% hunger, Wortox prefers pocket souls above a reserve of ten. Companions also use equipment to keep warm or dry.
- **Character abilities.** Wickerbottom can return to a remembered bookcase. Wortox heals nearby injured players and releases one soul at a time to heal himself when safe and missing at least 20 health. Wigfrid can craft and charge an Elding Spear with the materials she carries.

## Combat and revival

The companion assists her current leader, chooses armour and tries to dodge incoming attacks. With poor equipment and low health, she may retreat. Issue Follow again to call her away from a fight.

A companion with a usable revival item or ability can help a dead player within 20 units, even while waiting or working independently. If the companion dies, her ghost calls for help twice. “Wendy, portal respawn” sends her to a portal. “Wendy, revive” or the wheel's Revive command searches for a resurrection point within 16 units.

## Board games

At 20 affinity, open the panel and choose **Games**. Play the companion, invite a player on the same shard, or select yourself to play both sides. An invitation expires after 45 seconds. Minimize the board to keep the game open. The world keeps running.

| Game | Rules |
| --- | --- |
| Gomoku | 15×15, Black moves first. Five or more in a row wins. No forbidden moves |
| Go | 19×19, Black first, area scoring and 7.5 komi to White. Two passes or an accepted count request opens scoring. Mark dead groups and confirm on both sides, or resume play |
| Chinese Chess | Red first. Select a piece and then its destination. Checkmate and stalemate both lose. Repetitions use simplified perpetual-check rules |

The companion accepts takebacks. Other players must agree. Disconnecting or changing shards ends the match. Match history records players and results separately for the forest and caves. Boards and chats are not archived.

## Optional local assistant

Enable model mode in the mod settings and match the six-digit game pairing code to the assistant (initially `321151`). Normal companion commands work with model mode off.

- **Windows API.** Launch `StartVoice.vbs` from the mod folder. Enter your own DeepSeek API key in model settings, save and restart. The key holder pays for requests. Voice is optional. Hold `F9` to record and release to transcribe.
- **Windows browser.** Load `tools/companion_bridge/browser_extension` as an unpacked extension in Chrome or Edge. Sign in to a supported DeepSeek or Doubao chat page, refresh it and pair the extension using the assistant's **web connection code**.
- **Linux dedicated server.** Copy `AssistantAPI.example.json` to `AssistantAPI.json`, set the key and pairing code, choose regular pairing on both shards, and run `sh ./StartAssistantLinux.sh` with Python 3.10 or later. Admin-client mode can instead relay through an online administrator's Windows assistant.

In public game chat, address the companion by name. Typed or spoken input in the assistant needs no name. Public messages can cross connected shards, while giving an item, reviving someone or following a player requires the same shard. After updates, restart the assistant and re-enter the world. Browser users should also reload the extension and refresh the chat page. [Assistant reference in Chinese](../../tools/companion_bridge/README.md)

## Troubleshooting

For cave-enabled worlds, compare the forest, caves and client logs. Login timeouts such as `CURL ERROR (28)` and `ValidateGameSessionTokenResponse Network Failure` point to the server's connection to Klei. For repeated `PANIC: missing required prefab` errors in a new world, try creating a separate medium-sized world with default generation settings. Include the mod version, server type, character, reproduction steps and complete Lua stack trace when [reporting a problem](https://github.com/Im-Chuyu/Journey-Together/issues).
