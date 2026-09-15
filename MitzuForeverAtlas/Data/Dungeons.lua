MitzuForeverAtlas = MitzuForeverAtlas or {}

-- Official dungeon names announced by Blizzard for World of Warcraft: Forever.
-- Runtime IDs, bosses, maps, loot tables, and encounter metadata are intentionally
-- left unset until verified in the beta client.
MitzuForeverAtlas.Dungeons = {
    { key = "hall_of_thanes",       name = "Hall of Thanes",       status = "AWAITING_BETA_DATA" },
    { key = "ruins_of_lordaeron",   name = "Ruins of Lordaeron",   status = "AWAITING_BETA_DATA" },
    { key = "whelgars_excavation",  name = "Whelgar's Excavation", status = "AWAITING_BETA_DATA" },
    { key = "city_of_dalaran",      name = "City of Dalaran",      status = "AWAITING_BETA_DATA" },
    { key = "blackmaw_hold",        name = "Blackmaw Hold",        status = "AWAITING_BETA_DATA" },
    { key = "drowned_city",         name = "Drowned City",         status = "AWAITING_BETA_DATA" },
    { key = "kroldok_stronghold",   name = "Krol'dok Stronghold",  status = "AWAITING_BETA_DATA" },
    { key = "alcaz_prison",         name = "Alcaz Prison",         status = "AWAITING_BETA_DATA" },
    { key = "shapers_terrace",      name = "Shaper's Terrace",     status = "AWAITING_BETA_DATA" },
}

function MitzuForeverAtlas:GetDungeonByKey(key)
    for _, dungeon in ipairs(self.Dungeons) do
        if dungeon.key == key then
            return dungeon
        end
    end
end
