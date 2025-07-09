if not LVS then return end

local function LVS_OnTakeDamage(self, dmginfo)
    self:CalcShieldDamage( dmginfo )
	self:CalcDamage( dmginfo )
	self:TakePhysicsDamage( dmginfo )
	self:OnAITakeDamage( dmginfo )
end

local function LVS_StartReduceDamage(self, damage, vehType, isExplosion)
    local p = 1

    if vehType == "light" then
        p = 0.125
    elseif vehType == "plane" or vehType == "helicopter" then
        p = 0.145
    elseif vehType ~= "armored" then
        p = 1.2
    else
        p = 0.125 -- armored baseline?
    end

    if isExplosion then return p * damage end
    return damage
end

local function LVS_CalcDamage(self, dmginfo)
    if dmginfo:IsDamageType(self.DSArmorIgnoreDamageType) then return end

    local vehType = Reforger.GetVehicleType(self) -- always return or cahce or recache
    local dmgType = dmginfo:GetDamageType()

    local isFireDamage      = dmginfo:IsDamageType(DMG_BURN)
    local isExplosion       = dmginfo:IsExplosionDamage()
    local isCollisionDamage = dmginfo:GetDamageType() == (DMG_CRUSH + DMG_VEHICLE)
    local isSmallDamage     = bit.band(dmgType, DMG_BULLET + DMG_BUCKSHOT + DMG_CLUB) ~= 0

    local criticalHit = false

    local engine = self.GetEngine and self:GetEngine() or nil
    local engineHP = IsValid(engine) and engine:GetHP() or 0
    local engineMaxHP = IsValid(engine) and engine:GetMaxHP() or 1
    local engineIsDying = (engineHP / engineMaxHP) < 0.35

    local maxHP = self:GetMaxHP()
    local curHP = self:GetHP()
    local vehicleIsDying = (curHP / maxHP) < 0.15

    Reforger.HandleCollisionDamage(self, dmginfo)

    local damage = LVS_StartReduceDamage(self, dmginfo:GetDamage(), vehType, isExplosion)
    if damage <= 0 then return end

    if dmginfo:IsDamageType(self.DSArmorDamageReductionType) then
        dmginfo:ScaleDamage(self.DSArmorDamageReduction)
        damage = math.max(0.45 * damage, 1)
    end

    if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not isFireDamage then return end
    
    if bit.band(dmgType, DMG_AIRBOAT) then damage = math.Rand(0.085, 0.4) * damage end -- can add some random for nostalgia

    if not isCollisionDamage then
        criticalHit = self:CalcComponentDamage(dmginfo)

        if (isExplosion or curHP < -10) and (engineIsDying or vehicleIsDying) and not self:IsOnFire() and math.random() < 0.5 then
            if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
                Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)
                Reforger.IgniteLimited(self)
                Reforger.DevLog("Inner Fire was started!")
            end
        end
    end

    Reforger.RotorsGetDamage(self, dmginfo)

    if vehType == "armored" then
        if not isSmallDamage then
            Reforger.HandleRayDamage(self, dmginfo)
        end
    else
        Reforger.HandleRayDamage(self, dmginfo)
    end

    if isFireDamage then
        if self:IsOnFire() then Reforger.ApplyPlayersDamage(self, dmginfo) end
        
        self:ReforgerCleanDecals()

        if math.random() < 0.5 then Reforger.AmmoracksTakeTransmittedDamage(self, dmginfo) end
        if math.random() < 0.85 then Reforger.DamageDamagableParts(self, partDamage) end
    end

    local isAmmorackDestroyed = Reforger.IsAmmorackDestroyed(self)

    if isFireDamage and isAmmorackDestroyed then
        if vehicleIsDying then
            damage = damage * 1.25
        elseif math.random() < 0.35 then
            damage = damage * 5
        else
            damage = 100 * 2.5
        end

        if not self:IsOnFire() and math.random() < 0.25 then
            if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
                Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)
                Reforger.IgniteLimited(self, 10) -- sepcial situation
                Reforger.DevLog("Inner Fire was started!")
            end
        end
    end

    if not criticalHit and isSmallDamage then damage = 0.325 * damage end

    -- Damage Clamping
    if not isAmmorackDestroyed and not self:IsOnFire() and (engineIsDying or vehicleIsDying) then
        if math.random() < 0.5 then
            local partDamage = 0.95 * damage
            Reforger.DamageDamagableParts(self, partDamage)
            Reforger.DevLog("Part Damage: ", partDamage)
        end

        damage = 0.085 * damage
    elseif (not isFireDamage or not self:IsOnFire()) and (engineIsDying or vehicleIsDying) then damage = 0.1 * damage end

    if damage < 10 and not isSmallDamage then damage = 1.5 * damage end

    -- Apply damage
    local newHP = math.Clamp(curHP - damage, -maxHP, maxHP)

    self:SetHP(newHP)

    if self:IsDestroyed() then return end

    local attacker = dmginfo:GetAttacker()

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

    if engineIsDying and (newHP / maxHP) < 0.1 then Reforger.IgniteLimited(self) end

    if newHP <= 0 then
        self.FinalAttacker = attacker
        self.FinalInflictor = dmginfo:GetInflictor()

        self:SetDestroyed(isCollisionDamage)
        self:ClearPDS()

        if IsValid(attacker) and attacker:IsPlayer() then
            net.Start("lvs_killmarker")
            net.Send(attacker)
        end

        local explodeDelay = math.Clamp((self:GetVelocity():Length() - 200) / 200, 1.5, 16)

        if vehType == "plane" or vehType == "helicopter" then explodeDelay = 3 end
        if isAmmorackDestroyed then explodeDelay = explodeDelay * 2 end
        if isFireDamage and not isAmmorackDestroyed then explodeDelay = (explodeDelay + 1) * 4 end
        if vehType == "armored" and not isFireDamage and not self:IsOnFire() then
            if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
                Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)
                Reforger.IgniteLimited(self)
                Reforger.DevLog("Inner Fire was started!")
            end
            explodeDelay = 20
        end

        explodeDelay = self:PreExplode( explodeDelay )

        timer.Simple(2 + explodeDelay, function()
            if not IsValid(self) then return end
            Reforger.StopLimitedFire(self)
            self:Explode()
        end)
    end
end

local function LVS_RewriteDamageSystem(ent)
    if not IsValid(ent) or not ent.LVS then return end

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
        self:ReforgerCleanDecals()
        Reforger.StopLimitedFire(self)
        self:Extinguish()

        if vehType == "plane" and istable(self.rotors) then
            for _, rotor in pairs(self.rotors) do
                if rotor.Repair then rotor:Repair() end
            end
        end

        if oldMaintenance then oldMaintenance(self, ...) end
    end

    local oldRepaired = ent.OnRepaired
    ent.OnRepaired = function(self, ...)
        self:Extinguish()

        Reforger.StopLimitedFire(self)
        Reforger.RepairRotors(self)

        if oldRepaired then oldRepaired(self, ...) end
    end
end

return {LVS_RewriteDamageSystem}