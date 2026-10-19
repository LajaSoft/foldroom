# FFB dependency

`ffb.gdextension` and the debug Linux x86-64 binary are copied without modification from the adjacent `godot-racing/demo/addons/ffb/` project. They target Godot 4.4.x; the shared Docker runtime is Godot 4.4.1.

Source: `../godot-racing/src/ffb_device.{h,cpp}`, `ffb_manager.{h,cpp}` and `register_types.{h,cpp}`, with its `godot-cpp` dependency and `SConstruct`. From the FoldRoom root, `docker compose run --rm ffb-build` rebuilds and installs the debug library using those sources. No static dependency on the racing demo's GDScript classes is required: `scripts/controls.gd` instantiates FFBManager through ClassDB.

Only development/debug execution is packaged here. A release export also needs the matching template_release library built from that source.
