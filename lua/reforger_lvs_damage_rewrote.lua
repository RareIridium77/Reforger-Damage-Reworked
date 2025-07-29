if not LVS then return end

local RDamage = Reforger.Damage
local Rotors = Reforger.Rotors
local Armored = Reforger.Armored

local getvehtype = Reforger.GetVehicleType

local gnwval = Reforger.GetNetworkValue
local snwval = Reforger.SetNetworkValue

local ignitelimited = RDamage.IgniteLimited
local stopignitelimited = RDamage.StopLimitedFire

local isfiredamage = RDamage.IsFireDamageType
local issmalldamage = RDamage.IsSmallDamageType
local ismeleedamage = RDamage.IsMeleeDamageType
local iscollisiondamage = RDamage.IsCollisionDamageType

local applyPlayersDamage = RDamage.ApplyPlayersDamage
local handleRayDamage = RDamage.HandleRayDamage
local damageParts = RDamage.DamageParts
local fixDamageForce = RDamage.FixDamageForce

local damageAmmoracks = Armored.DamageAmmoracks
local isammorackdestroyed = Armored.IsAmmorackDestroyed

local repairRotors = Rotors.RepairRotors
local rotorsGetDamage = Rotors.RotorsGetDamage

local devlog   = Reforger.DevLog
local safeint  = Reforger.SafeInt
local safefloat = Reforger.SafeFloat

local pairEntityAll = Reforger.Scanners.PairEntityAll

local runhook  = hook.Run

local istable  = istable
local isnumber = isnumber
local IsValid  = IsValid
local rand     = math.Rand
local randm    = math.random

local LVS_DamageReducing = {
    light = 1.25,
    plane = 1.8,
    helicopter = 1.2,
    armored = 1.2,
    undefined = 1
}

local LVS_InstantKillChance = {
    light = 0.85,
    plane = 0.7,
    helicopter = 0.5,
    armored = 0,
    undefined = 1
}

local innerFireChance = Reforger.Convar("damage.chance.innerfire")
local explodeChanceArmored = Reforger.Convar("damage.chance.explode.armored")
local explodeChanceUnarmored = Reforger.Convar("damage.chance.explode.unarmored")

local function IsValidPlayer(a)
    return IsValid(a) and a:IsPlayer()
end

local function LVS_OnTakeDamage(self, dmginfo)
    if not self:IsInitialized() then return end

    local attacker = dmginfo:GetAttacker()

    fixDamageForce(dmginfo, attacker, self)

    self:CalcShieldDamage( dmginfo )
	self:CalcDamage( dmginfo )

	self:TakePhysicsDamage( dmginfo ) 
	self:OnAITakeDamage( dmginfo )
end

local function IsArmored(ent)
    return IsValid(ent) and ent.reforgerType == "armored"
end

local function IsAircraft(ent)
    if not IsValid(ent) then return false end
    local vehType = getvehtype(ent)
    return vehType == "plane" or vehType == "helicopter"
end

local function LVS_TryStartInnerFire(self, repeatCount, force)
    if not IsValid(self) or self:IsOnFire() then return false end
    local innerFireChance = innerFireChance:GetFloat() or 0.5

    if randm() < innerFireChance or force then
        devlog("Inner Fire chance passed for ", self)
    else
        devlog("Inner Fire chance failed for ", self)
        return false
    end

    local pre = runhook("Reforger.LVS_CanStartInnerFire", self, repeatCount)
    if pre == false and not force then return end

    if not gnwval(self, "Bool", "InnerFire") then
        snwval(self, "Bool", "InnerFire", true)

        if isnumber(repeatCount) and repeatCount >= 1 then
            ignitelimited(self, self:BoundingRadius(), repeatCount)
        else
            ignitelimited(self)
        end

        devlog("Inner Fire Started on ", self)
        runhook("Reforger.LVS_InnerFireStarted", self, repeatCount)
        return true
    end

    return false
end

local function LVS_TryStopInnerFire(self)
    if not IsValid(self) then return false end

    local pre = runhook("Reforger.LVS_CanStopInnerFire", self)
    if pre == false then return end

    if gnwval(self, "Bool", "InnerFire") then
        snwval(self, "Bool", "InnerFire", false)

        self:Extinguish()
        stopignitelimited(self)

        devlog("Inner Fire was stopped")
        runhook("Reforger.LVS_InnerFireStopped", self)

        return true
    end

    return false
end

local function LVS_HandleGib(self)
    local allowgb = safeint("gibs.keep") == 1
    local allowfreeze = safeint("gibs.freeze") == 1
    local delaygb = safeint("gibs.delay")
    
    if allowgb then
        self.reforgerGib = true
        self.Think = function() return false end
    else
        timer.Simple(1, function()
            if not IsValid(self) then return end
            self.RemoveTimer = CurTime() + delaygb
            self.Think = function(slf)
                if self.RemoveTimer < CurTime() then
                    self:Remove()
                    return false
                end

                slf:NextThink( CurTime() + 0.5 )
                return true
            end
        end)
    end

    if allowfreeze then
        timer.Simple(5, function()
            if not IsValid(self) then return end
            local physObj = self:GetPhysicsObject()
            if IsValid(physObj) then
                physObj:EnableMotion(false)
            end
        end)
    end
end

local function LVS_ExplodeWithDelay(self, delay, isCollision)
    timer.Simple(delay, function()
        if not IsValid(self) then return end
        
        stopignitelimited(self)
        
        self:SetDestroyed(isCollision)
        self:Explode()

        LVS_HandleGib(self)
    end)
end

local function LVS_StartReduceDamage(self, damage, vehType, isExplosion)
    local p = LVS_DamageReducing[vehType]

    if not isExplosion then return p * damage end
    return damage
end

local function LVS_CalcDamage(self, dmginfo)
    if dmginfo:IsDamageType(self.DSArmorIgnoreDamageType) then return end

    local originalDamage = dmginfo:GetDamage()
    if originalDamage <= 0 then return end
    
    local damage = originalDamage

    if dmginfo:IsDamageType(self.DSArmorDamageReductionType) then
        if damage ~= 0 then
            dmginfo:ScaleDamage(self.DSArmorDamageReduction)
            dmginfo:SetDamage(math.max(damage, 1))
        end
    end

    local vehType = getvehtype(self) -- always return or cahce or recache
    local dmgType = dmginfo:GetDamageType()
    local isArmored = IsArmored(self)

    local isExplosion       = dmginfo:IsExplosionDamage()
    
    local isFireDamage      = isfiredamage(self, dmgType)
    local isCollisionDamage = iscollisiondamage(dmgType)
    local isSmallDamage     = issmalldamage(dmgType)
    local isMeleeDamage     = ismeleedamage(dmgType)

    if isArmored and isSmallDamage then return end
    if not isArmored and isMeleeDamage then return end

    local attacker          = dmginfo:GetAttacker()
    local inflictor         = dmginfo:GetInflictor()
    
    local criticalHit       = false
    local isMine            = false
    
    if self.NotExploded and not self.GonnaExplode then
        if isFireDamage then
            local pDamage = DamageInfo()
            pDamage:SetDamage(rand(1, 5))
            pDamage:SetDamagePosition(self:GetPos())
            pDamage:SetDamageForce(VectorRand(1, 2))
            pDamage:SetDamageType(DMG_AIRBOAT)

            applyPlayersDamage(self, dmginfo)
            damageParts(self, pDamage)
        else  
            handleRayDamage(self, dmginfo)
        end

        if isFireDamage and originalDamage >= 70 and self.ReforgerExplode then
            self.ExplodedAlready = false
            timer.Simple(rand(5, 20), function()
                if not IsValid(self) then return end
                self:ReforgerExplode()
            end)
            self.GonnaExplode = true
        end
        return
    end

    if self.GonnaDestroyed or self.ExplodedAlready then return end

    if IsValid(attacker) and IsValid(inflictor) then
        isMine = attacker.Mine or inflictor.Mine or attacker:GetNWBool("IsMine") or inflictor:GetNWBool("IsMine")
    end

    local engine            = self.GetEngine and self:GetEngine() or nil
    local engineHP          = 0
    local engineMaxHP       = 1
    local engineIsDying     = false
    
    if IsValid(engine) then
        engineHP = engine:GetHP()
        engineMaxHP = engine:GetMaxHP()
        engineIsDying = (engineHP / engineMaxHP) < 0.35
    end

    local maxHP = self:GetMaxHP()
    local curHP = self:GetHP()
    local vehicleIsDying = (curHP / maxHP) < 0.15

    damage = LVS_StartReduceDamage(self, dmginfo:GetDamage(), vehType, isExplosion)

    if damage <= 0 then return end

    local damageForce = dmginfo:GetDamageForce()

    if damageForce:Length() < self.DSArmorIgnoreForce and not isFireDamage then return end
    
    if bit.band(dmgType, DMG_AIRBOAT) then damage = rand(0.085, 0.4) * damage end -- can add some random for nostalgia

    if not isCollisionDamage then
        criticalHit = self:CalcComponentDamage(dmginfo)

        if not isMine and (isExplosion or curHP < -10) and (engineIsDying or vehicleIsDying) and randm() < 0.5 then
            self:StartInnerFire(1)
        end
    end

    if not criticalHit and isExplosion and originalDamage > curHP then
        criticalHit = true
    
        self:StartInnerFire(5)
    end

    
    if not isFireDamage then
        rotorsGetDamage(self, dmginfo)
        handleRayDamage(self, dmginfo)
    end

    if isFireDamage and not isMine then
        self:ReforgerCleanDecals() -- for optimization of VFire

        local shouldDamagePlayers =
            (isArmored and self:IsOnFire()) or
            (not isArmored)

        if shouldDamagePlayers then
            applyPlayersDamage(self, dmginfo)
        end

        if randm() < 0.5 then
            damageAmmoracks(self, dmginfo)
            devlog("Ammmo rack take damage", dmginfo)
        end

        if randm() < 0.85 then
            local partDamage = math.min(0.5 * damage, 100)
            damageParts(self, partDamage)
        end
    end
    
    local isAmmorackDestroyed = isammorackdestroyed(self)
    
    -- One shot fix or One explode fix. (Example mine TM-62 from SW bombs can one shot everything)
    if isArmored then
        local shouldClamp = false

        if damage > curHP and not vehicleIsDying and not isAmmorackDestroyed then
            damage = math.Clamp(damage, curHP * 0.1, curHP * 0.95)
        elseif isMine then
            local mineMultiplier = safefloat("damage.mine.multiplier", 0.25)
            local mineMaxDamage = safefloat("damage.mine.max", 100)
            local mineMinDamage = safefloat("damage.mine.min", 1)

            devlog("Reducing damage for Mine")
            damage = math.Clamp(damage, mineMinDamage, mineMaxDamage) * mineMultiplier
        end
    end

    if not criticalHit and isSmallDamage then damage = math.max(damage * 0.325, 0.5) end

    -- Damage Clamping
    if not isAmmorackDestroyed and not self:IsOnFire() and (engineIsDying or vehicleIsDying) then
        -- if damage is more than curHp for 60% then not damage components
        if damage < (curHP * 0.6) and randm() < 0.5 and not isMine then
            local partDamage = math.min(0.95 * damage, 100)
            damageParts(self, partDamage)
        end

        damage = 0.085 * damage

    elseif (not isFireDamage or not self:IsOnFire()) and (engineIsDying or vehicleIsDying) then damage = 0.1 * damage end

    if damage < 10 and not isSmallDamage then damage = 1.5 * damage end

    if vehicleIsDying and not criticalHit and not isFireDamage then
        damage = 0.85 * damage
    end

    --------------------------- In LVS standard ammorack gives 100 damage when it destroyes
    --------------------------- Means ammorack doesn't exists but is giving damage (bug that I found while playing with tanks)

    if not isAmmorackDestroyed then
        isAmmorackDestroyed = (isArmored and isFireDamage and originalDamage >= 70)
    end

    if isAmmorackDestroyed then
        if vehicleIsDying then
            damage = damage * 1
        else
            damage = damage * 1.5
        end

        if not isMine and randm() < 0.25 then self:StartInnerFire(5) end
    end
    
    -- Apply damage
    local newHP = math.Clamp(curHP - damage, -maxHP, maxHP)

    self:SetHP(newHP)

    if self:IsDestroyed() then return end

    local isValidAttacker = IsValidPlayer(attacker)

    if isValidAttacker and not isFireDamage then
        net.Start("lvs_hitmarker")
            net.WriteBool(criticalHit)
        net.Send(attacker)
    end

    if damage > 1 and not isCollisionDamage and not isFireDamage then
        net.Start("lvs_hurtmarker")
            net.WriteFloat(math.min(damage / 50, 1))
        net.Send(self:GetEveryone())
    end

    if engineIsDying and (newHP / maxHP) < 0.1 then ignitelimited(self) end

    if self.GonnaDestroyed == true then return end

    local chance = randm()
    local armChance = explodeChanceArmored:GetFloat() or 0.5
    local unarmChance = explodeChanceUnarmored:GetFloat() or 0.5

    if newHP <= 0 then
        self.GonnaDestroyed = true

        if isValidAttacker then self.FinalAttacker = attacker end

        devlog("Explosion roll:", chance, " | Threshold:", isArmored and armChance or unarmChance)

        local shouldNotExplode = (isArmored and chance >= armChance) or (not isArmored and chance >= unarmChance)
        if not isFireDamage and shouldNotExplode and not IsAircraft(self) then
            LVS_HandleGib(self)

            self.NotExploded = true
            self:SetAI(false)
            self:SetAIGunners(false)
            self:StartInnerFire(8, true)
            
            self:PreExplode(1)

            local soundEmitters = pairEntityAll(self, "lvs_soundemitter")

            for _, sEmitter in pairs(soundEmitters) do
                if IsValid(sEmitter) then
                    sEmitter:Stop()
                end
            end

            self.ReforgerExplode = self.Explode
            self.Explode = function(self)
                if self.ExplodedAlready then return end

                self.ExplodedAlready = true
            end
            
            self.OnMaintenance = function() end

            self:SetDestroyed(true)
            self:StopEngine()

            runhook("Reforger.LVS_VehicleNotExploded", self, dmginfo)
            return
        end

        self.FinalInflictor = inflictor

        self:ClearPDS()

        if isValidAttacker then
            net.Start("lvs_killmarker")
            net.Send(attacker)
        end

        local isInstantKill = (isExplosion and randm() < LVS_InstantKillChance[vehType]) or originalDamage > maxHP
        local explodeDelay = math.Clamp((self:GetVelocity():Length() - 200) / 200, 1.5, 16)

        if isInstantKill then
            explodeDelay = 0
        end

        if explodeDelay > 0 and not isMine then
            if vehType == "light" and isExplosion then
                self:StartInnerFire(1, true)
            end

            if isArmored then
                if isFireDamage and not isAmmorackDestroyed then
                    explodeDelay = (explodeDelay + 1) * 4
                end

                if not isAmmorackDestroyed then
                    self:StartInnerFire(4, true)
                    explodeDelay = rand(10, 15)
                end
            end
        end

        explodeDelay = self:PreExplode(explodeDelay)
        LVS_ExplodeWithDelay(self, explodeDelay, isCollisionDamage)
    end
end

local function LVS_RewriteDamageSystem(ent)
    if not IsValid(ent) then return end

    if not ent.LVS then return end

    devlog("Overriding damage system for: " .. tostring(ent))

    local originalRemoveDecals = ent.RemoveAllDecals
    local vehType = getvehtype(ent)

    if not isfunction(ent.ReforgerCleanDecals) then
        ent.ReforgerCleanDecals = function(self)
            if not originalRemoveDecals then return end

            originalRemoveDecals(self)

            if vehType == "light" or IsAircraft(self) then
                local wheels = self.GetWheels and self:GetWheels() or {}
                if istable(wheels) then
                    for _, wheel in ipairs(wheels) do
                        if IsValid(wheel) then
                            originalRemoveDecals(wheel)
                        end
                    end
                end
            end

            local parts = self._dmgParts or self:GetTable()._dmgParts
            if istable(parts) then
                for _, part in ipairs(parts) do
                    local target = part.entity
                    if IsValid(target) then
                        originalRemoveDecals(target)
                    end
                end
            end
        end
    end

    ent.RemoveAllDecals = function() end

    ent.OnTakeDamage = LVS_OnTakeDamage
    ent.CalcDamage = LVS_CalcDamage

    ent.StartInnerFire = LVS_TryStartInnerFire
    ent.StopInnerFire = LVS_TryStopInnerFire

    local oldMaintenance = ent.OnMaintenance
    ent.OnMaintenance = function(self, ...)
        stopignitelimited(self)

        self:ReforgerCleanDecals()
        self:Extinguish()

        if oldMaintenance then oldMaintenance(self, ...) end
    end

    local oldRepaired = ent.OnRepaired
    ent.OnRepaired = function(self, ...)
        self:Extinguish()

        stopignitelimited(self)
        repairRotors(self)

        if oldRepaired then oldRepaired(self, ...) end
    end
end

hook.Add("Reforger.LVS_CannotEnterNotExploded", "Reforger.LVS_NotExplodedVehicleMsg", function(ply)
    if IsValidPlayer(ply) then
        ply:ChatPrint("Cannot enter this vehicle. It's destroyed.")
    end
end)

hook.Add("CanPlayerEnterVehicle", "Reforger.LVS_CannotEnterVehicle", function(ply, veh)
    local pod = veh
    local podParent = pod:GetParent()

    if pod.LVS and pod.NotExploded then
        runhook("Reforger.LVS_CannotEnterNotExploded", ply, veh)
        return false 
    end

    if IsValid(podParent) and podParent.LVS and podParent.NotExploded then
        runhook("Reforger.LVS_CannotEnterNotExploded", ply, veh)
        return false 
    end

    return true
end)

hook.Add("LVS.IsEngineStartAllowed", "Reforger.LVS_CannotStartEngineNotExploded", function(veh)
    if veh.NotExploded and veh:IsValid() then
        return false
    end
end)

hook.Add("LVS.CanPlayerDrive", "Reforger.LVS_CannotDriveNotExploded", function(ply, veh)
    if veh.NotExploded and veh:IsValid() then
        return false
    end
end)

return {LVS_RewriteDamageSystem}