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

> [!CAUTION]
> Do not delete the pre-existing assets (files that are already in this folder).

Sandstorm v3's coconut palms use custom asset `2412a`, which is not part of
`mod.zip`. These original files are bundled separately:

- `models/custom/2412.obj` from <https://user-assets.krunker.io/2412/model.obj>
- `textures/custom/2412.png` from <https://user-assets.krunker.io/2412/model.png>

The map's `ms` field supplies the model scale. The `a` suffix enables the
browser's alpha cutoff of `0.02` so leaf cutouts do not occlude the background.
