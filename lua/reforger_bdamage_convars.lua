if SERVER then
    local FCVAR_SERVER = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY)
    CreateConVar("reforger_enable_gibs", "0", FCVAR_SERVER, "Keep vehicle gibs in your map", 0, 1)
end