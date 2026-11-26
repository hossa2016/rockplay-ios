"""Ajustes del proyecto iOS generado por `flutter create`.

- Audio en segundo plano (radio y reproductor nativo).
- Conexiones http (algunas emisoras no usan https).
- Nombre visible y versión mínima de iOS.
"""
import plistlib
import re

PLIST = "ios/Runner/Info.plist"
with open(PLIST, "rb") as f:
    info = plistlib.load(f)

info["CFBundleDisplayName"] = "RockPlay IA"
info["UIBackgroundModes"] = ["audio"]
info["NSAppTransportSecurity"] = {"NSAllowsArbitraryLoads": True}
info["LSApplicationQueriesSchemes"] = ["https", "http", "youtube", "spotify"]
info["ITSAppUsesNonExemptEncryption"] = False
info["UIFileSharingEnabled"] = True
info["LSSupportsOpeningDocumentsInPlace"] = True
info["NSPhotoLibraryUsageDescription"] = "Para guardar la imagen de Tu mes."
info["NSPhotoLibraryAddUsageDescription"] = "Para guardar la imagen de Tu mes."
info["NSMicrophoneUsageDescription"] = "No se usa el micrófono."
info["NSCalendarsUsageDescription"] = "Para añadir conciertos a tu calendario."

with open(PLIST, "wb") as f:
    plistlib.dump(info, f)

# Versión mínima de iOS (varios plugins piden 13 o más).
pod = "ios/Podfile"
s = open(pod, encoding="utf-8").read()
s = re.sub(r"^#?\s*platform :ios, .*$", "platform :ios, '14.0'", s, flags=re.M)
if "platform :ios" not in s:
    s = "platform :ios, '14.0'\n" + s
# permission_handler: sin permisos especiales compilados.
if "PERMISSION_" not in s:
    s = s.replace(
        "flutter_additional_ios_build_settings(target)",
        "flutter_additional_ios_build_settings(target)\n"
        "    target.build_configurations.each do |config|\n"
        "      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'\n"
        "    end",
    )
open(pod, "w", encoding="utf-8").write(s)

pbx = "ios/Runner.xcodeproj/project.pbxproj"
p = open(pbx, encoding="utf-8").read()
p = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 14.0;", p)
open(pbx, "w", encoding="utf-8").write(p)
print("iOS listo")
