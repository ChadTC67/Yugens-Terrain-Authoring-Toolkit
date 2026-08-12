# Yūgen's Terrain Authoring Toolkit
The public version of the Marching Squares Terrain plugin for the [Godot Engine](https://godotengine.org/).

This project is an effort to create a simple to use and powerfull terrain authoring tool inside godot aimed at 3D pixel art games. However, the plugin featured in this project can be used for a wide variety of games and experimentation is encouraged!

## Features

### Terraforming Brushes

What is a terrain plugin without its terraforming tools! As the terrain is heightmap based, all the terraforming brushes can only extrude in the postive and negative Y axis, however, this still allows for plenty of amazing ways to shape your terrain to your liking:

* **BRUSH TOOL** → A simple way to elevate and lower terrain cells;

* **LEVEL TOOL** → Set the terrain's selected cells' height to a user-set value;

* **SMOOTH TOOL** → Smooth the terrain depending on the average height of neighbouring cells;

* **BRIDGE TOOL** → Create a bridge between two points by drawing a straight or curved line between them.

### Visual Brushes

To enhance the visuals of your terrain and game the plugin currently features a set of 3 visual-based brushes that each alter the terrain in a different way.

* **GRASS MASK TOOL** → Paint a mask map that determines whether selected cells should draw `MultiMeshInstance3d` grass instances;

* **VERTEX PAINTER TOOL** → Paint up to 255 custom textures onto the terrain vertices each with their own list of simple and advanced settings;

* **POPULATOR TOOL** → Spawn flowers onto the terrain via the custom `MarchingSquaresFlowerPlanter` node.

### Plugin Management Tools

These custom tabs and brushes allow you to change and debug terrain, chunk and heightmap settings. They offer a wide variety of customisability so you can create your dream terrain and game feel!

* **DEBUG BRUSH TOOL** → By selecting terrain cells you can print certain information about them in the in-editor output terminal;

* **CHUNK MANAGEMENT TOOL** → Here you can change not only global chunk settings but also manage the smoothing algorithm of individual chunks;

* **HEIGHTMAP TOOL** → This tool comes in three parts: 1) terrain importing; 2) terrain exporting; 3) heightmap extraction and linked brush placement. These tools are all focussed on creating a faster terrain workflow;

* **TERRAIN SETTINGS TOOL** → This final tool allows for terrain wide changes that do not only affect the chunks themselves but also the tool-related meshes inside it. A couple examples are global wind, post-processing effects, texture blend settings and cell shading.

___

For more in-depth documentation on all the above tools and features, please refer to the _documentation_ folder in the addon.

For community showcases, feature requests and bug reporting, please refer to the [discord](https://discord.gg/ZSeYkTCgft).
A bug can also be reported by opening a new issue thread in the issues tab of this github project.

## Install Guide

To install the plugin, simply download or clone the latest stable version of this project and copy the plugin from this project's addon folder into your own. Make sure to turn on the plugin in godot by going into the project settings and under "plugins" checking the checkbox next to the plugin's name.

Watch the [YouTube](https://www.youtube.com/playlist?list=PLXcmz5ZRdiyTpf_Jk9gGNb9QQ6Hus8xiP) videos to get started with the plugin!!!

## Known Issues

1. d3d12 doesn't load terrain material properly when in game on some devices

## PR Workflow

Please target and base your PR's on `public-testing` instead of `main` otherwise we cannot review or aprove them!

Also make sure to give a good description of what your PR fixes or adds so we don't have to go through all the files unnecessarily.

## Credits

Developed by [Yūgen](https://www.youtube.com/@yugen_seishin) and originally forked from [Jackachulian](https://github.com/jackachulian/jackachulian) on github.

Collaborators (v1.1.0 ONWARDS):
* [DanTrz](https://github.com/DanTrz)
* [powertomato](https://github.com/powertomato)
* [santarl](https://github.com/santarl)
* [OfficiallyBeez](https://github.com/OfficialBeez)
* [BrennanTanner](https://github.com/BrennanTanner)
* [Craig Kerwin](https://github.com/craig-kerwin)

A special thanks to OfficiallyBeez, DanTrz (creator of the TileMapLayer3D plugin), powertomato and santarl for co-authoring big parts of the plugin since the 1.0 release. They have been amazing contributors to the project and awesome people to work with!

Contributors:
* [Dylearn](https://www.youtube.com/@Dylearn)
* [AtSaturn](https://www.youtube.com/@AtPlayerSaturn)
* My lifelong best friends!

###
A big thanks to the above people for giving helpful insights, discussing certain features and thinking together about math related problems. Without them I couldn't have finished the plugin as fast as I have.
