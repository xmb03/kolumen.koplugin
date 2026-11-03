--[[
    i18n.lua - Lightweight Gettext drop-in replacement for KOReader standalone plugins.
    Allows plugins to provide localized strings via modular Lua catalogs in l10n/<lang>.lua.
--]]

local has_gettext, core_gettext = pcall(require, "gettext")

local I18n = {
    _loaded = {},
}

-- Fetch the active user language from KOReader settings or system environment
local function getActiveLanguage()
    local lang
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language")
    end
    if not lang then
        lang = os.getenv("LANG") or "en"
    end
    if type(lang) == "string" then
        return lang:gsub("-", "_")
    end
    return "en"
end

-- Load language catalog table from l10n/<lang>.lua
local function loadCatalog(lang)
    if I18n._loaded[lang] ~= nil then
        return I18n._loaded[lang]
    end

    local lang_prefix = lang:match("^([a-z]+)") or lang
    local candidates = { lang, lang_prefix:lower() }

    for _, l in ipairs(candidates) do
        -- 1. Try standard Lua require: l10n.<lang>
        local ok, catalog = pcall(require, "l10n." .. l)
        if ok and type(catalog) == "table" then
            I18n._loaded[lang] = catalog
            return catalog
        end

        -- 2. Fallback to direct file path based on script location
        local info = debug.getinfo(1, "S")
        local plugin_dir = info and info.source and info.source:match("@?(.*[/\\])") or ""
        local path = plugin_dir .. "l10n/" .. l .. ".lua"
        local fok, fcatalog = pcall(dofile, path)
        if fok and type(fcatalog) == "table" then
            I18n._loaded[lang] = fcatalog
            return fcatalog
        end
    end

    I18n._loaded[lang] = false
    return false
end

-- Primary translation lookup
function I18n.translate(msgid)
    if not msgid or type(msgid) ~= "string" then
        return msgid
    end

    local lang = getActiveLanguage()
    local catalog = loadCatalog(lang)
    if catalog and catalog[msgid] then
        return catalog[msgid]
    end

    -- Fallback to core KOReader gettext for common shared strings
    if has_gettext and (type(core_gettext) == "table" or type(core_gettext) == "function") then
        local ok, res = pcall(core_gettext, msgid)
        if ok and res and res ~= msgid then
            return res
        end
    end

    return msgid
end

setmetatable(I18n, {
    __call = function(_, msgid)
        return I18n.translate(msgid)
    end,
})

return I18n
