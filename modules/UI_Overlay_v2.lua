-- MitzuMPlus Coach Overlay v5.5.0
-- Midnight-safe live coach anchored to Blizzard's Mythic+ Scenario tracker.
--
-- v5.4.2 (BUG CRITICO COACH-1): el refresco ya NO depende del OnUpdate del
-- propio frame. Un frame oculto no recibe OnUpdate, asi que el overlay no podia
-- volver a mostrarse por si mismo (misma clase de bug que el de v5.3.4). Ahora
-- lo mueve un ticker externo que vive mientras haya run o preview activa.
--
-- v5.4.2 (BUG CRITICO COACH-2): el modo PRUEBA se quedaba pegado durante una
-- key real. Refresh() lo desactiva en cuanto detecta key + run reales, y
-- ShowOverlay() ya no cae en preview silenciosamente cuando la key todavia no
-- ha arrancado: deja el ticker trabajando hasta que arranque.
--
-- v5.5.0 (BUG GLIFOS-1): el cliente de WoW NO renderiza emoji. Los caracteres
-- de calavera y de flecha arriba/abajo salian como cuadrados vacios. Todo el texto
-- es ahora ASCII + acentos latinos, que si estan en las fuentes del juego.
--
-- v5.5.0 (LEGIBILIDAD): fondo opcional. Sin fondo el texto lleva contorno
-- (OUTLINE) y colores saturados para no perderse sobre el mundo.
--
-- v5.5.0 (INFO): lineas nuevas opcionales — ritmo de fuerzas vs ritmo
-- necesario, reloj/tiempo restante, margen de muertes y mana del healer.
local MitzuMPlus=_G.MitzuMPlus
if not MitzuMPlus then return end
local UPDATE=0.5
local function T() return MitzuMPlus.Theme end

-- Layout dinamico: el numero de lineas depende de lo que el usuario active.
-- Textura de barra de Blizzard. Es la que usan sus propias barras de estado
-- (marco de objetivo, banda, escenario) y la referencia mas comun entre
-- addons, asi que existe seguro en cualquier instalacion. Sustituye a las
-- barras ASCII "[====----]", que ademas de feas dependian del ancho de fuente.
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local MAX_LINES   = 14
local LINE_HEIGHT = 21
local TOP_PAD     = 36    -- espacio del titulo/resultado
local BOTTOM_PAD  = 10

local function keyIsActive()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok,active=pcall(C_ChallengeMode.IsChallengeModeActive)
        return ok and active==true
    end
    return false
end
local function fmt(s)
    s=math.max(0,tonumber(s) or 0); return string.format('%d:%02d',math.floor(s/60),math.floor(s%60))
end
local function signed(s)
    local v=tonumber(s) or 0
    return (v>=0 and '+' or '-')..fmt(math.abs(v))
end
local function progressBar(pct,width)
    width=width or 20;pct=math.max(0,math.min(100,tonumber(pct) or 0))
    local filled=math.floor((pct/100)*width+.5)
    return '['..string.rep('=',filled)..string.rep('-',width-filled)..']'
end
-- Resolve the Blizzard frame that actually renders the active Mythic+ timer.
-- Midnight/Mainline keeps the M+ timer on ScenarioObjectiveTracker.ChallengeModeBlock.
-- We never modify Blizzard's frame; it is used only as an anchor reference.
-- v5.4.3: un frame puede estar "shown" y aun no tener rect calculado, o estar
-- shown con un padre oculto. Anclarse a el da una posicion basura. Se exige:
--   IsVisible() (toda la cadena de padres visible) + rect real con ancho > 0.
local function usableAnchor(f)
    if not f then return false end
    if f.IsVisible and not f:IsVisible() then return false end
    if not f.GetTop or f:GetTop() == nil then return false end
    if not f.GetWidth or (f:GetWidth() or 0) <= 0 then return false end
    return true
end

local function trackerFrame()
    local scenario = _G.ScenarioObjectiveTracker
    if scenario then
        -- Preferencia absoluta: el bloque oficial de Challenge Mode. Blizzard lo
        -- crea/activa DESPUES de CHALLENGE_MODE_START (durante la cuenta atras
        -- todavia no existe), por eso el ticker reevalua esto en cada refresco y
        -- el overlay salta al bloque en cuanto aparece.
        local challenge = scenario.ChallengeModeBlock
        if usableAnchor(challenge) then
            return challenge, "ScenarioObjectiveTracker.ChallengeModeBlock"
        end
        if usableAnchor(scenario) then
            return scenario, "ScenarioObjectiveTracker"
        end
    end

    -- Fallback only. ObjectiveTrackerFrame contains quests/campaign modules too, so
    -- it is less precise than ScenarioObjectiveTracker during a key.
    local objective = _G.ObjectiveTrackerFrame
    if usableAnchor(objective) then
        return objective, "ObjectiveTrackerFrame"
    end
    return nil, "UIParent"
end
local function settings()
    return MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
end
local function opt(key, default)
    local st=settings()
    if not st or st[key]==nil then return default end
    return st[key]
end
-- ═════════════════════════════════════════════════════════════════════════
-- NIVEL DE INTERFAZ  (v7.6.0)
--
-- Dos ejes distintos, que antes estaban mezclados:
--   coachDisplayMode  = CUANTO ESPACIO ocupa   (COMPLEMENT / REPLACE / COMPACT)
--   uiLevel           = PARA QUIEN es el texto (LEARN / PRO)
--
-- LEARN no es "Pro con menos lineas": cambia el REGISTRO. En vez de dar datos
-- para que el jugador los interprete, dice que hacer y por que importa cada
-- numero. Un novato no sabe que el 100% de fuerzas es obligatorio; ponerle
-- "96.55%" a secas no le informa de nada.
--
-- Por defecto PRO: cambiar el comportamiento de una instalacion existente al
-- actualizar seria peor que no traer la funcion. Se elige en Configuracion.
-- ═════════════════════════════════════════════════════════════════════════
local function uiLevel()
    local v = tostring(opt('uiLevel', 'PRO')):upper()
    return (v == 'LEARN') and 'LEARN' or 'PRO'
end

local function displayMode()
    local mode = tostring(opt('coachDisplayMode', 'COMPLEMENT')):upper()
    if mode ~= 'REPLACE' and mode ~= 'COMPACT' then mode = 'COMPLEMENT' end
    return mode
end

-- ── Paleta ───────────────────────────────────────────────────────────────
-- Sin fondo hace falta MUCHO mas contraste: el mundo detras es marron, verde y
-- naranja segun la mazmorra, asi que los grises del modo con fondo desaparecen.
local function palette()
    local transparent = opt('coachTransparent', true) == true
    if transparent then
        return {
            title  = {1.00,0.86,0.10},
            main   = {1.00,0.95,0.55},
            info   = {0.55,0.95,1.00},
            dim    = {1.00,0.80,0.30},
            good   = {0.35,1.00,0.45},
            warn   = {1.00,0.85,0.15},
            bad    = {1.00,0.35,0.30},
            none   = {0.85,0.85,0.90},
        }, true
    end
    return {
        title  = {0.95,0.75,0.18},
        main   = {0.90,0.90,0.92},
        info   = {0.62,0.82,0.95},
        dim    = {0.65,0.65,0.68},
        good   = {0.25,0.90,0.45},
        warn   = {0.95,0.82,0.20},
        bad    = {0.95,0.25,0.25},
        none   = {0.72,0.72,0.75},
    }, false
end

-- ═════════════════════════════════════════════════════════════════════════
-- DATOS DE EJEMPLO PARA LA VISTA PREVIA  (v7.6.1)
--
-- BUG PREVIEW-1: la vista previa pintaba CUATRO LINEAS FIJAS y devolvia antes
-- de llegar a la logica real. O sea: no previsualizaba nada. Cambiar entre
-- Aprendiendo y Pro con el Coach en pantalla mostraba el mismo texto, porque
-- ese texto no dependia de ningun ajuste.
--
-- Ahora la previa fabrica un snapshot verosimil y lo pasa por EL MISMO camino
-- de dibujado que una llave real. Asi enseña de verdad lo que vas a ver: el
-- modo, el fondo, las lineas activadas y los colores.
--
-- Los valores son los de una llave a media carrera y algo justa, que es cuando
-- el Coach tiene algo que decir. Una previa con todo en verde no dejaria ver
-- ni los avisos ni los colores de alerta.
-- ═════════════════════════════════════════════════════════════════════════
local function fakeSnapshot()
    local limit, elapsed = 1800, 1020          -- 30:00 de limite, 17:00 jugados
    local projected      = 1735                -- 28:55 -> +1 justo
    return {
        hasBasis      = true,
        result        = '+1',
        projectedTime = projected,
        margin        = limit - projected,
        elapsed       = elapsed,
        timeLimit     = limit,
        timeRemaining = limit - elapsed,
        enemyPct      = 71.4,
        bossesDone    = 2,
        bossesTotal   = 3,
        deaths        = 3,
        deathTimeLost = 45,
        deathBudget   = 4,
        pullsLeft     = 4,
        nextPullPct   = 6.2,
        routeMode     = 'auto',
        -- Ritmo por DEBAJO del necesario a proposito: asi la previa dispara
        -- el aviso de "acelera" y se ven los colores de alerta. Con todo en
        -- verde no se podria comprobar como avisa el Coach.
        pacePct       = 3.2,
        neededPct     = 3.9,
        confidence    = 62,
        pbTime        = 1680,
        pbDelta       = 1680 - projected,
    }
end

local function fakeOfficial(s)
    return {
        -- El modo REPLACE pinta el nombre y el nivel en la cabecera. Sin
        -- estos campos la previa mostraba "MYTHIC+ +0", que no es un error
        -- pero tampoco previsualiza nada.
        dungeonName   = 'MAZMORRA DE PRUEBA',
        keyLevel      = 12,
        enemyCurrent  = 214,
        enemyTotal    = 300,
        elapsed       = s.elapsed,
        timeLimit     = s.timeLimit,
        plus2Time     = s.timeLimit * 0.8,
        plus3Time     = s.timeLimit * 0.6,
        enemyPct      = s.enemyPct,
        deaths        = s.deaths,
        deathTimeLost = s.deathTimeLost,
        bosses        = {
            { name = 'Primer jefe',  completed = true  },
            { name = 'Segundo jefe', completed = true  },
            { name = 'Jefe final',   completed = false },
        },
    }
end

local function setText(fs,text,color)
    if not fs then return end
    fs:SetText(text or '')
    if color then fs:SetTextColor(color[1],color[2],color[3],1) end
end

function MitzuMPlus:InitOverlay()
    if self.OverlayFrame then return self.OverlayFrame end
    -- v5.4.3: 250x104 con fuentes *Small era ilegible en pantallas grandes.
    -- Base mas ancha, fuentes de tamano normal y escala configurable
    -- (settings.coachScale) para que cada uno lo ajuste a su resolucion.
    local f=CreateFrame('Frame','MitzuMPlusCoachOverlay',UIParent,'BackdropTemplate')
    f:SetSize(360,134); f:SetFrameStrata('MEDIUM'); f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
    f:SetBackdropColor(0.025,0.03,0.04,0.93); f:SetBackdropBorderColor(0.45,0.36,0.12,0.85)
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); T():ApplyFont(title,'title',14); title:SetPoint('TOPLEFT',12,-9); title:SetText('MITZUMPLUS COACH'); title:SetTextColor(0.95,0.75,0.18,1)
    local result=f:CreateFontString(nil,'OVERLAY','GameFontNormalHuge'); T():ApplyFont(result,'title',22); result:SetPoint('TOPRIGHT',-12,-6)
    f._title=title; f._result=result

    -- v5.5.0: pool fijo de lineas. Refresh() rellena las que hagan falta y
    -- oculta el resto; asi las funciones opcionales no obligan a recrear frames
    -- en mitad de una key.
    f._lines={}
    for i=1,MAX_LINES do
        -- Solo TOPLEFT a proposito: sin ancho fijado, la FontString se
        -- autodimensiona y NUNCA hace wrap. Con un segundo anclaje a la
        -- derecha, una linea larga saltaria de renglon y se solaparia con la
        -- siguiente, que tiene la Y fijada.
        local fs=f:CreateFontString(nil,'OVERLAY','GameFontHighlight')
        T():ApplyFont(fs,'normal',13)
        fs:SetPoint('TOPLEFT',12,-(TOP_PAD+(i-1)*LINE_HEIGHT))
        fs:SetJustifyH('LEFT')
        fs:SetWordWrap(false)
        fs:Hide()
        f._lines[i]=fs
    end

    -- Pool paralelo de barras reales, una por ranura de linea. Se crean todas
    -- por adelantado por el mismo motivo que las FontStrings: crear frames en
    -- mitad de una llave es justo cuando no conviene.
    f._bars={}
    for i=1,MAX_LINES do
        local bar=CreateFrame('StatusBar',nil,f)
        bar:SetStatusBarTexture(BAR_TEXTURE)
        bar:SetMinMaxValues(0,100)
        bar:SetValue(0)
        bar:SetHeight(LINE_HEIGHT-6)
        bar:SetPoint('TOPLEFT',12,-(TOP_PAD+(i-1)*LINE_HEIGHT)-1)
        bar:SetPoint('RIGHT',f,'RIGHT',-12,0)

        local bg=bar:CreateTexture(nil,'BACKGROUND')
        bg:SetAllPoints(bar)
        bg:SetTexture(BAR_TEXTURE)
        bg:SetVertexColor(0.15,0.14,0.12,0.9)
        bar._bg=bg

        local txt=bar:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
        T():ApplyFont(txt,'mono',11)
        txt:SetPoint('CENTER',bar,'CENTER',0,0)
        bar._text=txt

        bar:Hide()
        f._bars[i]=bar
    end

    -- ── v5.4.4: mover el Coach a mano ────────────────────────────────────
    -- Arrastrar con boton izquierdo. Al soltar se guarda la posicion y se pasa
    -- a modo libre (desanclado de Blizzard): mantener las dos cosas a la vez es
    -- imposible, el Reanchor lo devolveria al tracker en el siguiente tick.
    -- Con "Bloquear posicion" se apaga EnableMouse para que el overlay no
    -- intercepte NINGUN clic sobre el mundo durante la key.
    f:SetMovable(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function(self)
        local st=settings()
        if st and st.coachLocked then return end
        self._dragging=true
        self:StartMoving()
    end)
    f:SetScript('OnDragStop',function(self)
        if not self._dragging then return end
        self:StopMovingOrSizing()
        self._dragging=false
        local st=settings()
        -- v5.8.1: el mensaje largo solo la PRIMERA vez que se rompe el anclaje.
        -- Colocar el Coach a gusto son 3 o 4 arrastres seguidos, y repetir el
        -- parrafo entero en cada uno es ruido: a partir del segundo ya no
        -- cambia nada, solo se guarda la posicion.
        local wasAnchored = (not st) or st.coachAnchorBlizzard ~= false
        if st then st.coachAnchorBlizzard=false end
        local profile=MitzuMPlus.db and MitzuMPlus.db.profile
        if profile then
            local point,_,relPoint,x,y=self:GetPoint()
            profile.overlayPosition=profile.overlayPosition or {}
            profile.overlayPosition.point    = point
            profile.overlayPosition.relPoint = relPoint
            profile.overlayPosition.x        = x
            profile.overlayPosition.y        = y
        end
        self._anchorKey=nil
        self:Reanchor(true)
        if wasAnchored and MitzuMPlus.Print then
            MitzuMPlus:Print('|cFFd9b33eCoach:|r posición guardada. Se ha desactivado el anclaje al tracker de Blizzard; vuelve a activarlo en M+ COACH si lo quieres pegado al bloque de la llave.')
        end
    end)

    -- El raton solo se habilita cuando el overlay es arrastrable. Bloqueado no
    -- intercepta clics (problema conocido de overlays sobre el mundo).
    function f:ApplyMouse()
        local st=settings()
        local locked=st and st.coachLocked==true
        self:EnableMouse(not locked)
    end

    -- Escala. Se aplica solo cuando cambia: SetScale en cada refresco seria
    -- trabajo tirado 2 veces por segundo.
    function f:ApplyScale()
        local st=MitzuMPlus.db and MitzuMPlus.db.profile and MitzuMPlus.db.profile.settings
        local scale=tonumber(st and st.coachScale) or 1.0
        if scale < 0.7 then scale = 0.7 elseif scale > 2.0 then scale = 2.0 end
        if self._appliedScale ~= scale then
            self:SetScale(scale)
            self._appliedScale = scale
            self._anchorKey = nil   -- fuerza recolocar con el nuevo tamano
        end
        return scale
    end

    -- ── v5.5.0: fondo on/off ─────────────────────────────────────────────
    -- Sin fondo el texto queda sobre el mundo, asi que se le pone contorno
    -- negro (OUTLINE) + sombra. Sin eso, cualquier suelo claro se lo come.
    -- Se aplica solo cuando cambia el ajuste: SetFont 9 veces por tick seria
    -- trabajo tirado.
    function f:ApplyBackground(force)
        -- Un reemplazo debe conservar un fondo legible porque ocupa el lugar
        -- del tracker oficial. Complemento/Compacto respetan la preferencia.
        local transparent = displayMode() ~= 'REPLACE' and opt('coachTransparent', true) == true
        if not force and self._appliedBg == transparent then return transparent end
        self._appliedBg = transparent

        if transparent then
            self:SetBackdropColor(0,0,0,0)
            self:SetBackdropBorderColor(0,0,0,0)
        else
            self:SetBackdropColor(0.025,0.03,0.04,0.93)
            self:SetBackdropBorderColor(0.45,0.36,0.12,0.85)
        end

        local function style(fs)
            if not fs or not fs.GetFont then return end
            local file,size = fs:GetFont()
            if not file then return end
            fs:SetFont(file, size, transparent and 'OUTLINE' or '')
            fs:SetShadowColor(0,0,0, transparent and 1 or 0.7)
            fs:SetShadowOffset(1,-1)
        end
        style(self._title); style(self._result)
        for i=1,MAX_LINES do style(self._lines[i]) end
        return transparent
    end

    function f:RestoreBlizzardTracker()
        local state=self._blizzardState
        if not state or not state.frame then return end
        pcall(state.frame.SetAlpha,state.frame,state.alpha or 1)
        if state.mouse ~= nil and state.frame.EnableMouse then pcall(state.frame.EnableMouse,state.frame,state.mouse) end
        self._blizzardState=nil
    end

    function f:SuppressBlizzardTracker(frame)
        if not frame then self:RestoreBlizzardTracker();return false end
        if self._blizzardState and self._blizzardState.frame ~= frame then self:RestoreBlizzardTracker() end
        if not self._blizzardState then
            local alpha=frame.GetAlpha and frame:GetAlpha() or 1
            local mouse=frame.IsMouseEnabled and frame:IsMouseEnabled() or nil
            self._blizzardState={frame=frame,alpha=alpha,mouse=mouse}
        end
        local ok=pcall(frame.SetAlpha,frame,0)
        if ok and frame.EnableMouse then pcall(frame.EnableMouse,frame,false) end
        return ok
    end

    function f:Reanchor(force)
        -- Mientras el usuario arrastra, no tocamos la posicion: el ticker
        -- llamaria a Reanchor 2 veces por segundo y le arrancaria el frame
        -- de las manos.
        if self._dragging then return end

        local st = settings()
        local anchorToBlizzard = not st or st.coachAnchorBlizzard ~= false
        local scale=self:ApplyScale()
        self:ApplyMouse()
        self:ApplyBackground()

        if not anchorToBlizzard then
            -- El usuario puede soltar el anclaje mientras REPLACE esta activo.
            -- Restaurar antes de entrar al modo libre evita dejar oculto el
            -- bloque oficial por una salida temprana de esta funcion.
            self:RestoreBlizzardTracker()
            if force or self._anchorKey ~= "FREE" then
                self:ClearAllPoints()
                local profile = MitzuMPlus.db and MitzuMPlus.db.profile
                local pos = profile and profile.overlayPosition
                if pos and pos.point and pos.x and pos.y then
                    self:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                    self._anchorName = "libre (posición guardada)"
                else
                    self:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-40,-260)
                    self._anchorName = "libre (por defecto)"
                end
                self._anchorKey = "FREE"
            end
            return
        end

        local t, name = trackerFrame()
        if not t then
            -- Edit Mode y las transiciones de Scenario pueden destruir u
            -- ocultar temporalmente el bloque. Nunca conservamos una
            -- supresion de Blizzard si ya no tenemos un ancla valida.
            self:RestoreBlizzardTracker()
            if force or self._anchorKey ~= "FALLBACK" then
                self:ClearAllPoints()
                self:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-40,-260)
                self._anchorKey = "FALLBACK"
                self._anchorName = "UIParent fallback"
            end
            return
        end

        -- ═════════════════════════════════════════════════════════════════
        -- v7.7.0 — el tracker nativo se oculta en LOS DOS modos.
        --
        -- Antes solo lo ocultaba REPLACE; COMPLEMENT lo dejaba visible al lado,
        -- que era el sentido original del nombre. Por peticion expresa, ahora
        -- ambos lo suprimen: el Coach ya muestra tiempo, fuerzas y jefes, asi
        -- que tener las dos cosas en pantalla era informacion duplicada.
        --
        -- Se suprime con SetAlpha(0) + EnableMouse(false), NO con :Hide().
        -- Hide() sobre los frames de Blizzard pelea con su propia logica de
        -- mostrado y es la via rapida a un error de accion prohibida — el mismo
        -- tipo de fallo que ya dio UnregisterEvent en el EventTracker.
        -- ═════════════════════════════════════════════════════════════════
        local mode = displayMode()
        local suppress = (mode == 'REPLACE' or mode == 'COMPLEMENT') and not self._preview
            and _G.MitzuMPlusCurrentRun ~= nil and keyIsActive()
            and name == "ScenarioObjectiveTracker.ChallengeModeBlock"
        local canReplace = suppress and mode == 'REPLACE'

        -- Si se oculta el nativo, el Coach OCUPA SU SITIO en los dos modos.
        -- Anclarlo al lado de un frame invisible dejaria un hueco donde antes
        -- estaba el tracker, que es peor que no ocultarlo.
        if suppress then
            if not self:SuppressBlizzardTracker(t) then return end
            local key=tostring(t).."|"..mode
            if force or self._anchorKey~=key then
                self:ClearAllPoints();self:SetPoint('TOPRIGHT',t,'TOPRIGHT',0,0)
                self._anchorKey=key
                self._anchorName=name.." ("..(canReplace and "reemplazado" or "sustituido")..")"
            end
            return
        end
        self:RestoreBlizzardTracker()

        -- Anchor BESIDE the official M+ tracker instead of below the complete
        -- ObjectiveTrackerFrame. The latter also contains quests/campaigns and
        -- could push the coach off-screen (or make it overlap those objectives).
        -- Pick the side dynamically so Edit Mode layouts on either side still work.
        local targetLeft = t.GetLeft and t:GetLeft() or nil
        local targetRight = t.GetRight and t:GetRight() or nil
        local screenWidth = UIParent.GetWidth and UIParent:GetWidth() or 1920
        -- GetWidth() devuelve el ancho SIN escalar; targetLeft/Right vienen en
        -- unidades de pantalla. Sin convertir, la eleccion de lado fallaba en
        -- cuanto se tocaba la escala.
        local panelWidth = (self:GetWidth() or 360) * (scale or 1)
        local gap = 8
        local side = "LEFT"

        if targetLeft and targetLeft < (panelWidth + 20) and targetRight and (screenWidth - targetRight) >= (panelWidth + 20) then
            side = "RIGHT"
        end

        local key = tostring(t) .. "|" .. side
        if force or self._anchorKey ~= key then
            self:ClearAllPoints()
            if side == "RIGHT" then
                self:SetPoint('TOPLEFT',t,'TOPRIGHT',gap,0)
            else
                self:SetPoint('TOPRIGHT',t,'TOPLEFT',-gap,0)
            end
            self._anchorKey = key
            self._anchorName = name .. " (" .. side .. ")"
        end
    end

    -- Pinta la lista de lineas y ajusta la altura del frame al numero real.
    -- Una entrada de `lines` puede ser texto {texto,color} o barra
    -- {texto,color,bar=pct}. La barra ocupa la ranura entera y lleva su propio
    -- texto centrado encima, como las barras de escenario de Blizzard.
    function f:_Paint(lines)
        local n=math.min(#lines, MAX_LINES)
        for i=1,MAX_LINES do
            local fs=self._lines[i]
            local bar=self._bars[i]
            local L=(i<=n) and lines[i] or nil

            if L and L.bar then
                fs:SetText(''); fs:Hide()
                local pct=math.max(0,math.min(100,tonumber(L.bar) or 0))
                bar:SetValue(pct)
                local c=L[2] or {0.35,1.00,0.45}
                bar:SetStatusBarColor(c[1],c[2],c[3],1)
                bar._text:SetText(L[1] or '')
                bar:Show()
            elseif L then
                bar:Hide()
                setText(fs, L[1], L[2])
                fs:Show()
            else
                bar:Hide()
                fs:SetText(''); fs:Hide()
            end
        end
        local h = TOP_PAD + n*LINE_HEIGHT + BOTTOM_PAD
        if self._appliedHeight ~= h then
            self:SetHeight(h)
            self._appliedHeight = h
        end
    end

    function f:Refresh()
        local st=settings()
        if st and st.overlayEnabled==false then self:RestoreBlizzardTracker();self:Hide(); return end

        local run=_G.MitzuMPlusCurrentRun
        local live=(run~=nil) and (MitzuMPlus.PredictionEngine~=nil) and keyIsActive()
        local C=palette()
        local mode=displayMode()
        if self._appliedMode~=mode then
            self._appliedMode=mode;self._anchorKey=nil
            self:SetWidth(mode=='REPLACE' and 390 or (mode=='COMPACT' and 330 or 360))
            self:ApplyBackground(true)
        end
        setText(self._title,'MITZUMPLUS COACH',C.title)

        -- La preview jamas debe sobrevivir al arranque de una key real.
        if self._preview and live then self._preview=false end

        -- La previa ya NO devuelve aqui: rellena datos de ejemplo y sigue por
        -- el camino normal, para que lo que se ve sea lo que habra en la llave.
        local previewing = self._preview == true
        if previewing then
            setText(self._title,'MITZUMPLUS COACH · PRUEBA',C.title)
        end

        if not previewing and not live then self:RestoreBlizzardTracker();self:Hide(); return end

        local s
        if previewing then
            s = fakeSnapshot()
        else
            s = MitzuMPlus.PredictionEngine:GetSnapshot(run)
        end
        if not s then self:RestoreBlizzardTracker();self:Hide(); return end

        local official
        if previewing then
            official = fakeOfficial(s)
        else
            official = MitzuMPlus.KeystoneTracker and MitzuMPlus.KeystoneTracker.GetOfficialSnapshot
                and MitzuMPlus.KeystoneTracker:GetOfficialSnapshot() or nil
        end
        self:Reanchor()
        self:Show()

        local lines={}
        local function add(text,color)
            -- Acepta add('texto',color) o add({texto,color,bar=pct}).
            if type(text)=='table' then lines[#lines+1]=text
            else lines[#lines+1]={text,color} end
        end

        local function priorityAdvice()
            if (s.timeRemaining or 9999)<=120 then return 'PRIORIDAD: quedan menos de 2 minutos',C.bad end
            if s.deathBudget and s.deathBudget<=1 then return 'PRIORIDAD: casi sin margen para otra muerte',C.bad end
            if s.pacePct and s.neededPct and s.pacePct<s.neededPct then
                return string.format('PRIORIDAD: acelera fuerzas (faltan %.1f%%/min)',s.neededPct-s.pacePct),C.warn
            end
            if (s.bossesDone or 0)<(s.bossesTotal or 0) then return 'PRIORIDAD: siguiente boss y supervivencia',C.info end
            return 'PRIORIDAD: completa fuerzas sin asumir riesgos',C.good
        end

        if mode=='COMPACT' then
            local rc=C.warn;if s.result=='+3' or s.result=='+2' then rc=C.good elseif s.result=='FUERA' then rc=C.bad end
            setText(self._result,s.result or '—',rc)
            add(string.format('Tiempo %s   |   quedan %s',fmt(s.elapsed),fmt(s.timeRemaining or 0)),C.main)
            add(string.format('Fuerzas %.2f%%   |   jefes %d/%d',s.enemyPct or 0,s.bossesDone or 0,s.bossesTotal or 0),C.main)
            add(string.format('Muertes %d   |   penalización %s',s.deaths or 0,fmt(s.deathTimeLost or 0)),C.dim)
            local advice,ac=priorityAdvice();add(advice,ac)
            self:_Paint(lines);return
        elseif mode=='REPLACE' and official then
            setText(self._title,string.format('%s  +%d',official.dungeonName~='' and official.dungeonName or 'MYTHIC+',official.keyLevel or 0),C.title)
            local left=math.max(0,(official.timeLimit or 0)-(official.elapsed or 0)-(official.deathTimeLost or 0))
            setText(self._result,fmt(left),left<=120 and C.bad or (left<=300 and C.warn or C.info))
            add(string.format('Tiempo  %s / %s   |   quedan %s',fmt(official.elapsed),fmt(official.timeLimit),fmt(left)),C.main)
            local timePct=(official.timeLimit or 0)>0 and ((official.elapsed+official.deathTimeLost)/official.timeLimit*100) or 0
            add({string.format('Reloj  %.0f%%',timePct),
                 timePct>=100 and C.bad or C.info, bar=timePct})
            add(string.format('Umbrales  +3 %s   |   +2 %s',fmt(official.plus3Time),fmt(official.plus2Time)),C.dim)
            local count=''
            if (official.enemyTotal or 0)>0 then count=string.format('   |   %d/%d',official.enemyCurrent or 0,official.enemyTotal) end
            add(string.format('Fuerzas  %.2f%%%s',official.enemyPct or 0,count),C.main)
            add({string.format('Fuerzas  %.2f%%',official.enemyPct or 0),
                 (official.enemyPct or 0)>=100 and C.good or C.main,
                 bar=official.enemyPct or 0})
            for _,boss in ipairs(official.bosses or {}) do
                add(string.format('[%s] %s',boss.completed and 'OK' or '  ',boss.name or 'Boss'),boss.completed and C.good or C.none)
            end
            add(string.format('Muertes  %d   |   penalización %s',official.deaths or 0,fmt(official.deathTimeLost or 0)),C.dim)
            if s.result and s.projectedTime then
                add(string.format('Coach  %s proyectado   |   margen %s',s.result,signed(s.margin or 0)),s.result=='FUERA' and C.bad or C.info)
            else add('Coach  sin progreso suficiente para proyectar',C.none) end
            local advice,ac=priorityAdvice();add(advice,ac)
            self:_Paint(lines);return
        end

        -- ═══════════════════════════════════════════════════════════════
        -- MODO APRENDIENDO
        --
        -- Se lidera con la accion, no con el dato. Cada numero viene con su
        -- referencia ("de 100% que necesitas") porque un numero suelto solo
        -- informa a quien ya sabe cual es el bueno.
        --
        -- Sin tooltips a proposito: el Coach no debe capturar el raton durante
        -- una llave (ya hubo un bug de clics interceptados), asi que la
        -- explicacion va DENTRO de la linea en vez de al pasar por encima.
        -- ═══════════════════════════════════════════════════════════════
        if uiLevel()=='LEARN' then
            local adv,advColor=priorityAdvice()
            add(adv:gsub('^PRIORIDAD: ','→ '),advColor)

            if s.hasBasis and s.result then
                local rc=C.warn
                if s.result=='+3' or s.result=='+2' then rc=C.good elseif s.result=='FUERA' then rc=C.bad end
                setText(self._result,s.result,rc)
                if s.result=='FUERA' then
                    add(string.format('Vas FUERA de tiempo por %s',fmt(math.abs(s.margin or 0))),C.bad)
                else
                    add(string.format('Vas para %s · te sobran %s',s.result,fmt(math.abs(s.margin or 0))),rc)
                end
                if s.confidence and s.confidence<50 then
                    add('  (aún es pronto, esto puede cambiar)',C.dim)
                end
            else
                setText(self._result,'—',C.none)
                add('Aún no hay datos para saber cómo vas',C.none)
            end

            add(string.format('Fuerzas  %.1f%% de 100%% que necesitas',s.enemyPct or 0),
                (s.enemyPct or 0)>=100 and C.good or C.main)
            add({'', (s.enemyPct or 0)>=100 and C.good or C.main, bar=s.enemyPct or 0})
            add(string.format('Jefes  %d de %d',s.bossesDone or 0,s.bossesTotal or 0),
                (s.bossesDone or 0)>=(s.bossesTotal or 0) and C.good or C.main)

            local left=s.timeRemaining or 0
            local lc=C.info
            if left<=120 then lc=C.bad elseif left<=300 then lc=C.warn end
            add(string.format('Quedan  %s de %s',fmt(left),fmt(s.timeLimit or 0)),lc)

            if (s.deaths or 0)>0 then
                -- En Aprendiendo se dice el coste TOTAL (penalizacion + vuelta),
                -- que es lo que un novato nota y no sabe atribuir.
                local cost = (s.deathTimeLost or 0) + (s.deathDowntime or 0)
                add(string.format('Muertes  %d · os han costado %s',s.deaths,fmt(cost)),C.dim)
            end

            self:_Paint(lines)
            return
        end

        -- Sin base para proyectar no se muestra un resultado inventado.
        if not s.hasBasis or not s.result then
            setText(self._result,'—',C.none)
            add('Proyección  —   |   sin progreso suficiente', C.none)
        else
            local rc=C.warn
            if s.result=='+3' or s.result=='+2' then rc=C.good elseif s.result=='FUERA' then rc=C.bad end
            setText(self._result,s.result,rc)
            add(string.format('Proyección  %s   |   margen %s',fmt(s.projectedTime),signed(s.margin)), C.main)
        end

        -- Fuerzas ACTUALES. Antes solo se veia el % del siguiente pull, asi que
        -- era imposible comprobar de un vistazo si el addon estaba leyendo bien
        -- Enemy Forces contra el tracker de Blizzard.
        add(string.format('Fuerzas  %.2f%%   |   jefes %d/%d',s.enemyPct or 0,s.bossesDone,s.bossesTotal), C.main)
        -- Barra real con la textura de Blizzard. Con el tracker nativo oculto,
        -- sin ella se perdia la unica lectura visual del progreso de fuerzas.
        add({string.format('%.2f%% de 100%%',s.enemyPct or 0),
             (s.enemyPct or 0)>=100 and C.good or C.main,
             bar=s.enemyPct or 0})

        -- 'AUTO'/'RUTA' no significaban nada para quien no escribio el codigo.
        local source=s.routeMode=='route' and 'de la ruta' or 'estimado'
        add(string.format('Quedan  ~%d packs   |   el siguiente ~%.1f%% (%s)',s.pullsLeft,s.nextPullPct,source), C.main)

        -- ── Ritmo (opcional) ─────────────────────────────────────────────
        -- Es la lectura mas accionable que existe en directo: si el ritmo real
        -- va por debajo del necesario, hay que acelerar AHORA, no al final.
        if opt('coachShowPace', true) then
            if s.pacePct and s.neededPct then
                local pc = (s.pacePct >= s.neededPct) and C.good or C.bad
                add(string.format('Ritmo  %.1f%%/min   |   necesario  %.1f%%/min', s.pacePct, s.neededPct), pc)
            elseif s.pacePct then
                add(string.format('Ritmo  %.1f%%/min   |   necesario  —', s.pacePct), C.info)
            end
        end

        -- ── Reloj (opcional) ─────────────────────────────────────────────
        if opt('coachShowClock', true) and (s.timeLimit or 0) > 0 then
            local left = s.timeRemaining or 0
            local lc = C.info
            if left <= 120 then lc = C.bad elseif left <= 300 then lc = C.warn end
            add(string.format('Tiempo  %s / %s   |   quedan  %s', fmt(s.elapsed), fmt(s.timeLimit), fmt(left)), lc)
        end

        -- ── Muertes + confianza ──────────────────────────────────────────
        -- Antes decia solo 'Confianza 85%': confianza EN QUE, no se sabia.
        local conf = s.confidence and string.format('Fiabilidad proyección %d%%',s.confidence) or 'Fiabilidad —'
        -- Se enseña la penalizacion oficial Y lo que cuesta de verdad cada
        -- muerte (penalizacion + carrera de vuelta medida), porque son cosas
        -- distintas y la segunda es la que decide la llave.
        local deathTxt = string.format('Muertes %d (%s)', s.deaths, fmt(s.deathTimeLost))
        if s.realPerDeath and s.realPerDeath > 0 then
            deathTxt = string.format('Muertes %d · %s cada una', s.deaths, fmt(s.realPerDeath))
        end
        if opt('coachShowDeathBudget', true) and s.deathBudget then
            deathTxt = deathTxt .. string.format('  margen %d', s.deathBudget)
        end
        add(conf..'   |   '..deathTxt, C.dim)

        -- ── Personal Best (sin flechas Unicode: el cliente no las dibuja) ─
        if s.pbDelta then
            local tag = s.pbDelta>=0 and 'por delante' or 'por detrás'
            local pc  = s.pbDelta>=0 and C.good or C.bad
            -- "por detras del PB por 0:55" salia de encadenar dos plantillas.
            add(string.format('PB %s   |   %s %s del récord',
                fmt(s.pbTime or 0), fmt(math.abs(s.pbDelta)), tag), pc)
        end

        self:_Paint(lines)
    end

    f:Hide(); f:ApplyBackground(true); f:Reanchor(true); self.OverlayFrame=f
    return f
end

-- Driver externo. Un frame oculto no recibe OnUpdate, asi que el overlay no
-- puede ser responsable de despertarse a si mismo. El ticker solo vive mientras
-- hay una run activa o una preview explicita, y se apaga solo.
function MitzuMPlus:_StartOverlayDriver()
    if self._overlayTicker then return end
    if not (C_Timer and C_Timer.NewTicker) then return end
    self._overlayTicker=C_Timer.NewTicker(UPDATE,function()
        local f=MitzuMPlus.OverlayFrame
        if not f then MitzuMPlus:_StopOverlayDriver(); return end
        if not f._preview and not _G.MitzuMPlusCurrentRun then
            if f.RestoreBlizzardTracker then f:RestoreBlizzardTracker() end
            f:Hide(); MitzuMPlus:_StopOverlayDriver(); return
        end
        f:Refresh()
    end)
end

function MitzuMPlus:_StopOverlayDriver()
    if self._overlayTicker then
        if self._overlayTicker.Cancel then self._overlayTicker:Cancel() end
        self._overlayTicker=nil
    end
end

function MitzuMPlus:GetOverlayAnchorStatus()
    if not self.OverlayFrame then self:InitOverlay() end
    local f=self.OverlayFrame
    if f then f:Reanchor(true) end
    return f and (f._anchorName or "sin resolver") or "overlay no disponible"
end

-- Reaplica fondo/contorno al vuelo cuando se cambia el ajuste en Configuración.
function MitzuMPlus:RefreshOverlayStyle()
    local f=self.OverlayFrame
    if not f then return end
    f:ApplyBackground(true)
    if f:IsShown() then f:Refresh() end
end

function MitzuMPlus:ShowOverlayPreview()
    if not self.OverlayFrame then self:InitOverlay() end
    local f=self.OverlayFrame; if not f then return end
    f._preview=true
    self:_StartOverlayDriver()
    f:Reanchor(true)
    f:Show()
    f:Refresh()
end

-- Muestra el Coach REAL. Ya no cae en preview cuando la key aun no ha
-- arrancado: arranca el driver y Refresh() lo mostrara en cuanto
-- IsChallengeModeActive() sea true. Los llamantes que quieran la vista de
-- prueba deben pedir ShowOverlayPreview() explicitamente.
function MitzuMPlus:ShowOverlay()
    if not self.OverlayFrame then self:InitOverlay() end
    local f=self.OverlayFrame; if not f then return end
    f._preview=false
    self:_StartOverlayDriver()
    f:Reanchor(true)
    f:Refresh()
end

function MitzuMPlus:HideOverlay()
    self:_StopOverlayDriver()
    if self.OverlayFrame then
        self.OverlayFrame._preview=false
        if self.OverlayFrame.RestoreBlizzardTracker then self.OverlayFrame:RestoreBlizzardTracker() end
        self.OverlayFrame:Hide()
    end
end

function MitzuMPlus:ToggleOverlay()
    if not self.OverlayFrame then self:InitOverlay() end
    local f=self.OverlayFrame; if not f then return end
    if f:IsShown() then
        self:HideOverlay()
    elseif _G.MitzuMPlusCurrentRun and keyIsActive() then
        self:ShowOverlay()
    else
        self:ShowOverlayPreview()
    end
end
