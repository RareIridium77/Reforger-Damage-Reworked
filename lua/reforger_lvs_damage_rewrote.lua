local function LVS_Explode(self, dmginfo)
    if not IsValid(self) then return end

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

local function LVS_OnTakeDamage(self, dmginfo)
    if self.CalcShieldDamage then self:CalcShieldDamage( dmginfo ) end
    if self.CalcDamage then self:CalcDamage( dmginfo ) end
    if self.TakePhysicsDamage then self:TakePhysicsDamage( dmginfo ) end
    if self.OnAITakeDamage then self:OnAITakeDamage( dmginfo ) end
end

local function LVS_HandleDamageReduction(self, dmginfo)
    if dmginfo:IsDamageType(self.DSArmorDamageReductionType) and dmginfo:GetDamage() > 0 then
        dmginfo:ScaleDamage(self.DSArmorDamageReduction)
        dmginfo:SetDamage(math.max(dmginfo:GetDamage(), 1))
    end
end

local function LVS_HandleExplosionModifier(self, dmginfo)
    if dmginfo:IsExplosionDamage() then
        dmginfo:SetDamage(0.15 * dmginfo:GetDamage())
    end
end

local function LVS_HandleAirboatModifier(self, dmginfo)
    if dmginfo:IsDamageType(DMG_AIRBOAT) then
        dmginfo:SetDamage(0.125 * dmginfo:GetDamage())
    end
end

local function LVS_HandleFireLogic(self, dmginfo, damage, critical, engineDying, ammorackDestroyed)
    if self:IsOnFire() then return end

    local curHP, maxHP = self:GetHP(), self:GetMaxHP()

    if engineDying and not self:IsOnFire() then
        self:Ignite(1, self:BoundingRadius())
    end

    if dmginfo:IsExplosionDamage() and not self:IsOnFire() and (curHP / maxHP) < 0.5 then
        self:Ignite(10, self:BoundingRadius())
    end

    if ammorackDestroyed then
        self:Ignite(2, self:BoundingRadius())
    end
end

local function LVS_CalcDamage(self, dmginfo)
    if self:IsDestroyed() then return end
    if dmginfo:IsDamageType(self.DSArmorIgnoreDamageType) then return end
    if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not dmginfo:IsDamageType( DMG_BURN ) then return end

    local vehType = Reforger.GetVehicleType(self)
    local Engine = self.GetEngine and self:GetEngine() or nil

    LVS_HandleDamageReduction(self, dmginfo)
    LVS_HandleExplosionModifier(self, dmginfo)
    LVS_HandleAirboatModifier(self, dmginfo)

    Reforger.ApplyPlayerFireDamage(self, dmginfo)

    if vehType == "plane" or vehType == "helicopter" then
        Reforger.RotorsGetDamage(self, dmginfo)
    end

    local damage = dmginfo:GetDamage()
    local curHP, maxHP = self:GetHP(), self:GetMaxHP()
    local isExplosion = dmginfo:IsExplosionDamage()
    local isSmall = dmginfo:IsDamageType( DMG_BULLET ) or dmginfo:IsDamageType( DMG_CLUB ) or dmginfo:IsDamageType( DMG_BUCKSHOT )
    local isCollision = dmginfo:GetDamageType() == ( DMG_CRUSH + DMG_VEHICLE )
    local isFire = dmginfo:IsDamageType( DMG_BURN )
    local isInDying = (curHP / maxHP) < 0.125
    local ammorackDestroyed = Reforger.IsAmmorackDestroyed(self)

    local engineHPFrac = IsValid(Engine) and (Engine:GetHP() / Engine:GetMaxHP()) or 1
    local engineDying = engineHPFrac < 0.32

    if vehType == "undefined" then 
        isInDying = (curHP / maxHP) < 0.6
    end

    local critical = false
    if not isCollision and not dmginfo:IsDamageType(DMG_CLUB) then
        critical = self:CalcComponentDamage(dmginfo)
        Reforger.DamagePlayer(self, dmginfo)
    end

    if isExplosion and critical and IsValid(Engine) and not Engine:GetDestroyed() then
        Engine:SetHP(math.max(1, Engine:GetHP() - damage))
        if (Engine:GetHP() / Engine:GetMaxHP()) < 0.4 then
            self:StopEngine()
            if not self:IsOnFire() then
                Engine:Ignite(10, Engine:BoundingRadius())
            end
            Engine:SetDestroyed(true)
        end
    end

    LVS_HandleFireLogic(self, dmginfo, damage, critical, engineDying, ammorackDestroyed)

    curHP = self:GetHP()
    if damage <= 0 then return end

    if not critical and isSmall then
        damage = 1
    elseif critical and isSmall then
        damage = damage / 2
    end

    if not critical and curHP <= 5 and curHP >= 1 and not isFire then
        damage = 0.002 * damage
    end

    if vehType == "armored" and not isExplosion and not isFire and isInDying then
        damage = 0.002 * damage
    end

    local newHP = math.Clamp(curHP - damage, -maxHP, maxHP)

    self:SetHP(newHP)

    if self:IsDestroyed() then return end

    local attacker = dmginfo:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and not dmginfo:IsDamageType(DMG_BURN) then
        net.Start("lvs_hitmarker")
            net.WriteBool(critical)
        net.Send(attacker)
    end

    if damage > 1 and not isCollision and not dmginfo:IsDamageType(DMG_BURN) then
        net.Start("lvs_hurtmarker")
            net.WriteFloat(math.min(damage / 50, 1))
        net.Send(self:GetEveryone())
    end

    local otherCondition = newHP <= 0
    local planeCondition = (vehType == "plane" or vehType == "helicopter") and isCollision and isFire
    local armoredCondition = vehType == "armored" and ((self:IsOnFire() and isFire) or ammorackDestroyed)
    local lightCondition = vehType == "light"

    -- crutches

    local delay = 0.5
    if armoredCondition then delay = 0 end

    if not self.ExplosionPending then
        self.ExplosionPending = true

        timer.Simple(delay, function()
            if not IsValid(self) then return end
            LVS_Explode(self, dmginfo)
        end)
    end

    -- end
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