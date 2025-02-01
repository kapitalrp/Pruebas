-- server/main.lua
ESX = exports["es_extended"]:getSharedObject()

local currentTournament = nil  -- Datos del torneo actual
local activeMatches = {}       -- [source] = match en curso

-- Función auxiliar para contar elementos en una tabla
local function tablelength(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end

-- Función para barajar una tabla (para emparejamientos aleatorios)
local function shuffleTable(tbl)
    math.randomseed(os.time())
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

---------------------------------------------------------------
-- EVENTO: Crear torneo (iniciado desde el cliente/admin)
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:createTournament')
AddEventHandler('esx_tournament:createTournament', function(data)
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end

    if xPlayer.getGroup() ~= 'admin' then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No tienes permiso para crear torneos.",
            type = "danger"
        })
        return
    end

    if currentTournament then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "Ya existe un torneo activo.",
            type = "danger"
        })
        return
    end

    currentTournament = {
        id = os.time(), -- Usamos el timestamp como ID único
        name = data.name,
        allowedWeapon = data.allowedWeapon,
        pointA = data.pointA,  -- Spawn para jugador 1
        pointB = data.pointB,  -- Spawn para jugador 2
        waitingRoom = data.waitingRoom, -- Sala de espera
        maxParticipants = data.maxParticipants or Config.DefaultMaxParticipants,
        reward = data.reward,  -- Tabla con la configuración de recompensa
        participants = {},
        currentRoundParticipants = {},
        status = 'registration', -- registration, in_progress, finished
        round = 0,
        matches = {}
    }

    TriggerClientEvent('atr_ui:CreateNotification', -1, {
        title = "Torneo Abierto",
        description = "Se ha abierto el registro para el torneo: " .. data.name,
        type = "info",
        isPersistent = true,
        id = "tournament_status"
    })

    -- Abre el menú de inscripción para todos los jugadores
    TriggerClientEvent('esx_tournament:openJoinMenu', -1, currentTournament.id)

    Citizen.CreateThread(function()
        Citizen.Wait(Config.RegistrationTime)
        if currentTournament and currentTournament.status == 'registration' then
            startTournament()
        end
    end)
end)

---------------------------------------------------------------
-- EVENTO: Unirse al torneo
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:joinTournament')
AddEventHandler('esx_tournament:joinTournament', function(tournamentId)
    local _source = source
    if not currentTournament or currentTournament.id ~= tournamentId then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No hay torneo activo para unirse.",
            type = "danger"
        })
        return
    end

    if currentTournament.status ~= 'registration' then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "El registro para este torneo ya ha cerrado.",
            type = "danger"
        })
        return
    end

    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end

    -- Evitar registros duplicados
    for _, participant in ipairs(currentTournament.participants) do
        if participant.identifier == xPlayer.identifier then
            TriggerClientEvent('atr_ui:CreateNotification', _source, {
                title = "Error",
                description = "Ya estás registrado en el torneo.",
                type = "warning"
            })
            return
        end
    end

    local participantData = {
        source = _source,
        identifier = xPlayer.identifier,
        name = xPlayer.getName() or ("ID " .. _source)
    }
    table.insert(currentTournament.participants, participantData)
    table.insert(currentTournament.currentRoundParticipants, participantData)
    
    -- Guardar la posición original del jugador aunque no haya sala de espera
    TriggerClientEvent("esx_tournament:storeOriginalPos", _source)

    -- Notificar y enviar a la sala de espera (si está definida)
    TriggerClientEvent('atr_ui:CreateNotification', _source, {
        title = "Inscripción",
        description = "Te has inscrito en el torneo: " .. currentTournament.name,
        type = "info"
    })
    if currentTournament.waitingRoom then
        TriggerClientEvent("esx_tournament:joinWaitingRoom", _source, currentTournament.waitingRoom)
    end

    -- Actualizar notificación persistente para todos
    TriggerClientEvent("esx_tournament:updateWaitingRoomNotification", -1, currentTournament.name, #currentTournament.participants, currentTournament.maxParticipants)

    -- Si se alcanza el máximo de cupos, iniciar el torneo automáticamente
    if #currentTournament.participants >= currentTournament.maxParticipants then
        startTournament()
    end
end)

---------------------------------------------------------------
-- EVENTO: Inicio forzado del torneo (por admin)
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:adminStartTournament')
AddEventHandler('esx_tournament:adminStartTournament', function()
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer or xPlayer.getGroup() ~= 'admin' then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No tienes permiso.",
            type = "danger"
        })
        return
    end
    if not currentTournament or currentTournament.status ~= 'registration' then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No hay torneo en registro.",
            type = "danger"
        })
        return
    end

    startTournament()
end)

---------------------------------------------------------------
-- EVENTO: Cancelar torneo (por admin)
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:cancelTournament')
AddEventHandler('esx_tournament:cancelTournament', function()
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer or xPlayer.getGroup() ~= 'admin' then
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No tienes permiso para cancelar torneos.",
            type = "danger"
        })
        return
    end
    if currentTournament then
        TriggerClientEvent('atr_ui:CreateNotification', -1, {
            title = "Torneo Cancelado",
            description = "El torneo " .. currentTournament.name .. " ha sido cancelado por un administrador.",
            type = "danger",
            isPersistent = true,
            id = "tournament_status"
        })
        currentTournament = nil
    else
        TriggerClientEvent('atr_ui:CreateNotification', _source, {
            title = "Error",
            description = "No hay torneo activo para cancelar.",
            type = "warning"
        })
    end
end)

---------------------------------------------------------------
-- Función: Iniciar el torneo (cierre del registro o forzado)
---------------------------------------------------------------
function startTournament()
    if not currentTournament then return end
    if tablelength(currentTournament.participants) < 2 then
        TriggerClientEvent('atr_ui:CreateNotification', -1, {
            title = "Error",
            description = "No hay suficientes jugadores para iniciar el torneo.",
            type = "danger",
            isPersistent = true,
            id = "tournament_status"
        })
        currentTournament = nil
        return
    end

    currentTournament.status = 'in_progress'
    currentTournament.round = 1
    TriggerClientEvent('atr_ui:CreateNotification', -1, {
        title = "Torneo Iniciado",
        description = "El torneo " .. currentTournament.name .. " ha comenzado! (Round 1)",
        type = "info",
        isPersistent = true,
        id = "tournament_status"
    })
    scheduleMatches()
end

---------------------------------------------------------------
-- Función: Programar los matches para el round actual
---------------------------------------------------------------
function scheduleMatches()
    if not currentTournament then return end
    local roundPlayers = currentTournament.currentRoundParticipants
    if #roundPlayers < 1 then
        TriggerClientEvent('atr_ui:CreateNotification', -1, {
            title = "Torneo Finalizado",
            description = "El torneo ha finalizado.",
            type = "info",
            isPersistent = true,
            id = "tournament_status"
        })
        -- Remover la notificación persistente
        TriggerClientEvent('atr_ui:RemoveNotification', -1, "tournament_status")
        currentTournament = nil
        return
    end

    -- Si solo queda un jugador, es el ganador
    if #roundPlayers == 1 then
        local winner = roundPlayers[1]
        TriggerClientEvent('atr_ui:CreateNotification', -1, {
            title = "Torneo Finalizado",
            description = "El ganador del torneo " .. currentTournament.name .. " es " .. winner.name,
            type = "success",
            isPersistent = true,
            id = "tournament_status"
        })
        if currentTournament.reward then
            awardReward(winner.source, currentTournament.reward)
        end
        -- Teletransportar ganador si finaliza
        TriggerClientEvent('esx_tournament:returnOriginal', winner.source)
        -- Remover la notificación persistente
        TriggerClientEvent('atr_ui:RemoveNotification', -1, "tournament_status")
        currentTournament = nil
        return
    end

    roundPlayers = shuffleTable(roundPlayers)
    currentTournament.matches = {}
    local nextRoundPlayers = {}

    while #roundPlayers >= 2 do
        local p1 = table.remove(roundPlayers, 1)
        local p2 = table.remove(roundPlayers, 1)
        local match = {
            player1 = p1,
            player2 = p2,
            winner = nil,
            finished = false
        }
        table.insert(currentTournament.matches, match)
    end

    -- Si sobra un jugador (bye)
    if #roundPlayers == 1 then
        local byePlayer = roundPlayers[1]
        TriggerClientEvent('atr_ui:CreateNotification', byePlayer.source, {
            title = "Bye",
            description = "No hay oponente, avanzas al siguiente round.",
            type = "info"
        })
        table.insert(nextRoundPlayers, byePlayer)
    end

    currentTournament.currentRoundParticipants = nextRoundPlayers

    for i, match in ipairs(currentTournament.matches) do
        startMatch(match, i)
        Citizen.Wait(5000)
    end
end

---------------------------------------------------------------
-- Función: Iniciar un match específico
---------------------------------------------------------------
function startMatch(match, matchIndex)
    if not match then return end

    local player1 = match.player1
    local player2 = match.player2

    if not player1 or not player2 then return end

    TriggerClientEvent('atr_ui:CreateNotification', player1.source, {
        title = "Match",
        description = "Match contra " .. player2.name .. " iniciará en " .. Config.MatchCountdown .. " segundos.",
        type = "info"
    })
    TriggerClientEvent('atr_ui:CreateNotification', player2.source, {
        title = "Match",
        description = "Match contra " .. player1.name .. " iniciará en " .. Config.MatchCountdown .. " segundos.",
        type = "info"
    })

    Citizen.SetTimeout(Config.MatchCountdown * 1000, function()
        TriggerClientEvent('esx_tournament:startMatch', player1.source, {
            spawn = currentTournament.pointA,
            allowedWeapon = currentTournament.allowedWeapon,
            ammo = Config.WeaponAmmo,
            opponent = player2.name
        })
        TriggerClientEvent('esx_tournament:startMatch', player2.source, {
            spawn = currentTournament.pointB,
            allowedWeapon = currentTournament.allowedWeapon,
            ammo = Config.WeaponAmmo,
            opponent = player1.name
        })
        activeMatches[player1.source] = match
        activeMatches[player2.source] = match
    end)
end

---------------------------------------------------------------
-- Función: Terminar un match, registrando ganador y perdedor
---------------------------------------------------------------
function onMatchFinish(match, winner, loser)
    if not currentTournament then return end
    if match.finished then return end
    match.finished = true
    match.winner = winner
    table.insert(currentTournament.currentRoundParticipants, winner)
    TriggerClientEvent('atr_ui:CreateNotification', winner.source, {
        title = "Match Ganado",
        description = "¡Has ganado el match!",
        type = "success"
    })
    -- Quitar el arma también al ganador
    TriggerClientEvent('esx_tournament:matchWon', winner.source, currentTournament.allowedWeapon)
    -- Forzar al perdedor a estar vivo antes de teletransportarlo
    TriggerClientEvent('esx_tournament:forceAlive', loser.source)
    TriggerClientEvent('esx_tournament:matchLost', loser.source, currentTournament.allowedWeapon)
    checkRoundCompletion()
end

---------------------------------------------------------------
-- EVENTO: Se notifica la muerte de un jugador en un match
---------------------------------------------------------------
RegisterNetEvent('esx_tournament:playerDied')
AddEventHandler('esx_tournament:playerDied', function()
    local _source = source
    if not activeMatches[_source] then return end
    local match = activeMatches[_source]
    if match.finished then return end

    local winner, loser
    if match.player1.source == _source then
        winner = match.player2
        loser = match.player1
    else
        winner = match.player1
        loser = match.player2
    end

    activeMatches[match.player1.source] = nil
    activeMatches[match.player2.source] = nil

    onMatchFinish(match, winner, loser)
end)

---------------------------------------------------------------
-- Función: Verificar si todos los matches del round han finalizado
---------------------------------------------------------------
function checkRoundCompletion()
    if not currentTournament then return end
    local allFinished = true
    for i, match in ipairs(currentTournament.matches) do
        if not match.finished then
            allFinished = false
            break
        end
    end

    if allFinished then
        Citizen.Wait(3000)
        currentTournament.round = currentTournament.round + 1
        TriggerClientEvent('atr_ui:CreateNotification', -1, {
            title = "Nuevo Round",
            description = "Round " .. currentTournament.round .. " iniciará pronto.",
            type = "info",
            isPersistent = true,
            id = "tournament_status"
        })
        scheduleMatches()
    end
end

---------------------------------------------------------------
-- Función: Otorgar recompensa al ganador
---------------------------------------------------------------
function awardReward(playerSource, reward)
    local xPlayer = ESX.GetPlayerFromId(playerSource)
    if not xPlayer then return end
    if reward.type == "cash" then
        if reward.hand > 0 then xPlayer.addMoney(reward.hand) end
        if reward.bank > 0 then xPlayer.addAccountMoney("bank", reward.bank) end
        TriggerClientEvent('atr_ui:CreateNotification', playerSource, { 
            title = "Recompensa", 
            description = "Has recibido $" .. reward.hand .. " en efectivo y $" .. reward.bank .. " en banco.", 
            type = "success" 
        })
    elseif reward.type == "items" then
        for _, itemData in ipairs(reward.items) do
            local success, response = exports.ox_inventory:AddItem(xPlayer.identifier, itemData.name, itemData.count)
            if not success then
                TriggerClientEvent('atr_ui:CreateNotification', playerSource, { 
                    title = "Recompensa", 
                    description = "Error al entregar " .. itemData.name .. ": " .. response, 
                    type = "danger" 
                })
            else
                TriggerClientEvent('atr_ui:CreateNotification', playerSource, { 
                    title = "Recompensa", 
                    description = "Has recibido " .. itemData.count .. " de " .. itemData.name, 
                    type = "success" 
                })
            end
        end
    elseif reward.type == "vehicle" then
        MySQL.Async.execute('INSERT INTO owned_vehicles (owner, vehicle) VALUES (@owner, @vehicle)', {
            ['@owner'] = xPlayer.identifier,
            ['@vehicle'] = json.encode({model = reward.model, plate = reward.plate})
        }, function(rowsChanged)
            if rowsChanged > 0 then
                TriggerClientEvent('atr_ui:CreateNotification', playerSource, { 
                    title = "Recompensa", 
                    description = "Vehículo agregado a tu garaje.", 
                    type = "success" 
                })
            else
                TriggerClientEvent('atr_ui:CreateNotification', playerSource, { 
                    title = "Recompensa", 
                    description = "Error al agregar el vehículo.", 
                    type = "danger" 
                })
            end
        end)
    end
end

---------------------------------------------------------------
-- Manejo de desconexión de un jugador durante un match
---------------------------------------------------------------
AddEventHandler('playerDropped', function(reason)
    local _source = source
    if activeMatches[_source] then
        local match = activeMatches[_source]
        local winner, loser
        if match.player1.source == _source then
            winner = match.player2
            loser = match.player1
        else
            winner = match.player1
            loser = match.player2
        end

        activeMatches[match.player1.source] = nil
        activeMatches[match.player2.source] = nil

        onMatchFinish(match, winner, loser)
    end
end)
