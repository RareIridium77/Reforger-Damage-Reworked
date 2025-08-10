if CLIENT then return end -- This file is for server-side only

local devlog = Reforger.DevLog
local addmodule = Reforger.AddEntityModule
local rafunc    = function(idf, func)
    addmodule(Reforger, idf, func)
end
local gnwval = Reforger.GetNetworkValue
local snwval = Reforger.SetNetworkValue

local pcall = pcall
local istable = istable
local ipairs = ipairs
local isfunction = isfunction
local stringReplace = string.Replace
local fileExists = file.Exists
local timerSimple = timer.Simple
local IsValid = IsValid
local addhook = hook.Add

local function Reforger_CheckPlayerFramework(ply)
    timerSimple(1, function()
        if not IsValid(ply) then return end

        if not istable(_G.Reforger) then
            ply:ChatPrint("[Reforger] Required Reforger Framework is missing. Please install it here: https://steamcommunity.com/sharedfiles/filedetails/?id=3516478641")
        end
    end)
end
addhook("PlayerInitialSpawn", "Reforger.CheckPlayerFramework", Reforger_CheckPlayerFramework)

local function Reforger_DamageModule()
    if Reforger.Disabled == true then return end

    local bases = { "lvs", "glide", "simfphys" }
    local template = "reforger_#_damage_rewrote.lua"

    for _, b in ipairs(bases) do
        local path = stringReplace(template, "#", b)
        local exists = fileExists(path, "LUA")

        if not exists then
            devlog("[WARN] File not found: " .. path)
            continue
        end

        local ok, funcs = pcall(include, path)

        if not ok then
            devlog("[ERROR] Failed to include " .. path .. ": " .. tostring(funcs))
            continue
        end

        if not istable(funcs) or not isfunction(funcs[1]) then
            devlog("[WARN] Invalid return from " .. path .. ", expected table with function at index 1")
            continue
        end

        if istable(funcs) and isfunction(funcs[1]) then
            rafunc(b .. "_RewroteDamage", funcs[1])
            devlog("[Reforger] Damage hook loaded: " .. b)
        end
    end
end

if not Reforger or Reforger.Disabled == true then return end

local function IsPlayerBurning(ply)
    return gnwval(ply, "Bool", "IsBurning")
end

local function SetPlayerBurning(ply, state)
    snwval(ply, "Bool", "IsBurning", state)
end

local function Reforger_PlayerBurningModule(ply, veh)
    if not IsValid(ply) then return end
    if not IsValid(veh) then return end

    local alreadyBurning = IsPlayerBurning(ply)

    if not alreadyBurning and veh:IsOnFire() then
        SetPlayerBurning(ply, true)
        devlog("Player " .. ply:Nick() .. " started to burn")
    end
end

local function Reforger_ResetBurnStatus(ply)
    if not IsValid(ply) then return end

    if IsPlayerBurning(ply) then
        SetPlayerBurning(ply, false)
        devlog("Player " .. ply:Nick() .. " stopped burning")
    end
end

local function Reforger_FreezedGibsPickup(ply, ent)
    -- Prevent picking up reforger gibs
    if ent.reforgerGib then
        return false
    end
end

addhook("Reforger.Init", "Reforger.DamageModule", Reforger_DamageModule)
addhook("Reforger.PlayerBurningInVehicle", "Reforger.PlayerBurningModule", Reforger_PlayerBurningModule)
addhook("PlayerLeaveVehicle", "Reforger.ResetBurnStatus", Reforger_ResetBurnStatus)
addhook("PlayerSpawn", "Reforger.ResetBurnStatusOnRespawn", Reforger_ResetBurnStatus)
addhook("PhysgunPickup", "Reforger.FreezedGibsPickup", Reforger_FreezedGibsPickup)