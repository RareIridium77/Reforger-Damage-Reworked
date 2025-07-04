local function LVS_OnTakeDamage(self, dmginfo)
    if self.CalcShieldDamage then self:CalcShieldDamage( dmginfo ) end
    if self.CalcDamage then self:CalcDamage( dmginfo ) end
    if self.TakePhysicsDamage then self:TakePhysicsDamage( dmginfo ) end
    if self.OnAITakeDamage then self:OnAITakeDamage( dmginfo ) end
end

local function LVS_CalcDamage(self, dmginfo)
    if dmginfo:IsDamageType( self.DSArmorIgnoreDamageType ) then return end -- Ignoring LVS entity's Ignored damage type

    -- Damage Reduction
    if dmginfo:IsDamageType( self.DSArmorDamageReductionType ) then
		if dmginfo:GetDamage() ~= 0 then
			dmginfo:ScaleDamage( self.DSArmorDamageReduction )
			dmginfo:SetDamage( math.max(dmginfo:GetDamage(),1) )
		end
	end

    if dmginfo:IsDamageType( DMG_BLAST ) then dmginfo:SetDamage(0.25 * dmginfo:GetDamage()) end
    if dmginfo:IsDamageType( DMG_AIRBOAT ) then dmginfo:SetDamage(0.125 * dmginfo:GetDamage()) end

    -- End

    local Damage = dmginfo:GetDamage()
    local CurHealth = self:GetHP()
    local Engine = self.GetEngine and self:GetEngine() or nil

    -- Conditions

    local IsFireDamage = dmginfo:IsDamageType( DMG_BURN ) or dmginfo:IsDamageType(DMG_DIRECT)
    local IsCollisionDamage = dmginfo:GetDamageType() == ( DMG_CRUSH + DMG_VEHICLE )
    local IsSmallDamage = dmginfo:IsDamageType( DMG_BULLET ) or dmginfo:IsDamageType( DMG_CLUB ) or dmginfo:IsDamageType( DMG_BUCKSHOT ) -- Is this damage are small? (not critical)
    local CriticalHit = false

    if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not IsFireDamage then return end

    -- End

    -- Calculate Other Damage

    Reforger.ApplyPlayerFireDamage(self, dmginfo)

    if not IsCollisionDamage and not dmginfo:IsDamageType( DMG_CLUB ) then
        CriticalHit = self:CalcComponentDamage( dmginfo )

        if dmginfo:IsDamageType( DMG_AIRBOAT ) then
            Damage = 1.5 * Damage
        end

        Reforger.DamagePlayer(self, dmginfo)
    end

    if dmginfo:IsDamageType( DMG_BLAST ) and self:GetVehicleType() == "car" then
        if IsValid(Engine) and not Engine:GetDestroyed() then
            Engine:SetHP( math.max(1, Engine:GetHP() - Damage) )
            
            if (Engine:GetHP() / Engine:GetMaxHP()) < 0.25 then
                self:StopEngine()
                self:Ignite(10, self:BoundingRadius())
                Engine:SetDestroyed(true)
            end
        end
    end

    if self:GetVehicleType() == "plane" then
        if (CurHealth / self:GetMaxHP()) < 0.45 then
            self:Ignite(10, self:BoundingRadius())
            self:StopEngine()
        end
    end

    -- End

    -- Damage Calculation

    CurHealth = self:GetHP() -- Need's to be updated

    if Damage <= 0 then return end

    if not CriticalHit and IsSmallDamage then Damage = 1 end

    if CriticalHit and IsSmallDamage then Damage = Damage / 2 end

    if not CriticalHit and CurHealth <= 5 and CurHealth >= 1 then
        Damage = 0.002 * Damage
    end

    local NewHealth = math.Clamp( CurHealth - Damage, -self:GetMaxHP(), self:GetMaxHP() )

    -- End

    self:SetHP( NewHealth ) -- Apply new health to LVS entity

    if self:IsDestroyed() then return end

    -- Send Hitmarker data to client

    local Attacker = dmginfo:GetAttacker() 

    if IsValid( Attacker ) and Attacker:IsPlayer() and not IsFireDamage then
        net.Start( "lvs_hitmarker" )
            net.WriteBool( CriticalHit )
        net.Send( Attacker )
    end

    if Damage > 1 and not IsCollisionDamage and not IsFireDamage then
        net.Start( "lvs_hurtmarker" )
            net.WriteFloat( math.min( Damage / 50, 1 ) )
        net.Send( self:GetEveryone() )
    end

    -- End

    -- LVS Explosion

    if NewHealth <= 0  then
        self.FinalAttacker = dmginfo:GetAttacker() 
        self.FinalInflictor = dmginfo:GetInflictor()

        self:SetDestroyed( IsCollisionDamage )
        self:ClearPDS()

        local Attacker = self.FinalAttacker

        if IsValid( Attacker ) and Attacker:IsPlayer() then
            net.Start( "lvs_killmarker" )
            net.Send( Attacker )
        end

        local ExplodeTime = self:PreExplode( math.Clamp((self:GetVelocity():Length() - 200) / 200,1.5,16) )

        timer.Simple( ExplodeTime, function()
            if not IsValid( self ) then return end
            self:Explode()
        end)
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

                    local lvs_type = self:GetVehicleType() or nil
                    
                    if lvs_type == "car" or lvs_type == "plane" then
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

        lvs_entity.OnMaintenance = function(self, ...)
            self:ReforgerCleanDecals()

            if self:GetVehicleType() == "plane" and istable(self.rotors) and next(self.rotors) ~= nil then
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