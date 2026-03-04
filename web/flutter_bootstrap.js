{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Keep web startup independent from gstatic/CDN fetch failures.
    renderer: "canvaskit",
    canvasKitBaseUrl: "/canvaskit/",
  },
});
