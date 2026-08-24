///|
/// The DSH shell patch is macOS composition policy. Keep its web resources in
/// separate files; the package pre-build step embeds them into MoonBit.
fn dsh_shell_patch() -> @webview_host.HostPatchBundle {
  let origins = [
    @webview_host.WebViewOrigin::parse(@app.default_url).unwrap(),
    @webview_host.WebViewOrigin::parse(@app.default_chat_url).unwrap(),
  ]
  @webview_host.HostPatchBundle::new(
    id="dsh-shell",
    version="1.0.0",
    allowed_origins=origins,
    stylesheet=Some(dsh_shell_patch_css),
    document_end_script=Some(dsh_shell_patch_js),
  )
}

///|
/// Coordinates are relative to the WebView's top-left origin and are kept
/// outside the shared app so only macOS opts into the native drag exception.
fn dsh_top_no_drag_regions(
  viewport_width : Double,
) -> Array[@webview_host.WebViewNoDragRegion] {
  let right = viewport_width.max(260.0)
  [
    @webview_host.WebViewNoDragRegion::new(
      left=right - 180.0,
      top=10.0,
      right=right - 10.0,
      bottom=32.0,
    ),
  ]
}
