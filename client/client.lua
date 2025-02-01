-- client/main.lua
ESX = exports["es_extended"]:getSharedObject()

local inTournamentMatch = false
local currentTournamentId = nil
local waitingZone = nil
local originalPosition = nil  -- Posición original del jugador

---------------------------------------------------------------
-- Función para remover notificaciones (usando core_ui)
---------------------------------------------------------------
function removeNotification(id)
    SendNUIMessage({
        action = 'removeNotification',
        id = id
    })
end

---------------------------------------------------------------
-- Función CoreNotify: notificaciones con estilo
---------------------------------------------------------------
local function CoreNotify(message, notifType, duration)
    notifType = notifType or "default"
    duration = duration or 3000
    exports.core_ui:notify({
        id = "temp_" .. math.random(1000,9999),
        title = "<b>Notificación</b>",
        description = message,
        type = notifType,
        duration = duration,
        pulse = true
    })
end

---------------------------------------------------------------
-- Función de raycast (usando lib.raycast.fromCamera)
---------------------------------------------------------------
function startRaycast(callback)
    Citizen.CreateThread(function()
        local raycastActive = true
        while raycastActive do
            Citizen.Wait(0)
            DrawRect(0.5, 0.5, 0.01, 0.01, 255, 0, 0, 255)
            if IsControlJustReleased(0, 38) then -- Tecla E
                local hit, entityHit, endCoords, surfaceNormal, materialHash = lib.raycast.fromCamera(511, 4, 50)
                if hit then
                    raycastActive = false
                    callback(endCoords)
                    break
                else
                    CoreNotify("No se pudo obtener la ubicación. Intenta de nuevo.", "warning")
                end
            end
        end
    end)
end

---------------------------------------------------------------
-- Función para seleccionar recompensa
---------------------------------------------------------------
function openRewardSelection(callback)
    lib.registerContext({
        id = "reward_options",
        title = "Selecciona el tipo de recompensa",
        canClose = true,
        options = {
            {
                title = "Dinero en Efectivo",
                description = "Recompensa: Efectivo",
                icon = "money-bill-wave",
                onSelect = function()
                    local input = lib.inputDialog("Recompensa - Efectivo", {
                        { type = "number", label = "Cantidad de efectivo", required = true }
                    })
                    if input and input[1] then
                        callback({ type = "cash", hand = tonumber(input[1]), bank = 0 })
                    else
                        callback(nil)
                    end
                end
            },
            {
                title = "Dinero en Banco",
                description = "Recompensa: Banco",
                icon = "university",
                onSelect = function()
                    local input = lib.inputDialog("Recompensa - Banco", {
                        { type = "number", label = "Cantidad en banco", required = true }
                    })
                    if input and input[1] then
                        callback({ type = "cash", hand = 0, bank = tonumber(input[1]) })
                    else
                        callback(nil)
                    end
                end
            },
            {
                title = "Vehículo",
                description = "Recompensa: Vehículo",
                icon = "car",
                onSelect = function()
                    local input = lib.inputDialog("Recompensa - Vehículo", {
                        { type = "input", label = "Modelo del vehículo", required = true },
                        { type = "input", label = "Patente", required = true }
                    })
                    if input and input[1] and input[2] then
                        callback({ type = "vehicle", model = input[1], plate = input[2] })
                    else
                        callback(nil)
                    end
                end
            },
            {
                title = "Ítems",
                description = "Recompensa: Ítems",
                icon = "box",
                onSelect = function()
                    local itemsData = exports.ox_inventory:Items()  -- Supone que devuelve una tabla { itemName = { label = "Bread", ... }, ... }
                    local options = {}
                    for itemName, data in pairs(itemsData) do
                        table.insert(options, {
                            title = data.label,
                            description = "Selecciona este ítem",
                            icon = "box",
                            onSelect = function()
                                local input = lib.inputDialog("Recompensa - Ítems", {
                                    { type = "number", label = "Cantidad", required = true }
                                })
                                if input and input[1] then
                                    callback({ type = "items", items = { { name = itemName, count = tonumber(input[1]) } } })
                                else
                                    callback(nil)
                                end
                            end
                        })
                    end
                    lib.registerContext({
                        id = "reward_items",
                        title = "Selecciona un ítem",
                        menu = "reward_options",
                        canClose = true,
                        options = options
                    })
                    lib.showContext("reward_items")
                end
            }
        }
    })
    lib.showContext("reward_options")
end

---------------------------------------------------------------
-- Clase TournamentCreator (usando lib.class)
---------------------------------------------------------------
local TournamentCreator = lib.class("TournamentCreator")

function TournamentCreator:constructor()
    self.name = ""
    self.allowedWeapon = ""
    self.pointA = nil
    self.pointB = nil
    self.waitingRoom = nil
    self.maxParticipants = Config.DefaultMaxParticipants
    self.reward = nil  -- Configuración de recompensa
end

function TournamentCreator:registerMenu()
    lib.registerContext({
        id = "tournament_creation",
        title = "Creación de Torneo",
        canClose = true,
        options = {
            {
                title = "Establecer Nombre",
                description = "Nombre: " .. (self.name ~= "" and self.name or "No definido"),
                icon = "edit",
                onSelect = function()
                    local input = lib.inputDialog("Nombre del Torneo", {
                        { type = "input", label = "Ingresa el nombre", required = true }
                    })
                    if input and input[1] then
                        self.name = input[1]
                        self:registerMenu()
                        lib.showContext("tournament_creation")
                    end
                end
            },
            {
                title = "Seleccionar Arma",
                description = "Arma: " .. (self.allowedWeapon ~= "" and self.allowedWeapon or "No definida"),
                icon = "crosshairs",
                onSelect = function()
                    self:openWeaponMenu()
                end
            },
            {
                title = "Fijar Punto A",
                description = self.pointA and ("(" .. self.pointA.x .. ", " .. self.pointA.y .. ", " .. self.pointA.z .. ")") or "No definido",
                icon = "map-marker",
                onSelect = function()
                    CoreNotify("Apunta a la ubicación y presiona [E] para fijar Punto A", "info")
                    startRaycast(function(result)
                        self.pointA = result
                        self:registerMenu()
                        lib.showContext("tournament_creation")
                    end)
                end
            },
            {
                title = "Fijar Punto B",
                description = self.pointB and ("(" .. self.pointB.x .. ", " .. self.pointB.y .. ", " .. self.pointB.z .. ")") or "No definido",
                icon = "map-marker",
                onSelect = function()
                    CoreNotify("Apunta a la ubicación y presiona [E] para fijar Punto B", "info")
                    startRaycast(function(result)
                        self.pointB = result
                        self:registerMenu()
                        lib.showContext("tournament_creation")
                    end)
                end
            },
            {
                title = "Fijar Sala de Espera",
                description = self.waitingRoom and ("(" .. self.waitingRoom.x .. ", " .. self.waitingRoom.y .. ", " .. self.waitingRoom.z .. ")") or "No definida",
                icon = "home",
                onSelect = function()
                    CoreNotify("Apunta a la ubicación y presiona [E] para fijar la Sala de Espera", "info")
                    startRaycast(function(result)
                        self.waitingRoom = result
                        self:registerMenu()
                        lib.showContext("tournament_creation")
                    end)
                end
            },
            {
                title = "Establecer Cupos Máximos",
                description = "Cupos: " .. self.maxParticipants,
                icon = "users",
                onSelect = function()
                    lib.registerContext({
                        id = "tournament_maxParticipants",
                        title = "Selecciona cupos máximos",
                        menu = "tournament_creation",
                        canClose = true,
                        options = {
                            { title = "8", onSelect = function() self.maxParticipants = 8; self:registerMenu(); lib.showContext("tournament_creation") end },
                            { title = "16", onSelect = function() self.maxParticipants = 16; self:registerMenu(); lib.showContext("tournament_creation") end },
                            { title = "32", onSelect = function() self.maxParticipants = 32; self:registerMenu(); lib.showContext("tournament_creation") end }
                        }
                    })
                    lib.showContext("tournament_maxParticipants")
                end
            },
            {
                title = "Configurar Recompensa",
                description = self.reward and ("[" .. self.reward.type .. "]") or "No definida",
                icon = "gift",
                onSelect = function()
                    openRewardSelection(function(rewardData)
                        if rewardData then
                            self.reward = rewardData
                            CoreNotify("Recompensa configurada: [" .. rewardData.type .. "]", "success")
                        else
                            CoreNotify("Recompensa no configurada.", "warning")
                        end
                        self:registerMenu()
                        lib.showContext("tournament_creation")
                    end)
                end
            },
            {
                title = "Crear Torneo",
                icon = "check",
                onSelect = function()
                    if self.name == "" or self.allowedWeapon == "" or not self.pointA or not self.pointB or not self.waitingRoom then
                        CoreNotify("Debes completar todos los campos.", "warning")
                    else
                        TriggerServerEvent("esx_tournament:createTournament", {
                            name = self.name,
                            allowedWeapon = self.allowedWeapon,
                            pointA = self.pointA,
                            pointB = self.pointB,
                            waitingRoom = self.waitingRoom,
                            maxParticipants = self.maxParticipants,
                            reward = self.reward
                        })
                        CoreNotify("Torneo creado: " .. self.name, "success")
                    end
                end
            },
            {
                title = "Cancelar Torneo",
                icon = "times",
                onSelect = function()
                    TriggerServerEvent("esx_tournament:cancelTournament")
                    CoreNotify("Torneo cancelado.", "danger")
                end
            }
        }
    })
end

function TournamentCreator:openWeaponMenu()
    local options = {}
    local weaponList = cache("weapon_list", function() return Config.WeaponsList end, 60000)
    for _, w in ipairs(weaponList) do
        table.insert(options, {
            title = w.label .. " (" .. w.value .. ")",
            icon = "gun",
            onSelect = function()
                self.allowedWeapon = w.value
                self:registerMenu()
                lib.showContext("tournament_creation")
            end
        })
    end
    lib.registerContext({
        id = "tournament_weapon",
        title = "Selecciona el arma",
        menu = "tournament_creation",
        canClose = true,
        options = options
    })
    lib.showContext("tournament_weapon")
end

function TournamentCreator:openMenu()
    self:registerMenu()
    lib.showContext("tournament_creation")
end

local tournamentCreator = TournamentCreator:new()

---------------------------------------------------------------
-- Menú para inscribirse en el torneo (context menu)
---------------------------------------------------------------
lib.registerContext({
    id = "tournament_join",
    title = "Torneo abierto: ¿Deseas unirte?",
    canClose = true,
    options = {
        {
            title = "Unirse",
            icon = "sign-in-alt",
            onSelect = function()
                if currentTournamentId then
                    TriggerServerEvent("esx_tournament:joinTournament", currentTournamentId)
                else
                    CoreNotify("No hay torneo abierto para unirse.", "warning")
                end
            end
        },
        {
            title = "Cancelar",
            icon = "times",
            onSelect = function()
                lib.hideContext()
            end
        }
    }
})

---------------------------------------------------------------
-- Comandos
---------------------------------------------------------------
RegisterCommand('creartorneo', function()
    tournamentCreator = TournamentCreator:new()  -- Reinicia datos
    tournamentCreator:openMenu()
end, false)

RegisterCommand('unirseTorneo', function()
    if currentTournamentId then
        TriggerServerEvent("esx_tournament:joinTournament", currentTournamentId)
    else
        CoreNotify("No hay torneo abierto para unirse.", "warning")
    end
end, false)

RegisterCommand('iniciatorneo', function()
    TriggerServerEvent("esx_tournament:adminStartTournament")
end, false)

RegisterCommand('canceltorneo', function()
    TriggerServerEvent("esx_tournament:cancelTournament")
end, false)

---------------------------------------------------------------
-- Evento: Abrir menú para inscribirse
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:openJoinMenu')
AddEventHandler('esx_tournament:openJoinMenu', function(tournamentId)
    currentTournamentId = tournamentId
    lib.showContext("tournament_join")
end)

---------------------------------------------------------------
-- Evento: Actualizar notificación persistente de sala de espera
---------------------------------------------------------------
RegisterNetEvent("esx_tournament:updateWaitingRoomNotification")
AddEventHandler("esx_tournament:updateWaitingRoomNotification", function(tournamentName, currentCount, maxCount)
    exports.core_ui:notify({
         id = "tournament_status",
         title = "Torneo: " .. tournamentName,
         description = "Cupos: " .. currentCount .. "/" .. maxCount,
         isPersistent = true,
         type = "info"
    })
end)

---------------------------------------------------------------
-- Evento: Unirse a la sala de espera
---------------------------------------------------------------
RegisterNetEvent("esx_tournament:joinWaitingRoom")
AddEventHandler("esx_tournament:joinWaitingRoom", function(waitingRoomCoords)
    if not originalPosition then
        originalPosition = GetEntityCoords(PlayerPedId())
    end
    ESX.Game.Teleport(PlayerPedId(), waitingRoomCoords, function()
         CoreNotify("Bienvenido a la sala de espera del torneo", "info", 3000)
    end)
    if waitingZone then waitingZone:remove() end
    waitingZone = lib.zones.sphere({
         coords = waitingRoomCoords,
         radius = Config.WaitingRoomRadius,
         debug = false,
         onEnter = function(self)
             CoreNotify("Entraste a la sala de espera", "info", 2000)
         end,
         onExit = function(self)
             ESX.Game.Teleport(PlayerPedId(), waitingRoomCoords, function()
                 CoreNotify("No puedes salir de la sala de espera", "warning", 2000)
             end)
         end,
         inside = function(self)
             lib.disableControls:Add(24,25,142,106,140)
         end
    })
end)

---------------------------------------------------------------
-- Hilo para verificar que el jugador permanezca en la sala de espera
---------------------------------------------------------------
Citizen.CreateThread(function()
    while true do
         Citizen.Wait(500)
         if waitingZone then
              local pedCoords = GetEntityCoords(PlayerPedId())
              if not waitingZone:contains(pedCoords) then
                  ESX.Game.Teleport(PlayerPedId(), waitingZone.data.coords, function()
                      CoreNotify("No puedes salir de la sala de espera", "warning", 1500)
                  end)
              end
         end
    end
end)

---------------------------------------------------------------
-- Evento: Devolver al jugador a su posición original
---------------------------------------------------------------
RegisterNetEvent("esx_tournament:returnOriginal")
AddEventHandler("esx_tournament:returnOriginal", function()
    if originalPosition then
        ESX.Game.Teleport(PlayerPedId(), originalPosition, function()
            CoreNotify("Regresaste a tu posición original.", "info", 3000)
            originalPosition = nil
        end)
    end
end)

---------------------------------------------------------------
-- Evento: Iniciar match (teletransporte, asignación de arma, etc.)
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:startMatch')
AddEventHandler('esx_tournament:startMatch', function(data)
    if waitingZone then
         waitingZone:remove()
         waitingZone = nil
         lib.disableControls:Clear(24,25,142,106,140)
    end

    local spawn = data.spawn
    local allowedWeapon = data.allowedWeapon
    local ammo = data.ammo or Config.WeaponAmmo
    local opponent = data.opponent

    ESX.Game.Teleport(PlayerPedId(), spawn, function()
        CoreNotify("Match iniciado contra " .. opponent, "info")
        RemoveAllPedWeapons(PlayerPedId(), true)
        RemoveWeaponFromPed(PlayerPedId(), GetHashKey(allowedWeapon))  -- Extra seguridad
        Citizen.Wait(500)
        GiveWeaponToPed(PlayerPedId(), GetHashKey(allowedWeapon), ammo, false, true)
        SetPedArmour(PlayerPedId(), 0)
        SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
        inTournamentMatch = true
    end)
end)

---------------------------------------------------------------
-- Evento: Al perder el match se remueve el arma, se reviven y se retorna a la posición original
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:matchLost')
AddEventHandler('esx_tournament:matchLost', function(weapon)
    RemoveWeaponFromPed(PlayerPedId(), GetHashKey(weapon))
    CoreNotify("Has perdido el match. Tu arma del torneo ha sido removida.", "danger")
    inTournamentMatch = false
    Citizen.SetTimeout(Config.ReviveDelay * 1000, function()
        TriggerEvent('esx_ambulancejob:revive')
        Citizen.Wait(700)
        local playerPed = PlayerPedId()
        if originalPosition then
            ESX.Game.Teleport(playerPed, originalPosition, function()
                local dist = #(GetEntityCoords(playerPed) - originalPosition)
                if dist > 10.0 then
                    ESX.Game.Teleport(playerPed, originalPosition)
                end
            end)
        end
        CoreNotify("Has sido revivido. Volviendo a tu posición original...", "success")
        TriggerEvent("esx_tournament:returnOriginal")
    end)
end)

---------------------------------------------------------------
-- Evento: Al ganar el match se remueve el arma
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:matchWon')
AddEventHandler('esx_tournament:matchWon', function(weapon)
    RemoveWeaponFromPed(PlayerPedId(), GetHashKey(weapon))
    CoreNotify("Ganaste el match. Se te ha removido el arma.", "success")
    inTournamentMatch = false
end)

---------------------------------------------------------------
-- Evento: Almacenar la posición original del jugador
---------------------------------------------------------------
RegisterNetEvent("esx_tournament:storeOriginalPos")
AddEventHandler("esx_tournament:storeOriginalPos", function()
    if not originalPosition then
        originalPosition = GetEntityCoords(PlayerPedId())
    end
end)

---------------------------------------------------------------
-- Monitorización de la muerte durante un match
---------------------------------------------------------------
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if inTournamentMatch then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                inTournamentMatch = false
                TriggerServerEvent("esx_tournament:playerDied")
            end
        end
    end
end)
