local frame = CreateFrame("Frame", "MitzuForeverClassicUIFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(500, 300)
frame:SetPoint("CENTER")
frame:Hide()
frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
frame.title:SetText("Mitzu Forever Classic UI")

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
text:SetJustifyH("LEFT")
text:SetText("Pre-beta scaffold\n\nGoal: Classic visual presets, readability and accessibility without changing secure combat actions.\n\nNo protected frames are modified in combat in this scaffold.")

if _G.MitzuForeverClassicUI then
    _G.MitzuForeverClassicUI.Toggle = function()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end
