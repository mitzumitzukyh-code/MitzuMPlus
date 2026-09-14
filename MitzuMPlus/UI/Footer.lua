-- MitzuMPlus compact product footer.
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon("MitzuMPlus")
local Theme = MitzuMPlus.Theme
local Footer = {}
MitzuMPlus.Footer = Footer

function Footer:Create(parent)
    local footer = parent.footerContainer
    footer:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(footer, { r = 0.016, g = 0.016, b = 0.027, a = 0.85 })

    local line = footer:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(line, Theme.GOLD.gold0)

    local brand = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    brand:SetPoint("LEFT", footer, "LEFT", 12, 0)
    Theme:ApplyFont(brand, "normal", 12)
    brand:SetText("MitzuMPlus")
    Theme:SetTextColor(brand, Theme.TEXT.dim)

    local summary = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("LEFT", footer, "LEFT", 170, 0)
    summary:SetPoint("RIGHT", footer, "RIGHT", -30, 0)
    summary:SetJustifyH("RIGHT")
    summary:SetWordWrap(false)
    Theme:ApplyFont(summary, "normal", 12)
    Theme:SetTextColor(summary, Theme.TEXT.dim)
    footer.summary = summary

    self.container = footer
    parent.footer = footer
    self:UpdateStats()
    return footer
end

function Footer:UpdateStats()
    if not self.container then return end
    local total, best = 0, 0
    local runs = MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs or {}
    for _, run in pairs(type(runs) == "table" and runs or {}) do
        if type(run) == "table" then
            total = total + 1
            best = math.max(best, tonumber(run.keyLevel) or 0)
        end
    end
    local bestText = best > 0 and ("Best +" .. best) or "Sin runs"
    self.container.summary:SetText(string.format("%d runs · %s · v%s",
        total, bestText, tostring(MitzuMPlus.VERSION or "?")))
end

return Footer
