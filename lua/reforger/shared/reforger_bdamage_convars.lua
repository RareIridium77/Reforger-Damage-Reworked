if SERVER and Reforger then
    local createCvar = Reforger.CreateConvar
    createCvar("gibs.keep", "1", "Keep vehicle gibs in your map (server)", 0, 1)
    createCvar("gibs.freeze", "0", "Freeze vehicle gibs (ONLY LVS)", 0, 1) -- ONLY LVS LVS LVS LVS LVS LVS LVS
    createCvar("gibs.delay", "30", "Delay to remove gibs (ONLY LVS)", 1, 120) -- ONLY LVS LVS LVS LVS LVS LVS LVS

    createCvar("damage.mine.multiplier", "0.25", "1 - means full damage less value - less damage (server)", 0.01, 5)
    createCvar("damage.mine.max", "100", "Maximum damage for mines (server)", 1, 99999)
    createCvar("damage.mine.min", "1", "Minimum damage for mines (server)", 1, 99999)

    createCvar("damage.chance.innerfire", "0.5", "Enhance damage from inner fire (ONLY LVS)", 0, 1) -- ONLY LVS LVS LVS LVS LVS LVS LVS
    createCvar("damage.chance.explode.armored", "0.5", "Chance to explode armored vehicles (ONLY LVS)", 0, 1) -- ONLY LVS LVS LVS LVS LVS LVS LVS
    createCvar("damage.chance.explode.unarmored", "0.5", "Chance to explode unarmored vehicles (ONLY LVS)", 0, 1) -- ONLY LVS LVS LVS LVS LVS LVS LVS
end