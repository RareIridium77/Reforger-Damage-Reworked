if not LVS then return end

local RDamage = Reforger.Damage
local Rotors = Reforger.Rotors
local Armored = Reforger.Armored

local LVS_DamageReducing = {
    light = 1.25,
    plane = 0.145,
    helicopter = 0.145,
    armored = 1.2,
    undefined = 1
}

local LVS_InstantKillChance = {
    light = 0.85,
    plane = 0.5,
    helicopter = 0.5,
    armored = 0.2,
    undefined = 1
}

local function LVS_OnTakeDamage(self, dmginfo)
    self:CalcShieldDamage( dmginfo )
	self:CalcDamage( dmginfo )
	self:TakePhysicsDamage( dmginfo )
	self:OnAITakeDamage( dmginfo )
end

local function LVS_TryStartInnerFire(self, repeatCount)
    if not IsValid(self) or self:IsOnFire() then return false end

    local pre = hook.Run("Reforger.CanStartInnerFire", self, repeatCount)
    if pre == false then return end

    if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
        Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)

        if isnumber(repeatCount) and repeatCount >= 1 then
            RDamage.IgniteLimited(self, self:BoundingRadius(), repeatCount)
        else
            RDamage.IgniteLimited(self)
        end

        Reforger.DevLog("Inner Fire Started on ", self)
        hook.Run("Reforger.InnerFireStarted", self, repeatCount)
        return true
    end

    return false
end

local function LVS_TryStopInnerFire(self)
    if not IsValid(self) then return false end

    local pre = hook.Run("Reforger.CanStopInnerFire", self)
    if pre == false then return end

    if Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
        Reforger.SetNetworkValue(self, "Bool", "InnerFire", false)

        self:Extinguish()
        RDamage.StopLimitedFire(self)

        Reforger.DevLog("Inner Fire was stopped")
        hook.Run("Reforger.InnerFireStopped", self)

        return true
    end

    return false
end

local function LVS_ExplodeWithDelay(self, delay, isCollision)
    timer.Simple(delay, function()
        if not IsValid(self) then return end
        
        RDamage.StopLimitedFire(self)
        
        self:SetDestroyed(isCollision)
        self:Explode()

        local allowgb = Reforger.SafeInt("gibs.keep") == 1
        local allowfreeze = Reforger.SafeInt("gibs.freeze") == 1
        local delaygb = Reforger.SafeInt("gibs.delay")
        
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
    end)
end

local function LVS_StartReduceDamage(self, damage, vehType, isExplosion)
    local p = LVS_DamageReducing[vehType]

    if not isExplosion then return p * damage end
    return damage
end

local function LVS_CalcDamage(self, dmginfo)
    if self.GonnaDestroyed == true then return end
    if dmginfo:IsDamageType(self.DSArmorIgnoreDamageType) then return end

    local originalDamage = dmginfo:GetDamage()
    local damage = originalDamage

    if dmginfo:IsDamageType(self.DSArmorDamageReductionType) then
        if damage ~= 0 then
            dmginfo:ScaleDamage(self.DSArmorDamageReduction)
            dmginfo:SetDamage(math.max(damage, 1))
        end
    end

    local vehType = Reforger.GetVehicleType(self) -- always return or cahce or recache
    local dmgType = dmginfo:GetDamageType()

    local isExplosion       = dmginfo:IsExplosionDamage()
    
    local isFireDamage      = RDamage.IsFireDamageType(self, dmgType)
    local isCollisionDamage = RDamage.IsCollisionDamageType(dmgType)
    local isSmallDamage     = RDamage.IsSmallDamageType(dmgType)

    local attacker          = dmginfo:GetAttacker()
    local inflictor         = dmginfo:GetInflictor()
    
    local criticalHit       = false
    local isMine            = false

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

    if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not isFireDamage then return end
    
    if bit.band(dmgType, DMG_AIRBOAT) then damage = math.Rand(0.085, 0.4) * damage end -- can add some random for nostalgia

    if not isCollisionDamage then
        criticalHit = self:CalcComponentDamage(dmginfo)

        if not isMine and (isExplosion or curHP < -10) and (engineIsDying or vehicleIsDying) and math.random() < 0.5 then
            self:StartInnerFire(1)
        end
    end

    if not criticalHit and isExplosion and originalDamage > curHP then
        criticalHit = true
    end

    Rotors.RotorsGetDamage(self, dmginfo)
    RDamage.HandleRayDamage(self, dmginfo)
    
    local isAmmorackDestroyed = Armored.IsAmmorackDestroyed(self)

    if isFireDamage and not isMine then
        self:ReforgerCleanDecals() -- for optimization of VFire

        local shouldDamagePlayers =
            (vehType == "armored" and self:IsOnFire()) or
            (vehType ~= "armored")

        if shouldDamagePlayers then
            RDamage.ApplyPlayersDamage(self, dmginfo)
        end

        if math.random() < 0.5 then
            Armored.DamageAmmoracks(self, dmginfo)
        end

        if math.random() < 0.85 then
            local partDamage = math.min(0.5 * damage, 100)
            RDamage.DamageParts(self, partDamage)
        end
    end

    -- One shot fix or One explode fix. (Example mine TM-62 from SW bombs can one shot everything)
    if vehType == "armored" then
        local shouldClamp = false

        if damage > curHP and not vehicleIsDying and not isAmmorackDestroyed then
            damage = math.Clamp(damage, curHP * 0.1, curHP * 0.95)
        elseif isMine then
            local mineMultiplier = Reforger.SafeFloat("damage.mine.multiplier", 0.25)
            local mineMaxDamage = Reforger.SafeFloat("damage.mine.max", 100)
            local mineMinDamage = Reforger.SafeFloat("damage.mine.min", 1)

            Reforger.DevLog("Reducing damage for Mine")
            damage = math.Clamp(damage, mineMinDamage, mineMaxDamage) * mineMultiplier
        end
    end

    if not criticalHit and isSmallDamage then damage = math.max(damage * 0.325, 0.5) end

    -- Damage Clamping
    if not isAmmorackDestroyed and not self:IsOnFire() and (engineIsDying or vehicleIsDying) then
        -- if damage is more than curHp for 60% then not damage components
        if damage < (curHP * 0.6) and math.random() < 0.5 and not isMine then
            local partDamage = math.min(0.95 * damage, 100)
            RDamage.DamageParts(self, partDamage)
        end

        damage = 0.085 * damage

    elseif (not isFireDamage or not self:IsOnFire()) and (engineIsDying or vehicleIsDying) then damage = 0.1 * damage end

    if damage < 10 and not isSmallDamage then damage = 1.5 * damage end

    if vehicleIsDying and not criticalHit and not isFireDamage then
        damage = 0.85 * damage
    end

    --------------------------- In LVS standard ammorack gives 100 damage when it destroyes
    --------------------------- Means ammorack doesn't exists but is giving damage (bug that I found while playing with tanks)
    if isAmmorackDestroyed or (vehType == "armored" and isFireDamage and dmginfo:GetDamage() >= 50) then
        if vehicleIsDying then
            damage = damage * 1.25
        elseif math.random() < 0.35 then
            damage = damage * 5
        else
            damage = damage * 0.75
        end

        if not isMine and math.random() < 0.25 then self:StartInnerFire(5) end
        isAmmorackDestroyed = true
    end
    

    -- Apply damage
    local newHP = math.Clamp(curHP - damage, -maxHP, maxHP)

    self:SetHP(newHP)

    if self:IsDestroyed() then return end

    if IsValid(attacker) and attacker:IsPlayer() and not isFireDamage then
        net.Start("lvs_hitmarker")
            net.WriteBool(criticalHit)
        net.Send(attacker)
    end

    if damage > 1 and not isCollisionDamage and not isFireDamage then
        net.Start("lvs_hurtmarker")
            net.WriteFloat(math.min(damage / 50, 1))
        net.Send(self:GetEveryone())
    end

    if IsValid(attacker) and attacker:IsPlayer() then
        self.FinalAttacker = attacker
    end

    if engineIsDying and (newHP / maxHP) < 0.1 then RDamage.IgniteLimited(self) end

    if self.GonnaDestroyed == true then return end

    if newHP <= 0 then
        self.FinalInflictor = inflictor

        self:ClearPDS()

        if IsValid(attacker) and attacker:IsPlayer() then
            net.Start("lvs_killmarker")
            net.Send(attacker)
        end

        local isInstantKill = (isExplosion and math.random() < LVS_InstantKillChance[vehType]) or originalDamage > maxHP
        local explodeDelay = math.Clamp((self:GetVelocity():Length() - 200) / 200, 1.5, 16)

        if isInstantKill then
            explodeDelay = 0
        end

        if explodeDelay > 0 and not isMine then
            if vehType == "light" and isExplosion then
                self:StartInnerFire(1)
            end

            if vehType == "armored" then
                if isFireDamage and not isAmmorackDestroyed then
                    explodeDelay = (explodeDelay + 1) * 4
                end

                if not isAmmorackDestroyed then
                    self:StartInnerFire(4)
                    explodeDelay = math.Rand(10, 15)
                end
            end
        end

        self.GonnaDestroyed = true

        explodeDelay = self:PreExplode(explodeDelay)

        LVS_ExplodeWithDelay(self, explodeDelay, isCollisionDamage)
    end
end

local function LVS_RewriteDamageSystem(ent)
    if not IsValid(ent) then return end

    if not ent.LVS then return end

    Reforger.DevLog("Overriding damage system for: " .. tostring(ent))

    local originalRemoveDecals = ent.RemoveAllDecals
    local vehType = Reforger.GetVehicleType(ent)

    if not isfunction(ent.ReforgerCleanDecals) then
        ent.ReforgerCleanDecals = function(self)
            if not originalRemoveDecals then return end

            originalRemoveDecals(self)

            if vehType == "light" or vehType == "plane" or vehType == "helicopter" then
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
    ent.CalcDamage    = LVS_CalcDamage

    local oldMaintenance = ent.OnMaintenance
    ent.OnMaintenance = function(self, ...)
        RDamage.StopLimitedFire(self)

        self:ReforgerCleanDecals()
        self:Extinguish()

        if oldMaintenance then oldMaintenance(self, ...) end
    end

    local oldRepaired = ent.OnRepaired
    ent.OnRepaired = function(self, ...)
        self:Extinguish()

        RDamage.StopLimitedFire(self)
        Rotors.RepairRotors(self)

        if oldRepaired then oldRepaired(self, ...) end
    end

    ent.StartInnerFire = LVS_TryStartInnerFire
    ent.StopInnerFire = LVS_TryStopInnerFire
end

return {LVS_RewriteDamageSystem}