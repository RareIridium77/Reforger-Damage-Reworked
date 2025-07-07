local function Simfphys_RewriteProjectileDamage(proj)
	if not IsValid(proj) then return end
	
	if proj.Damage and proj.BlastDamage then
		proj.Damage = 0.15 * proj.Damage
		proj.BlastDamage = 0.15 * proj.BlastDamage
	end
end

local function Simfphys_OnTakeDamage(self, dmginfo)
    if not self:IsInitialized() then return end
    if not simfphys.DamageEnabled then return end
	
    if hook.Run("simfphysOnTakeDamage", self, dmginfo) then return end
    
    local Damage = dmginfo:GetDamage()
    local DamagePos = dmginfo:GetDamagePosition()
    local Type = dmginfo:GetDamageType()

    self.LastAttacker = dmginfo:GetAttacker()
    self.LastInflictor = dmginfo:GetInflictor()
    
    local IsExplosion = dmginfo:IsExplosionDamage()
    local IsFireDamage = dmginfo:IsDamageType(DMG_BURN)
    local IsSmallDamage = dmginfo:IsDamageType(DMG_BULLET) or dmginfo:IsDamageType(DMG_CLUB) or dmginfo:IsDamageType(DMG_BUCKSHOT)
    local CriticalHit = false
    local OldHP = self:GetCurHealth()
    local MaxHP = self:GetMaxHealth()

    net.Start("simfphys_spritedamage")
        net.WriteEntity(self)
        net.WriteVector(self:WorldToLocal(DamagePos))
        net.WriteBool(false)
    net.Broadcast()

    if (LVS and Type == DMG_AIRBOAT) or dmginfo:IsDamageType(DMG_BLAST) then
        Type = DMG_DIRECT
        Damage = 0.75 * Damage
    end

    if IsSmallDamage then
        Damage = math.Rand(2, 5)
    end

    Reforger.ApplyPlayerFireDamage(self, dmginfo)
    Reforger.HandleCollisionDamage(self, dmginfo)

    if not IsSmallDamage and self.IsArmored then Reforger.HandleRayDamage(self, dmginfo) end
    if IsSmallDamage and self.IsArmored then return end

    if IsExplosion and (OldHP / MaxHP) < 0.3 and math.random() < 0.4 then
        if not self:IsOnFire() then
            Reforger.IgniteForever(self)
            Reforger.DevLog("Inner Fire started on Simfphys vehicle!")
        end
    end

    if IsSmallDamage and OldHP <= 3.5 and OldHP >= 1 then return end
    
    self:ApplyDamage(Damage, Type)

    local NewHP = self:GetCurHealth()
    if (NewHP / MaxHP) < 0.15 then
        CriticalHit = true
    end

    if LVS and OldHP ~= NewHP and IsValid(self.LastAttacker) and self.LastAttacker:IsPlayer() and not IsFireDamage then
        net.Start("lvs_hitmarker")
            net.WriteBool(CriticalHit)
        net.Send(self.LastAttacker)
    end

    if (NewHP / MaxHP) < 0.135 and not self:IsOnFire() and not IsExplosion then
        Reforger.IgniteForever(self)
    end
end

local function Simfphys_RewriteDamageSystem(simfphys_obj)
    if not IsValid(simfphys_obj) then return end

	-- Rewriting simfphys tank projectile (THAT KILLS LVS TANKS WITH ONE SHOT)
	local class = simfphys_obj:GetClass()

	if class == "simfphys_tankprojectile" then
		Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(simfphys_obj)))
		Simfphys_RewriteProjectileDamage(simfphys_obj)
		return
	end

    local allowgb = Reforger.SafeInt("keep_gibs") > 0

	if class == "gmod_sent_vehicle_fphysics_gib" and allowgb then
		Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(simfphys_obj)))
		
		simfphys_obj:SetCollisionGroup(COLLISION_GROUP_VEHICLE)

		simfphys_obj.Think = function()
			return false
		end
		return 
	end

    if simfphys_obj.IsSimfphyscar then
        Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(simfphys_obj)))
        
        -- On Take Damage
        simfphys_obj.OnTakeDamage = Simfphys_OnTakeDamage
        -- End

        -- On Repair vehicle
        local repairfunc = simfphys_obj.OnRepaired

        simfphys_obj.OnRepaired = function(self)
			self:RemoveAllDecals()

			Reforger.StopInfiniteFire(self)
			
			if repairfunc then
				repairfunc(self)
			end
		end
		
        -- End
    end
end

return {Simfphys_RewriteDamageSystem}