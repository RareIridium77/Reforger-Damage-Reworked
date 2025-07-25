if not Glide then return end

local RDamage = Reforger.Damage
local Rotors = Reforger.Rotors

local getvehtype = Reforger.GetVehicleType
local getvehbase = Reforger.GetVehicleBase

local ignitelimited = RDamage.IgniteLimited
local stopignitelimited = RDamage.StopLimitedFire

local isfiredamage = RDamage.IsFireDamageType
local iscollisiondamage = RDamage.IsCollisionDamageType
local issmalldamage = RDamage.IsSmallDamageType

local handleCollisionDamage = RDamage.HandleCollisionDamage
local applyPlayersDamage = RDamage.ApplyPlayersDamage
local handleRayDamage = RDamage.HandleRayDamage
local fixDamageForce = RDamage.FixDamageForce

local rotorsGetDamage = Rotors.RotorsGetDamage

local devlog   = Reforger.DevLog
local safeint  = Reforger.SafeInt

local istable  = istable
local isnumber = isnumber
local IsValid  = IsValid

local VehicleTypes = Glide.VEHICLE_TYPE
local VehicleType_Reduce = {
    [VehicleTypes.CAR] = 0.05,
    [VehicleTypes.MOTORCYCLE] = 0.05,
    [VehicleTypes.TANK] = 0.05,
    [VehicleTypes.HELICOPTER] = 0.075,
    [VehicleTypes.PLANE] = 0.075,
    [VehicleTypes.BOAT] = 0.05,
    [VehicleTypes.UNDEFINED] = 0.05,
}

local function Glide_GetReducedDamage(self, dmg)
    if not IsValid(self) or not self.VehicleType then return dmg end
    return dmg * (VehicleType_Reduce[self.VehicleType] or 1)
end

local function Glide_OnTakeDamage( self, dmginfo )
    if self.hasExploded then return end

    local Attacker = dmginfo:GetAttacker()

    fixDamageForce(dmginfo, Attacker, self)

    local Damage = dmginfo:GetDamage()
    if Damage <= 0 then return end

    -- Conditions
    local DamageType        = dmginfo:GetDamageType()

    local Type              = getvehtype(self)
    local Base              = getvehbase(self)
    local IsFireDamage      = isfiredamage(self, DamageType)
    local IsCollisionDamage = iscollisiondamage(DamageType)
    local IsSmallDamage     = issmalldamage(DamageType)

    -- End
    
    -- Engine Damage

    if not IsSmallDamage or IsFireDamage then
        local multiplier = 1

        if self.VehicleType == VehicleTypes.MOTORCYCLE then -- special situation for motorcycle
            multiplier = 3
        end

        dmginfo:SetDamageForce(Vector(0, 0, 0))

        self:TakeEngineDamage( (Damage / self.MaxChassisHealth) * self.EngineDamageMultiplier * multiplier )
    end

    -- End

    --  Other Damage
    rotorsGetDamage(self, dmginfo)
    handleCollisionDamage(self, dmginfo)

    if IsFireDamage then
        applyPlayersDamage(self, dmginfo)
    end

    -- End

    -- Damage Reduce

    if dmginfo:IsDamageType( DMG_BLAST ) then
        Damage = 0.65 * Damage
    elseif IsSmallDamage then
        Damage = Glide_GetReducedDamage(self, Damage)
    end

    -- End

    -- Damage players
    
    if IsSmallDamage and not dmginfo:IsDamageType(DMG_CLUB) and Type ~= "armored" then handleRayDamage(self, dmginfo) end

    -- End

    -- Applying Damage

    local CurHealth = self:GetChassisHealth()

    if IsSmallDamage and CurHealth <= 3.5 and CurHealth >= 1 then return end
    if IsSmallDamage and Type == "armored" then return end

    local NewHealth = math.Clamp( CurHealth - Damage, 0, self.MaxChassisHealth )

    self:SetChassisHealth( NewHealth )
    self:UpdateHealthOutputs()

    -- End

    self.lastDamageAttacker = Attacker
    self.lastDamageInflictor = dmginfo:GetInflictor()

    local fire_condition = false

    if self.VehicleType == VehicleTypes.MOTORCYCLE or self.VehicleType == VehicleTypes.BOAT then
        fire_condition = (NewHealth / self.MaxChassisHealth) < 0.99 and self:WaterLevel() < 3 and self.CanCatchOnFire
    else
        fire_condition = (NewHealth / self.MaxChassisHealth) < 0.45 and self:WaterLevel() < 3 and self.CanCatchOnFire
    end

    if fire_condition and not IsCollisionDamage then
        self:SetIsEngineOnFire( true )
        ignitelimited(self)
    end

    if NewHealth <= 0 then
        stopignitelimited(self)
        self:Explode( self.lastDamageAttacker, self.lastDamageInflictor )
    end
end

local function Glide_RewriteDamageSystem(glide_object)
    if not IsValid(glide_object) then return end

    local class = glide_object:GetClass()

    if class == "glide_gib" then
        local allowgb = safeint("gibs.keep") > 0

        if allowgb then
			glide_object.reforgerGib = true
            glide_object:SetCollisionGroup(COLLISION_GROUP_VEHICLE)
            glide_object.Think = function() return false end
        end
        return 
    end

    if glide_object.IsGlideVehicle then
        devlog(string.gsub("Overriding damage system for: +", "+", tostring(glide_object)))

        -- On Take Damage
        glide_object.OnTakeDamage = Glide_OnTakeDamage
        -- End

        -- After Repair
        local repairfunc = glide_object.Repair

        glide_object.Repair = function(self)
            glide_object:RemoveAllDecals()
            stopignitelimited(self)
            repairfunc(self)
        end
        -- End
    end
end

return {Glide_RewriteDamageSystem}