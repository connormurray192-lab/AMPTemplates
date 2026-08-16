# Modded Minecraft — AMP Template for CurseForge Modpacks

A custom [AMP](https://cubecoders.com/AMP) Generic Module template that runs CurseForge modpack
servers (Forge / NeoForge / Fabric / Quilt / vanilla). Point it at a modpack page URL — e.g.
`https://www.curseforge.com/minecraft/modpacks/star-technology` — click **Update**, and it
downloads and installs the server files automatically.

Rather than wrapping the `itzg/docker-minecraft-server` Docker image (AMP's Generic module can
only run containers based on `cubecoders/ampbase`), this template uses the same engine that
image uses internally — [itzg/mc-image-helper](https://github.com/itzg/mc-image-helper) — so you
get the same `AUTO_CURSEFORGE`-style behaviour natively inside AMP. It also downloads its own
Temurin Java runtimes, so nothing needs to be installed on the host.

**Linux AMP hosts only** (works both with and without AMP's Docker/container mode).

## Files

| File | Purpose |
|---|---|
| `moddedminecraft.kvp` | Main template definition |
| `moddedminecraftconfig.json` | Settings shown in the AMP web UI |
| `moddedminecraftmetaconfig.json` | Maps settings into `server.properties` |
| `moddedminecraftports.json` | Port definition (TCP 25565) |
| `moddedminecraftupdates.json` | Update stages: installs mc-image-helper, Java, and the modpack |
| `manifest.json` | Marks the folder as an AMP `AppTemplates` repository so AMP discovers it |
| `start-modded.sh` | Reference copy of the launch script (the template embeds this itself — you do **not** need to upload it) |

## Installation

AMP only loads templates from **configuration repositories** it has been told about — it clones
each one into `Plugins/ADSModule/DeploymentTemplates/<owner>-<repo>-<branch>/`. Copying template
files onto the host by hand does *not* work, no matter where you put them (see
[Why not just copy the files?](#why-not-just-copy-the-files) below).

1. Push this folder to a **public** GitHub repository. It must be public so AMP can clone it
   without credentials.

2. In the AMP web UI on the **controller**, go to **Configuration → Instance Deployment →
   Configuration Repositories** and add:

   ```
   connormurray192-lab/AMPTemplates:main
   ```

3. Restart the ADS instance (`ampinstmgr restart ADS01`) or use the refresh action on that page.
   The ADS log should show `Updating remote source connormurray192-lab/AMPTemplates:main`.

4. **Create Instance** → select **Modded Minecraft** from the application list.

To update the template later, push to the repo — AMP re-pulls it on every ADS restart.

### Why not just copy the files?

Two dead ends, both verified on AMP 2.8:

- Files placed in a hand-made folder under `DeploymentTemplates/` are ignored, even with a valid
  `manifest.json` and even when the folder is made into a git repository.
- Files placed inside the official `CubeCoders-AMPTemplates-main/` folder are **deleted** on the
  next ADS restart, because AMP resets that clone when it re-pulls from GitHub.

## Setting up a modpack

1. Get a free CurseForge API key from <https://console.curseforge.com> (create an account →
   API Keys). This is required by CurseForge for automated downloads.
2. In the instance: **Configuration → Modpack**
   - **Modpack Page URL** – the pack's page, e.g.
     `https://www.curseforge.com/minecraft/modpacks/star-technology`.
     To pin a specific version, use a file page URL: `.../star-technology/files/1234567`.
   - **CurseForge API Key** – paste your key.
3. **Configuration → Java and Memory**
   - Tick **Accept Minecraft EULA**.
   - Pick the **Java Version** to match the pack's Minecraft version
     (1.20.5+ → 21, 1.17–1.20.4 → 17, 1.12–1.16 → 8). Star Technology (MC 1.20.1) → Java 17.
   - Set memory (most big packs want 6–8 GB max).
4. Click **Update** on the instance. Watch the console: it downloads mc-image-helper, the Java
   runtime, then installs the modpack (first install can take several minutes).
5. **Start** the server.

### Updating the pack

When the pack author publishes a new version, just click **Update** again — mc-image-helper
synchronises mods/configs to the newest server files (or to the pinned file if you used a
file URL). Your world and settings are kept.

## Notes & troubleshooting

- **"Files require manual download"** — a few pack authors disallow automated distribution of
  certain mods. mc-image-helper will list the offending files in the console with their project
  pages; download them manually and place them in the pack's `mods` folder, then Update again.
- **Wrong Java version** — if the server crashes immediately with class-file or module errors,
  the Java version doesn't match the pack. Change it and click Update (the new runtime is
  fetched automatically).
- **Memory** — `-Xms`/`-Xmx` from the settings are applied both to jar launches and to Forge's
  `run.sh` (via `user_jvm_args.txt`).
- The launch entry point is read from `.install-results.env` (written by mc-image-helper);
  if missing, `start-modded.sh` falls back to detecting `run.sh`, `fabric-server-launch.jar`,
  `server.jar`, etc.
- To change the pinned mc-image-helper version, edit `MIH=1.66.1` in
  `moddedminecraftupdates.json`.
