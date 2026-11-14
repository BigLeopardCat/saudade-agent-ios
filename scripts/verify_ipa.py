"""Check the actual packaged application and extension, not only build settings."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import zipfile

p = argparse.ArgumentParser()
p.add_argument("ipa", type=Path)
p.add_argument("--commit", required=True)
p.add_argument("--build", required=True)
args = p.parse_args()
with zipfile.ZipFile(args.ipa) as z:
    app_path = "Payload/Lingyue.app/"
    app = plistlib.loads(z.read(app_path + "Info.plist"))
    extension = plistlib.loads(z.read(app_path + "PlugIns/LingyueIsland.appex/Info.plist"))
    assert app["BuildSourceCommit"] == extension["BuildSourceCommit"] == args.commit
    assert app["CFBundleVersion"] == extension["CFBundleVersion"] == args.build
    assert app["CFBundleShortVersionString"] == extension["CFBundleShortVersionString"] == "0.2.0"
    assert len([n for n in z.namelist() if n.startswith(app_path) and n.endswith(".webp")]) == 24
    assert app.get("CFBundleIcons"), "AppIcon missing from packaged plist"
manifest = {"sourceCommit": args.commit, "version": app["CFBundleShortVersionString"],
            "build": args.build, "sha256": hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
            "appBundleID": app["CFBundleIdentifier"], "extensionBundleID": extension["CFBundleIdentifier"],
            "signed": False, "embeddedStickers": 24}
args.ipa.with_name("build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest))
