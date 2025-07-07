return {
    LVS_HandleDamageReduction = function(self, dmginfo)
        if dmginfo:IsDamageType(self.DSArmorDamageReductionType) and dmginfo:GetDamage() > 0 then
            dmginfo:ScaleDamage(self.DSArmorDamageReduction)
            dmginfo:SetDamage(math.max(0.25 * dmginfo:GetDamage(), 1))
        end
    end,

    LVS_HandleExplosionModifier = function(self, dmginfo, vehType)
        if dmginfo:IsExplosionDamage() then
            local p = 0.125

            
            if vehType ~= "armored" then p = 1 end -- ALWAYS FIRST
            
            if vehType == "light" then p = 0.125 end
            if vehType == "plane" or vehType == "helicopter" then p = 0.145 end
            
            dmginfo:SetDamage(p * dmginfo:GetDamage())
        end
    end,

    LVS_HandleAirboatModifier = function(self, dmginfo)
        if dmginfo:IsDamageType(DMG_AIRBOAT) then
            dmginfo:SetDamage(math.random(0.085, 0.2) * dmginfo:GetDamage()) -- can add some random for nostalgia
        end
    end,

    LVS_HandleFireLogic = function(self, ammorackDestroyed)
        if self:IsOnFire() then return end

        if ammorackDestroyed then
            Reforger.IgniteForever(self)
        end
    end
}