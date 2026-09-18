-- Experimental Mythic+ lab localization. English is the base/default locale.
-- Separate AceLocale namespace avoids reopening the production locale table.
local L = LibStub("AceLocale-3.0"):NewLocale("MitzuMPlusExperimental", "enUS", true)
if not L then return end

L["LFG_NEEDS_PREFIX"] = "Party needs"
L["LFG_COVERAGE_READY"] = "Core coverage ready"
L["LFG_NEED_TANK"] = "Tank"
L["LFG_NEED_HEALER"] = "Healer"
L["LFG_NEED_LUST"] = "Bloodlust"
L["LFG_NEED_BREZ"] = "Battle rez"
L["LFG_NEED_DPS_N"] = "DPS x%d"
