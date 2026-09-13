-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - UI/Panels/Coach.lua
-- v5.4.1: corrige layout, hitboxes y añade vista previa segura para probar la UI fuera de una key.
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
local Theme = MitzuMPlus.Theme

local PanelCoach = {}
MitzuMPlus.PanelCoach = PanelCoach

local function settings()
    if not MitzuMPlus.db then return {} end
    local p = MitzuMPlus.db.profile
    p.settings = p.settings or {}
    return p.settings
end

local function currentRun()
    return _G.MitzuMPlusCurrentRun
end

local function yesno(v)
    return v and "|cFF21DE66ACTIVO|r" or "|cFFFF5555INACTIVO|r"
end

local function safeSpec()
    local sid, name
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then sid = PlayerUtil.GetCurrentSpecID() end
    if (not sid or sid == 0) and GetSpecialization and GetSpecializationInfo then
        local i = GetSpecialization()
        if i then sid, name = GetSpecializationInfo(i) end
    end
    if sid and not name and GetSpecializationInfoByID then
        local _, n = GetSpecializationInfoByID(sid)
        name = n
    end
    return sid, name or "Desconocida"
end

local function isKeyActive()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        return ok and active or false
    end
    return currentRun() ~= nil
end

local function makeSection(parent, title, height)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    f:SetHeight(height or 160)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=32, edgeSize=10,
            insets={left=3,right=3,top=3,bottom=3},
        })
        f:SetBackdropColor(0.045,0.045,0.05,0.92)
        f:SetBackdropBorderColor(0.35,0.30,0.12,0.9)
    end
    local hdr=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    Theme:ApplyFont(hdr,"title",14)
    hdr:SetPoint("TOPLEFT",14,-13)
    hdr:SetText(title)
    hdr:SetTextColor(0.95,0.75,0.18,1)
    f.innerY=-42
    return f
end

local function makeInfo(section, label)
    local row=CreateFrame("Frame",nil,section)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT",14,section.innerY)
    row:SetPoint("TOPRIGHT",-14,section.innerY)
    section.innerY=section.innerY-28

    local l=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    Theme:ApplyFont(l,"normal",12)
    l:SetPoint("LEFT",0,0)
    l:SetPoint("RIGHT",row,"CENTER",-10,0)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    l:SetText(label)
    l:SetTextColor(0.76,0.76,0.79,1)

    local v=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    Theme:ApplyFont(v,"mono",12)
    v:SetPoint("LEFT",row,"CENTER",10,0)
    v:SetPoint("RIGHT",0,0)
    v:SetJustifyH("RIGHT")
    v:SetWordWrap(false)
    v:SetText("—")
    row.label=l
    row.value=v
    return row
end

local function makeToggle(section, label, description, getter, setter)
    local row=CreateFrame("Frame",nil,section)
    row:SetHeight(38)
    row:SetPoint("TOPLEFT",14,section.innerY)
    row:SetPoint("TOPRIGHT",-14,section.innerY)
    section.innerY=section.innerY-42
    local cb=CreateFrame("CheckButton",nil,row,"UICheckButtonTemplate")
    cb:SetSize(24,24); cb:SetPoint("RIGHT",0,0); cb:SetChecked(getter())
    cb:SetScript("OnClick",function(self) setter(self:GetChecked()); PanelCoach:Refresh() end)
    local l=row:CreateFontString(nil,"OVERLAY","GameFontNormal")
    Theme:ApplyFont(l,"normal",13)
    l:SetPoint("TOPLEFT",0,-2); l:SetPoint("RIGHT",cb,"LEFT",-8,0); l:SetJustifyH("LEFT"); l:SetWordWrap(false); l:SetText(label)
    local d=row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    Theme:ApplyFont(d,"normal",11)
    d:SetPoint("TOPLEFT",l,"BOTTOMLEFT",0,-1); d:SetPoint("RIGHT",cb,"LEFT",-8,0); d:SetJustifyH("LEFT"); d:SetWordWrap(false); d:SetText(description or ""); d:SetTextColor(0.66,0.66,0.69,1)
    row.check=cb
    return row
end

-- WoW's SetPoint does not accept percentage strings. Dedicated equal-width row.
local function makeButtonRow(section, buttons)
    local row=CreateFrame("Frame",nil,section)
    row:SetHeight(30)
    row:SetPoint("TOPLEFT",14,section.innerY)
    row:SetPoint("TOPRIGHT",-14,section.innerY)
    section.innerY=section.innerY-35
    local prev=nil
    row.buttons={}
    for i,b in ipairs(buttons) do
        local btn=CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
        btn:SetHeight(25); btn:SetText(b[1]); btn:SetScript("OnClick",function() if b[2] then b[2]() end; PanelCoach:Refresh() end)
        if btn:GetFontString() then Theme:ApplyFont(btn:GetFontString(),"normal",12) end
        if #buttons==1 then
            btn:SetPoint("TOPLEFT",0,0); btn:SetPoint("TOPRIGHT",0,0)
        elseif i==1 then
            btn:SetPoint("TOPLEFT",0,0); btn:SetPoint("TOPRIGHT",row,"TOP",-3,0)
        elseif i==2 and #buttons==2 then
            btn:SetPoint("TOPLEFT",row,"TOP",3,0); btn:SetPoint("TOPRIGHT",0,0)
        else
            local width=math.floor((row:GetWidth()>0 and row:GetWidth() or 900)/#buttons)-6
            btn:SetWidth(width)
            if not prev then btn:SetPoint("LEFT",0,0) else btn:SetPoint("LEFT",prev,"RIGHT",6,0) end
        end
        row.buttons[i]=btn
        prev=btn
    end
    return row
end

function PanelCoach:Create(parent)
    local container
    if MitzuMPlus.Tabs and MitzuMPlus.Tabs.CreatePanelContainer then
        container=MitzuMPlus.Tabs:CreatePanelContainer(parent)
    else
        container=CreateFrame("Frame",nil,parent); container:SetAllPoints(parent)
    end

    local scroll=CreateFrame("ScrollFrame",nil,container,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",16,-16); scroll:SetPoint("BOTTOMRIGHT",-34,16)
    local content=CreateFrame("Frame",nil,scroll)
    content:SetSize(1,640); scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged",function(self,w) content:SetWidth(math.max(1,w-22)) end)

    local y=0
    -- 4 info (28) + 3 toggles (42) + 3 filas de botones (35) desde -42:
    -- ultima fila arriba en -350, alto 30 => 380 px usados.
    local live=makeSection(content,">> COACH EN VIVO",400)
    live:SetPoint("TOPLEFT",0,y); live:SetPoint("TOPRIGHT",0,y); y=y-410
    self.liveActive=makeInfo(live,"Estado de la Mítica+")
    self.liveAnchor=makeInfo(live,"Anclaje Blizzard")
    self.liveOverlay=makeInfo(live,"Overlay")
    self.liveScale=makeInfo(live,"Tamaño del Coach")
    makeToggle(live,"Coach en vivo","Muestra proyección, margen, pulls y confianza durante la key.",function() return settings().overlayEnabled~=false end,function(v) settings().overlayEnabled=v; if not v then MitzuMPlus:HideOverlay() elseif isKeyActive() then MitzuMPlus:ShowOverlay() end end)
    makeToggle(live,"Anclar al tracker de Blizzard","Usa el bloque oficial de Challenge Mode como referencia visual.",function() return settings().coachAnchorBlizzard~=false end,function(v) settings().coachAnchorBlizzard=v; if MitzuMPlus.OverlayFrame then MitzuMPlus.OverlayFrame:Reanchor(true) end end)
    makeToggle(live,"Bloquear posición","Bloqueado no se puede arrastrar y no intercepta clics sobre el mundo.",function() return settings().coachLocked==true end,function(v)
        settings().coachLocked=v
        if MitzuMPlus.OverlayFrame and MitzuMPlus.OverlayFrame.ApplyMouse then
            MitzuMPlus.OverlayFrame:ApplyMouse()
        end
    end)

    -- Ajuste de tamano con efecto inmediato: el overlay cambia mientras miras.
    local function nudgeScale(delta)
        local s=settings()
        local v=(tonumber(s.coachScale) or 1.0)+delta
        if v<0.7 then v=0.7 elseif v>2.0 then v=2.0 end
        s.coachScale=v
        if MitzuMPlus.OverlayFrame then
            if MitzuMPlus.OverlayFrame.ApplyScale then MitzuMPlus.OverlayFrame:ApplyScale() end
            MitzuMPlus.OverlayFrame:Reanchor(true)
        end
        if MitzuMPlus.Print then MitzuMPlus:Print(string.format("Coach: tamaño %d%%", math.floor(v*100+0.5))) end
    end
    makeButtonRow(live,{{"TAMAÑO  -",function() nudgeScale(-0.1) end},{"TAMAÑO  +",function() nudgeScale(0.1) end}})
    makeButtonRow(live,{{"RESTABLECER POSICIÓN",function()
        local p=MitzuMPlus.db and MitzuMPlus.db.profile
        if p then p.overlayPosition={point=nil,relPoint=nil,x=-20,y=-100} end
        settings().coachAnchorBlizzard=true
        if MitzuMPlus.OverlayFrame then MitzuMPlus.OverlayFrame:Reanchor(true) end
        if MitzuMPlus.Print then MitzuMPlus:Print("Coach: posición restablecida y anclaje a Blizzard reactivado.") end
    end}})
    makeButtonRow(live,{{"VISTA PREVIA",function() if MitzuMPlus.ShowOverlayPreview then MitzuMPlus:ShowOverlayPreview() else MitzuMPlus:ShowOverlay() end end},{"REANCLAR + PROBAR",function() if not MitzuMPlus.OverlayFrame then MitzuMPlus:InitOverlay() end; if MitzuMPlus.OverlayFrame then MitzuMPlus.OverlayFrame:Reanchor(true) end; if MitzuMPlus.ShowOverlayPreview and not isKeyActive() then MitzuMPlus:ShowOverlayPreview() elseif MitzuMPlus.ShowOverlay then MitzuMPlus:ShowOverlay() end; if MitzuMPlus.Print then MitzuMPlus:Print("Coach: "..tostring(MitzuMPlus:GetOverlayAnchorStatus())) end end}})


    local route=makeSection(content,">> RUTAS · MDT",220)
    route:SetPoint("TOPLEFT",0,y); route:SetPoint("TOPRIGHT",0,y); y=y-230
    self.routeMode=makeInfo(route,"Ruta actual")
    self.routePulls=makeInfo(route,"Pulls")
    self.routeLearn=makeInfo(route,"Aprendizaje AUTO")
    makeToggle(route,"Aprendizaje automático de ruta","Aprende el tamaño real de tus pulls a partir de Enemy Forces legible.",function() return settings().routeAutoLearn~=false end,function(v) settings().routeAutoLearn=v end)
    self.routeButtonRow=makeButtonRow(route,{{"IMPORTAR MDT",function() if MitzuMPlus.MDTImporter then MitzuMPlus.MDTImporter:ShowDialog() end end},{"BORRAR RUTA",function() if MitzuMPlus.RouteAdvisor then MitzuMPlus.RouteAdvisor:ClearRoute(currentRun()) end end}})

    local pred=makeSection(content,">> PREDICCIÓN",210)
    pred:SetPoint("TOPLEFT",0,y); pred:SetPoint("TOPRIGHT",0,y); y=y-220
    self.predResult=makeInfo(pred,"Resultado proyectado")
    self.predMargin=makeInfo(pred,"Margen")
    self.predPulls=makeInfo(pred,"Pulls restantes / siguiente")
    self.predConfidence=makeInfo(pred,"Confianza")
    makeToggle(pred,"Predicción en vivo","Calcula +3/+2/+1, margen, pulls restantes y confianza usando estado M+ permitido.",function() return settings().predictionEnabled~=false end,function(v) settings().predictionEnabled=v end)

    local diag=makeSection(content,">> DIAGNÓSTICO",150)
    diag:SetPoint("TOPLEFT",0,y); diag:SetPoint("TOPRIGHT",0,y); y=y-160
    self.diagRun=makeInfo(diag,"Run interna")
    self.diagTracker=makeInfo(diag,"Tracker Blizzard")
    makeButtonRow(diag,{{"PROBAR / REFRESCAR",function() if isKeyActive() then MitzuMPlus:ShowOverlay() elseif MitzuMPlus.ShowOverlayPreview then MitzuMPlus:ShowOverlayPreview() end end},{"COPIAR ESTADO AL CHAT",function()
        if MitzuMPlus.Print then
            local sid,sn=safeSpec(); local anchor=MitzuMPlus.GetOverlayAnchorStatus and MitzuMPlus:GetOverlayAnchorStatus() or "n/a"
            MitzuMPlus:Print(string.format("Coach UI: key=%s · run=%s · spec=%s(%s) · anchor=%s",tostring(isKeyActive()),tostring(currentRun()~=nil),tostring(sn),tostring(sid or "?"),tostring(anchor)))
        end
    end}})

    content:SetHeight(math.max(720,-y+20))
    self.container=container
    container:SetScript("OnUpdate", function(_, elapsed)
        PanelCoach._acc = (PanelCoach._acc or 0) + elapsed
        if PanelCoach._acc >= 1.0 then
            PanelCoach._acc = 0
            PanelCoach:Refresh()
        end
    end)
    if MitzuMPlus.Tabs then MitzuMPlus.Tabs:RegisterPanel("coach",container) end
    container:Hide()
    return container
end

function PanelCoach:Refresh()
    if not self.container then return end
    local active=isKeyActive()
    if self.liveActive then self.liveActive.value:SetText(yesno(active)) end
    local anchor="sin resolver"
    if MitzuMPlus.GetOverlayAnchorStatus then anchor=MitzuMPlus:GetOverlayAnchorStatus() end
    if self.liveAnchor then self.liveAnchor.value:SetText(anchor) end
    if self.liveOverlay then
        local shown=MitzuMPlus.OverlayFrame and MitzuMPlus.OverlayFrame:IsShown()
        self.liveOverlay.value:SetText(yesno(shown))
    end
    if self.liveScale then
        self.liveScale.value:SetText(string.format("%d%%", math.floor((tonumber(settings().coachScale) or 1.0)*100+0.5)))
    end

    local ra=MitzuMPlus.RouteAdvisor
    local r=ra and ra:GetImportedRoute() or nil
    if self.routeMode then
        local name=r and (r.name or "MDT") or "AUTO"
        self.routeMode.value:SetText(r and ("|cFF21DE66"..name.."|r") or "AUTO")
    end
    if self.routePulls then self.routePulls.value:SetText(r and tostring(#(r.pulls or {})) or "—") end
    if self.routeLearn then
        local avg,n=ra and ra:GetAveragePullPct() or nil,0
        if ra then avg,n=ra:GetAveragePullPct() end
        self.routeLearn.value:SetText(avg and string.format("%.1f%% · %d muestras",avg,n or 0) or "esperando pulls")
    end

    local snap=MitzuMPlus.PredictionEngine and MitzuMPlus.PredictionEngine:GetSnapshot(currentRun()) or nil
    if snap then
        -- v5.4.4: sin base para proyectar se muestra "—", no un 0 que parece dato.
        if self.predResult then
            self.predResult.value:SetText(snap.result and tostring(snap.result) or "|cFFBBBBBB— sin datos|r")
        end
        if self.predMargin then
            self.predMargin.value:SetText(snap.margin and string.format("%+.0fs",snap.margin) or "—")
        end
        if self.predPulls then self.predPulls.value:SetText(string.format("%d · ~%.1f%%",tonumber(snap.pullsLeft) or 0,tonumber(snap.nextPullPct) or 0)) end
        if self.predConfidence then
            self.predConfidence.value:SetText(snap.confidence and string.format("%d%%",snap.confidence) or "—")
        end
    else
        if self.predResult then self.predResult.value:SetText("—") end
        if self.predMargin then self.predMargin.value:SetText("—") end
        if self.predPulls then self.predPulls.value:SetText("—") end
        if self.predConfidence then self.predConfidence.value:SetText("—") end
    end

    if self.diagRun then self.diagRun.value:SetText(currentRun() and "|cFF21DE66ASIGNADA|r" or "—") end
    if self.diagTracker then self.diagTracker.value:SetText(anchor) end
end

return true
