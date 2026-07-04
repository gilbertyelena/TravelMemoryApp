#!/usr/bin/env python3
import shutil, sys, os
src = os.path.expanduser("~/.gemini/antigravity/brain/11ca8238-dc8f-400f-b5c4-a8637426c941/travel_steward_icon_1778332728493.png")
dst = os.path.expanduser("~/TravelMemory/TravelMemory/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
shutil.copy2(src, dst)
print(f"Copied {os.path.getsize(dst)} bytes to {dst}")
