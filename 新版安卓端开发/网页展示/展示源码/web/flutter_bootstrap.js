{{flutter_js}}
{{flutter_build_config}}
window.addEventListener('flutter-first-frame', () => document.getElementById('loading')?.remove(), {once: true});
_flutter.loader.load({
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({hostElement: document.getElementById('app'), canvasKitBaseUrl: 'canvaskit/', fontFallbackBaseUrl: 'fonts/fallback/'});
    await appRunner.runApp();
  }
});
