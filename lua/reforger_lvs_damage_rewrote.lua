local function LVS_OnTakeDamage(self, dmginfo)
    if self.CalcShieldDamage then self:CalcShieldDamage( dmginfo ) end
    if self.CalcDamage then self:CalcDamage( dmginfo ) end
    if self.TakePhysicsDamage then self:TakePhysicsDamage( dmginfo ) end
    if self.OnAITakeDamage then self:OnAITakeDamage( dmginfo ) end
end

local function LVS_CalcDamage(self, dmginfo)
    if self:IsDestroyed() then return end
    if dmginfo:IsDamageType(self.DSArmorIgnoreDamageType) then return end

    -- Damage Reduction
    if dmginfo:IsDamageType(self.DSArmorDamageReductionType) and dmginfo:GetDamage() > 0 then
        dmginfo:ScaleDamage(self.DSArmorDamageReduction)
        dmginfo:SetDamage(math.max(dmginfo:GetDamage(), 1))
    end

    -- Special Damage Types
    if dmginfo:IsDamageType(DMG_BLAST) then
        dmginfo:SetDamage(0.25 * dmginfo:GetDamage())
    elseif dmginfo:IsDamageType(DMG_AIRBOAT) then
        dmginfo:SetDamage(0.125 * dmginfo:GetDamage())
    end

    local damage = dmginfo:GetDamage()
    local curHP = self:GetHP()
    local maxHP = self:GetMaxHP()
    local Engine = self.GetEngine and self:GetEngine() or nil
    local vehType = Reforger.GetVehicleType(self)

    local isFire = dmginfo:IsDamageType(DMG_BURN) or dmginfo:IsDamageType(DMG_DIRECT)
    local isCollision = dmginfo:GetDamageType() == (DMG_CRUSH + DMG_VEHICLE)
    local isSmall = dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_CLUB) or dmginfo:IsDamageType(DMG_BUCKSHOT)
    local isExplosion = dmginfo:IsExplosionDamage()
    local isInDeath = (curHP / maxHP) < 0.125

    if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not isFire then return end

    -- Damage to players
    Reforger.ApplyPlayerFireDamage(self, dmginfo)

    local critical = false
    local engineHPFrac = IsValid(Engine) and (Engine:GetHP() / Engine:GetMaxHP()) or 1
    local engineDying = engineHPFrac < 0.45

    if not isCollision and not dmginfo:IsDamageType(DMG_CLUB) then
        critical = self:CalcComponentDamage(dmginfo)
        Reforger.DamagePlayer(self, dmginfo)
    end

    -- Blast damage to engine
    if isExplosion and critical and IsValid(Engine) and not Engine:GetDestroyed() then
        Engine:SetHP(math.max(1, Engine:GetHP() - damage))

        if (Engine:GetHP() / Engine:GetMaxHP()) < 0.4 then
            self:StopEngine()

            if not self:IsOnFire() then
                self:Ignite(10, self:BoundingRadius())
            end

            Engine:SetDestroyed(true)
        end
    end

    -- Fire chance logic
    if engineDying and not self:IsOnFire() then
        self:Ignite(10, self:BoundingRadius())
    end

    if critical and not self:IsOnFire() then
        self:Ignite(10, self:BoundingRadius())
    end

    if isExplosion and not self:IsOnFire() and (curHP / maxHP) < 0.5 then
        self:Ignite(10, self:BoundingRadius())
    end

    if isInDeath and not self:IsOnFire() and math.random() < 0.8 then
        self:Ignite(10, self:BoundingRadius())
    end

    if vehType == "plane" and (curHP / maxHP) < 0.45 then
        if not self:IsOnFire() then
            self:Ignite(10, self:BoundingRadius())
        end
        self:StopEngine()
    end

    -- Update HP after components logic
    curHP = self:GetHP()
    isInDeath = (curHP / maxHP) < 0.125

    if damage <= 0 then return end

    -- Small damage adjustment
    if not critical and isSmall then
        damage = 1
    elseif critical and isSmall then
        damage = damage / 2
    end

    if not critical and curHP <= 5 and curHP >= 1 then
        damage = 0.002 * damage
    end

    
    if vehType == "armored" and (curHP / maxHP) > 0.2 then
        damage = 1
    end

    local newHP = math.Clamp(curHP - damage, -maxHP, maxHP)

    self:SetHP(newHP)

    if self:IsDestroyed() then return end

    -- Hitmarker
    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and not isFire then
        net.Start("lvs_hitmarker")
            net.WriteBool(critical)
        net.Send(attacker)
    end

    -- Hurtmarker
    if damage > 1 and not isCollision and not isFire then
        net.Start("lvs_hurtmarker")
            net.WriteFloat(math.min(damage / 50, 1))
        net.Send(self:GetEveryone())
    end

    -- Explosion logic
    if newHP <= 0 then
        local canExplode = true
        
        if vehType == "armored" and not isFire then
            canExplode = false
        end

        if Reforger.IsAmmorackDestroyed(self) then
            canExplode = true
        end

        if canExplode then
            self.FinalAttacker = dmginfo:GetAttacker()
            self.FinalInflictor = dmginfo:GetInflictor()
            self:SetDestroyed(isCollision)
            self:ClearPDS()

            if IsValid(self.FinalAttacker) and self.FinalAttacker:IsPlayer() then
                net.Start("lvs_killmarker")
                net.Send(self.FinalAttacker)
            end

            local explodeTime = self:PreExplode(math.Clamp((self:GetVelocity():Length() - 200) / 200, 1.5, 16))
            timer.Simple(explodeTime, function()
                if not IsValid(self) then return end
                self:Explode()
            end)
        end
    end
end

local function LVS_RewriteDamageSystem(lvs_entity)
    if not IsValid(lvs_entity) then return end

    if lvs_entity.LVS then
        Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(lvs_entity)))
        
        -- Rewriting decals
        local removealldecalsfunc = lvs_entity.RemoveAllDecals

        if not isfunction(lvs_entity.ReforgerCleanDecals) then
            lvs_entity.ReforgerCleanDecals = function(self)
                if removealldecalsfunc then
                    -- remove decals from body
                    
                    removealldecalsfunc(self)

                    -- End
                    
                    -- removing from wheels (LVS Cars and LVS Planes)

                    if Type == "light" or Type == "plane" then
                        local wheels = self:GetWheels() or {}

                        if istable(wheels) and next(wheels) ~= nil then

                            for _, wheel in ipairs(wheels) do
                                if not IsValid(wheel) then continue end

                                removealldecalsfunc(wheel)
                            end

                        end
                    end

                    -- End

                    -- removing from damagable parts (I think works on every LVS). Sometimes damagable parts ~= wheels

                    local data = self:GetTable()
                    local parts = data['_dmgParts']

                    if istable(wheels) and next(wheels) ~= nil then

                        for _, part in ipairs(parts) do
                            local target = part.entity

                            if not IsValid(target) then continue end

                            removealldecalsfunc(target)
                        end
                        
                    end
                    -- End
                end
            end
        end
        
        lvs_entity.RemoveAllDecals = function() end -- to keep decals on model
        
        -- End

        lvs_entity.OnTakeDamage = LVS_OnTakeDamage
        lvs_entity.CalcDamage = LVS_CalcDamage

        -- Clear decals after full recover
        local onmainteance = lvs_entity.OnMaintenance
        local Type = Reforger.GetVehicleType(self)

        lvs_entity.OnMaintenance = function(self, ...)
            self:ReforgerCleanDecals()

            if Type == "plane" and istable(self.rotors) and next(self.rotors) ~= nil then
                for _, rotor in pairs(self.rotors) do
                    if rotor.Repair then
                        rotor:Repair()
                    end
                end
            end

            if onmainteance then
                onmainteance(self, ...)
            end
        end
        -- End
    end
end

return {LVS_RewriteDamageSystem}