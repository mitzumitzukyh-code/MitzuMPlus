-- ═══════════════════════════════════════════════════════════════════════════
-- MitzuMPlus M+ Historial - EventBus
-- Sistema de eventos para comunicación entre módulos
-- ═══════════════════════════════════════════════════════════════════════════

local ADDON_NAME = "MitzuMPlus_Historial"
local MitzuMPlus = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)

local EventBus = {}
MitzuMPlus.EventBus = EventBus
EventBus._handlers = {}

function EventBus:On(event, handler, priority)
    if type(event) ~= "string" or type(handler) ~= "function" then return end
    
    if not self._handlers[event] then
        self._handlers[event] = {}
    end
    
    self._handlers[event][#self._handlers[event] + 1] = {
        fn = handler,
        priority = priority or 50
    }
    
    table.sort(self._handlers[event], function(a, b)
        return a.priority > b.priority
    end)
end

function EventBus:Off(event, handler)
    if not self._handlers[event] then return end
    
    for i = #self._handlers[event], 1, -1 do
        if self._handlers[event][i].fn == handler then
            table.remove(self._handlers[event], i)
        end
    end
end

function EventBus:Emit(event, ...)
    local handlers = self._handlers[event]
    if not handlers then return end
    
    for _, h in ipairs(handlers) do
        local ok, err = pcall(h.fn, ...)
        if not ok then
            if MitzuMPlus and MitzuMPlus.Print then
                MitzuMPlus:Print(string.format("|cFFFF0000[MitzuMPlus EventBus Error]|r %s: %s", tostring(event), tostring(err)))
            end
        end
    end
end

function EventBus:Clear(event)
    if event then
        self._handlers[event] = nil
    else
        self._handlers = {}
    end
end

-- FIX: MitzuMPlus.EventBus ya fue asignado en la línea 10 al declarar la tabla.
-- La segunda asignación era redundante. Solo se conserva el alias global.
_G.MitzuMPlusEventBus = EventBus
