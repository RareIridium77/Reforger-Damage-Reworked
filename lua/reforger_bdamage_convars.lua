if SERVER and Reforger then
    Reforger.CreateConvar("gibs.keep", "1", "Keep vehicle gibs in your map (server)", 0, 1)
    Reforger.CreateConvar("gibs.freeze", "0", "Freeze vehicle gibs (ONLY LVS)", 0, 1) -- ONLY LVS LVS LVS LVS LVS LVS LVS
    Reforger.CreateConvar("gibs.delay", "30", "Delay to remove gibs (ONLY LVS)", 1, 120) -- ONLY LVS LVS LVS LVS LVS LVS LVS

    Reforger.CreateConvar("damage.mine.multiplier", "0.25", "1 - means full damage less value - less damage (server)", 0.01, 5)
    Reforger.CreateConvar("damage.mine.max", "100", "Maximum damage for mines (server)", 1, 99999)
    Reforger.CreateConvar("damage.mine.min", "1", "Minimum damage for mines (server)", 1, 99999)
end