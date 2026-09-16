local frame = CreateFrame("Frame", "MitzuForeverProfessionsFrame", UIParent, "BasicFrameTemplateWithInset")
frame:SetSize(520, 360)
frame:SetPoint("CENTER")
frame:Hide()
frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
frame.title:SetText("Mitzu Forever Professions")

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -42)
text:SetJustifyH("LEFT")
text:SetText("Pre-beta scaffold\n\nPlanned: recipes, Blueprint sources, Camping objects, materials and party-buff planning.\n\nOnly verified beta/official data will be added.")

if _G.MitzuForeverProfessions then
    _G.MitzuForeverProfessions.Toggle = function()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end
