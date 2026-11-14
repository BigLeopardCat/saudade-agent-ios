#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Technical export only: the artwork was edited/generated with built-in image_gen.
# iOS AppIcon must be exactly 1024px and opaque. Shared avatar is bounded for WidgetKit.
sips -z 1024 1024 Artwork/lingyue-app-icon-master.png --out App/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
sips -z 384 384 Artwork/lingyue-island-head-master.png --out Resources/Assets.xcassets/LingyueAvatar.imageset/lingyue-head.png >/dev/null
swift scripts/verify_assets.swift
