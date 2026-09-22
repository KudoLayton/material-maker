# Material Maker

This is a tool based on [Godot Engine](https://godotengine.org/) that can
be used to create textures procedurally and paint 3D models.

Its user interface is based on Godot's GraphEdit node: textures and brushes are
described as interconnected nodes.

![Screenshot](material_maker/doc/images/screenshot.png)

## Modular GPU Particles (this fork)

This fork targets **Godot 4.7.2 stable / Forward+ / Vulkan** for modular particles.
Source builds require access to the **private** runtime repository and its pinned
submodule; the addon source is not published in this public repository.

```powershell
git clone --recurse-submodules git@github.com:KudoLayton/material-maker.git
# For an existing checkout:
git submodule update --init --recursive
```

The runtime is mounted at `addons/mm_gpu_particles` from
`git@github.com:KudoLayton/godot-modular-gpu-particles.git`.
See [MODULAR_PARTICLES.md](MODULAR_PARTICLES.md) for authoring/build instructions,
[STANDARD_PARTICLE_MODULES.md](STANDARD_PARTICLE_MODULES.md) for the 12 editable
basic modules, searchable catalog, and acceleration/drag solver workflow,
and [GODOT_PARTICLES_PLUGIN.md](GODOT_PARTICLES_PLUGIN.md) for game integration.
The upstream downloads below do **not** contain this fork's modular editor.

## Download

- **[itch.io](https://rodzilla.itch.io/material-maker)**
- **[Steam](https://store.steampowered.com/app/4110830/Material_Maker/)**

On Windows, you can also install Material Maker using [Scoop](https://scoop.sh):

```text
scoop bucket add extras
scoop install material-maker
```
... or [Chocolatey](https://chocolatey.org/) (default or portable install):
```text
choco install material-maker
```
```text
choco install material-maker.portable
```

on macOS, you can also install Material Maker using [Homebrew](https://brew.sh/):

```text
brew install material-maker
```

Can't wait for next release? Automated builds from master branch are available (use at your own risk):

[![Build Material Maker](https://github.com/RodZill4/material-maker/actions/workflows/dev-desktop-builds.yml/badge.svg?branch=master)](https://github.com/RodZill4/material-maker/actions/workflows/dev-desktop-builds.yml?query=branch%3Amaster)

## Documentation

- **[User manual](https://rodzill4.github.io/material-maker/doc/)**

## Translations

Translation files can be installed using the **Install** button in the **Preferences** dialog.

- [Chinese translation](https://raw.githubusercontent.com/RodZill4/material-maker/f1be50b21a0f4991ac39e12a5362f5c5eb4c83a0/material_maker/locale/translations/zh.csv) (Created by **free_king**)

## Community

- **[Discord server](https://discord.gg/PF5V3mFwFM)**
- **[Material Maker subreddit](https://www.reddit.com/r/MaterialMaker/)**

## License

Copyright (c) 2018-present Rodolphe Suescun and contributors

Unless otherwise specified, files in this repository are licensed under the
MIT license. See [LICENSE.md](LICENSE.md) for more information.
