#!/usr/bin/env python3
"""
Add ProviderListViewController.swift and ProviderEditViewController.swift
(which also contains ModelPickerViewController) to the pbxproj.
"""
PBXPROJ = "/Users/baishuxu/Documents/Xcode/AGIMUS/AGIMUS/AGIMUS.xcodeproj/project.pbxproj"

NEW = [
    ("BB000001BB000001BB000001", "BB000002BB000002BB000002",
     "ProviderListViewController.swift"),
    ("BB000003BB000003BB000003", "BB000004BB000004BB000004",
     "ProviderEditViewController.swift"),
]

with open(PBXPROJ) as f:
    content = f.read()

# 1. PBXBuildFile
bf_entries = "\n".join(
    f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};'
    for fr, bf, name in NEW
)
content = content.replace("/* End PBXBuildFile section */",
                           bf_entries + "\n/* End PBXBuildFile section */")

# 2. PBXFileReference
fr_entries = "\n".join(
    f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'
    for fr, bf, name in NEW
)
content = content.replace("/* End PBXFileReference section */",
                           fr_entries + "\n/* End PBXFileReference section */")

# 3. Add file refs to ViewControllers group
# The ViewControllers group (AA000024) ends with its last existing member before );
for fr, bf, name in NEW:
    content = content.replace(
        '\t\t\t\tAA00001BAA00001BAA00001B /* SettingsViewController.swift */,',
        f'\t\t\t\tAA00001BAA00001BAA00001B /* SettingsViewController.swift */,\n\t\t\t\t{fr} /* {name} */,'
    )

# 4. Add to Sources build phase
bf_refs = "\n".join(
    f'\t\t\t\t{bf} /* {name} in Sources */,'
    for fr, bf, name in NEW
)
content = content.replace(
    '\t\t\t\tAA00001CAA00001CAA00001C /* SettingsViewController.swift in Sources */,',
    f'\t\t\t\tAA00001CAA00001CAA00001C /* SettingsViewController.swift in Sources */,\n{bf_refs}'
)

with open(PBXPROJ, "w") as f:
    f.write(content)

# Verify
for fr, bf, name in NEW:
    ok_fr = fr in content
    ok_bf = bf in content
    print(f"  [{'OK' if ok_fr and ok_bf else 'FAIL'}] {name}")
