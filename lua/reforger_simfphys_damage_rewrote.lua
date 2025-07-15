if not simfphys then return end

local D = Reforger.Damage

-- ConVars
local playerDamageConvar = GetConVar("sv_simfphys_playerdamage")
local damageConvar = GetConVar("sv_simfphys_enabledamage")

local function Simfphys_RewriteProjectileDamage(proj)
	if not IsValid(proj) then return end

	if proj.Damage and proj.BlastDamage then
		proj.Damage = 0.15 * proj.Damage
		proj.BlastDamage = 0.15 * proj.BlastDamage
	end
end

local function Simfphys_OnTakeDamage(self, dmginfo)
	if not self:IsInitialized() then return end
	if not damageConvar:GetBool() then return end
	if hook.Run("simfphysOnTakeDamage", self, dmginfo) then return end

	local Damage        = dmginfo:GetDamage()
	local DamagePos     = dmginfo:GetDamagePosition()
	local Type          = dmginfo:GetDamageType()
	local IsExplosion   = dmginfo:IsExplosionDamage()
	local IsFireDamage  = D.IsFireDamageType(self, Type)
	local IsSmallDamage = D.IsSmallDamageType(Type)

	local CriticalHit   = false

	local OldHP = self:GetCurHealth()
	local MaxHP = self:GetMaxHealth()

	self.LastAttacker = dmginfo:GetAttacker()
	self.LastInflictor = dmginfo:GetInflictor()

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

	if playerDamageConvar:GetBool() and IsFireDamage then
		D.ApplyPlayersDamage(self, dmginfo)
	end

	if self.IsArmored then
		if not IsSmallDamage then
			D.HandleRayDamage(self, dmginfo)
		end
	else
		D.HandleRayDamage(self, dmginfo)
	end

	if IsSmallDamage and self.IsArmored then return end

	if IsExplosion and (OldHP / MaxHP) < 0.3 and math.random() < 0.4 then
		if not self:IsOnFire() then
			D.IgniteLimited(self)
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
		D.IgniteLimited(self)
	end
end

-- FROM ORIGINAL SIMFPHYS 
local function Spark( pos , normal , snd )
	local effectdata = EffectData()
	effectdata:SetOrigin( pos - normal )
	effectdata:SetNormal( -normal )
	util.Effect( "stunstickimpact", effectdata, true, true )
	
	if snd then
		sound.Play( Sound( snd ), pos, 75)
	end
end

-- IN MAIN CHANGES IS THAT COLLISION WILL SEND DMG_CRUSH NOT DMG_GENERIC
local COLLISION_DAMAGE_SCALE = 0.15

local function Simfphys_PhysicsCollide(self, data, physobj)
	if hook.Run("simfphysPhysicsCollide", self, data, physobj) then return end

	local hitEnt = data.HitEntity

	if IsValid(hitEnt) then
		if hitEnt:IsNPC() or hitEnt:IsNextBot() or hitEnt:IsPlayer() then
			Spark(data.HitPos, data.HitNormal, "MetalVehicle.ImpactSoft")
			return
		end
	end

	if data.Speed > 60 and data.DeltaTime > 0.2 then
		local pos = data.HitPos
		local damageType = DMG_CRUSH

		if IsValid(hitEnt) and hitEnt:IsVehicle() then
			damageType = DMG_VEHICLE
		end

		local function applyCollisionDamage(damageAmount)
			local dmginfo = DamageInfo()
			dmginfo:SetDamage(damageAmount * COLLISION_DAMAGE_SCALE)
			dmginfo:SetDamageType(damageType)
			dmginfo:SetAttacker(self)
			dmginfo:SetInflictor(self)
			dmginfo:SetDamagePosition(pos)

			D.HandleCollisionDamage(self, dmginfo)

			self:TakeDamageInfo(dmginfo)
		end

		if data.Speed > 1000 then
			Spark(pos, data.HitNormal, "MetalVehicle.ImpactHard")
			self:HurtPlayers(5)
			applyCollisionDamage((data.Speed / 7) * simfphys.DamageMul)
		else
			Spark(pos, data.HitNormal, "MetalVehicle.ImpactSoft")

			if data.Speed > 250 then
				if not (IsValid(hitEnt) and hitEnt:IsPlayer()) then
					if simfphys.DamageMul > 1 then
						applyCollisionDamage((data.Speed / 28) * simfphys.DamageMul)
					end
				end
			end

			if data.Speed > 500 then
				self:HurtPlayers(2)
				applyCollisionDamage((data.Speed / 14) * simfphys.DamageMul)
			end
		end
	end
end

local function Simfphys_RewriteDamageSystem(simfphys_obj)
	if not IsValid(simfphys_obj) then return end

	local class = simfphys_obj:GetClass()

	-- Rewrite projectile damage
	if class == "simfphys_tankprojectile" then
		Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(simfphys_obj)))
		Simfphys_RewriteProjectileDamage(simfphys_obj)
		return
	end

	-- Rewriting gibs (if allowed)
	if class == "gmod_sent_vehicle_fphysics_gib" and simfphys_obj.MakeSound == true then
		local allowgb = Reforger.SafeInt("gibs.keep") > 0

		if allowgb then
			simfphys_obj.reforgerGib = true
			simfphys_obj:SetCollisionGroup(COLLISION_GROUP_VEHICLE)
			simfphys_obj.Think = function() return false end
		end
		return
	end

	-- Main vehicle rewrite
	if simfphys_obj.IsSimfphyscar then
		Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(simfphys_obj)))

		simfphys_obj.OnTakeDamage = Simfphys_OnTakeDamage
		simfphys_obj.PhysicsCollide = Simfphys_PhysicsCollide

		local repairfunc = simfphys_obj.OnRepaired
		simfphys_obj.OnRepaired = function(self)
			self:RemoveAllDecals()
			D.StopLimitedFire(self)

			if repairfunc then
				repairfunc(self)
			end
		end
	end
end

return { Simfphys_RewriteDamageSystem }
