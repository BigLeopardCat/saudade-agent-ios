"""Boot a clean simulator matching the selected SDK, with a bounded startup wait."""
import json
import subprocess
import sys

sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip()
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"], text=True))["runtimes"]
matches = [r for r in runtimes if r.get("isAvailable") and r["version"].startswith(sdk) and "iOS" in r["identifier"]]
if not matches:
    raise RuntimeError("No installed iOS simulator runtime matches SDK " + sdk)
runtime = matches[0]["identifier"]
print("Preparing clean iPhone 15 Pro simulator: " + runtime, file=sys.stderr, flush=True)
device = subprocess.check_output(["xcrun", "simctl", "create", "Lingyue-CI", "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro", runtime], text=True).strip()
subprocess.run(["xcrun", "simctl", "boot", device], check=True, stdout=sys.stderr, timeout=60)
subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, stdout=sys.stderr, timeout=180)
print(device, flush=True)
