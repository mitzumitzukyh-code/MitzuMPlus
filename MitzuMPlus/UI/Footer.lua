-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - Footer
-- Footer con watermark + stats rápidas + reloj
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local Theme = MitzuMPlus.Theme
local Footer = {}
MitzuMPlus.Footer = Footer

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE FOOTER
-- ═══════════════════════════════════════════════════════════════════════════

function Footer:Create(parent)
    local footer = parent.footerContainer
    
    -- BUG-L1 FIX: usar BACKDROPS.panel (tiene edgeFile) para que
    -- SetBackdropBorderColor funcione. BACKDROPS.simple no tiene borde.
    footer:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(footer, { r = 0.016, g = 0.016, b = 0.027, a = 0.85 })
    
    local topBorder = footer:CreateTexture(nil, "BORDER")
    topBorder:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    topBorder:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    topBorder:SetHeight(1)
    topBorder:SetTexture("Interface\\Buttons\\WHITE8X8")
    Theme:SetVertexColor(topBorder, Theme.GOLD.gold0)
    
    if MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings and MitzuMPlus.db.profile.settings.showWatermark then
        local watermark = footer:CreateFontString(nil, "OVERLAY")
        watermark:SetPoint("LEFT", footer, "LEFT", 12, 0)
        Theme:ApplyFont(watermark, "mono", 12)
        watermark:SetText("MitzuMPlus M+ HISTORIAL · by Mutzukyhs")
        Theme:SetTextColor(watermark, Theme.TEXT.dim)
        
        footer.watermark = watermark
    end
    
    local rightContainer = CreateFrame("Frame", nil, footer)
    rightContainer:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
    rightContainer:SetHeight(Theme.LAYOUT.footerHeight)
    rightContainer:SetWidth(300)
    
    local xOffset = 0
    
    -- Valores dinámicos: se rellenan en UpdateStats() al crear y al registrar runs
    local runsTag = self:CreateTag(rightContainer, "0 RUNS")
    runsTag:SetPoint("RIGHT", rightContainer, "RIGHT", xOffset, 0)
    footer.runsTag = runsTag
    xOffset = xOffset - runsTag:GetWidth() - 8

    local bestTag = self:CreateTag(rightContainer, "+0 BEST")
    bestTag:SetPoint("RIGHT", rightContainer, "RIGHT", xOffset, 0)
    footer.bestTag = bestTag
    xOffset = xOffset - bestTag:GetWidth() - 8
    
    local versionTag = self:CreateTag(rightContainer, "v" .. MitzuMPlus.VERSION)
    versionTag:SetPoint("RIGHT", rightContainer, "RIGHT", xOffset, 0)
    footer.versionTag = versionTag
    xOffset = xOffset - versionTag:GetWidth() - 10
    
    local clock = footer:CreateFontString(nil, "OVERLAY")
    clock:SetPoint("RIGHT", rightContainer, "RIGHT", xOffset, 0)
    Theme:ApplyFont(clock, "mono", 12)
    Theme:SetTextColor(clock, Theme.TEXT.dim)
    footer.clock = clock
    
    self:StartClockUpdate(footer)
    self:UpdateStats()   -- FIX: poblar con datos reales desde DB al crear

    self.container = footer
    parent.footer = footer
    
    return footer
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE TAG
-- ═══════════════════════════════════════════════════════════════════════════

function Footer:CreateTag(parent, text)
    local tag = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    tag:SetHeight(22)
    tag:SetBackdrop(Theme.BACKDROPS.panel)
    Theme:SetBackdropColor(tag, Theme.BG.btnPrim)
    Theme:SetBackdropBorderColor(tag, Theme.GOLD.gold0)
    
    local tagText = tag:CreateFontString(nil, "OVERLAY")
    tagText:SetPoint("CENTER")
    Theme:ApplyFont(tagText, "mono", 12)
    tagText:SetText(text)
    Theme:SetTextColor(tagText, Theme.GOLD.gold3)
    
    tag.text = tagText
    
    local textWidth = tagText:GetStringWidth()
    tag:SetWidth(textWidth + 12)
    
    return tag
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UPDATE STATS TAGS
-- ═══════════════════════════════════════════════════════════════════════════

function Footer:UpdateStats()
    if not self.container then return end
    
    local totalRuns = 0
    local bestKey = 0
    
    if MitzuMPlus.db and MitzuMPlus.db.global and MitzuMPlus.db.global.runs then
        for _, run in pairs(MitzuMPlus.db.global.runs) do
            if type(run) == "table" then
                totalRuns = totalRuns + 1
                if run.keyLevel and run.keyLevel > bestKey then
                    bestKey = run.keyLevel
                end
            end
        end
    end
    
    if self.container.runsTag and self.container.runsTag.text then
        self.container.runsTag.text:SetText(string.format("%d RUNS", totalRuns))
        local textWidth = self.container.runsTag.text:GetStringWidth()
        self.container.runsTag:SetWidth(textWidth + 12)
    end
    
    if self.container.bestTag and self.container.bestTag.text then
        if bestKey > 0 then
            self.container.bestTag.text:SetText(string.format("+%d BEST", bestKey))
        else
            self.container.bestTag.text:SetText("NO RUNS")
        end
        local textWidth = self.container.bestTag.text:GetStringWidth()
        self.container.bestTag:SetWidth(textWidth + 12)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CLOCK UPDATE
-- ═══════════════════════════════════════════════════════════════════════════

function Footer:StartClockUpdate(footer)
    local function UpdateClock()
        if footer and footer.clock and footer:IsVisible() then
            local hour, minute, second = GetGameTime()
            -- Fase 3.1: prefijo "ST" para indicar Server Time inequívocamente
            footer.clock:SetText(string.format("ST %02d:%02d:%02d", hour, minute, second))
        end
    end

    UpdateClock()

    C_Timer.NewTicker(1, function()
        UpdateClock()
    end)
end

return Footer
