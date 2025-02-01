-- config.lua
Config = {}

Config.Locale = 'es'

-- Lista de armas disponibles para el torneo (label y el "value" para GiveWeaponToPed)
Config.WeaponsList = {
    {label = "Pistola", value = "weapon_pistol"},
    {label = "Pistola de Combate", value = "weapon_combatpistol"},
    {label = "SMG", value = "weapon_smg"},
    {label = "Carabina", value = "weapon_carbinerifle"}
}

-- Tiempo de registro del torneo (en milisegundos)
Config.RegistrationTime = 60000       -- 60 segundos

-- Cuenta regresiva (en segundos) para el inicio de cada match
Config.MatchCountdown = 5            -- 10 segundos

-- Cantidad de munición que se entregará con el arma permitida en el match (se dará 500)
Config.WeaponAmmo = 500

-- Tiempo (en segundos) de espera para revivir al jugador que perdió (usando esx_ambulancejob)
Config.ReviveDelay = 5

-- Número máximo de participantes por defecto (si no se configura, se usará este valor)
Config.DefaultMaxParticipants = 8

-- Radio (en metros) de la sala de espera
Config.WaitingRoomRadius = 5
