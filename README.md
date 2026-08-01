# hp2-coop-multiplayer

Harry Potter and the Chamber of Secrets — PC Co-op / Multiplayer Mod

Cooperative multiplayer for the PC version of **Harry Potter and the Chamber of Secrets** (UE1 / Metallicafan212 **M212** engine). Two game instances sync Harry's position, rotation, velocity, animations, health, map travel, spell projectiles, prop pickups, and lumos secret triggers over UDP. The remote player is rendered as a ghost puppet (no collision — won't trip level triggers).

## Legal Disclaimer

This is a non-profit, fan-made open-source project.
It is not affiliated with, endorsed, or sponsored by Warner Bros., Electronic Arts, or J.K. Rowling.
All game assets, trademarks, and registered trademarks belong to their respective owners.
This repository contains ONLY custom networking/code logic and does NOT include any proprietary game assets or copyrighted files.

---

## For players

### What you need

1. **Windows 10/11 x64**
2. Your own copy of **Harry Potter and the Chamber of Secrets** (PC)
3. **Metallicafan212 M212 Engine/Editor** installed **into that game folder**
   - Brings `Game.exe` (M212), `UCC.exe`, `IpDrv.dll` / `IpDrv.u`, and modern rendering
   - The author **forbids redistributing** the installer. Get it from the [Harry Potter Modding Discord](https://discord.gg/th3K6Epnug) or follow the project-info links on [hp-games.net (M212)](https://hp-games.net/metallicafan212-s-harry-potter-2-en)
4. This repository (clone or download)

You do **not** need Python to play — a prebuilt `dist/HGame.u` is included.

### Install (one click)

1. Clone or download this repo.
2. Double-click **`Install.bat`**.
3. When asked, paste the full path to your game folder (the folder that contains `System\Game.exe`).
4. Wait until it finishes. It will:
   - Save the path in `config.json`
   - Back up your original `System\HGame.u` (once) as `HGame.u.bak-hp2coop`
   - Install the co-op package
   - Ensure `EditPackages=IpDrv` is listed before `HGame` in `Default.ini`
   - Create soft sandboxes under `instances\P1`, `P2`, `P3` inside your game folder

To change the game path later, edit `config.json` and run `Install.bat` again.

### Play on one PC (local)

Double-click **`PlayLocal.bat`**.

This launches two windowed instances on the map from `config.json` (default `PrivetDr.unr`):

| Instance | Role | Profile |
|----------|------|---------|
| P1 | Host UDP `:7777` | `Documents\HP2Coop-P1` |
| P2 | Client → `127.0.0.1:7777` | `Documents\HP2Coop-P2` |

You should see a green status strip and messages like `[HP2Coop] remote player is on your map`. Walk around — the other Harry should follow.

M212 requires `-NEWWINDOW` for a second instance on one PC (the launchers already pass this).

### Play on LAN / Internet

**Host PC** — double-click **`Host.bat`**, or:

```bat
Host.bat [port] [playerName]
REM default: port from config.json (7777), name Host
```

Open **UDP** on that port in Windows Firewall (and router port-forward for Internet). Or use ZeroTier / Radmin VPN and share the VPN IP.

**Client PC** — same install (clone + `Install.bat` pointed at their own game copy), then:

```bat
Join.bat <hostIp> [port] [playerName]
REM example: Join.bat 192.168.1.10 7777 Hermione
```

If you run `Join.bat` with no arguments, it will ask for the host IP.

Both players should load the **same map**. The puppet is only shown while maps match. When one player changes map, the other **auto-follows** (a joining client is pulled onto the host's current map).

### In-game console commands

| Command | Effect |
|---------|--------|
| `CoopHost [port]` | Listen for a peer |
| `CoopConnect <ip> [port]` | Connect to host |
| `CoopDisconnect` | Leave session |
| `CoopStatus` | Print peer / counters |
| `CoopDebug` | Toggle debug HUD strip |

### Known limitations (v3)

- **Synced:** position/anim/health, map travel, spell projectiles + their world effects, prop pickups (beans/cards/frogs), lumos secret triggers
- **Not synced:** enemy AI positions/state, physics props, doors/movers not caused by spells, cutscene progress, potion mixing, vendor stock
- Chest contents are random per instance — bean *types* may differ slightly, but pickups stay consistent thanks to location-based matching
- Puppet has **no collision** (by design — avoids double-triggering maps)
- Map travel syncs, but the follower spawns at the map's normal start point, not at the leader's exact position
- Language-independent

---

## Configuration

### Repo config (`config.json`)

Created from `config.example.json` on first install. **Not committed** (see `.gitignore`).

```json
{
  "game_path": "C:\\Path\\To\\Harry Potter and the Chamber of Secrets",
  "default_map": "PrivetDr.unr",
  "default_port": 7777
}
```

| Key | Meaning |
|-----|---------|
| `game_path` | Your HP2 + M212 install root (contains `System\Game.exe`) |
| `default_map` | Map passed to `Game.exe` on launch |
| `default_port` | Default UDP port for host/client |

All launchers and install/rebuild scripts read this file. There are **no hardcoded `G:\...` paths**.

### Session config (`Documents\HP2Coop-P*\HP2Coop.ini`)

Auto-written by the launchers; also editable:

```ini
[HGame.CoopManager]
LastHost=192.168.1.10
LastPort=7777
PlayerName=Hermione
bSessionActive=True
bWasHost=False
bShowDebug=True
```

---

## For developers

### Repo layout

```
hp2-coop-multiplayer/
  Install.bat / PlayLocal.bat / Host.bat / Join.bat
  SetupDev.bat / Rebuild.bat
  config.example.json
  dist/HGame.u                 prebuilt package for players
  mod/src/HP2Coop/...          UnrealScript injects (source of truth)
  scripts/                     PowerShell implementation
  tools/                       created by SetupDev.bat (gitignored)
```

This repo does **not** contain game Maps, Textures, Sounds, or engine binaries. Those stay in your local game install.

### One-time toolchain setup

1. Run **`Install.bat`** so `game_path` is set and sandboxes exist.
2. Install **Python 3** and **Git** on PATH.
3. Double-click **`SetupDev.bat`** — clones into `tools/`:
   - [Die4Ever/unrealscript-injector](https://github.com/Die4Ever/unrealscript-injector)
   - [metallicafan212/HP2UScriptDecompile](https://github.com/metallicafan212/HP2UScriptDecompile)

### Edit and rebuild

Sources:

| File | Role |
|------|------|
| `CoopHarry.uc` | Injects `harry` (entry + console cmds) |
| `CoopHud.uc` | Injects `HPHud` (debug strip) |
| `CoopSpell.uc` | Injects `baseSpell` (broadcasts local casts) |
| `CoopHProp.uc` | Injects `HProp` (broadcasts pickups) |
| `CoopLumosTrigger.uc` | Injects `LumosTrigger` (broadcasts lumos secrets) |
| `CoopManager.uc` / `CoopLink.uc` / `CoopPuppet.uc` | New co-op classes |

Rebuild:

```bat
Rebuild.bat
```

This generates `mod/src/compiler_settings.json` from your `game_path`, runs the injector (`ucc make` via M212), refreshes hardlinks in `instances\P*\System`, and updates `dist/HGame.u`.

`EditPackages=IpDrv` must appear **before** `HGame` in `System\Default.ini` (and in `Documents\Harry - Coding Evolved\HP.ini` if you compile with that UserFolder). `Install.bat` / `Rebuild.bat` patch `Default.ini` for you.

After rebuilding, stop all `Game.exe` processes (Rebuild does this) before testing.

### Protocol (UDP text)

```
HPCOOP|1|HELLO|name
HPCOOP|1|HELLOACK|name
HPCOOP|1|PING|seq
HPCOOP|1|PONG|seq
HPCOOP|1|S|map|x|y|z|yaw|pitch|vx|vy|vz|anim|rate|hp
HPCOOP|1|MAP|mapfile.unr
HPCOOP|1|SP|class|x|y|z|pitch|yaw|charge|target|ox|oy|oz
HPCOOP|1|PICK|name|class|x|y|z
HPCOOP|1|LTRIG|triggerName
HPCOOP|1|BYE
```

State packets ~20 Hz. Puppet interpolates + short dead-reckoning from velocity.

`MAP` is announced once per map change (and right after connect): the peer auto-travels via `harry.LoadLevel()`. Tie-break when both travel at once: within ~5 s of arrival the host wins, otherwise whoever traveled first leads.

World sync (v3):

- **SP** — spell projectile; peer spawns the same projectile from the puppet
- **PICK** — prop pickup; peer runs `DoPickupProp()` (name match, fallback nearest same-class within 300 uu)
- **LTRIG** — lumos secret trigger; peer fires the same-named trigger Event

Loop safety: remote-applied actions hold `CoopManager.bApplyingRemote`; hooks never broadcast while it is set. Peer-spawned spells don't re-broadcast (caster is the puppet, not local harry).

### What this repo contains

- Co-op UnrealScript sources
- Prebuilt `dist/HGame.u`
- Install / launch / rebuild scripts with configurable `game_path`
- Documentation

### What this repo does **not** contain

- Game maps, textures, sounds, music, or proprietary packages
- M212 Engine/Editor installer
- Vendor trees (`unrealscript-injector`, `HP2UScriptDecompile`) — cloned locally by `SetupDev.bat`

---

## License

MIT — see [LICENSE](LICENSE).
