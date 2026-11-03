local ok, _ = pcall(require, "i18n")
if not ok or not _ then
    _ = require("gettext")
end

return {
    name = "kolumen",
    fullname = _("KOlumen"),
    description = _("Adjust screen brightness continuously in real time by dragging vertically in the center of the screen."),
    category = "gesture",
    version = "1.1.0",
}
