#!/usr/bin/env python3
"""
Patches AGIMUS.xcodeproj/project.pbxproj to:
  1. Set GENERATE_INFOPLIST_FILE = NO (app target, both configs)
  2. Remove INFOPLIST_KEY_* keys and UIMainStoryboardFile keys
  3. Add all new Swift source files to:
       - PBXFileReference
       - PBXGroup (under the AGIMUS group with sub-groups)
       - PBXBuildFile
       - PBXSourcesBuildPhase (152A39F82F83BF570048BAF8)
"""

import re, sys

PBXPROJ = "/Users/baishuxu/Documents/Xcode/AGIMUS/AGIMUS/AGIMUS.xcodeproj/project.pbxproj"

# ── New files to add ───────────────────────────────────────────────────────────
# (fileRefID, buildFileID, relative_path, display_name)
NEW_FILES = [
    # Models
    ("AA000001AA000001AA000001", "AA000002AA000002AA000002", "AGIMUS/Models/ChatMessage.swift",              "ChatMessage.swift"),
    ("AA000003AA000003AA000003", "AA000004AA000004AA000004", "AGIMUS/Models/ChatSession.swift",               "ChatSession.swift"),
    ("AA000005AA000005AA000005", "AA000006AA000006AA000006", "AGIMUS/Models/ProviderConfig.swift",            "ProviderConfig.swift"),
    # Services
    ("AA000007AA000007AA000007", "AA000008AA000008AA000008", "AGIMUS/Services/KeychainService.swift",         "KeychainService.swift"),
    ("AA000009AA000009AA000009", "AA00000AAA00000AAA00000A", "AGIMUS/Services/SettingsStore.swift",           "SettingsStore.swift"),
    ("AA00000BAA00000BAA00000B", "AA00000CAA00000CAA00000C", "AGIMUS/Services/SessionStore.swift",            "SessionStore.swift"),
    ("AA00000DAA00000DAA00000D", "AA00000EAA00000EAA00000E", "AGIMUS/Services/ChatAPIService.swift",          "ChatAPIService.swift"),
    # Utils
    ("AA00000FAA00000FAA00000F", "AA000010AA000010AA000010", "AGIMUS/Utils/Extensions.swift",                 "Extensions.swift"),
    ("AA000011AA000011AA000011", "AA000012AA000012AA000012", "AGIMUS/Utils/MarkdownRenderer.swift",           "MarkdownRenderer.swift"),
    # Views
    ("AA000013AA000013AA000013", "AA000014AA000014AA000014", "AGIMUS/Views/InputBarView.swift",               "InputBarView.swift"),
    ("AA000015AA000015AA000015", "AA000016AA000016AA000016", "AGIMUS/Views/MessageCell.swift",                "MessageCell.swift"),
    # ViewControllers
    ("AA000017AA000017AA000017", "AA000018AA000018AA000018", "AGIMUS/ViewControllers/SessionListViewController.swift", "SessionListViewController.swift"),
    ("AA000019AA000019AA000019", "AA00001AAA00001AAA00001A", "AGIMUS/ViewControllers/ChatViewController.swift",        "ChatViewController.swift"),
    ("AA00001BAA00001BAA00001B", "AA00001CAA00001CAA00001C", "AGIMUS/ViewControllers/SettingsViewController.swift",    "SettingsViewController.swift"),
]

# Sub-group IDs and their display names + members (fileRefIDs)
GROUPS = [
    ("AA000020AA000020AA000020", "Models",          ["AA000001AA000001AA000001","AA000003AA000003AA000003","AA000005AA000005AA000005"]),
    ("AA000021AA000021AA000021", "Services",        ["AA000007AA000007AA000007","AA000009AA000009AA000009","AA00000BAA00000BAA00000B","AA00000DAA00000DAA00000D"]),
    ("AA000022AA000022AA000022", "Utils",           ["AA00000FAA00000FAA00000F","AA000011AA000011AA000011"]),
    ("AA000023AA000023AA000023", "Views",           ["AA000013AA000013AA000013","AA000015AA000015AA000015"]),
    ("AA000024AA000024AA000024", "ViewControllers", ["AA000017AA000017AA000017","AA000019AA000019AA000019","AA00001BAA00001BAA00001B"]),
]

with open(PBXPROJ, "r") as f:
    content = f.read()

original = content  # keep for diffing

# ── 1. GENERATE_INFOPLIST_FILE = NO ───────────────────────────────────────────
content = content.replace("GENERATE_INFOPLIST_FILE = YES;", "GENERATE_INFOPLIST_FILE = NO;")

# ── 2. Remove INFOPLIST_KEY_* and UIMainStoryboardFile lines ──────────────────
content = re.sub(r'\t+INFOPLIST_KEY_[^\n]+\n', '', content)
content = re.sub(r'\t+INFOPLIST_KEY_UIMainStoryboardFile[^\n]*\n', '', content)

# ── 3. PBXBuildFile section ────────────────────────────────────────────────────
build_file_entries = "\n".join(
    f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};'
    for fr, bf, _, name in NEW_FILES
)
content = content.replace(
    "/* End PBXBuildFile section */",
    build_file_entries + "\n/* End PBXBuildFile section */"
)

# ── 4. PBXFileReference section ───────────────────────────────────────────────
file_ref_entries = "\n".join(
    f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'
    for fr, _, _, name in NEW_FILES
)
content = content.replace(
    "/* End PBXFileReference section */",
    file_ref_entries + "\n/* End PBXFileReference section */"
)

# ── 5. PBXGroup section — sub-groups ─────────────────────────────────────────
group_entries = []
for gid, gname, members in GROUPS:
    members_str = "\n".join(f'\t\t\t\t{m} /* {next(n for f,_,_,n in NEW_FILES if f==m)} */,' for m in members)
    group_entries.append(
        f'\t\t{gid} /* {gname} */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n'
        f'{members_str}\n'
        f'\t\t\t);\n'
        f'\t\t\tname = {gname};\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};'
    )
group_block = "\n".join(group_entries)
content = content.replace(
    "/* End PBXGroup section */",
    group_block + "\n/* End PBXGroup section */"
)

# ── 6. Add sub-group IDs to main AGIMUS group ─────────────────────────────────
# The main AGIMUS group starts after: 152A39FE2F83BF570048BAF8 /* AGIMUS */ = {
group_ids_str = "\n".join(
    f'\t\t\t\t{gid} /* {gname} */,'
    for gid, gname, _ in GROUPS
)
# Insert before first existing child in that group (AppDelegate.swift)
content = content.replace(
    "\t\t\t\t152A39FF2F83BF570048BAF8 /* AppDelegate.swift */,",
    group_ids_str + "\n\t\t\t\t152A39FF2F83BF570048BAF8 /* AppDelegate.swift */,"
)

# ── 7. PBXSourcesBuildPhase — add build files ─────────────────────────────────
build_file_refs = "\n".join(
    f'\t\t\t\t{bf} /* {name} in Sources */,'
    for _, bf, _, name in NEW_FILES
)
# Insert before existing first entry in the main Sources phase
content = content.replace(
    "\t\t\t\t152A3A042F83BF570048BAF8 /* ViewController.swift in Sources */,",
    build_file_refs + "\n\t\t\t\t152A3A042F83BF570048BAF8 /* ViewController.swift in Sources */,"
)

# ── 8. Write back ─────────────────────────────────────────────────────────────
with open(PBXPROJ, "w") as f:
    f.write(content)

print("Done. Lines changed:", sum(1 for a, b in zip(original.splitlines(), content.splitlines()) if a != b))
