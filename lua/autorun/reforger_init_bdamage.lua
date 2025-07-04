if CLIENT then return end -- I'am overthinker


-- After Reforger will Initialized addon starts working

hook.Add("Reforger.Init", "Reforger.DamageModule", function()
    if not istable(rawget(_G, "Reforger")) or not rawget(_G, "Reforger") then error("Reforger Base was not installed!") end

    local bases = { "lvs", "glide", "simfphys" }
    local template = "reforger_#_damage_rewrote.lua"

    for _, b in ipairs(bases) do
        local funcs = include( string.Replace(template, "#", b) )
        local rewrite = funcs[1]
        Reforger.DevLog(string.Replace(template, "#", b).." iuncluded")
        Reforger.AddEntityFunction(b.."_RewroteDamage", rewrite)
    end
end)

hook.Add("Reforger.PlayerBurningInVehicle", "Reforger.PlayerBurningModule", function(ply, veh)
    if not IsValid(ply) then return end
    if not IsValid(veh) then return end

    local alreadyBurning = ply:GetNWBool("Reforger.IsBurning", false)

    if not alreadyBurning and veh:IsOnFire() then
        ply:SetNWBool("Reforger.IsBurning", true)
        Reforger.DevLog("Player " .. ply:Nick() .. " started to burn")
    end
end)

hook.Add("PlayerLeaveVehicle", "Reforger.ResetBurnStatus", function(ply, veh)
    if not IsValid(ply) then return end

    if ply:GetNWBool("Reforger.IsBurning", false) then
        ply:SetNWBool("Reforger.IsBurning", false)
        Reforger.DevLog("Player " .. ply:Nick() .. " stopped burning")
    end
end)

hook.Add("PlayerSpawn", "Reforger.ResetBurnStatusOnRespawn", function(ply)
    if not IsValid(ply) then return end
    ply:SetNWBool("Reforger.IsBurning", false)
end)