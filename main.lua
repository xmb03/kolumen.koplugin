--[[
    KOlumen — Real-time Brightness Plugin for KOReader
    Allows adjusting brightness continuously in real time by dragging vertically in the center of the screen on phones.
    - Two adjustment modes:
        * Adaptive (relative): initial touch point equals current brightness. Smooth delta adjustment,
          no sudden brightness jumps when touching the screen.
        * Fixed (absolute): position on screen maps strictly (bottom = 0%, middle = 50%, top = 100%).
    - Excludes margins from the top and bottom of the screen (default 15%) for gesture initiation.
    - Real-time continuous tracking: updates dynamically as finger moves (no lift needed).
    - All integer percentage values from 0% to 100% are smoothly reachable.
    - Top-centered OSD badge:
        * Registered as toast = true (NEVER blocks event propagation to ReaderUI).
        * Non-modal, zero-delay gesture passthrough.
        * Swiping is always available at any time without any blocking timeout.
        * Smooth updates in place: "Brightness: 58%".
        * Theme-adaptive (Dark mode / Light mode).
        * Dismisses after inactivity timeout or immediately on page turn / tap.
--]]

local Device = require("device")

-- Safety guard: only enable on devices with touchscreen and adjustable frontlight
if not Device:isTouchDevice() or not Device:hasFrontlight() then
    return { disabled = true }
end

local Screen = Device.screen
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local RectSpan = require("ui/widget/rectspan")
local TextWidget = require("ui/widget/textwidget")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local logger = require("logger")
local has_i18n, i18n = pcall(require, "i18n")
local _ = (has_i18n and i18n) or require("gettext")

local has_datastorage, DataStorage = pcall(require, "datastorage")
local has_luasettings, LuaSettings = pcall(require, "luasettings")

-- Constants
local GESTURE_DIRECTION_RATIO = 1.2
local DRAG_LOCK_THRESHOLD_DP = 6
local BADGE_WIDTH_DP = 190
local BADGE_HEIGHT_DP = 38
local BADGE_TOP_MARGIN_DP = 28
local BADGE_RADIUS_DP = 10
local BADGE_FONT_SIZE = 18

local function logInfo(...)
    if logger and logger.info then
        logger.info("KOlumen:", ...)
    end
end

local function logDbg(...)
    if logger and logger.dbg then
        logger.dbg("KOlumen:", ...)
    end
end

--------------------------------------------------------------------------------
-- Custom Top-Centered Theme-Adaptive OSD Widget
-- Has toast = true so UIManager treats it as an overlay toast that NEVER blocks
-- subsequent gestures or touches from reaching ReaderUI.
--------------------------------------------------------------------------------
local BrightnessOSD = InputContainer:extend{
    name = "BrightnessOSD",
    toast = true, -- Crucial: treated as toast by UIManager, never stops event propagation!
    percent = 50,
    plugin = nil,
    text_widget = nil,
    frame = nil,
    _is_night = nil,
}

function BrightnessOSD:init()
    logDbg("BrightnessOSD:init called, percent =", self.percent)
    local is_night = Screen.night_mode or (G_reader_settings and G_reader_settings:isTrue("night_mode"))
    self._is_night = is_night

    local fgcolor = is_night and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local bgcolor = is_night and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local border_color = is_night and Blitbuffer.COLOR_GRAY_5 or Blitbuffer.COLOR_DARK_GRAY

    local bordersize = Screen:scaleBySize(1.5)
    local badge_w = Screen:scaleBySize(BADGE_WIDTH_DP)
    local badge_h = Screen:scaleBySize(BADGE_HEIGHT_DP)
    local inner_w = badge_w - bordersize * 2
    local inner_h = badge_h - bordersize * 2

    local format_str = _("Brightness: %d%%")
    self.text_widget = TextWidget:new{
        text = string.format(format_str, self.percent or 50),
        face = Font:getFace("cfont", BADGE_FONT_SIZE),
        fgcolor = fgcolor,
    }

    self.frame = FrameContainer:new{
        width = badge_w,
        height = badge_h,
        background = bgcolor,
        color = border_color,
        bordersize = bordersize,
        radius = Screen:scaleBySize(BADGE_RADIUS_DP),
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            self.text_widget,
        },
    }

    local screen_w = Screen:getWidth()
    local top_margin = Screen:scaleBySize(BADGE_TOP_MARGIN_DP)

    self[1] = VerticalGroup:new{
        align = "center",
        RectSpan:new{
            width = screen_w,
            height = top_margin,
        },
        self.frame,
    }

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = screen_w,
        h = top_margin + badge_h + Screen:scaleBySize(4),
    }
end

-- Allow all key events and touches to pass straight through
function BrightnessOSD:onKeyPress(key)
    if self.plugin and self.plugin._tracking_active ~= true then
        self.plugin:hideOSD()
    end
    return false
end

function BrightnessOSD:onKeyRepeat()
    return false
end

function BrightnessOSD:onGesture(ev)
    if self.plugin and self.plugin._tracking_active ~= true then
        -- Dismiss OSD early if user taps or turns page horizontally
        if ev and (ev.ges == "tap" or ev.ges == "double_tap" or
                   (ev.ges == "swipe" and (ev.direction == "west" or ev.direction == "east"))) then
            self.plugin:hideOSD()
        end
    end
    return false
end

function BrightnessOSD:onCloseWidget()
    if self.plugin and self.plugin.osd_widget == self then
        self.plugin.osd_widget = nil
    end
end

function BrightnessOSD:paintTo(bb, x, y)
    InputContainer.paintTo(self, bb, x, y)
end

function BrightnessOSD:updatePercent(percent)
    local is_night = Screen.night_mode or (G_reader_settings and G_reader_settings:isTrue("night_mode"))
    if self._is_night ~= is_night then
        self._is_night = is_night
        self.text_widget.fgcolor = is_night and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        self.frame.background = is_night and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        self.frame.color = is_night and Blitbuffer.COLOR_GRAY_5 or Blitbuffer.COLOR_DARK_GRAY
    end

    if self.percent == percent then return end
    self.percent = percent

    local format_str = _("Brightness: %d%%")
    self.text_widget:setText(string.format(format_str, percent))

    -- CRITICAL FIX: "all" marks the underlying ReaderUI dirty so that it redraws
    -- the book page background underneath before our badge paints.
    -- Without "all", KOReader only paints BrightnessOSD onto existing Screen.bb pixels,
    -- causing old digits/borders to layer and smear on top of each other!
    UIManager:setDirty("all", function()
        return "ui", self.dimen
    end)
end

--------------------------------------------------------------------------------
-- Plugin Controller
--------------------------------------------------------------------------------
local KOlumen = WidgetContainer:extend{
    name = "kolumen",
    is_doc_only = false,

    -- Configuration
    enabled = true,
    mode = "adaptive",            -- "adaptive" (relative) or "fixed" (absolute)
    vertical_margin = 0.15,       -- 15% margin from top and bottom
    horizontal_zone_ratio = 0.50, -- 50% screen width in the center
    show_osd = true,              -- show real-time on-screen badge
    osd_timeout = 1.5,            -- badge display timeout in seconds (never blocks swiping)

    -- Runtime gesture tracking state
    _current_pct = nil,
    _tracking_active = nil,       -- true = brightness drag, false = ignored/horizontal, nil = undecided
    _last_start_x = nil,
    _last_start_y = nil,
    _adaptive_start_pct = nil,    -- starting brightness for adaptive mode
    _adaptive_anchor_y = nil,     -- anchor Y coordinate for adaptive mode
    osd_widget = nil,
    _hide_osd_func = nil,
}

function KOlumen:init()
    logInfo("Initializing KOlumen real-time continuous plugin...")
    self:loadSettings()
    self:registerZones()

    if self.ui then
        if self.ui.registerPostReaderReadyCallback then
            self.ui:registerPostReaderReadyCallback(function()
                logInfo("postReaderReadyCallback: registering zones AFTER ReaderReady")
                self:registerZones()
            end)
        end
        if self.ui.menu and self.ui.menu.registerToMainMenu then
            self.ui.menu:registerToMainMenu(self)
        end
    end

    UIManager:nextTick(function()
        self:registerZones()
    end)

    logInfo("KOlumen initialized successfully.")
end

function KOlumen:onReaderReady()
    logInfo("onReaderReady: scheduling post-ready zone registration")
    UIManager:nextTick(function()
        logInfo("nextTick from onReaderReady: re-registering zones")
        self:registerZones()
    end)
end

function KOlumen:loadSettings()
    if has_datastorage and has_luasettings and DataStorage.getSettingsDir then
        local settings_dir = DataStorage:getSettingsDir()
        if settings_dir then
            local file_path = settings_dir .. "/kolumen.lua"
            local ok, s = pcall(LuaSettings.open, LuaSettings, file_path)
            if ok and s then
                self.settings_storage = s
                self.enabled = s:readSetting("enabled", self.enabled)
                self.mode = s:readSetting("mode", self.mode)
                self.vertical_margin = s:readSetting("vertical_margin", self.vertical_margin)
                self.horizontal_zone_ratio = s:readSetting("horizontal_zone_ratio", self.horizontal_zone_ratio)
                self.show_osd = s:readSetting("show_osd", self.show_osd)
                self.osd_timeout = s:readSetting("osd_timeout", self.osd_timeout)
                return
            end
        end
    end

    if G_reader_settings and G_reader_settings.readSetting then
        self.enabled = G_reader_settings:readSetting("kolumen_enabled", self.enabled)
        self.mode = G_reader_settings:readSetting("kolumen_mode", self.mode)
        self.vertical_margin = G_reader_settings:readSetting("kolumen_vertical_margin", self.vertical_margin)
        self.horizontal_zone_ratio = G_reader_settings:readSetting("kolumen_h_ratio", self.horizontal_zone_ratio)
        self.show_osd = G_reader_settings:readSetting("kolumen_show_osd", self.show_osd)
        self.osd_timeout = G_reader_settings:readSetting("kolumen_osd_timeout", self.osd_timeout)
    end
end

function KOlumen:saveSetting(key, val)
    if self.settings_storage then
        self.settings_storage:saveSetting(key, val)
        self.settings_storage:flush()
    elseif G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting("kolumen_" .. key, val)
        if G_reader_settings.flush then
            G_reader_settings.flush()
        end
    end
end

-- Register KOReader native TouchZones with priority overrides
function KOlumen:registerZones()
    if not self.ui or not self.ui.registerTouchZones then
        logInfo("ui:registerTouchZones not available on current UI")
        return
    end

    -- Fullscreen screen_zone so that GestureRange:match() never drops active tracking
    -- when the user drags their finger or drifts horizontally during the swipe.
    -- Strict zone initiation (horizontal center & vertical margins) is enforced in onPanMove!
    local zone_fullscreen = {
        ratio_x = 0.0,
        ratio_y = 0.0,
        ratio_w = 1.0,
        ratio_h = 1.0,
    }

    local overrides_vertical_edge = {
        "readerconfigmenu_ext_swipe",
        "readerconfigmenu_swipe",
        "readermenu_ext_swipe",
        "readermenu_swipe",
        "paging_swipe",
        "rolling_swipe",
        "filemanager_ext_swipe",
        "filemanager_swipe",
    }
    local overrides_pan = {
        "paging_pan",
        "paging_swipe",
        "rolling_pan",
        "rolling_swipe",
    }
    local overrides_pan_release = {
        "paging_pan_release",
        "rolling_pan_release",
    }

    self.ui:registerTouchZones({
        -- 1. Pan handler: continuous real-time finger tracking while dragging
        {
            id = "kolumen_swipe_pan",
            ges = "pan",
            screen_zone = zone_fullscreen,
            overrides = overrides_pan,
            handler = function(ges)
                return self:onPanMove(ges)
            end,
        },
        -- 2. Pan release: finalize brightness when finger is lifted
        {
            id = "kolumen_swipe_pan_release",
            ges = "pan_release",
            screen_zone = zone_fullscreen,
            overrides = overrides_pan_release,
            handler = function(ges)
                return self:onPanRelease(ges)
            end,
        },
        -- 3. Swipe handler: catch quick flick releases and standalone vertical swipes
        {
            id = "kolumen_swipe",
            ges = "swipe",
            screen_zone = zone_fullscreen,
            overrides = overrides_vertical_edge,
            handler = function(ges)
                return self:onPanRelease(ges)
            end,
        },
    })
    logInfo("KOlumen touch zones registered successfully.")
end

-- Calculate active screen vertical range and boundaries
function KOlumen:getActiveRangeH()
    local screen_h = Screen:getHeight()
    local v_margin = self.vertical_margin or 0.15
    local top_limit = screen_h * v_margin
    local bottom_limit = screen_h * (1.0 - v_margin)
    local range_h = bottom_limit - top_limit
    if range_h <= 0 then range_h = 1 end
    return range_h, top_limit, bottom_limit
end

-- Query current hardware brightness as a 0-100 percentage
function KOlumen:getCurrentPercent()
    local powerd = Device:getPowerDevice()
    if not powerd then
        return self._current_pct or 50
    end
    local cur_intensity = powerd:frontlightIntensity()
    if not cur_intensity then
        cur_intensity = powerd.fl_intensity or (powerd.frontlightIntensityHW and powerd:frontlightIntensityHW()) or 50
    end
    local min_val = powerd.fl_min or 0
    local max_val = powerd.fl_max or 100
    local range = max_val - min_val
    if range <= 0 then
        return 50
    end
    local pct = math.floor(((cur_intensity - min_val) / range) * 100.0 + 0.5)
    return math.max(0, math.min(100, pct))
end

-- Fixed mode: absolute screen position
-- Bottom of active zone (Y >= bottom_limit) = 0%
-- Center of active zone = 50%
-- Top of active zone (Y <= top_limit) = 100%
function KOlumen:yToPercent(y)
    local range_h, _, bottom_limit = self:getActiveRangeH()
    local ratio = (bottom_limit - y) / range_h
    ratio = math.max(0.0, math.min(1.0, ratio))
    return math.floor(ratio * 100.0 + 0.5)
end

-- Adaptive mode: relative adjustment from touch point
-- Dynamic anti-deadzone re-anchoring: if brightness hits 0% or 100% and user keeps dragging,
-- the anchor point is shifted so reversing direction responds immediately.
function KOlumen:computeAdaptivePercent(cur_y)
    local range_h = self:getActiveRangeH()
    local start_pct = self._adaptive_start_pct or self:getCurrentPercent()
    local anchor_y = self._adaptive_anchor_y or cur_y
    local delta_y = anchor_y - cur_y
    local delta_pct = (delta_y / range_h) * 100.0
    local raw_pct = start_pct + delta_pct

    if raw_pct > 100.0 then
        self._adaptive_start_pct = 100
        self._adaptive_anchor_y = cur_y
        return 100
    elseif raw_pct < 0.0 then
        self._adaptive_start_pct = 0
        self._adaptive_anchor_y = cur_y
        return 0
    else
        return math.floor(raw_pct + 0.5)
    end
end

-- Real-time handler called on EVERY movement of finger
function KOlumen:onPanMove(ges)
    if not self.enabled then return false end
    if not ges then return false end

    -- Extract current finger position
    local cur_x = ges.pos and ges.pos.x or ges.x
    local cur_y = ges.pos and ges.pos.y or ges.y
    if not cur_y then return false end

    -- Determine gesture start position
    local start_x
    if ges.start_pos and ges.start_pos.x then
        start_x = ges.start_pos.x
    elseif ges.relative and ges.relative.x and cur_x then
        start_x = cur_x - ges.relative.x
    else
        start_x = cur_x
    end

    local start_y
    if ges.start_pos and ges.start_pos.y then
        start_y = ges.start_pos.y
    elseif ges.relative and ges.relative.y then
        start_y = cur_y - ges.relative.y
    else
        start_y = cur_y
    end

    -- If a new gesture started (start coordinates changed), reset tracking state cleanly
    if self._last_start_x ~= start_x or self._last_start_y ~= start_y then
        self._last_start_x = start_x
        self._last_start_y = start_y
        self._tracking_active = nil
        self._adaptive_start_pct = nil
        self._adaptive_anchor_y = nil
    end

    local screen_w = Screen:getWidth()
    local _, top_limit, bottom_limit = self:getActiveRangeH()

    local h_ratio = self.horizontal_zone_ratio or 0.50
    local h_margin = (1.0 - h_ratio) / 2.0
    local left_limit = screen_w * h_margin
    local right_limit = screen_w * (1.0 - h_margin)

    -- 1. Gesture initiation boundary check:
    -- If gesture started outside center horizontal zone or in top/bottom margins, do NOT initiate brightness adjustment!
    if self._tracking_active == nil then
        if start_x and (start_x < left_limit or start_x > right_limit) then
            self._tracking_active = false
            return false
        end
        if start_y and (start_y < top_limit or start_y > bottom_limit) then
            self._tracking_active = false
            return false
        end

        -- Check horizontal vs vertical intent
        if ges.relative then
            local dx = math.abs(ges.relative.x or 0)
            local dy = math.abs(ges.relative.y or 0)
            local threshold = Screen:scaleBySize(DRAG_LOCK_THRESHOLD_DP)
            if dx > threshold or dy > threshold then
                if dx > dy * GESTURE_DIRECTION_RATIO then
                    -- Horizontal swipe: let page turning take over
                    self._tracking_active = false
                    return false
                else
                    self._tracking_active = true
                    self._adaptive_start_pct = self:getCurrentPercent()
                    self._adaptive_anchor_y = start_y or cur_y
                end
            else
                -- Small movement: wait for clearer direction before locking in
                return false
            end
        else
            self._tracking_active = true
            self._adaptive_start_pct = self:getCurrentPercent()
            self._adaptive_anchor_y = start_y or cur_y
        end
    end

    if self._tracking_active ~= true then
        return false
    end

    -- Real-time continuous tracking: update brightness and OSD dynamically
    local percent
    if self.mode == "fixed" then
        percent = self:yToPercent(cur_y)
    else
        if not self._adaptive_start_pct then
            self._adaptive_start_pct = self:getCurrentPercent()
            self._adaptive_anchor_y = start_y or cur_y
        end
        percent = self:computeAdaptivePercent(cur_y)
    end
    self:applyBrightness(percent, false)
    return true
end

function KOlumen:onPanRelease(ges)
    if not self.enabled then return false end
    local was_active = self._tracking_active
    local adaptive_anchor_y = self._adaptive_anchor_y
    local adaptive_start_pct = self._adaptive_start_pct

    self._tracking_active = nil
    self._last_start_x = nil
    self._last_start_y = nil
    self._adaptive_start_pct = nil
    self._adaptive_anchor_y = nil

    if was_active ~= true then
        -- Check if this was a standalone fast vertical swipe in the center
        if was_active == nil and ges and ges.ges == "swipe" then
            local screen_w = Screen:getWidth()
            local range_h, top_limit, bottom_limit = self:getActiveRangeH()
            local h_ratio = self.horizontal_zone_ratio or 0.50
            local h_margin = (1.0 - h_ratio) / 2.0
            local left_limit = screen_w * h_margin
            local right_limit = screen_w * (1.0 - h_margin)

            local start_x = ges.pos and ges.pos.x
            local start_y = ges.pos and ges.pos.y
            if start_x and start_y and
               start_x >= left_limit and start_x <= right_limit and
               start_y >= top_limit and start_y <= bottom_limit and
               (ges.direction == "north" or ges.direction == "south") then
                local end_y = ges.end_pos and ges.end_pos.y or start_y
                local percent
                if self.mode == "fixed" then
                    percent = self:yToPercent(end_y)
                else
                    local cur_pct = self:getCurrentPercent()
                    local delta_y = start_y - end_y
                    local delta_pct = (delta_y / range_h) * 100.0
                    percent = math.floor(cur_pct + delta_pct + 0.5)
                    percent = math.max(0, math.min(100, percent))
                end
                self:applyBrightness(percent, true)
                return true
            end
        end
        return false
    end

    -- Extract final release position (swipe uses end_pos, pan_release uses pos)
    local cur_y = ges and ((ges.ges == "swipe" and ges.end_pos and ges.end_pos.y) or (ges.pos and ges.pos.y) or ges.y)
    if cur_y then
        local percent
        if self.mode == "fixed" then
            percent = self:yToPercent(cur_y)
        else
            self._adaptive_anchor_y = adaptive_anchor_y
            self._adaptive_start_pct = adaptive_start_pct
            percent = self:computeAdaptivePercent(cur_y)
            self._adaptive_anchor_y = nil
            self._adaptive_start_pct = nil
        end
        self:applyBrightness(percent, true)
    elseif self._current_pct then
        self:applyBrightness(self._current_pct, true)
    end
    return true
end

-- Apply brightness to hardware and update OSD
function KOlumen:applyBrightness(percent, is_final)
    if not is_final and self._current_pct == percent then
        return
    end
    self._current_pct = percent

    local powerd = Device:getPowerDevice()
    if powerd then
        local min_val = powerd.fl_min or 0
        local max_val = powerd.fl_max or 100
        local range = max_val - min_val
        if range <= 0 then range = 1 end

        local new_val = math.floor(min_val + (percent / 100.0) * range + 0.5)
        new_val = math.max(min_val, math.min(max_val, new_val))

        if is_final then
            logInfo(string.format("Final brightness: %d%% (hardware val=%d)", percent, new_val))
        else
            logDbg(string.format("Realtime brightness: %d%% (hardware val=%d)", percent, new_val))
        end

        powerd:setIntensity(new_val)
        if is_final and powerd.updateResumeFrontlightState then
            powerd:updateResumeFrontlightState()
        end
    end

    if self.show_osd then
        self:showOSD(percent)
    end
end

-- Top-centered OSD badge: updates smoothly in-place and disappears after inactivity
-- Never blocks swiping; gestures can be initiated at any moment without delay.
function KOlumen:showOSD(percent)
    if not self.show_osd then return end

    -- Verify that the widget is actually still active in KOReader's window stack
    if self.osd_widget and not UIManager:isWidgetShown(self.osd_widget) then
        self.osd_widget = nil
    end

    if not self.osd_widget then
        self.osd_widget = BrightnessOSD:new{ percent = percent, plugin = self }
        UIManager:show(self.osd_widget, "ui", self.osd_widget.dimen)
    else
        self.osd_widget:updatePercent(percent)
    end
    UIManager:forceRePaint()

    -- Reset inactivity timer: disappears after timeout, but NEVER blocks swiping
    if self._hide_osd_func then
        UIManager:unschedule(self._hide_osd_func)
    end
    local timeout = self.osd_timeout or 1.5
    self._hide_osd_func = function()
        self._hide_osd_func = nil
        self:hideOSD()
    end
    UIManager:scheduleIn(timeout, self._hide_osd_func)
end

function KOlumen:hideOSD()
    if self._hide_osd_func then
        UIManager:unschedule(self._hide_osd_func)
        self._hide_osd_func = nil
    end
    if self.osd_widget then
        local widget = self.osd_widget
        self.osd_widget = nil
        local dimen = widget.dimen and widget.dimen:copy()
        UIManager:close(widget, "ui", dimen)
        UIManager:forceRePaint()
    end
end

function KOlumen:onCloseDocument()
    self:hideOSD()
end

function KOlumen:onDestroy()
    self:onCloseDocument()
end

function KOlumen:getSubMenuItems()
    return {
        {
            text = _("Enable brightness swipe"),
            checked_func = function() return self.enabled end,
            callback = function()
                self.enabled = not self.enabled
                self:saveSetting("enabled", self.enabled)
            end,
        },
        {
            text = _("Adjustment mode"),
            help_text = _("Choose between adaptive and fixed mode"),
            sub_item_table = {
                {
                    text = _("Adaptive (relative)"),
                    help_text = _("Brightness changes relative to initial touch point (current brightness at touch start)"),
                    checked_func = function() return (self.mode or "adaptive") == "adaptive" end,
                    radio = true,
                    callback = function()
                        self.mode = "adaptive"
                        self:saveSetting("mode", "adaptive")
                    end,
                },
                {
                    text = _("Fixed (absolute)"),
                    help_text = _("Absolute position: bottom is 0%, center is 50%, top is 100%"),
                    checked_func = function() return self.mode == "fixed" end,
                    radio = true,
                    callback = function()
                        self.mode = "fixed"
                        self:saveSetting("mode", "fixed")
                    end,
                },
            },
        },
        {
            text = _("Top and bottom margin"),
            help_text = _("Screen edge margins (100% top, 0% bottom)"),
            sub_item_table = {
                {
                    text = "10%",
                    checked_func = function() return math.abs(self.vertical_margin - 0.10) < 0.01 end,
                    callback = function()
                        self.vertical_margin = 0.10
                        self:saveSetting("vertical_margin", 0.10)
                        self:registerZones()
                    end,
                },
                {
                    text = "15% (" .. _("default") .. ")",
                    checked_func = function() return math.abs(self.vertical_margin - 0.15) < 0.01 end,
                    callback = function()
                        self.vertical_margin = 0.15
                        self:saveSetting("vertical_margin", 0.15)
                        self:registerZones()
                    end,
                },
                {
                    text = "20%",
                    checked_func = function() return math.abs(self.vertical_margin - 0.20) < 0.01 end,
                    callback = function()
                        self.vertical_margin = 0.20
                        self:saveSetting("vertical_margin", 0.20)
                        self:registerZones()
                    end,
                },
                {
                    text = "25%",
                    checked_func = function() return math.abs(self.vertical_margin - 0.25) < 0.01 end,
                    callback = function()
                        self.vertical_margin = 0.25
                        self:saveSetting("vertical_margin", 0.25)
                        self:registerZones()
                    end,
                },
            },
        },
        {
            text = _("Center zone width"),
            help_text = _("Percentage of screen width in the center"),
            sub_item_table = {
                {
                    text = "30%",
                    checked_func = function() return math.abs(self.horizontal_zone_ratio - 0.30) < 0.01 end,
                    callback = function()
                        self.horizontal_zone_ratio = 0.30
                        self:saveSetting("horizontal_zone_ratio", 0.30)
                        self:registerZones()
                    end,
                },
                {
                    text = "40%",
                    checked_func = function() return math.abs(self.horizontal_zone_ratio - 0.40) < 0.01 end,
                    callback = function()
                        self.horizontal_zone_ratio = 0.40
                        self:saveSetting("horizontal_zone_ratio", 0.40)
                        self:registerZones()
                    end,
                },
                {
                    text = "50% (" .. _("default") .. ")",
                    checked_func = function() return math.abs(self.horizontal_zone_ratio - 0.50) < 0.01 end,
                    callback = function()
                        self.horizontal_zone_ratio = 0.50
                        self:saveSetting("horizontal_zone_ratio", 0.50)
                        self:registerZones()
                    end,
                },
                {
                    text = "60%",
                    checked_func = function() return math.abs(self.horizontal_zone_ratio - 0.60) < 0.01 end,
                    callback = function()
                        self.horizontal_zone_ratio = 0.60
                        self:saveSetting("horizontal_zone_ratio", 0.60)
                        self:registerZones()
                    end,
                },
                {
                    text = "70%",
                    checked_func = function() return math.abs(self.horizontal_zone_ratio - 0.70) < 0.01 end,
                    callback = function()
                        self.horizontal_zone_ratio = 0.70
                        self:saveSetting("horizontal_zone_ratio", 0.70)
                        self:registerZones()
                    end,
                },
            },
        },
        {
            text = _("Show brightness indicator"),
            checked_func = function() return self.show_osd end,
            callback = function()
                self.show_osd = not self.show_osd
                self:saveSetting("show_osd", self.show_osd)
            end,
        },
        {
            text = _("Indicator display duration"),
            help_text = _("Swiping is always available, even while indicator is shown"),
            sub_item_table = {
                {
                    text = "1.0 " .. _("sec"),
                    checked_func = function() return math.abs((self.osd_timeout or 1.5) - 1.0) < 0.1 end,
                    callback = function()
                        self.osd_timeout = 1.0
                        self:saveSetting("osd_timeout", 1.0)
                    end,
                },
                {
                    text = "1.5 " .. _("sec (default)"),
                    checked_func = function() return math.abs((self.osd_timeout or 1.5) - 1.5) < 0.1 end,
                    callback = function()
                        self.osd_timeout = 1.5
                        self:saveSetting("osd_timeout", 1.5)
                    end,
                },
                {
                    text = "2.0 " .. _("sec"),
                    checked_func = function() return math.abs((self.osd_timeout or 1.5) - 2.0) < 0.1 end,
                    callback = function()
                        self.osd_timeout = 2.0
                        self:saveSetting("osd_timeout", 2.0)
                    end,
                },
                {
                    text = "3.0 " .. _("sec"),
                    checked_func = function() return math.abs((self.osd_timeout or 1.5) - 3.0) < 0.1 end,
                    callback = function()
                        self.osd_timeout = 3.0
                        self:saveSetting("osd_timeout", 3.0)
                    end,
                },
            },
        },
    }
end

function KOlumen:addToMainMenu(menu_items)
    local menu_entry = {
        text = _("KOlumen"),
        sub_item_table = self:getSubMenuItems(),
    }

    if menu_items.gesture_manager then
        table.insert(menu_items.gesture_manager.sub_item_table, menu_entry)
    elseif menu_items.device and menu_items.device.sub_item_table then
        table.insert(menu_items.device.sub_item_table, menu_entry)
    else
        menu_items.kolumen = menu_entry
    end
end

return KOlumen
