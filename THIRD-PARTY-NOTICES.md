# Third-party notices

Forever Flight Timer and Forever Instance Timer bundle these libraries, unmodified, in their `Libs` folders. Each library keeps its own license. The license texts ship inside each addon; its `Libs/LICENSES.txt` maps every library to its license file.

| Library | Version | Source | License |
|---|---|---|---|
| AceConfig-3.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, CallbackHandler-1.0 | Ace3 Release-r1403 | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) | BSD-style, Copyright (c) 2007, Ace3 Development Team: `Libs/LICENSE-Ace3.txt` |
| LibStub | as shipped with Ace3 Release-r1403 | [WoWUIDev/Ace3](https://github.com/WoWUIDev/Ace3) | Public domain, as stated in `LibStub.lua` |
| LibSharedMedia-3.0 | v12.1.0 (12000002) | repos.wowace.com/wow/libsharedmedia-3-0 ([project page](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)) | GNU LGPL v2.1, as stated in `LibSharedMedia-3.0.lua`: `Libs/LibSharedMedia-3.0/LICENSE.txt` |
| AceGUI-3.0-SharedMediaWidgets | trunk r65 (data 9004) | repos.wowace.com/wow/ace-gui-3-0-shared-media-widgets ([project page](https://www.curseforge.com/wow/addons/ace-gui-3-0-shared-media-widgets)) | BSD 3-Clause, Copyright (c) 2010, Yssaril: `Libs/AceGUI-3.0-SharedMediaWidgets/LICENSE.txt` |

Forever Addon Fixes bundles no libraries.

**Test-only downloads, not part of this repository:**
- The Tests workflow downloads GearQuestForever and AtlasLoot Classic Forever from CurseForge at test time, because Forever Addon Fixes' smoke tests run against their real code.
- `tools/ci/fetch-test-deps.sh` pins the exact files and checksums.
