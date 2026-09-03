# Brand Assets

`Sources/` contains the original TokChan artwork and is kept outside the `TokChan` app target. Treat these files as source material; do not edit them when updating generated assets.

The app-bundled derivatives live in `TokChan/Assets.xcassets`. From the repository root, regenerate them with:

```sh
swift .trellis/tasks/09-03-update-app-icons/generate_assets.swift
```
