# Game assets

Please unpack Krunker's `mod.zip` into this folder, more specifically:

- `models/*`
- `textures/*`
- `sound/*`

HUD and menu text use the bundled `css/fonts/Rajdhani-SemiBold.ttf` from
[Google Fonts](https://github.com/google/fonts/tree/main/ofl/rajdhani), licensed
under the SIL Open Font License in `css/fonts/Rajdhani-OFL.txt`.

> [!TIP]
> The client has been checked against the current `mod.zip` used by the latest
> Krunker build. Older packs may omit models or textures referenced by v3 maps.

Weapon rigs use the current browser model scales, grips and sight mounts.
The AK, SMG, LMG, Semi Auto, Famas and Blaster include their reflex sights.
Both release packagers refresh all supported weapons from the unpacked pack,
including textures and HUD icons, using `config/weapon-assets.txt`.
This also includes the practice-class primaries and `textures/scopes/scope_0.png`.
The shotgun uses the browser's Nova Pump replacement (`weapon_6_0.obj`,
`weapon_6_38.png`) with its own model scale and mounting offset.

Run `python download_maps.py` from the repository to refresh all 47 official
map files from GAPI. The script keeps native server IDs aligned with the
browser catalog, and both packagers replace the map files in older archives.
The script downloads map JSON; it does not download custom hosted models or
browser scripts referenced by those maps.

> [!CAUTION]
> Do not delete the pre-existing assets (files that are already in this folder).

Sandstorm v3's coconut palms use custom asset `2412a`, which is not part of
`mod.zip`. These original files are bundled separately:

- `models/custom/2412.obj` from <https://user-assets.krunker.io/2412/model.obj>
- `textures/custom/2412.png` from <https://user-assets.krunker.io/2412/model.png>

The map's `ms` field supplies the model scale. The `a` suffix enables the
browser's alpha cutoff of `0.02` so leaf cutouts do not occlude the background.

Burg also references hosted assets absent from `mod.zip`. Run
`python download_burg_assets.py` to restore the original OBJ/PNG pairs for
`632` (trees), `2846` (windows), `30061`, `30162`, `61806`, `61815`, and `61820`
from `https://user-assets.krunker.io/<id>/model.obj` and `model.png`.
The same script retains `models/custom/27432.gltf` from that host and converts
its single static foliage mesh to OBJ, preserving the original coordinates
and UVs. Its material is untextured white; the map supplies the foliage colors.
This conversion supports that specific static asset, not animated glTF models.
Both release packagers overlay the bundled custom models and textures using
`config/map-assets.txt`, so older seed archives receive the missing art too.
