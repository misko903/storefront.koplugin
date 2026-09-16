-- storefront_blueprint_test.lua
-- Unit tests for Storefront Blueprint Manager, Cloud Sync, and Diff Engine.

require("tests/spec_helper")

package.path = "plugins/storefront.koplugin/?.lua;storefront.koplugin/?.lua;/mnt/c/Users/jpautz/Documents/storefront/storefront.koplugin/storefront.koplugin/?.lua;/mnt/c/Users/jpautz/Documents/storefront/storefront.koplugin/?.lua;?.lua;" .. package.path

local failures = 0
local function check(label, condition)
    if condition then
        print("PASS\t" .. label)
    else
        failures = failures + 1
        print("FAIL\t" .. label)
    end
    io.stdout:flush()
end

local BlueprintMgr = require("storefront_blueprint_mgr")
local BlueprintCloud = require("storefront_blueprint_cloud")
local InstallStore = require("storefront_installs")

print("=== Running Storefront Blueprint Automated Test Suite ===")

-- 1. Blueprint Generation with 'latest' Strategy
do
    -- Mock install store data
    InstallStore.save({
        ["readimer.koplugin"] = {
            owner = "uroybd",
            repo = "readimer.koplugin",
            version = "1.2.0",
            installed_version = "1.2.0",
            installed_tag = "v1.2.0",
            sha = "abc1234",
            source = "release",
        },
        ["covermenu.koplugin"] = {
            owner = "author",
            repo = "covermenu.koplugin",
            version = "0.9.0",
            installed_tag = "v0.9.0",
            sha = "def5678",
            source = "release",
        }
    })
    InstallStore.savePatches({
        ["1-margins.lua"] = {
            name = "Custom Margins",
            owner = "koreader",
            repo = "koreader-patches",
            version = "1.0",
            sha = "patchsha123",
        }
    })
    InstallStore.saveFonts({
        ["literata"] = {
            name = "Literata",
            family = "Literata",
            source = "google-fonts",
        }
    })

    local bp = BlueprintMgr.generateBlueprint{
        name = "My Test Setup",
        author = "TestAuthor",
        version_strategy = "latest",
    }

    check("Blueprint has schema URL", bp["$schema"] == BlueprintMgr.SCHEMA_URL)
    check("Blueprint has generator 'Storefront'", bp.generator == "Storefront")
    check("Blueprint has format_version >= 1", bp.format_version and bp.format_version >= 1)
    check("Blueprint has assigned name", bp.name == "My Test Setup")
    check("Blueprint has assigned author", bp.author == "TestAuthor")
    check("Blueprint version_strategy is latest", bp.version_strategy == "latest")
    check("Blueprint contains 2 plugins", #bp.plugins == 2)
    check("Plugins sorted alphabetically", bp.plugins[1].id == "covermenu.koplugin" and bp.plugins[2].id == "readimer.koplugin")
    check("Plugin version defaults to latest", bp.plugins[1].version == "latest")
    check("Plugin pinned_tag is preserved as reference", bp.plugins[2].pinned_tag == "v1.2.0")
    check("Blueprint contains 1 patch", #bp.patches == 1 and bp.patches[1].filename == "1-margins.lua")
    check("Blueprint contains 1 font", #bp.fonts == 1 and bp.fonts[1].name == "Literata")
end

-- 2. Blueprint Generation with 'pinned' Strategy
do
    local bp_pinned = BlueprintMgr.generateBlueprint{
        name = "Pinned Setup",
        version_strategy = "pinned",
    }

    check("Pinned blueprint version_strategy is pinned", bp_pinned.version_strategy == "pinned")
    check("Plugin has exact pinned version", bp_pinned.plugins[2].version == "1.2.0")
    check("Plugin has pinned_sha", bp_pinned.plugins[2].pinned_sha == "abc1234")
    check("Patch has pinned_sha", bp_pinned.patches[1].pinned_sha == "patchsha123")
end

-- 3. Validation & Schema Enforcement
do
    local valid_bp = {
        ["$schema"] = BlueprintMgr.SCHEMA_URL,
        generator = "Storefront",
        format_version = 1,
        name = "Valid Setup",
    }
    local ok_v, err_v = BlueprintMgr.validateBlueprint(valid_bp)
    check("validateBlueprint accepts valid payload", ok_v == true and err_v == nil)

    local ok_bad_gen = BlueprintMgr.validateBlueprint({
        generator = "OtherTool",
        format_version = 1,
        name = "Bad Generator",
    })
    check("validateBlueprint rejects invalid generator", ok_bad_gen == false)

    local ok_bad_ver = BlueprintMgr.validateBlueprint({
        generator = "Storefront",
        format_version = 0,
        name = "Bad Version",
    })
    check("validateBlueprint rejects format_version < 1", ok_bad_ver == false)

    local ok_no_name = BlueprintMgr.validateBlueprint({
        generator = "Storefront",
        format_version = 1,
    })
    check("validateBlueprint rejects missing name", ok_no_name == false)

    -- JSON Parser robustness
    local ok_p, parsed = BlueprintMgr.parseBlueprint('{"$schema":"test","generator":"Storefront","format_version":1,"name":"Parsed"}')
    check("parseBlueprint parses and validates valid JSON", ok_p == true and parsed.name == "Parsed")

    local ok_malformed, _ = BlueprintMgr.parseBlueprint('{malformed json}')
    check("parseBlueprint rejects malformed JSON cleanly", ok_malformed == false)
end

-- 4. Diff Calculation Engine
do
    -- Blueprint has 3 plugins:
    -- 1) readimer.koplugin (installed, same tag -> installed)
    -- 2) covermenu.koplugin (installed, but blueprint wants pinned v2.0.0 -> update)
    -- 3) newplugin.koplugin (not installed -> missing)
    local test_bp = {
        name = "Diff Test Setup",
        generator = "Storefront",
        format_version = 1,
        plugins = {
            {
                id = "readimer.koplugin",
                name = "Readimer",
                repo = "uroybd/readimer.koplugin",
                version = "latest",
                pinned_tag = "v1.2.0",
            },
            {
                id = "covermenu.koplugin",
                name = "CoverMenu",
                repo = "author/covermenu.koplugin",
                version = "2.0.0",
                pinned_tag = "v2.0.0",
            },
            {
                id = "newplugin.koplugin",
                name = "New Plugin",
                repo = "someone/newplugin.koplugin",
                version = "latest",
            },
        },
        patches = {
            {
                filename = "1-margins.lua",
                name = "Custom Margins",
                repo = "koreader/koreader-patches",
                version = "latest",
            },
            {
                filename = "2-battery.lua",
                name = "Battery Tweak",
                repo = "koreader/koreader-patches",
                version = "latest",
            },
        },
        fonts = {
            { name = "Literata", family = "Literata" },
            { name = "Bitter", family = "Bitter" },
        },
        screensavers = {},
    }

    local diff = BlueprintMgr.diffBlueprint(test_bp)

    check("Diff summary counts total correctly (7 items)", diff.summary.total == 7)
    check("Diff detected 1 installed plugin (readimer)", diff.plugins[1].status == "installed" and diff.plugins[1].selected == false)
    check("Diff detected 1 plugin update (covermenu v2.0.0 vs v0.9.0)", diff.plugins[2].status == "update" and diff.plugins[2].selected == true)
    check("Diff detected 1 missing plugin (newplugin)", diff.plugins[3].status == "missing" and diff.plugins[3].selected == true)
    check("Diff detected 1 installed patch (1-margins)", diff.patches[1].status == "installed" and diff.patches[1].selected == false)
    check("Diff detected 1 missing patch (2-battery)", diff.patches[2].status == "missing" and diff.patches[2].selected == true)
    check("Diff detected 1 installed font (Literata)", diff.fonts[1].status == "installed" and diff.fonts[1].selected == false)
    check("Diff detected 1 missing font (Bitter)", diff.fonts[2].status == "missing" and diff.fonts[2].selected == true)
    check("Diff summary missing count is 3 (1 plugin, 1 patch, 1 font)", diff.summary.missing == 3)
    check("Diff summary updates count is 1", diff.summary.updates == 1)
    check("Diff summary installed count is 3", diff.summary.installed == 3)
end

-- 5. Cloud Shortcode Normalization
do
    check("normalizeCode handles standard 6-char code", BlueprintCloud.normalizeCode("A8K2M9") == "A8K2M9")
    check("normalizeCode strips lowercase and spaces", BlueprintCloud.normalizeCode("  a8k 2m9  ") == "A8K2M9")
    check("normalizeCode strips # and dashes", BlueprintCloud.normalizeCode("#A8K-2M9") == "A8K2M9")
    check("normalizeCode strips SF- prefix", BlueprintCloud.normalizeCode("SF-A8K2M9") == "A8K2M9")
    check("normalizeCode handles nil/empty", BlueprintCloud.normalizeCode(nil) == "")
end

-- 6. Disk-Aware Blueprint Generation and Diff (Excluding Uninstalled/Orphan Records)
do
    -- Mock Storefront instance with only 'readimer.koplugin' actually present on disk
    local mock_sf = {
        listInstalledPlugins = function(self)
            return {
                {
                    dirname = "readimer.koplugin",
                    name = "Readimer",
                    shortname = "readimer",
                    version = "1.2.0",
                },
                {
                    dirname = "autowarmth.koplugin",
                    name = "Auto Warmth",
                    shortname = "autowarmth",
                    root = "plugins",
                },
                {
                    dirname = "statistics.koplugin",
                    name = "Reading statistics",
                    shortname = "statistics",
                    root = "plugins",
                },
                {
                    dirname = "coverbrowser.koplugin",
                    name = "Cover Browser",
                    shortname = "coverbrowser",
                    root = "plugins",
                },
                {
                    dirname = "terminal.koplugin",
                    name = "Terminal",
                    shortname = "terminal",
                    root = "plugins",
                },
            }
        end,
        listInstalledPatches = function(self)
            return {
                { filename = "1-margins.lua" },
            }
        end,
        listInstalledFonts = function(self)
            return {
                { name = "Literata" },
            }
        end,
    }

    -- InstallStore has 'readimer.koplugin', 'covermenu.koplugin' (orphan/uninstalled), and 'Neo_Quick_Settings.koplugin' (orphan/uninstalled)
    InstallStore.save({
        ["readimer.koplugin"] = {
            owner = "uroybd",
            repo = "readimer.koplugin",
            version = "1.2.0",
            source = "release",
        },
        ["covermenu.koplugin"] = {
            owner = "author",
            repo = "covermenu.koplugin",
            version = "0.9.0",
            source = "release",
        },
        ["Neo_Quick_Settings.koplugin"] = {
            owner = "someone",
            repo = "Neo_Quick_Settings.koplugin",
            version = "1.0.0",
            source = "release",
        },
    })

    local live_bp = BlueprintMgr.generateBlueprint{
        name = "Live Disk Setup",
        version_strategy = "latest",
        include_plugins = true,
        include_patches = true,
        include_fonts = true,
        include_screensavers = false,
        include_settings = false,
        Storefront = mock_sf,
    }

    -- Only 'readimer.koplugin' should be in the blueprint!
    -- 'covermenu.koplugin' and 'Neo_Quick_Settings.koplugin' (uninstalled) must be excluded.
    -- All 4 core default plugins (autowarmth, statistics, coverbrowser, terminal) must be excluded.
    check("Live blueprint contains exactly 1 plugin", #live_bp.plugins == 1)
    check("Live blueprint only contains installed non-default plugin (readimer)", live_bp.plugins[1] and live_bp.plugins[1].id == "readimer.koplugin")

    -- Test diff with mock Storefront:
    -- 'Neo_Quick_Settings.koplugin' in a blueprint must be identified as 'missing', NOT 'installed'!
    -- Core plugins like 'autowarmth.koplugin' in imported blueprints must be ignored in diff review!
    local bp_with_uninstalled = {
        name = "Test Uninstalled & Core",
        generator = "Storefront",
        format_version = 1,
        plugins = {
            { id = "readimer.koplugin", name = "Readimer", repo = "uroybd/readimer.koplugin", version = "latest" },
            { id = "Neo_Quick_Settings.koplugin", name = "Neo Quick Settings", repo = "someone/Neo_Quick_Settings.koplugin", version = "latest" },
            { id = "autowarmth.koplugin", name = "Auto night mode", version = "latest" }, -- Core plugin without repo
            { id = "statistics.koplugin", name = "Reading statistics", repo = "koreader/koreader", version = "latest" }, -- Core plugin with dummy repo
        },
        patches = {},
        fonts = {},
    }

    local live_diff = BlueprintMgr.diffBlueprint(bp_with_uninstalled, mock_sf)
    check("Live diff ignored core plugins (only 2 valid plugins)", #live_diff.plugins == 2)
    check("Live diff found 1 installed plugin (readimer)", live_diff.plugins[1].status == "installed")
    check("Live diff found Neo_Quick_Settings is MISSING (not installed)", live_diff.plugins[2].status == "missing")
    check("Live diff selected Neo_Quick_Settings for install", live_diff.plugins[2].selected == true)
    check("Live diff summary: 1 missing, 1 installed", live_diff.summary.missing == 1 and live_diff.summary.installed == 1)
end

print(string.format("=== Blueprint Automated Tests Complete: %d Failures ===", failures))
if failures > 0 then
    os.exit(1)
end
