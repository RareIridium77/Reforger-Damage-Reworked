return {
    LVS_HandleDamageReduction = function(self, dmginfo)
        if dmginfo:IsDamageType(self.DSArmorDamageReductionType) and dmginfo:GetDamage() > 0 then
            dmginfo:ScaleDamage(self.DSArmorDamageReduction)
            dmginfo:SetDamage(math.max(0.5 * dmginfo:GetDamage(), 1))
        end
    end,

    LVS_HandleExplosionModifier= function(self, dmginfo, vehType)
        local p = 0.15

        if vehType == "light" then p = 0.25 end
        if vehType == "plane" or vehType == "helicopter" then p = 0.2 end

        if dmginfo:IsExplosionDamage() then
            dmginfo:SetDamage(p * dmginfo:GetDamage())
        end
    end,

    LVS_HandleAirboatModifier = function(self, dmginfo)
        if dmginfo:IsDamageType(DMG_AIRBOAT) then
            dmginfo:SetDamage(0.15 * dmginfo:GetDamage())
        end
    end,

    LVS_HandleFireLogic = function(self, dmginfo, damage, critical, ammorackDestroyed)
        if self:IsOnFire() then return end

        local curHP, maxHP = self:GetHP(), self:GetMaxHP()
        local vehType = Reforger.GetVehicleType(self)

        if dmginfo:IsExplosionDamage() and not self:IsOnFire() and (curHP / maxHP) < 0.5 then
            Reforger.IgniteForever(self)
        end

        if ammorackDestroyed then
            Reforger.IgniteForever(self)
        end
    end
}