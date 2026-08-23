# DeepSeek Harness Desktop

Standalone native [MoUI](https://github.com/wzzc-dev/MoUI) desktop shell for [DeepSeek Harness](https://github.com/deepseek-ai). Extracted from `examples/deepseek_harness_desktop` in the MoUI monorepo.

DSH owns the product UI and state; this app only embeds the local Harness surface in a controlled `moui_webview` platform view and reports a clear fallback when the native WebView is unavailable.

The retained app lives in `app/`; the macOS, Windows, and Linux entrypoints only assemble their native WebView plugin, Skia renderer, and native host.

## Prerequisites

- [MoonBit toolchain](https://www.moonbitlang.com/download/) (`moon` >= 0.1.8)
- Platform WebView dependencies:
  - **macOS**: Xcode and WebKit (bundled)
  - **Windows**: WebView2 runtime
  - **Linux**: WebKitGTK native dependencies (`libwebkit2gtk-4.1-dev`, `libsoup`, etc.)

## Run

```sh
# macOS
moon run macos_skia --target native

# Windows
moon run windows_skia --target native

# Linux
moon run linux_skia --target native
```

The default surface is `http://127.0.0.1:3080`, matching a local DSH host. Start the Host before launching this composition root. The app does not duplicate DSH navigation, sessions, profiles, settings, or terminal UI.

All three composition roots use the Skia provider route. `MOUI_SKIA_RENDERER` selects `auto` (the default), `skia-gpu`, or `skia-raster`; auto prefers the native GPU surface and falls back to Skia raster. When native WebView is unavailable, the app shows its capability fallback instead of embedding a substitute surface.

## Configuration

Use `Settings…` in the standard macOS application menu, or press `Cmd+,`, to change the DSH root URLs and appearance. The Theme control offers `System`, `Dark`, and `Light`; it is persisted as `dsh-desktop/theme-mode` and drives both the MoUI surface and the native WebView background. The native URL settings accept trimmed `http://` and `https://` URLs, persist through `NSUserDefaults`, and apply only after persistence succeeds. Saving the current URL only closes the dialog; it does not reload the WebView.

On macOS, the settings dialog is a MoUI modal above the full-window WKWebView. While it is open, the active Skia presenter moves above the WebView, uses a transparent frame clear, and the WebView excludes the full overlay bounds from hit testing. Skia auto mode tries the GPU surface first and falls back to the CPU raster presenter when GPU setup is unavailable. Closing the dialog restores the WebView as the front sibling and restores its input.

The first 32 points of the WebView are also a drag/no-drag strip: blank space moves the native window, while links, buttons, inputs, editable controls, and elements marked `data-moui-no-drag` remain clickable. DSH can add that attribute to any custom interactive control in its top bar.

## Theming & Navigation

When switching between Harness (`http://127.0.0.1:3080`) and Chat (`https://chat.deepseek.com/`), the resolved Theme background is applied to the native WebView before navigation starts. This prevents a system-light/Chat-dark switch from exposing the native WebView's default white or black startup surface. On macOS the resolved mode is also applied as the WKWebView's native Aqua/Dark Aqua appearance.

The floating button (brand blue) toggles between Harness and Chat. It can be dragged, docked to either edge (leaving a 16px peek tab), and secondary-tapped to open Settings.

The native composition root installs the versioned `dsh-shell` HostPatch (`v1.0.0`) before the first navigation and on every later configuration revision. Its stylesheet adjusts the expanded sidebar top inset, collapsed rail width, and related grid columns. The macOS traffic lights themselves are not resized.

## Project Structure

```
.
├── app/              # Platform-agnostic TEA program (Model/Msg/update/view)
│   ├── config.mbt
│   ├── model.mbt
│   ├── update.mbt
│   ├── view.mbt
│   ├── program.mbt
│   ├── runtime.mbt
│   └── commands.mbt
├── macos_skia/       # macOS composition root (WKWebView + Skia)
├── linux_skia/       # Linux composition root (WebKitGTK + Skia)
├── windows_skia/     # Windows composition root (WebView2 + Skia raster)
├── moon.mod          # Module manifest (deepseek_harness_desktop)
└── README.md
```

## Test

```sh
moon test app --target native
moon check macos_skia --target native
moon check linux_skia --target native
moon check windows_skia --target native
```

## Origin

This repository was extracted via `git subtree split -P examples/deepseek_harness_desktop` from [wzzc-dev/MoUI](https://github.com/wzzc-dev/MoUI). History is preserved with `LICENSE` as the root commit.

Upstream path: `examples/deepseek_harness_desktop/` in MoUI monorepo.

## License

Apache-2.0, see [LICENSE](./LICENSE).
