#!/usr/bin/env python3
"""
add_round4_files.py
Adds 7 new source files from Round-4 features to AGIMUS.xcodeproj/project.pbxproj.

New files:
  Models/TokenUsage.swift              CC000001
  Models/SearchProvider.swift          CC000002
  Services/SearchService.swift         CC000003
  Views/ThinkingView.swift             CC000004
  Views/ChatToolbarView.swift          CC000005
  ViewControllers/SearchProviderListViewController.swift  CC000006
  ViewControllers/SearchProviderEditViewController.swift  CC000007

Each new file needs:
  - PBXFileReference entry
  - PBXBuildFile entry
  - membership in its group's children list
  - membership in PBXSourcesBuildPhase files list
"""

import re, sys

PBXPROJ = "/Users/baishuxu/Documents/Xcode/AGIMUS/AGIMUS/AGIMUS.xcodeproj/project.pbxproj"

# (fileRef UUID, buildFile UUID, group path, filename)
NEW_FILES = [
    ("CC000001", "CC000011", "Models",           "TokenUsage.swift"),
    ("CC000002", "CC000012", "Models",           "SearchProvider.swift"),
    ("CC000003", "CC000013", "Services",         "SearchService.swift"),
    ("CC000004", "CC000014", "Views",            "ThinkingView.swift"),
    ("CC000005", "CC000015", "Views",            "ChatToolbarView.swift"),
    ("CC000006", "CC000016", "ViewControllers",  "SearchProviderListViewController.swift"),
    ("CC000007", "CC000017", "ViewControllers",  "SearchProviderEditViewController.swift"),
]

with open(PBXPROJ, "r", encoding="utf-8") as f:
    content = f.read()

# ── 1. PBXFileReference section ───────────────────────────────────────────────
file_ref_block = ""
for fid, _, grp, name in NEW_FILES:
    file_ref_block += (
        f"\t\t{fid} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {name}; sourceTree = \"<group>\"; }};\n"
    )

# Insert before the end of PBXFileReference section
content = content.replace(
    "/* End PBXFileReference section */",
    file_ref_block + "/* End PBXFileReference section */"
)

# ── 2. PBXBuildFile section ────────────────────────────────────────────────────
build_file_block = ""
for fid, bid, _, name in NEW_FILES:
    build_file_block += (
        f"\t\t{bid} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};\n"
    )

content = content.replace(
    "/* End PBXBuildFile section */",
    build_file_block + "/* End PBXBuildFile section */"
)

# ── 3. Add to group children ──────────────────────────────────────────────────
# Group pattern: find "path = <GroupName>;" then the children array
for fid, _, grp, name in NEW_FILES:
    # Match the group block that contains "path = <grp>;"
    pattern = (
        r"(path\s*=\s*" + re.escape(grp) + r"\s*;.*?children\s*=\s*\()(.*?)(\);)"
    )
    def add_child(m, fid=fid, name=name):
        return m.group(1) + m.group(2) + f"\t\t\t\t{fid} /* {name} */,\n" + m.group(3)
    new_content = re.sub(pattern, add_child, content, count=1, flags=re.DOTALL)
    if new_content == content:
        print(f"WARNING: Could not find group '{grp}' to add {name}")
    else:
        content = new_content

# ── 4. Add to PBXSourcesBuildPhase files ─────────────────────────────────────
sources_entries = "".join(
    f"\t\t\t\t{bid} /* {name} in Sources */,\n"
    for _, bid, _, name in NEW_FILES
)
# Insert before "/* End PBXSourcesBuildPhase section */"
content = content.replace(
    "/* End PBXSourcesBuildPhase section */",
    sources_entries + "\t\t\t/* End PBXSourcesBuildPhase section */"
)

with open(PBXPROJ, "w", encoding="utf-8") as f:
    f.write(content)

print("Done. Added", len(NEW_FILES), "files to project.pbxproj.")
