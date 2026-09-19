MitzuForeverAtlas = MitzuForeverAtlas or {}
MitzuForeverAtlas.UI = MitzuForeverAtlas.UI or {}
local UI = MitzuForeverAtlas.UI

local function CreateDungeonButton(parent, dungeon, index)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(190, 24)
    button:SetPoint("TOPLEFT", 12, -42 - ((index - 1) * 28))
    button:SetText(dungeon.name)
    button:SetScript("OnClick", function()
        UI:ShowDungeon(dungeon)
    end)
    return button
end

function UI:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", "MitzuForeverAtlasFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 430)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 6, 0)
    frame.title:SetText("MitzuForeverAtlas — WoW Forever")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", 220, -42)
    subtitle:SetText("Dungeon atlas / preparation companion")

    self.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.nameText:SetPoint("TOPLEFT", 220, -72)
    self.nameText:SetText("Select a dungeon")

    self.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.statusText:SetPoint("TOPLEFT", self.nameText, "BOTTOMLEFT", 0, -12)
    self.statusText:SetWidth(370)
    self.statusText:SetJustifyH("LEFT")
    self.statusText:SetText("Beta data has not been verified yet. No bosses, maps, IDs, routes, or loot are guessed.")

    self.detailText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.detailText:SetPoint("TOPLEFT", self.statusText, "BOTTOMLEFT", 0, -20)
    self.detailText:SetWidth(370)
    self.detailText:SetJustifyH("LEFT")
    self.detailText:SetJustifyV("TOP")
    self.detailText:SetText("Planned after beta validation:\n• static dungeon map\n• entrances and floor notes\n• boss list and verified loot\n• pre-pull CC / threat notes\n• profession Blueprint drops\n• no combat automation")

    for i, dungeon in ipairs(MitzuForeverAtlas.Dungeons or {}) do
        CreateDungeonButton(frame, dungeon, i)
    end

    self.frame = frame
end

function UI:ShowDungeon(dungeon)
    self:Create()
    self.nameText:SetText(dungeon.name)
    self.statusText:SetText("Status: " .. tostring(dungeon.status) .. "\nRuntime map IDs and encounter data will be filled only from the beta client or official Blizzard data.")
    if MitzuForeverAtlas.db then
        MitzuForeverAtlas.db.lastDungeon = dungeon.key
    end
end

function UI:Toggle()
    self:Create()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
        if MitzuForeverAtlas.db and MitzuForeverAtlas.db.lastDungeon then
            local dungeon = MitzuForeverAtlas:GetDungeonByKey(MitzuForeverAtlas.db.lastDungeon)
            if dungeon then self:ShowDungeon(dungeon) end
        end
    end
end
