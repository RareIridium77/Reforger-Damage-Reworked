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

local function Glide_AirplaneDamage(self, dmginfo)
    if not IsValid(self) then return end

    if not istable(self.rotors) then return end

    local rotor = Reforger.FindRotorsAlongRay(self, dmginfo)

    if not IsValid(rotor) then return end

    rotor.rotorHealth = rotor.rotorHealth - dmginfo:GetDamage() / 2

    if rotor.rotorHealth <= 0 and isfunction(rotor.Destroy) then
        rotor:Destroy()
        Reforger.DevLog("Rotor destroyed: " .. tostring(rotor))
    end
end

local function Glide_OnTakeDamage( self, dmginfo )
    if self.hasExploded then return end

    local Damage = dmginfo:GetDamage()
    if Damage <= 0 then return end

    -- Conditions

    local IsFireDamage = dmginfo:IsDamageType( DMG_BURN ) or dmginfo:IsDamageType( DMG_DIRECT )
    local IsCollisionDamage = dmginfo:IsDamageType(DMG_CRUSH)
    local IsSmallDamage = dmginfo:IsDamageType( DMG_BULLET ) or dmginfo:IsDamageType( DMG_CLUB ) or dmginfo:IsDamageType( DMG_BUCKSHOT )
    local Type = Reforger.GetVehicleType(self)

    -- End
    
    if Type == "plane" or Type == "helicopter" then
        Glide_AirplaneDamage(self, dmginfo)
    end

    -- Engine Damage

    if not IsSmallDamage or IsFireDamage then
        local multiplier = 1

        if self.VehicleType == VehicleTypes.MOTORCYCLE then -- special situation for motorcycle
            multiplier = 3
        end

        self:TakeEngineDamage( (Damage / self.MaxChassisHealth) * self.EngineDamageMultiplier * multiplier )
    end

    -- End

    -- Burn Damage Players
    Reforger.ApplyPlayerFireDamage(self, dmginfo)
    -- End

    -- Damage Reduce

    if dmginfo:IsDamageType( DMG_BLAST ) then
        Damage = 0.65 * Damage
    elseif IsSmallDamage then
        Damage = Glide_GetReducedDamage(self, Damage)
    end

    -- End

    -- Damage players
    
    if IsSmallDamage and not dmginfo:IsDamageType(DMG_CLUB) and Type ~= "armored" then Reforger.DamagePlayer(self, dmginfo) end

    -- End

    -- Applying Damage

    local CurHealth = self:GetChassisHealth()

    if IsSmallDamage and CurHealth <= 3.5 and CurHealth >= 1 then return end
    if IsSmallDamage and Type == "armored" then return end

    local NewHealth = math.Clamp( CurHealth - Damage, 0, self.MaxChassisHealth )

    self:SetChassisHealth( NewHealth )
    self:UpdateHealthOutputs()

    -- End

    self.lastDamageAttacker = dmginfo:GetAttacker()
    self.lastDamageInflictor = dmginfo:GetInflictor()

    local fire_condition = false

    if self.VehicleType == VehicleTypes.MOTORCYCLE or self.VehicleType == VehicleTypes.BOAT then
        fire_condition = (NewHealth / self.MaxChassisHealth) < 0.99 and self:WaterLevel() < 3 and self.CanCatchOnFire
    else
        fire_condition = (NewHealth / self.MaxChassisHealth) < 0.45 and self:WaterLevel() < 3 and self.CanCatchOnFire
    end

    if fire_condition and not IsCollisionDamage then
        self:SetIsEngineOnFire( true )
        self:Ignite(5, self:BoundingRadius())
    end

    if NewHealth <= 0 then
        self:Explode( self.lastDamageAttacker, self.lastDamageInflictor )
    end
end

local function Glide_RewriteDamageSystem(glide_veh)
    if not IsValid(glide_veh) then return end

    if glide_veh.IsGlideVehicle then
        Reforger.DevLog(string.gsub("Overriding damage system for: +", "+", tostring(glide_veh)))

        -- On Take Damage
        glide_veh.OnTakeDamage = Glide_OnTakeDamage
        -- End

        -- After Repair
        local repairfunc = glide_veh.Repair

        glide_veh.Repair = function(self)
            glide_veh:RemoveAllDecals()
            
            repairfunc(self)
        end
        -- End
    end
end

return {Glide_RewriteDamageSystem}