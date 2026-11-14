#!/usr/bin/env python3
"""Tail Player Queue events and post them to a Discord webhook. Stdlib only.

    DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/... \
        python3 discord_notifier.py /opt/factorio/script-output/player-queue/events.jsonl

Run it on the same machine as the headless server (script-output lives in the
server's write-data dir). Starts at the end of the file, so old events aren't replayed.
"""
import http.client
import json
import os
import sys
import time
import urllib.error
import urllib.request


def fmt(e):
    n, need, who = e["count"], e["needed"], e.get("player")
    names = ", ".join(e.get("players") or []) or "nobody"
    by = f"**{who}** joined. " if e["event"] == "released" and who else (f"**{who}** left. " if who else "")
    return {
        "released": f"🟢 {by}**Game on!** {n}/{need} online: {names}",
        "relocked": f"🔴 {by}Game locked at {n}/{need}. Need {need - n} more!",
        "join": f"➕ **{who}** joined, game in progress ({names})" if e.get("released")
        else f"⏳ **{who}** is waiting: {n}/{need}, need {need - n} more!",
        "leave": f"➖ **{who}** left: {n}/{need}",
    }.get(e["event"], f"{e['event']}: {n}/{need}")


def post(url, content):
    body = json.dumps({"content": content, "allowed_mentions": {"parse": []}}).encode()
    for _ in range(5):
        # Discord's CDN rejects the default Python-urllib User-Agent.
        req = urllib.request.Request(url, body, {"Content-Type": "application/json", "User-Agent": "player-queue-notifier/1.0"})
        try:
            urllib.request.urlopen(req, timeout=10).close()
            return
        except urllib.error.HTTPError as err:
            if err.code != 429:
                print(f"webhook HTTP {err.code}: {err.read()[:200]!r}", file=sys.stderr)
                return
            time.sleep(float(err.headers.get("Retry-After", 1)))
        except (OSError, http.client.HTTPException) as err:  # dropped connection, DNS, timeout...
            print(f"webhook error: {err}", file=sys.stderr)
            time.sleep(5)


def follow(path):
    # ponytail: file grows forever (one line per join/leave); truncate it whenever, we handle that.
    pos = os.path.getsize(path) if os.path.exists(path) else 0
    buf = b""
    while True:
        try:
            size = os.path.getsize(path)
        except FileNotFoundError:
            size = pos = 0
        if size < pos:  # truncated or recreated
            pos, buf = 0, b""
        if size > pos:
            with open(path, "rb") as f:
                f.seek(pos)
                buf += f.read()
                pos = f.tell()
            *lines, buf = buf.split(b"\n")
            yield from (line.decode("utf-8", "replace") for line in lines if line.strip())
        time.sleep(1)


def selftest():
    e = {"count": 2, "needed": 3, "player": "bob", "players": ["amy", "bob"], "released": False}
    assert fmt({**e, "event": "join"}) == "⏳ **bob** is waiting: 2/3, need 1 more!"
    assert "Game on!" in fmt({**e, "event": "released", "count": 3}) and "bob** joined" in fmt({**e, "event": "released"})
    assert "Need 1 more" in fmt({**e, "event": "relocked"}) and "left" in fmt({**e, "event": "relocked"})
    assert "game in progress" in fmt({**e, "event": "join", "released": True})
    assert fmt({**e, "event": "leave", "players": {}}) == "➖ **bob** left: 2/3"  # Lua empty table -> {}
    assert "nobody" in fmt({"event": "released", "count": 0, "needed": 0, "players": {}})
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    url = os.environ.get("DISCORD_WEBHOOK_URL")
    if not url or len(sys.argv) != 2:
        sys.exit(__doc__)
    for line in follow(sys.argv[1]):
        try:
            post(url, fmt(json.loads(line)))
        except (ValueError, KeyError) as err:
            print(f"bad event line {line!r}: {err}", file=sys.stderr)
