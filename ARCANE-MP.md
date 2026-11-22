# Arcane MP — AMP Template

Runs an [Arcane MP](https://arcane.mp) (HogwartsMP) dedicated server — the free, open-source
multiplayer mod for Hogwarts Legacy — as an AMP Generic Module instance.

## How the server is obtained

Arcane MP publishes **no standalone server archive**. The only public distribution of the server
build is the project's container image, `ghcr.io/arcane-mp/hogwartsmp-server`. The template's update
stage therefore pulls that image's layers straight from the registry with `curl` (anonymous token,
no Docker needed), unpacks `/opt/hogwartsmp` out of them, and flattens it into the instance
directory — so `resources/` and `.packages/` sit beside the binary, which is what the server expects
(the image ships them as symlinks into its data directory).

There is **no moving `latest` tag**: the version is pinned in the **Server Version** setting, and
client and server must be on the same release.

## Settings

| Group | Settings |
|---|---|
| Server Version | Server Version, Install Foundation Resources, Foundation Version |
| Server | Player Limit (max 512), Server Password, Map |
| Listing and Access | Masterlist Server Token, Package Secret, Resource Download URL |
| Gameplay | Auto Respawn, Gear Traits, Broom Upgrade Tier, Broom Speed Multiplier, Gear Stat Multiplier, CurseForge Mods |

All of these are written into `server.json`, which AMP edits in place (the installer writes the
server's own default file first so the mapping has something to edit).

## Ports

A single port (default **27015**) is used for **both** protocols: UDP carries game traffic and TCP
serves the client asset/server-info endpoint. Both must be reachable or players cannot download
resources and join.

## Notes

- **Listing**: the server appears on the public list only when a Masterlist Server Token is set
  (from <https://mafiahub.dev/dashboard/servers>). Without one it stays unlisted but is still
  directly connectable.
- **Package secret**: with neither a package secret nor a server token, the server warns at startup
  that the resource package key can be recomputed by anyone.
- **Foundation**: the optional Foundation resources add the gameplay layer, but they additionally
  require a MySQL 8.x / MariaDB 10.6+ database, which this template does not provision — see the
  [database guide](https://github.com/arcane-mp/foundations/blob/main/DATABASE.md). A bare server
  runs fine without one (it simply loads zero resources).
- **Architecture**: the published image is `linux/amd64` only, so this will not run on ARM hosts.
- Logs are written to `logs/` inside the instance directory, in addition to the AMP console.
