-- storefront_menu_blueprint_touch_test.lua
-- Verifies:
-- 1. In-place subview navigation in StorefrontSettingsCard without stacking/multiple overlays
-- 2. Hardware Back / Escape handling in StorefrontSettingsCard subviews
-- 3. Touch responsiveness (ges_events with GestureRange) in all StorefrontBlueprintUI rows
-- 4. Blueprints menu row taps do not fire on_close_callback prematurely

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

local StorefrontSettingsCard = require("storefront_settings_card")
local StorefrontBlueprintUI = require("storefront_blueprint_ui")

print("=== Running Single-Modal Settings & Blueprint Touch Regression Tests ===")

-- 1. Test In-Place Navigation in StorefrontSettingsCard
do
    _G.ui_tracker = { shown = {}, last_shown = nil, closed = {} }
    local close_count = 0
    local dummy_storefront = {
        browser_state = { kind = "plugin" },
        browserRefresh = function() end,
        saveBrowserState = function() end,
        getInstallRecordsMap = function() return {} end,
        getPatchRecordsMap = function() return {} end,
    }

    StorefrontSettingsCard.show(dummy_storefront, function()
        close_count = close_count + 1
    end)

    local overlay = _G.ui_tracker.last_shown
    check("Root settings overlay created", overlay ~= nil)
    check("Initial layout has category rows and close button", #overlay.layout >= 6)

    -- Identify category rows in root
    local catalog_row = overlay.layout[1][1]
    local screensaver_row = overlay.layout[2][1]
    local notif_row = overlay.layout[3][1]
    local blueprints_row = overlay.layout[4][1]
    local about_row = overlay.layout[5][1]
    local close_btn = overlay.layout[6][1]

    check("Root rows have onTap callback", type(catalog_row.onTap) == "function")
    check("Root rows have ges_events.Tap", catalog_row.ges_events and catalog_row.ges_events.Tap ~= nil)
    check("Root close button has callback", type(close_btn.callback) == "function")

    -- Tap Catalog & Search row -> navigate to catalog in-place
    catalog_row.onTap()
    overlay = _G.ui_tracker.last_shown
    check("Clean overlay shown for subview", overlay ~= nil)
    check("Close callback was not called during subview navigation", close_count == 0)

    -- In catalog subview: layout should have 5 setting rows + 1 action buttons row (Back & Close)
    check("Catalog subview layout has rows + action buttons row", #overlay.layout == 6)
    local back_btn = overlay.layout[#overlay.layout][1]
    local close_sub_btn = overlay.layout[#overlay.layout][2]
    check("Catalog has Back button", back_btn.text and back_btn.text:find("Back") ~= nil)
    check("Catalog has Close button", close_sub_btn.text and close_sub_btn.text:find("Close") ~= nil)

    -- Hardware Back key / Escape should return to root, NOT close dialog
    local handled = overlay:onClose()
    check("Hardware Back on subview returns true (consumed)", handled == true)
    check("Hardware Back did not close dialog", close_count == 0)
    overlay = _G.ui_tracker.last_shown
    check("Returned to root view with Close button", overlay.layout[#overlay.layout][1].text and overlay.layout[#overlay.layout][1].text:find("Close") ~= nil)

    -- Tap Notifications row -> navigate to notifications in-place
    overlay.layout[3][1].onTap()
    overlay = _G.ui_tracker.last_shown
    check("In notifications subview", #overlay.layout == 3) -- 2 rows + 1 action buttons row
    local notif_back = overlay.layout[#overlay.layout][1]
    check("Notifications has Back button", notif_back.text and notif_back.text:find("Back") ~= nil)

    -- Tap Back button -> returns to root
    notif_back.callback()
    overlay = _G.ui_tracker.last_shown
    check("Back button returned to root", overlay.layout[#overlay.layout][1].text and overlay.layout[#overlay.layout][1].text:find("Close") ~= nil)
    check("Close callback still not invoked", close_count == 0)

    -- Tap Screensavers row -> navigate to screensavers in-place
    overlay.layout[2][1].onTap()
    overlay = _G.ui_tracker.last_shown
    check("In screensavers subview", #overlay.layout == 3)
    local ss_back = overlay.layout[#overlay.layout][1]
    ss_back.callback()
    overlay = _G.ui_tracker.last_shown
    check("Returned from screensavers to root", overlay.layout[#overlay.layout][1].text and overlay.layout[#overlay.layout][1].text:find("Close") ~= nil)

    -- Now tap Close button in root
    local root_close = overlay.layout[#overlay.layout][1]
    root_close.callback()
    check("Closing root invokes on_close callback", close_count == 1)
end

-- 2. Test Blueprint UI Touch Responsiveness & No-Premature-Close
do
    _G.ui_tracker = { shown = {}, last_shown = nil, closed = {} }
    local close_fired = false
    local dummy_storefront = {
        browser_state = { kind = "plugin" },
        browserRefresh = function() end,
        saveBrowserState = function() end,
        getInstallRecordsMap = function() return {} end,
        getPatchRecordsMap = function() return {} end,
    }

    StorefrontBlueprintUI.showBlueprintsMenu(dummy_storefront, function()
        close_fired = true
    end)

    local bp_overlay = _G.ui_tracker.last_shown
    check("Blueprints menu overlay shown", bp_overlay ~= nil)
    check("Blueprints menu has 4 menu rows + 1 close button", #bp_overlay.layout == 5)

    -- Verify all 4 rows have ges_events, GestureRange, onTap, onTapSelect, isFocusable
    for idx = 1, 4 do
        local row = bp_overlay.layout[idx][1]
        check(string.format("Blueprint menu row %d has ges_events", idx), row.ges_events ~= nil and row.ges_events.Tap ~= nil)
        check(string.format("Blueprint menu row %d has onTap", idx), type(row.onTap) == "function")
        check(string.format("Blueprint menu row %d has onTapSelect", idx), type(row.onTapSelect) == "function")
        check(string.format("Blueprint menu row %d isFocusable", idx), row:isFocusable() == true)
    end

    -- Verify tapping a row does NOT fire close_fired
    -- Row 1 is Export
    bp_overlay.layout[1][1].onTap()
    check("Tapping Export row did NOT fire on_close_callback (no unwanted settings reopen)", close_fired == false)
end

-- 3. Test Export Dialog Touch Responsiveness
do
    _G.ui_tracker = { shown = {}, last_shown = nil, closed = {} }
    local dummy_storefront = {
        browser_state = { kind = "plugin" },
        browserRefresh = function() end,
        saveBrowserState = function() end,
        getInstallRecordsMap = function() return {} end,
        getPatchRecordsMap = function() return {} end,
    }

    StorefrontBlueprintUI.showExportDialog(dummy_storefront)
    local exp_overlay = _G.ui_tracker.last_shown
    check("Export dialog overlay shown", exp_overlay ~= nil)

    -- Check all interactive rows in export dialog have ges_events
    for idx = 1, #exp_overlay.layout - 1 do
        local row = exp_overlay.layout[idx][1]
        check(string.format("Export dialog row %d has ges_events", idx), row.ges_events ~= nil and row.ges_events.Tap ~= nil)
        check(string.format("Export dialog row %d has onTap", idx), type(row.onTap) == "function")
        check(string.format("Export dialog row %d has onTapSelect", idx), type(row.onTapSelect) == "function")
    end
end

-- 4. Test Diff Dialog Touch Responsiveness
do
    _G.ui_tracker = { shown = {}, last_shown = nil, closed = {} }
    local dummy_storefront = {
        browser_state = { kind = "plugin" },
        browserRefresh = function() end,
        saveBrowserState = function() end,
        getInstallRecordsMap = function() return {} end,
        getPatchRecordsMap = function() return {} end,
    }
    local dummy_bp = {
        ["$schema"] = "https://koreader-storefront.pages.dev/blueprint.schema.json",
        generator = "Storefront",
        format_version = 1,
        name = "Test Setup",
        plugins = {
            { id = "test1.koplugin", name = "Test 1" }
        },
        patches = {},
        fonts = {},
    }

    StorefrontBlueprintUI.showDiffDialog(dummy_storefront, dummy_bp)
    local diff_overlay = _G.ui_tracker.last_shown
    check("Diff dialog overlay shown", diff_overlay ~= nil)

    -- In diff dialog, the first item in layout before the bottom button group is the diff item row
    local item_row = diff_overlay.layout[1][1]
    check("Diff item row has ges_events", item_row.ges_events ~= nil and item_row.ges_events.Tap ~= nil)
    check("Diff item row has onTap", type(item_row.onTap) == "function")
    check("Diff item row has onTapSelect", type(item_row.onTapSelect) == "function")

    -- Check pagination controls and key/gesture handlers
    check("Diff dialog has onNextPage", type(diff_overlay.onNextPage) == "function")
    check("Diff dialog has onPrevPage", type(diff_overlay.onPrevPage) == "function")
    check("Diff dialog has onSwipe", type(diff_overlay.onSwipe) == "function")
    check("Diff dialog has NextPage key_event", diff_overlay.key_events and diff_overlay.key_events.NextPage ~= nil)
    check("Diff dialog has PrevPage key_event", diff_overlay.key_events and diff_overlay.key_events.PrevPage ~= nil)

    -- Test multi-item blueprint pagination (10 items => 2 pages with 8 items/page)
    local multi_bp = {
        ["$schema"] = "https://koreader-storefront.pages.dev/blueprint.schema.json",
        generator = "Storefront",
        format_version = 1,
        name = "Multi Item Blueprint",
        plugins = {
            { id = "p1", name = "Plugin 1" },
            { id = "p2", name = "Plugin 2" },
            { id = "p3", name = "Plugin 3" },
            { id = "p4", name = "Plugin 4" },
            { id = "p5", name = "Plugin 5" },
            { id = "p6", name = "Plugin 6" },
            { id = "p7", name = "Plugin 7" },
            { id = "p8", name = "Plugin 8" },
            { id = "p9", name = "Plugin 9" },
            { id = "p10", name = "Plugin 10" },
        },
        patches = {},
        fonts = {},
    }
    StorefrontBlueprintUI.showDiffDialog(dummy_storefront, multi_bp)
    local multi_overlay = _G.ui_tracker.last_shown
    check("Multi-item diff dialog overlay shown", multi_overlay ~= nil)

    -- Layout should contain: 8 item rows + 1 pagination buttons row + 1 action buttons row = 10 rows
    check("Multi-item diff has 10 layout rows", #multi_overlay.layout == 10)
    local pag_row = multi_overlay.layout[9]
    check("Pagination row has 2 buttons (prev, next)", #pag_row == 2)
    local prev_btn, next_btn = pag_row[1], pag_row[2]
    check("Prev button text is '‹'", prev_btn and prev_btn.args and prev_btn.args.text == "‹")
    check("Next button text is '›'", next_btn and next_btn.args and next_btn.args.text == "›")

    -- Test interactive checkbox toggling
    local row1 = multi_overlay.layout[1][1]
    check("Row 1 exists and has onTap", type(row1.onTap) == "function")
    local item1 = row1.item
    check("Row 1 has item reference", item1 ~= nil)
    local orig_sel = item1.selected
    row1.onTap()
    check("Tapping checkbox toggles selected state", item1.selected == not orig_sel)
    row1 = multi_overlay.layout[1][1]
    row1.onTap()
    check("Tapping checkbox again restores selected state", item1.selected == orig_sel)

    -- Test page flipping
    local next_result = multi_overlay.onNextPage()
    check("onNextPage succeeds", next_result == true)
    check("Page 2 has 4 layout rows (2 items + pagination + actions)", #multi_overlay.layout == 4)
    local prev_result = multi_overlay.onPrevPage()
    check("onPrevPage succeeds", prev_result == true)
    check("Back on Page 1 has 10 layout rows", #multi_overlay.layout == 10)

    -- Test swipe gesture pagination
    local swipe_west = multi_overlay:onSwipe({ direction = "west" })
    check("onSwipe west (next) succeeds", swipe_west == true)
    local swipe_east = multi_overlay:onSwipe({ direction = "east" })
    check("onSwipe east (prev) succeeds", swipe_east == true)
end

print(string.format("=== Single-Modal Settings & Blueprint Touch Tests Complete: %d Failures ===", failures))
if failures > 0 then
    os.exit(1)
end
