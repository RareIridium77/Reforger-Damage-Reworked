
-- Convars
AddCSLuaFile("reforger_bdamage_convars.lua")
include("reforger_bdamage_convars.lua")

if CLIENT then return end -- I'am overthinker

-- After Reforger will Initialized addon starts working

local function Reforger_CheckPlayerFramework(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end

        if not istable(_G.Reforger) then
            ply:ChatPrint("[Reforger] Required Reforger Framework is missing. Please install it here: https://steamcommunity.com/sharedfiles/filedetails/?id=3516478641")

            timer.Simple(4, function() ply:SendLua([[ gui.OpenURL("https://steamcommunity.com/sharedfiles/filedetails/?id=3516478641") ]]) end)
        end
    end)
end
hook.Add("PlayerInitialSpawn", "Reforger.CheckPlayerFramework", Reforger_CheckPlayerFramework)

local function Reforger_DamageModule()
    if Reforger.Disabled == true then return end

    local bases = { "lvs", "glide", "simfphys" }
    local template = "reforger_#_damage_rewrote.lua"

    for _, b in ipairs(bases) do
        local path = string.Replace(template, "#", b)
        local exists = file.Exists(path, "LUA")

        if not exists then
            Reforger.DevLog("[WARN] File not found: " .. path)
            continue
        end

        local ok, funcs = pcall(include, path)

        if not ok then
            Reforger.DevLog("[ERROR] Failed to include " .. path .. ": " .. tostring(funcs))
            continue
        end

        if istable(funcs) and isfunction(funcs[1]) then
            Reforger.AddEntityFunction(b .. "_RewroteDamage", funcs[1])
            Reforger.DevLog("[Reforger] Damage hook loaded: " .. b)
        else
            Reforger.DevLog("[WARN] Invalid return from " .. path .. ", expected table with function at index 1")
        end
    end
end

if not Reforger or Reforger.Disabled == true then return end

local function IsPlayerBurning(ply)
    return Reforger.GetNetworkValue(ply, "Bool", "IsBurning")
end

local function SetPlayerBurning(ply, state)
    Reforger.SetNetworkValue(ply, "Bool", "IsBurning", state)
end

local function Reforger_PlayerBurningModule(ply, veh)
    if not IsValid(ply) then return end
    if not IsValid(veh) then return end

    local alreadyBurning = IsPlayerBurning(ply)

    if not alreadyBurning and veh:IsOnFire() then
        SetPlayerBurning(ply, true)
        Reforger.DevLog("Player " .. ply:Nick() .. " started to burn")
    end
end

local function Reforger_ResetBurnStatus(ply, veh)
    if not IsValid(ply) then return end

    if IsPlayerBurning(ply) then
        SetPlayerBurning(ply, false)
        Reforger.DevLog("Player " .. ply:Nick() .. " stopped burning")
    end
end

local function Reforger_FreezedGibsPickup(ply, ent)
    if ent.reforgerGib then
        return false
    end
end

hook.Add("Reforger.Init", "Reforger.DamageModule", Reforger_DamageModule)
hook.Add("Reforger.PlayerBurningInVehicle", "Reforger.PlayerBurningModule", Reforger_PlayerBurningModule)
hook.Add("PlayerLeaveVehicle", "Reforger.ResetBurnStatus", Reforger_ResetBurnStatus)
hook.Add("PlayerSpawn", "Reforger.ResetBurnStatusOnRespawn", Reforger_ResetBurnStatus)
hook.Add("PhysgunPickup", "Reforger.FreezedGibsPickup", Reforger_FreezedGibsPickup)