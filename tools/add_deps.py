import subprocess

p = "pubspec.yaml"
lines = open(p, encoding="utf-8").read().split("\n")
SDK = '  sdk: ">=3.5.0 <4.0.0"'
done = False
for i, l in enumerate(lines):
    if l.strip() == "environment:" and not l.startswith((" ", "\t")):
        j = i + 1
        while j < len(lines) and (lines[j].startswith((" ", "\t")) or lines[j].strip() == ""):
            if lines[j].strip().startswith("sdk:"):
                lines[j] = SDK
                done = True
                break
            j += 1
        break
if not done:
    lines += ["", "environment:", SDK]
open(p, "w", encoding="utf-8").write("\n".join(lines))

PINNED = [
    "youtube_explode_dart:^3.1.0",
    "just_audio:^0.10.5",
    "audio_service:^0.18.18",
    "flutter_inappwebview:^6.1.5",
    "share_plus:^10.1.4",
    "flutter_local_notifications:^19.4.2",
    "file_picker:^10.3.3",
    "flutter_secure_storage:^9.2.4",
    "flutter_tts:^4.2.3",
    "crypto:^3.0.6",
    "android_intent_plus:^5.3.0",
]
# Sin versión: pub elige la compatible con las anteriores.
FREE = [
    "audio_session",
    "rxdart",
    "permission_handler:^11.3.1",
    "shared_preferences",
    "path_provider",
    "http",
    "youtube_player_iframe",
    "webview_flutter",
    "webview_flutter_android",
    "url_launcher",
    "package_info_plus",
    "quick_actions",
    "home_widget",
    "timezone",
    "flutter_volume_controller",
]

try:
    subprocess.run(["flutter", "pub", "add", *PINNED, *FREE], check=True)
except subprocess.CalledProcessError:
    # Respaldo: si algún pin no resuelve (p. ej. SDK de Flutter más viejo),
    # deja que pub resuelva las últimas versiones compatibles.
    print("Fallo con versiones fijadas; reintentando sin versiones...")
    subprocess.run(
        ["flutter", "pub", "add", *[d.split(":")[0] for d in PINNED], *FREE],
        check=True,
    )
