local handler = include("lvs/lvs_damage_funcs.lua")

local function LVS_OnTakeDamage(self, dmginfo)
    if self.CalcShieldDamage then self:CalcShieldDamage( dmginfo ) end
    if self.CalcDamage then self:CalcDamage( dmginfo ) end
    if self.TakePhysicsDamage then self:TakePhysicsDamage( dmginfo ) end
    if self.OnAITakeDamage then self:OnAITakeDamage( dmginfo ) end
end

local function LVS_CalcDamage(self, dmginfo)
    if dmginfo:IsDamageType( self.DSArmorIgnoreDamageType ) then return end

    local vehType = Reforger.GetVehicleType(self)
	local IsFireDamage = dmginfo:IsDamageType( DMG_BURN )
	local IsCollisionDamage = dmginfo:GetDamageType() == ( DMG_CRUSH + DMG_VEHICLE )
    local IsSmallDamage = dmginfo:GetDamageType() == ( DMG_CLUB + DMG_BULLET + DMG_BUCKSHOT )
    local IsExplosion = dmginfo:IsExplosionDamage()
    local IsAmmorackDestroyed = Reforger.IsAmmorackDestroyed( self )
	local CriticalHit = false

    local Engine = self.GetEngine and self:GetEngine() or nil
    local EngineIsDying = IsValid(Engine) and (Engine:GetHP() / Engine:GetMaxHP()) < 0.35
    local VehicleIsDying = (self:GetHP() / self:GetMaxHP()) < 0.35
    
    handler.LVS_HandleExplosionModifier(self, dmginfo, vehType)
	handler.LVS_HandleDamageReduction(self, dmginfo)
    handler.LVS_HandleAirboatModifier(self, dmginfo)

    Reforger.HandleCollisionDamage(self, dmginfo)

    local Damage = dmginfo:GetDamage()

	if dmginfo:GetDamageForce():Length() < self.DSArmorIgnoreForce and not IsFireDamage then return end

	if not IsCollisionDamage then
		CriticalHit = self:CalcComponentDamage( dmginfo )

        if IsExplosion and (EngineIsDying or VehicleIsDying) and math.random(0, 1) < 0.4 then -- 40% chance to Inner Fire
            if not self:IsOnFire() then
                if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
                    Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)
                    Reforger.IgniteForever(self)
                    Reforger.DevLog("Inner Fire was started!")
                end
            end
        end

        Reforger.HandleRayDamage(self, dmginfo)
        Reforger.RotorsGetDamage(self, dmginfo)
	end

    if IsFireDamage then
        Reforger.ApplyPlayerFireDamage(self, dmginfo)

        if self:IsOnFire() then
            Reforger.AmmoracksTakeTransmittedDamage(self, dmginfo)
            Reforger.DamageDamagableParts(self, dmginfo:GetDamage())
        end
    end

	if Damage <= 0 then return end

    if IsFireDamage and IsAmmorackDestroyed then
        Damage = 0.325 * Damage -- Reduce Ammorack given damage
    end

    local MaxHealth = self:GetMaxHP()
	local CurHealth = self:GetHP()

    if not CriticalHit and IsSmallDamage then
        Damage = 0.4 * Damage
    end

    if not CriticalHit and (CurHealth / MaxHealth) < 0.125 then
        Damage = 0.25 * Damage
    end

    -- Damage Clamping
    
    local minClamp = -MaxHealth

    if (not self:IsOnFire() and not IsExplosion) and (EngineIsDying or VehicleIsDying) then
        Damage = 0.1 * Damage
        minClamp = math.min(MaxHealth * 0.1, CurHealth)
    end

    if IsAmmorackDestroyed or (IsFireDamage and self:IsOnFire()) then minClamp = -MaxHealth end

    -- End

	local NewHealth = math.Clamp( CurHealth - Damage, minClamp, MaxHealth )

    if (NewHealth < minClamp or ammorackDestroyed) and vehType == "armored" then
        if not self:IsOnFire() then
            Reforger.IgniteForever(self)

            if not Reforger.GetNetworkValue(self, "Bool", "InnerFire") then
                Reforger.SetNetworkValue(self, "Bool", "InnerFire", true)
            end
        end
    end
    
	self:SetHP( NewHealth )

	if self:IsDestroyed() then return end

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

    if EngineIsDying and (NewHealth / MaxHealth) < 0.1 then Reforger.IgniteForever(self) end

	if NewHealth <= 0 or NewHealth <= 0 and vehType == "armored" and IsFireDamage then
		self.FinalAttacker = dmginfo:GetAttacker() 
		self.FinalInflictor = dmginfo:GetInflictor()

		self:SetDestroyed( IsCollisionDamage )
		self:ClearPDS()

		local Attacker = self.FinalAttacker

		if IsValid( Attacker ) and Attacker:IsPlayer() then
			net.Start( "lvs_killmarker" )
			net.Send( Attacker )
		end

		local ExplodeTime = self:PreExplode( math.Clamp((self:GetVelocity():Length() - 200) / 200, 1.5 ,16 ) )

        if vehType == "plane" or vehType == "helicopter" then
            ExplodeTime = 10
        end

        if IsAmmorackDestroyed then
            ExplodeTime = ExplodeTime * 2
        end

        if IsFireDamage and not IsAmmorackDestroyed then ExplodeTime = (ExplodeTime + 1) * 4 end

		timer.Simple( ExplodeTime, function()
			if not IsValid( self ) then return end

            Reforger.StopInfiniteFire(self)

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

                    if Type == "light" or Type == "plane" or Type == "helicopter" then
                        local wheels = self.GetWheels and self:GetWheels() or {}

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
        local onrepaired = lvs_entity.OnRepaired

        local Type = Reforger.GetVehicleType(self)

        lvs_entity.OnMaintenance = function(self, ...)
            self:ReforgerCleanDecals()

            Reforger.StopInfiniteFire(self)

            if Type == "plane" and istable(self.rotors) and next(self.rotors) ~= nil then
                for _, rotor in pairs(self.rotors) do
                    if rotor.Repair then
                        rotor:Repair()
                    end
                end
            end

            if onmainteance then onmainteance(self, ...) end
        end

        lvs_entity.OnRepaired = function(self, ...)
            Reforger.StopInfiniteFire(self)

            if Type == "plane" and istable(self.rotors) and next(self.rotors) ~= nil then
                for _, rotor in pairs(self.rotors) do
                    if rotor.Repair then
                        rotor:Repair()
                    end
                end
            end

            if onrepaired then onrepaired(self, ...) end
        end

        -- End
    end
end

return {LVS_RewriteDamageSystem}