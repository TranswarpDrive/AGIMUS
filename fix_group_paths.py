#!/usr/bin/env python3
"""
The custom sub-groups were created with `name = X` but no `path`.
Xcode resolves file paths relative to the nearest ancestor group that HAS a path.
Without `path` on the sub-group, files resolve against the parent AGIMUS group
(path = AGIMUS) → flat → wrong.

Fix: replace `name = X;` → `path = X;` for each custom group so that
file references (path = Foo.swift) resolve as AGIMUS/X/Foo.swift.
"""

PBXPROJ = "/Users/baishuxu/Documents/Xcode/AGIMUS/AGIMUS/AGIMUS.xcodeproj/project.pbxproj"

GROUPS = ["Models", "Services", "Utils", "Views", "ViewControllers"]

with open(PBXPROJ) as f:
    content = f.read()

# Each custom group block looks like:
#   AA... /* Models */ = {
#       isa = PBXGroup;
#       children = ( ... );
#       name = Models;
#       sourceTree = "<group>";
#   };
# We want to replace `name = Models;` with `path = Models;` inside those blocks.

import re

for grp in GROUPS:
    # Replace `name = GRP;` that appear right after our group's UUID comment
    # Safe pattern: only touch lines that have exactly `\t\t\tname = GRP;`
    # (the existing AGIMUSTests/AGIMUSUITests groups also use name= but they have path= already)
    content = content.replace(
        f"\t\t\tname = {grp};\n\t\t\tsourceTree",
        f"\t\t\tpath = {grp};\n\t\t\tsourceTree"
    )

with open(PBXPROJ, "w") as f:
    f.write(content)

# Verify
for grp in GROUPS:
    ok = f"path = {grp};" in content
    print(f"  [{'OK' if ok else 'FAIL'}] {grp} has path=")
