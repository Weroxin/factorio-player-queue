# Player Queue

**Nobody plays until enough players are online.**

Made for small groups playing PvP (or co-op) on a dedicated server, where nobody should get ahead by logging in alone. Players who join are held in a queue until the minimum player count is reached. Then everyone is released at the same moment.

## While waiting

- **Players are locked.** They can't move, mine, build, craft, shoot, drive, research, or open entities and inventories. Chat still works.
- **Vehicles stop.** Cars, spidertrons and manually driven trains stop, and their drivers are put out next to them (press Enter to get back in once released). Automatic trains keep running.
- **Biters are frozen.** They won't attack any player team, and evolution and expansion are paused. Your turrets still fire, so attack waves and asteroids are still dealt with.
- **The factory keeps running.** Production, research and trains all continue.
- A **"Waiting for players: 2/3"** box shows at the top of the screen, and joins and leaves are announced in chat.

When the minimum is reached, everyone is released together with a server-wide message, and biter settings go back to exactly what the server had before the freeze.

## When someone leaves mid-game

Everyone keeps playing for a **grace period** (default 5 minutes), with a countdown at the top of the screen. If someone joins before it runs out, the lock is cancelled. Otherwise everyone is locked and the biters are frozen again.

## Settings (Map settings tab, changeable mid-game)

| Setting | Default | |
|---|---|---|
| Minimum players | 3 | Players needed before anyone can play |
| Re-lock when count drops | On | Lock everyone again if players leave. If off, the game continues until the server is empty. |
| Re-lock grace period | 5 min | How long play continues after someone leaves before the lock. 0 = lock immediately. |
| Counted players | *(blank)* | Comma-separated usernames. Only these count toward the minimum. Blank means everyone counts. |
| Count admins | On | If off, admins don't count (they are still locked while waiting) |

When the server empties, the queue resets, so the next session starts locked again.

## `/queue` command (headless friendly)

Works from the server console, over RCON, or in chat. Unlike `/c`, it **does not disable achievements**.

```
/queue                      show status
/queue min 3                set the minimum (admins)
/queue relock on|off
/queue grace 5              grace period in minutes (0 = immediate)
/queue admins on|off
/queue allow amy, bob       only these count ("-" = everyone)
```

## Discord notifications (optional)

Mods can't make web requests, so the server writes queue events to `script-output/player-queue/events.jsonl`. The companion script [`discord_notifier.py`](https://github.com/Weroxin/factorio-player-queue/blob/main/discord_notifier.py) (Python 3, no dependencies) watches that file and posts to a Discord webhook:

```
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/... \
  python3 discord_notifier.py /path/to/factorio/script-output/player-queue/events.jsonl
```

Run it on the server machine. Example messages: *"⏳ amy is waiting: 1/3, need 2 more!"*, *"🟢 Game on! 3/3 online"*, *"⚠️ bob left. 2/3: everyone gets locked in 5 min unless 1 more join!"*. Player names can't trigger @mentions.

## Compatibility

- Factorio 2.1, with or without Space Age
- Multiplayer-safe and deterministic, tested on a headless dedicated server
- Uses a permission group named `player-queue-waiting`. If you remove the mod while players are locked, move them back to the Default group with `/permissions`.
