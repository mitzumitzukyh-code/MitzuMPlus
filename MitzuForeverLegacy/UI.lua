local frame = CreateFrame("Frame", "MitzuForeverLegacyFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(520, 340)
frame:SetPoint("CENTER")
frame:Hide()
frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
frame.title:SetText("Mitzu Forever Legacy")

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
text:SetJustifyH("LEFT")
text:SetText("Pre-beta scaffold\n\nPlanned: account-wide Legacy progress, per-character spend plans, challenge checklist and alt recommendations.\n\nOnly verified beta/official data will be added.")

if _G.MitzuForeverLegacy then
    _G.MitzuForeverLegacy.Toggle = function()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end
