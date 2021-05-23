local Keys = {
  ["ESC"] = 322, ["F1"] = 288, ["F2"] = 289, ["F3"] = 170, ["F5"] = 166, ["F6"] = 167, ["F7"] = 168, ["F8"] = 169, ["F9"] = 56, ["F10"] = 57,
  ["~"] = 243, ["1"] = 157, ["2"] = 158, ["3"] = 160, ["4"] = 164, ["5"] = 165, ["6"] = 159, ["7"] = 161, ["8"] = 162, ["9"] = 163, ["-"] = 84, ["="] = 83, ["BACKSPACE"] = 177,
  ["TAB"] = 37, ["Q"] = 44, ["W"] = 32, ["E"] = 38, ["R"] = 45, ["T"] = 245, ["Y"] = 246, ["U"] = 303, ["P"] = 199, ["["] = 39, ["]"] = 40, ["ENTER"] = 18,
  ["CAPS"] = 137, ["A"] = 34, ["S"] = 8, ["D"] = 9, ["F"] = 23, ["G"] = 47, ["H"] = 74, ["K"] = 311, ["L"] = 182,
  ["LEFTSHIFT"] = 21, ["Z"] = 20, ["X"] = 73, ["C"] = 26, ["V"] = 0, ["B"] = 29, ["N"] = 249, ["M"] = 244, [","] = 82, ["."] = 81,
  ["LEFTCTRL"] = 36, ["LEFTALT"] = 19, ["SPACE"] = 22, ["RIGHTCTRL"] = 70,
  ["HOME"] = 213, ["PAGEUP"] = 10, ["PAGEDOWN"] = 11, ["DELETE"] = 178,
  ["LEFT"] = 174, ["RIGHT"] = 175, ["TOP"] = 27, ["DOWN"] = 173,
  ["NENTER"] = 201, ["N4"] = 108, ["N5"] = 60, ["N6"] = 107, ["N+"] = 96, ["N-"] = 97, ["N7"] = 117, ["N8"] = 61, ["N9"] = 118
}

local PlayerData              = {}
local GUI                     = {}
local HasAlreadyEnteredMarker = false
local LastZone                = nil
local CurrentAction           = nil
local CurrentActionMsg        = ''
local CurrentActionData       = {}
local OnJob                   = false
local TargetCoords            = nil
local CurrentlyTowedVehicle   = nil
local Blips                   = {}
local NPCOnJob                = false
local NPCTargetTowable        = nil
local NPCTargetTowableZone    = nil
local NPCHasSpawnedTowable    = false
local NPCLastCancel           = GetGameTimer() - 5 * 60000
local NPCHasBeenNextToTowable = false
local NPCTargetDeleterZone    = false
local IsDead                  = false

local OnDuty				  = false

local VehicleHoods = {}

ESX                           = nil
GUI.Time                      = 0

Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
		Citizen.Wait(0)
	end
	
	Citizen.Wait(5000)
	PlayerData = ESX.GetPlayerData()
end)

function SelectRandomTowable()

  local index = GetRandomIntInRange(1,  #Config.Towables)

  for k,v in pairs(Config.Zones) do
    if v.Pos.x == Config.Towables[index].x and v.Pos.y == Config.Towables[index].y and v.Pos.z == Config.Towables[index].z then
      return k
    end
  end

end
function SetVehicleMaxMods(vehicle)
local number = math.random(100,999)
  local props = {

    modTurbo        = true,
    dirtLevel       = 0,
    plate           = 'MECH '..number ,
  }

  ESX.Game.SetVehicleProperties(vehicle, props)

end
function StartNPCJob()

  NPCOnJob = true

  NPCTargetTowableZone = SelectRandomTowable()
  local zone       = Config.Zones[NPCTargetTowableZone]

  Blips['NPCTargetTowableZone'] = AddBlipForCoord(zone.Pos.x,  zone.Pos.y,  zone.Pos.z)
  SetBlipRoute(Blips['NPCTargetTowableZone'], true)

  ESX.ShowNotification(_U('drive_to_indicated'))
end

function StopNPCJob(cancel)

  if Blips['NPCTargetTowableZone'] ~= nil then
    RemoveBlip(Blips['NPCTargetTowableZone'])
    Blips['NPCTargetTowableZone'] = nil
  end

  if Blips['NPCDelivery'] ~= nil then
    RemoveBlip(Blips['NPCDelivery'])
    Blips['NPCDelivery'] = nil
  end


  Config.Zones.VehicleDelivery.Type = -1

  NPCOnJob                = false
  NPCTargetTowable        = nil
  NPCTargetTowableZone    = nil
  NPCHasSpawnedTowable    = false
  NPCHasBeenNextToTowable = false

  if cancel then
    ESX.ShowNotification(_U('mission_canceled'))
  else
    TriggerServerEvent('esx_mecanojob:onNPCJobCompleted')
  end

end

function OpenMecanoActionsMenu()

  local elements = {
    {label = "Pojazdy", value = 'vehicle_list'},
    {label = "Ubrania robocze", value = 'cloakroom'},
    {label = "Ubranie cywilne", value = 'cloakroom2'},
	{label = "Umieść przedmioty", value = 'put_stock'}
  }
  
  table.insert(elements, {label = "Wyciągnij przedmioty", value = 'get_stock'})
  
  if Config.EnablePlayerManagement and PlayerData.job ~= nil and PlayerData.job.grade_name == 'boss' then
    table.insert(elements, {label = _U('boss_actions'), value = 'boss_actions'})
  end

  ESX.UI.Menu.CloseAll()

  ESX.UI.Menu.Open(
    'default', GetCurrentResourceName(), 'mecano_actions',
    {
      title    = _U('mechanic'),
      align    = 'center',
      elements = elements
    },
    function(data, menu)
      if data.current.value == 'vehicle_list' then

        if Config.EnableSocietyOwnedVehicles then

            local elements = {}

            ESX.TriggerServerCallback('esx_society:getVehiclesInGarage', function(vehicles)

              for i=1, #vehicles, 1 do
                table.insert(elements, {label = GetDisplayNameFromVehicleModel(vehicles[i].model) .. ' [' .. vehicles[i].plate .. ']', value = vehicles[i]})
              end

              ESX.UI.Menu.Open(
                'default', GetCurrentResourceName(), 'vehicle_spawner',
                {
                  title    = _U('service_vehicle'),
                  align    = 'center',
                  elements = elements,
                },
                function(data, menu)

                  menu.close()

                  local vehicleProps = data.current.value

                  ESX.Game.SpawnVehicle(vehicleProps.model, Config.Zones.VehicleSpawnPoint.Pos, 0.0, function(vehicle)
                    ESX.Game.SetVehicleProperties(vehicle, vehicleProps)
                    local playerPed = GetPlayerPed(-1)
                    TaskWarpPedIntoVehicle(playerPed,  vehicle,  -1)
                  end)

                  TriggerServerEvent('esx_society:removeVehicleFromGarage', 'mecano', vehicleProps)

                end,
                function(data, menu)
                  menu.close()
                end
              )

            end, 'mecano')

          else

            local elements = {
              {label = "Duży Holownik", value = 'towtruck'},
			        {label = "Baller", value = 'baller2'},
              {label = "Mały Holownik", value = 'towtruck2'},
            }


            ESX.UI.Menu.CloseAll()

            ESX.UI.Menu.Open(
              'default', GetCurrentResourceName(), 'spawn_vehicle',
              {
                title    = _U('service_vehicle'),
                align    = 'center',
                elements = elements
              },
              function(data, menu)
                for i=1, #elements, 1 do
                  if Config.MaxInService == -1 then
                    ESX.Game.SpawnVehicle(data.current.value, Config.Zones.VehicleSpawnPoint.Pos, 269.93, function(vehicle)
                      SetVehicleMaxMods(vehicle)
                      local playerPed = GetPlayerPed(-1)
                      TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
                    end)
                    break
                  else
                    ESX.TriggerServerCallback('esx_service:enableService', function(canTakeService, maxInService, inServiceCount)
                      if canTakeService then
                        ESX.Game.SpawnVehicle(data.current.value, Config.Zones.VehicleSpawnPoint.Pos, 269.93, function(vehicle)
                          SetVehicleMaxMods(vehicle)
                          local playerPed = GetPlayerPed(-1)
                          TaskWarpPedIntoVehicle(playerPed,  vehicle, -1)
                        end)
                      else
                        TriggerEvent("pNotify:SendNotification", {text = _U('service_full') .. inServiceCount .. '/' .. maxInService})
                      end
                    end, 'mecano')
                    break
                  end
                end
                menu.close()
              end,
              function(data, menu)
                menu.close()
                OpenMecanoActionsMenu()
              end
            )

          end
      end

      if data.current.value == 'cloakroom' then
        menu.close()
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)

            if skin.sex == 0 then
                TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_male)
            else
                TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_female)
            end
			
			OnDuty = true

        end)
      end

      if data.current.value == 'cloakroom2' then
        menu.close()
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)

            TriggerEvent('skinchanger:loadSkin', skin)

        end)
		OnDuty = false
      end

      if data.current.value == 'put_stock' then
        OpenPutStocksMenu()
      end

      if data.current.value == 'get_stock' then
        OpenGetStocksMenu()
      end

      if data.current.value == 'boss_actions' then
        TriggerEvent('esx_society:openBossMenu', 'mecano', function(data, menu)
          menu.close()
        end)
      end

    end,
    function(data, menu)
      menu.close()
      CurrentAction     = 'mecano_actions_menu'
      CurrentActionMsg  = _U('open_actions')
      CurrentActionData = {}
    end
  )
end

function OpenMecanoHarvestMenu()

  if Config.EnablePlayerManagement and PlayerData.job ~= nil and PlayerData.job.grade_name ~= 'recrue' then
    local elements = {
      {label = _U('gas_can'), value = 'gaz_bottle'},
      {label = _U('repair_tools'), value = 'fix_tool'},
      {label = _U('body_work_tools'), value = 'caro_tool'}
    }

    ESX.UI.Menu.CloseAll()

    ESX.UI.Menu.Open(
      'default', GetCurrentResourceName(), 'mecano_harvest',
      {
        title    = _U('harvest'),
        align    = 'center',
        elements = elements
      },
      function(data, menu)
        if data.current.value == 'gaz_bottle' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startHarvest')
        end

        if data.current.value == 'fix_tool' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startHarvest2')
        end

        if data.current.value == 'caro_tool' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startHarvest3')
        end

      end,
      function(data, menu)
        menu.close()
        CurrentAction     = 'mecano_harvest_menu'
        CurrentActionMsg  = _U('harvest_menu')
        CurrentActionData = {}
      end
    )
  else
    ESX.ShowNotification(_U('not_experienced_enough'))
  end
end

function OpenMecanoCraftMenu()
  if Config.EnablePlayerManagement and PlayerData.job ~= nil and PlayerData.job.grade_name ~= 'recrue' then

    local elements = {
      {label = _U('blowtorch'), value = 'blow_pipe'},
      {label = _U('repair_kit'), value = 'fix_kit'},
      {label = _U('body_kit'), value = 'caro_kit'}
    }

    ESX.UI.Menu.CloseAll()

    ESX.UI.Menu.Open(
      'default', GetCurrentResourceName(), 'mecano_craft',
      {
        title    = _U('craft'),
        align    = 'center',
        elements = elements
      },
      function(data, menu)
        if data.current.value == 'blow_pipe' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startCraft')
        end

        if data.current.value == 'fix_kit' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startCraft2')
        end

        if data.current.value == 'caro_kit' then
          menu.close()
          TriggerServerEvent('esx_mecanojob:startCraft3')
        end

      end,
      function(data, menu)
        menu.close()
        CurrentAction     = 'mecano_craft_menu'
        CurrentActionMsg  = _U('craft_menu')
        CurrentActionData = {}
      end
    )
  else
    TriggerEvent("pNotify:SendNotification", {text = _U('not_experienced_enough')})
  end
end

RegisterNetEvent('esx_mecanojob:setVehicleHoodStates')
AddEventHandler('esx_mecanojob:setVehicleHoodStates', function(vehicle, stat)

	VehicleHoods[vehicle] = stat

end)

function OpenMobileMecanoActionsMenu()

  ESX.UI.Menu.CloseAll()

	-- ,
--	 {label = _U('imp_veh'),     value = 'del_vehicle'},
	-- {label = _U('flat_bed'),       value = 'dep_vehicle'},
	-- {label = _U('place_objects'), value = 'object_spawner'}
  local elements = {}
	table.insert(elements, {label = "Otwórz Zamek",     value = 'hijack_vehicle'})
    table.insert(elements, {label = "Napraw cały pojazd",       value = 'fix_vehicle'})
    table.insert(elements, {label = "Napraw silnik pojazdu",       value = 'fix_vehicle_engine'})
    table.insert(elements, {label = "Wyczyść pojazd",      value = 'clean_vehicle'})
	table.insert(elements, {label = "Odholuj Pojazd",      value = 'del_vehicle'})
    table.insert(elements, {label = "Otwórz/Zamknij maskę pojazdu",      value = 'open_hood_vehicle'})
	table.insert(elements, {label = "Sciągnij/Wciągnij pojazd na lawete",      value = 'put_on_flatbed'})
  ESX.UI.Menu.Open(
    'default', GetCurrentResourceName(), 'mobile_mecano_actions',
    {
      title    = _U('mechanic'),
      align    = 'center',
      elements = elements
    },
    function(data, menu)
      if data.current.value == 'billing' then
        ESX.UI.Menu.Open(
          'dialog', GetCurrentResourceName(), 'billing',
          {
            title = _U('invoice_amount')
          },
          function(data, menu)
            local amount = tonumber(data.value)
            if amount == nil or amount < 0 then
              TriggerEvent("pNotify:SendNotification", {text = _U('amount_invalid')})
            else
              menu.close()
              local closestPlayer, closestDistance = ESX.Game.GetClosestPlayer()
              if closestPlayer == -1 or closestDistance > 3.0 then
                TriggerEvent("pNotify:SendNotification", {text = _U('no_players_nearby')})
              else
                TriggerServerEvent('esx_billing:sendBill', GetPlayerServerId(closestPlayer), 'society_mecano', _U('mechanic'), amount)
              end
            end
          end,
        function(data, menu)
          menu.close()
        end
        )
      end

      if data.current.value == 'hijack_vehicle' then
  
		local playerPed = PlayerPedId()
		local vehicle   = ESX.Game.GetVehicleInDirection()
		local coords    = GetEntityCoords(playerPed)

		if IsPedSittingInAnyVehicle(playerPed) then
			TriggerEvent("pNotify:SendNotification", {text = _U('inside_vehicle')})
			return
		end

		if DoesEntityExist(vehicle) then
			IsBusy = true
			TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
			Citizen.CreateThread(function()
				Citizen.Wait(10000)

				SetVehicleDoorsLocked(vehicle, 1)
				SetVehicleDoorsLockedForAllPlayers(vehicle, false)
				ClearPedTasksImmediately(playerPed)

				TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_unlocked')})
				IsBusy = false
			end)
		else
			TriggerEvent("pNotify:SendNotification", {text = _U('no_vehicle_nearby')})
		end
      end
	  
	  if data.current.value == 'hijack_vehicle_quick' then

        local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)

        if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end

          if DoesEntityExist(vehicle) then
            TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_WELDING", 0, true)
            Citizen.CreateThread(function()
              Citizen.Wait(2500)
              SetVehicleDoorsLocked(vehicle, 1)
              SetVehicleDoorsLockedForAllPlayers(vehicle, false)
              ClearPedTasksImmediately(playerPed)
              ESX.ShowNotification(_U('vehicle_unlocked'))
            end)
          end

        end

      end

	  if data.current.value == 'put_on_flatbed' then
		TriggerEvent("flatbed:tow")
	  end

	  if data.current.value == 'open_hood_vehicle' then
		
		local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)
	  
		if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end
		  
		  if(VehicleHoods[vehicle] == nil) then
			  SetVehicleDoorOpen(vehicle, 4, 0, 0)
			  VehicleHoods[vehicle] = 1
			  TriggerServerEvent("esx_mecanojob:setVehicleHoodState", vehicle, 1)
			  Citizen.Wait(750)
		  else
			if(VehicleHoods[vehicle] == 1) then
				SetVehicleDoorShut(vehicle, 4, 0)
				VehicleHoods[vehicle] = 0
				TriggerServerEvent("esx_mecanojob:setVehicleHoodState", vehicle, 0)
				Citizen.Wait(750)
			elseif(VehicleHoods[vehicle] == 0) then
				SetVehicleDoorOpen(vehicle, 4, 0, 0)
				VehicleHoods[vehicle] = 1
				TriggerServerEvent("esx_mecanojob:setVehicleHoodState", vehicle, 1)
				Citizen.Wait(750)
			end
		  end
		end
	  end
	  
	
      if data.current.value == 'fix_vehicle' then

		local playerPed = PlayerPedId()
		local vehicle   = ESX.Game.GetVehicleInDirection()
		local coords    = GetEntityCoords(playerPed)

		if IsPedSittingInAnyVehicle(playerPed) then
			TriggerEvent("pNotify:SendNotification", {text = _U('inside_vehicle')})
			return
		end

		if DoesEntityExist(vehicle) then
			IsBusy = true
			TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
			Citizen.CreateThread(function()
				Citizen.Wait(20000)

				SetVehicleFixed(vehicle)
				SetVehicleDeformationFixed(vehicle)
				SetVehicleUndriveable(vehicle, false)
				SetVehicleEngineOn(vehicle, true, true)
				ClearPedTasksImmediately(playerPed)

				TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_repaired')})
				IsBusy = false
			end)
		else
			TriggerEvent("pNotify:SendNotification", {text = _U('no_vehicle_nearby')})
		end
      end
	  
	
      if data.current.value == 'fix_vehicle_engine' then

        local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)

        if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end

          if DoesEntityExist(vehicle) then
			  TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
			  Citizen.CreateThread(function()
				Citizen.Wait(20000)
				--SetVehicleFixed(vehicle)
				--SetVehicleDeformationFixed(vehicle)
				SetVehicleEngineHealth(vehicle, 805.0)
				TriggerEvent("EngineToggle:FixEngine", vehicle)
				SetVehicleUndriveable(vehicle, false)
				Citizen.Wait(1500)
				ClearPedTasksImmediately(GetPlayerPed(-1))
				TriggerEvent("pNotify:SendNotification", {text = 'Silnik Naprawiony'})
			  end)
			end
        end
      end

      if data.current.value == 'clean_vehicle' then

        local playerPed = PlayerPedId()
		local vehicle   = ESX.Game.GetVehicleInDirection()
		local coords    = GetEntityCoords(playerPed)

		if IsPedSittingInAnyVehicle(playerPed) then
			TriggerEvent("pNotify:SendNotification", {text = _U('inside_vehicle')})
			return
		end

		if DoesEntityExist(vehicle) then
			IsBusy = true
			TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_MAID_CLEAN", 0, true)
			Citizen.CreateThread(function()
				Citizen.Wait(10000)

				SetVehicleDirtLevel(vehicle, 0)
				ClearPedTasksImmediately(playerPed)

				TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_cleaned')})
				IsBusy = false
			end)
		else
			TriggerEvent("pNotify:SendNotification", {text = _U('no_vehicle_nearby')})
		end
      end
	  
	  if data.current.value == 'fix_vehicle_quick' then

        local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)

        if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end

          if DoesEntityExist(vehicle) then
            TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
            Citizen.CreateThread(function()
              Citizen.Wait(5000)
              SetVehicleFixed(vehicle)
              SetVehicleDeformationFixed(vehicle)
              SetVehicleUndriveable(vehicle, false)
              SetVehicleEngineOn(vehicle,  true,  true)
              ClearPedTasksImmediately(playerPed)
             TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_repaired')})
            end)
          end
        end
      end
	  
	
      if data.current.value == 'fix_vehicle_engine_quick' then

        local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)

        if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end

          if DoesEntityExist(vehicle) then
			  TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
			  Citizen.CreateThread(function()
				Citizen.Wait(5000)
				--SetVehicleFixed(vehicle)
				--SetVehicleDeformationFixed(vehicle)
				SetVehicleEngineHealth(vehicle, 805.0)
				TriggerEvent("EngineToggle:FixEngine", vehicle)
				SetVehicleUndriveable(vehicle, false)
				Citizen.Wait(1500)
				ClearPedTasksImmediately(GetPlayerPed(-1))
				TriggerEvent("pNotify:SendNotification", {text = 'Silnik Naprawiony'})
			  end)
			end
        end
      end

      if data.current.value == 'clean_vehicle_quick' then

        local playerPed = GetPlayerPed(-1)
        local coords    = GetEntityCoords(playerPed)

        if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

          local vehicle = nil

          if IsPedInAnyVehicle(playerPed, false) then
            vehicle = GetVehiclePedIsIn(playerPed, false)
          else
            vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
          end

          if DoesEntityExist(vehicle) then
            TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_MAID_CLEAN", 0, true)
            Citizen.CreateThread(function()
              Citizen.Wait(2500)
              SetVehicleDirtLevel(vehicle, 0)
              ClearPedTasksImmediately(playerPed)
              ESX.ShowNotification(_U('vehicle_cleaned'))
            end)
          end
        end
      end

     if data.current.value == 'del_vehicle' then

        local ped = GetPlayerPed(-1)

        if DoesEntityExist(ped) and not IsEntityDead(ped) then
          local pos = GetEntityCoords( ped )

          if IsPedSittingInAnyVehicle(ped) then
            local vehicle = GetVehiclePedIsIn( ped, false )

            if GetPedInVehicleSeat(vehicle, -1) == ped then
              TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_impounded')})
              ESX.Game.DeleteVehicle(vehicle)
            else
              TriggerEvent("pNotify:SendNotification", {text = _U('must_seat_driver')})
            end
          else
            local vehicle = ESX.Game.GetVehicleInDirection()

            if DoesEntityExist(vehicle) then
              TriggerEvent("pNotify:SendNotification", {text = _U('vehicle_impounded')})
              ESX.Game.DeleteVehicle(vehicle)
            else
              TriggerEvent("pNotify:SendNotification", {text = _U('must_near')})
            end
          end
        end
		end
      
      

      if data.current.value == 'dep_vehicle' then

        local playerped = GetPlayerPed(-1)
        local vehicle = GetVehiclePedIsIn(playerped, true)

        local towmodel = GetHashKey('flatbedm2')
        local isVehicleTow = IsVehicleModel(vehicle, towmodel)

        if isVehicleTow then
          local targetVehicle = ESX.Game.GetVehicleInDirection()

          if CurrentlyTowedVehicle == nil then
            if targetVehicle ~= 0 then
              if not IsPedInAnyVehicle(playerped, true) then
                if vehicle ~= targetVehicle then
                  AttachEntityToEntity(targetVehicle, vehicle, 20, -0.5, -5.0, 1.0, 0.0, 0.0, 0.0, false, false, false, false, 20, true)
                  CurrentlyTowedVehicle = targetVehicle
                  ESX.ShowNotification(_U('vehicle_success_attached'))

                  if NPCOnJob then

                    if NPCTargetTowable == targetVehicle then
                      ESX.ShowNotification(_U('please_drop_off'))

                      Config.Zones.VehicleDelivery.Type = 1

                      if Blips['NPCTargetTowableZone'] ~= nil then
                        RemoveBlip(Blips['NPCTargetTowableZone'])
                        Blips['NPCTargetTowableZone'] = nil
                      end

                      Blips['NPCDelivery'] = AddBlipForCoord(Config.Zones.VehicleDelivery.Pos.x,  Config.Zones.VehicleDelivery.Pos.y,  Config.Zones.VehicleDelivery.Pos.z)

                      SetBlipRoute(Blips['NPCDelivery'], true)

                    end

                  end

                else
                  ESX.ShowNotification(_U('cant_attach_own_tt'))
                end
              end
            else
              ESX.ShowNotification(_U('no_veh_att'))
            end
          else

            AttachEntityToEntity(CurrentlyTowedVehicle, vehicle, 20, -0.5, -12.0, 1.0, 0.0, 0.0, 0.0, false, false, false, false, 20, true)
            DetachEntity(CurrentlyTowedVehicle, true, true)

            if NPCOnJob then

              if NPCTargetDeleterZone then

                if CurrentlyTowedVehicle == NPCTargetTowable then
                  ESX.Game.DeleteVehicle(NPCTargetTowable)
                  TriggerServerEvent('esx_mecanojob:onNPCJobMissionCompleted')
                  StopNPCJob()
                  NPCTargetDeleterZone = false

                else
                  ESX.ShowNotification(_U('not_right_veh'))
                end

              else
                ESX.ShowNotification(_U('not_right_place'))
              end

            end

            CurrentlyTowedVehicle = nil

            ESX.ShowNotification(_U('veh_det_succ'))
          end
        else
          ESX.ShowNotification(_U('imp_flatbed'))
        end
      end

      if data.current.value == 'object_spawner' then

        ESX.UI.Menu.Open(
          'default', GetCurrentResourceName(), 'mobile_mecano_actions_spawn',
          {
            title    = _U('objects'),
            align    = 'center',
            elements = {
              {label = _U('roadcone'),     value = 'prop_roadcone02a'},
              {label = _U('toolbox'), value = 'prop_toolchest_01'},
            },
          },
          function(data2, menu2)


            local model     = data2.current.value
            local playerPed = GetPlayerPed(-1)
            local coords    = GetEntityCoords(playerPed)
            local forward   = GetEntityForwardVector(playerPed)
            local x, y, z   = table.unpack(coords + forward * 1.0)

            if model == 'prop_roadcone02a' then
              z = z - 2.0
            elseif model == 'prop_toolchest_01' then
              z = z - 2.0
            end

            ESX.Game.SpawnObject(model, {
              x = x,
              y = y,
              z = z
            }, function(obj)
              SetEntityHeading(obj, GetEntityHeading(playerPed))
              PlaceObjectOnGroundProperly(obj)
            end)

          end,
          function(data2, menu2)
            menu2.close()
          end
        )

      end

    end,
  function(data, menu)
    menu.close()
  end
  )
end

function OpenGetStocksMenu()

  ESX.TriggerServerCallback('esx_mecanojob:getStockItems', function(items)

    print(json.encode(items))

    local elements = {}

    for i=1, #items, 1 do
      table.insert(elements, {label = 'x' .. items[i].count .. ' ' .. items[i].label, value = items[i].name})
    end

    ESX.UI.Menu.Open(
      'default', GetCurrentResourceName(), 'stocks_menu',
      {
        title    = _U('mechanic_stock'),
        align    = 'center',
        elements = elements
      },
      function(data, menu)

        local itemName = data.current.value

        ESX.UI.Menu.Open(
          'dialog', GetCurrentResourceName(), 'stocks_menu_get_item_count',
          {
            title = _U('quantity')
          },
          function(data2, menu2)

            local count = tonumber(data2.value)

            if count == nil then
             TriggerEvent("pNotify:SendNotification", {text = _U('invalid_quantity')})
            else
              menu2.close()
              menu.close()
              OpenGetStocksMenu()

              TriggerServerEvent('esx_mecanojob:getStockItem', itemName, count)
            end

          end,
          function(data2, menu2)
            menu2.close()
          end
        )

      end,
      function(data, menu)
        menu.close()
      end
    )

  end)

end

function OpenPutStocksMenu()

ESX.TriggerServerCallback('esx_mecanojob:getPlayerInventory', function(inventory)

    local elements = {}

    for i=1, #inventory.items, 1 do

      local item = inventory.items[i]

      if item.count > 0 then
        table.insert(elements, {label = item.label .. ' x' .. item.count, type = 'item_standard', value = item.name})
      end

    end

    ESX.UI.Menu.Open(
      'default', GetCurrentResourceName(), 'stocks_menu',
      {
        title    = _U('inventory'),
        align    = 'center',
        elements = elements
      },
      function(data, menu)

        local itemName = data.current.value

        ESX.UI.Menu.Open(
          'dialog', GetCurrentResourceName(), 'stocks_menu_put_item_count',
          {
            title = _U('quantity')
          },
          function(data2, menu2)

            local count = tonumber(data2.value)

            if count == nil then
              TriggerEvent("pNotify:SendNotification", {text = _U('invalid_quantity')})
            else
              menu2.close()
              menu.close()
              OpenPutStocksMenu()

              TriggerServerEvent('esx_mecanojob:putStockItems', itemName, count)
            end

          end,
          function(data2, menu2)
            menu2.close()
          end
        )

      end,
      function(data, menu)
        menu.close()
      end
    )

  end)

end


RegisterNetEvent('esx_mecanojob:onHijack')
AddEventHandler('esx_mecanojob:onHijack', function()
  local playerPed = GetPlayerPed(-1)
  local coords    = GetEntityCoords(playerPed)

  if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

    local vehicle = nil

    if IsPedInAnyVehicle(playerPed, false) then
      vehicle = GetVehiclePedIsIn(playerPed, false)
    else
      vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end

    local crochete = math.random(100)
    local alarm    = math.random(100)

    if DoesEntityExist(vehicle) then
      if alarm <= 33 then
        SetVehicleAlarm(vehicle, true)
        StartVehicleAlarm(vehicle)
	 if PlayerData.job.name ~= 'zwierzako' and PlayerData.job.name  ~= 'mecano' and PlayerData.job.name  ~= 'police' then
                TriggerEvent("outlaw:lockpick")
        end
      end
      TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_WELDING", 0, true)
      Citizen.CreateThread(function()
        Citizen.Wait(10000)
	local jobChance = 30
        if PlayerData.job.name == 'zwierzako' or PlayerData.job.name == 'mecano' or PlayerData.job.name == 'police' then
                jobChance = 100
        end

        if crochete <= jobChance then
          SetVehicleDoorsLocked(vehicle, 1)
          SetVehicleDoorsLockedForAllPlayers(vehicle, false)
          ClearPedTasksImmediately(playerPed)
          ESX.ShowNotification(_U('veh_unlocked'))
        else
          ESX.ShowNotification(_U('hijack_failed'))
          ClearPedTasksImmediately(playerPed)
        end
      end)
    end

  end
end)

RegisterNetEvent('esx_mecanojob:onCarokit')
AddEventHandler('esx_mecanojob:onCarokit', function()
  local playerPed = GetPlayerPed(-1)
  local coords    = GetEntityCoords(playerPed)

  if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

    local vehicle = nil

    if IsPedInAnyVehicle(playerPed, false) then
      vehicle = GetVehiclePedIsIn(playerPed, false)
    else
      vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end

    if DoesEntityExist(vehicle) then
      TaskStartScenarioInPlace(playerPed, "WORLD_HUMAN_HAMMERING", 0, true)
      Citizen.CreateThread(function()
        Citizen.Wait(10000)
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        ClearPedTasksImmediately(playerPed)
        ESX.ShowNotification(_U('body_repaired'))
      end)
    end
  end
end)

RegisterNetEvent('esx_mecanojob:onFixkit')
AddEventHandler('esx_mecanojob:onFixkit', function()
  local playerPed = GetPlayerPed(-1)
  local coords    = GetEntityCoords(playerPed)

  if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

    local vehicle = nil

    if IsPedInAnyVehicle(playerPed, false) then
	  TriggerEvent("pNotify:SendNotification", {text = 'Musisz wyjść z pojazdu aby naprawić silnik'})
    else 
      vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end

    if DoesEntityExist(vehicle) then
      TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
      Citizen.CreateThread(function()
		TriggerEvent('esx:showNotification', _U('you_used_repair_kit'))
		TriggerServerEvent("esx_mecanojob:removeFixTool")
		TriggerEvent("esx_anims:repair", true)
        Citizen.Wait(20000)
        --SetVehicleFixed(vehicle)
        --SetVehicleDeformationFixed(vehicle)
		SetVehicleEngineHealth(vehicle, 805.0)
		TriggerServerEvent("EngineToggle:FixEngines", vehicle)
        SetVehicleUndriveable(vehicle, false)
		TriggerEvent("esx_anims:repair", false)
		Citizen.Wait(1500)
		ClearPedTasksImmediately(GetPlayerPed(-1))
		TriggerEvent("pNotify:SendNotification", {text = 'Silnik Naprawiony'})
      end)
    end
  end
end)

RegisterNetEvent('esx_mecanojob:onPolFixkit')
AddEventHandler('esx_mecanojob:onPolFixkit', function()
  local playerPed = GetPlayerPed(-1)
  local coords    = GetEntityCoords(playerPed)

  if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, 5.0) then

    local vehicle = nil

    if IsPedInAnyVehicle(playerPed, false) then
	  TriggerEvent("pNotify:SendNotification", {text = 'Musisz wyjść z pojazdu aby naprawić silnik'})
    else
      vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end

    if DoesEntityExist(vehicle) then
      TaskStartScenarioInPlace(playerPed, "PROP_HUMAN_BUM_BIN", 0, true)
      Citizen.CreateThread(function()
		TriggerEvent('esx:showNotification', _U('you_used_repair_kit'))
		TriggerServerEvent("esx_mecanojob:removePolFixTool")
		TriggerEvent("esx_anims:repair", true)
        Citizen.Wait(20000)
        --SetVehicleFixed(vehicle)
        --SetVehicleDeformationFixed(vehicle)
		SetVehicleEngineHealth(vehicle, 805.0)
		TriggerServerEvent("EngineToggle:FixEngines", vehicle)
        SetVehicleUndriveable(vehicle, false)
		TriggerEvent("esx_anims:repair", false)
		Citizen.Wait(1500)
		ClearPedTasksImmediately(GetPlayerPed(-1))
		TriggerEvent("pNotify:SendNotification", {text = 'Silnik Naprawiony'})
      end)
    end
  end
end)

function setEntityHeadingFromEntity ( vehicle, playerPed )
    local heading = GetEntityHeading(vehicle)
    SetEntityHeading( playerPed, heading )
end

function getVehicleInDirection(coordFrom, coordTo)
  local rayHandle = CastRayPointToPoint(coordFrom.x, coordFrom.y, coordFrom.z, coordTo.x, coordTo.y, coordTo.z, 10, GetPlayerPed(-1), 0)
  local a, b, c, d, vehicle = GetRaycastResult(rayHandle)
  return vehicle
end

function deleteCar( entity )
    Citizen.InvokeNative( 0xEA386986E786A54F, Citizen.PointerValueIntInitialized( entity ) )
end

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
  PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
  PlayerData.job = job
end)

AddEventHandler('esx_mecanojob:hasEnteredMarker', function(zone)

  if zone == NPCJobTargetTowable then

  end

  if zone =='VehicleDelivery' then
    NPCTargetDeleterZone = true
  end

  if zone == 'MecanoActions' then
    CurrentAction     = 'mecano_actions_menu'
    CurrentActionMsg  = _U('open_actions')
    CurrentActionData = {}
  end

  if zone == 'MecanoActions2' then
    CurrentAction     = 'mecano_actions_menu'
    CurrentActionMsg  = _U('open_actions')
    CurrentActionData = {}
  end

  if zone == 'Garage' then
    CurrentAction     = 'mecano_harvest_menu'
    CurrentActionMsg  = _U('harvest_menu')
    CurrentActionData = {}
  end

  if zone == 'Craft' then
    CurrentAction     = 'mecano_craft_menu'
    CurrentActionMsg  = _U('craft_menu')
    CurrentActionData = {}
  end

  if zone == 'VehicleDeleter' then

    local playerPed = GetPlayerPed(-1)

    if IsPedInAnyVehicle(playerPed,  false) then

      local vehicle = GetVehiclePedIsIn(playerPed,  false)

      CurrentAction     = 'delete_vehicle'
      CurrentActionMsg  = _U('veh_stored')
      CurrentActionData = {vehicle = vehicle}
    end
  end

end)

AddEventHandler('esx_mecanojob:hasExitedMarker', function(zone)

  if zone =='VehicleDelivery' then
    NPCTargetDeleterZone = false
  end

  if zone == 'Craft' then
    TriggerServerEvent('esx_mecanojob:stopCraft')
    TriggerServerEvent('esx_mecanojob:stopCraft2')
    TriggerServerEvent('esx_mecanojob:stopCraft3')
  end

  if zone == 'Garage' then
    TriggerServerEvent('esx_mecanojob:stopHarvest')
    TriggerServerEvent('esx_mecanojob:stopHarvest2')
    TriggerServerEvent('esx_mecanojob:stopHarvest3')
  end

  CurrentAction = nil
  ESX.UI.Menu.CloseAll()
end)

AddEventHandler('esx_mecanojob:hasEnteredEntityZone', function(entity)

  local playerPed = GetPlayerPed(-1)

  if PlayerData.job ~= nil and PlayerData.job.name == 'mecano' and not IsPedInAnyVehicle(playerPed, false) then
    CurrentAction     = 'remove_entity'
    CurrentActionMsg  = _U('press_remove_obj')
    CurrentActionData = {entity = entity}
  end

end)

AddEventHandler('esx_mecanojob:hasExitedEntityZone', function(entity)

  if CurrentAction == 'remove_entity' then
    CurrentAction = nil
  end

end)

RegisterNetEvent('esx_phone:loaded')
AddEventHandler('esx_phone:loaded', function(phoneNumber, contacts)
  local specialContact = {
    name       = _U('mechanic'),
    number     = 'mecano',
    base64Icon = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAALEwAACxMBAJqcGAAAA4BJREFUWIXtll9oU3cUx7/nJA02aSSlFouWMnXVB0ejU3wcRteHjv1puoc9rA978cUi2IqgRYWIZkMwrahUGfgkFMEZUdg6C+u21z1o3fbgqigVi7NzUtNcmsac40Npltz7S3rvUHzxQODec87vfD+/e0/O/QFv7Q0beV3QeXqmgV74/7H7fZJvuLwv8q/Xeux1gUrNBpN/nmtavdaqDqBK8VT2RDyV2VHmF1lvLERSBtCVynzYmcp+A9WqT9kcVKX4gHUehF0CEVY+1jYTTIwvt7YSIQnCTvsSUYz6gX5uDt7MP7KOKuQAgxmqQ+neUA+I1B1AiXi5X6ZAvKrabirmVYFwAMRT2RMg7F9SyKspvk73hfrtbkMPyIhA5FVqi0iBiEZMMQdAui/8E4GPv0oAJkpc6Q3+6goAAGpWBxNQmTLFmgL3jSJNgQdGv4pMts2EKm7ICJB/aG0xNdz74VEk13UYCx1/twPR8JjDT8wttyLZtkoAxSb8ZDCz0gdfKxWkFURf2v9qTYH7SK7rQIDn0P3nA0ehixvfwZwE0X9vBE/mW8piohhl1WH18UQBhYnre8N/L8b8xQvlx4ACbB4NnzaeRYDnKm0EALCMLXy84hwuTCXL/ExoB1E7qcK/8NCLIq5HcTT0i6u8TYbXUM1cAyyveVq8Xls7XhYrvY/4n3gC8C+dsmAzL1YUiyfWxvHzsy/w/dNd+KjhW2yvv/RfXr7x9QDcmo1he2RBiCCI1Q8jVj9szPNixVfgz+UiIGyDSrcoRu2J16d3I6e1VYvNSQjXpnucAcEPUOkGYZs/l4uUhowt/3kqu1UIv9n90fAY9jT3YBlbRvFTD4fw++wHjhiTRL/bG75t0jI2ITcHb5om4Xgmhv57xpGOg3d/NIqryOR7z+r+MC6qBJB/ZB2t9Om1D5lFm843G/3E3HI7Yh1xDRAfzLQr5EClBf/HBHK462TG2J0OABXeyWDPZ8VqxmBWYscpyghwtTd4EKpDTjCZdCNmzFM9k+4LHXIFACJN94Z6FiFEpKDQw9HndWsEuhnADVMhAUaYJBp9XrcGQKJ4qFE9k+6r2+MG3k5N8VQ22TVglbX2ZwOzX2VvNKr91zmY6S7N6zqZicVT2WNLyVSehESaBhxnOALfMeYX+K/S2yv7wmMAlvwyuR7FxQUyf0fgc/jztfkJr7XeGgC8BJJgWNV8ImT+AAAAAElFTkSuQmCC'
  }
  TriggerEvent('esx_phone:addSpecialContact', specialContact.name, specialContact.number, specialContact.base64Icon)
end)

-- Pop NPC mission vehicle when inside area
Citizen.CreateThread(function()
  while true do

    Wait(5)

    if NPCTargetTowableZone ~= nil and not NPCHasSpawnedTowable then

      local coords = GetEntityCoords(GetPlayerPed(-1))
      local zone   = Config.Zones[NPCTargetTowableZone]

      if GetDistanceBetweenCoords(coords, zone.Pos.x, zone.Pos.y, zone.Pos.z, true) < Config.NPCSpawnDistance then

        local model = Config.Vehicles[GetRandomIntInRange(1,  #Config.Vehicles)]

        ESX.Game.SpawnVehicle(model, zone.Pos, 0, function(vehicle)
          NPCTargetTowable = vehicle
        end)

        NPCHasSpawnedTowable = true

      end

    end

    if NPCTargetTowableZone ~= nil and NPCHasSpawnedTowable and not NPCHasBeenNextToTowable then

      local coords = GetEntityCoords(GetPlayerPed(-1))
      local zone   = Config.Zones[NPCTargetTowableZone]

      if(GetDistanceBetweenCoords(coords, zone.Pos.x, zone.Pos.y, zone.Pos.z, true) < Config.NPCNextToDistance) then
        ESX.ShowNotification(_U('please_tow'))
        NPCHasBeenNextToTowable = true
      end

    end

  end
end)

-- Blipy
Citizen.CreateThread(function()
  local blip = AddBlipForCoord(Config.Zones.MecanoActions.Pos.x, Config.Zones.MecanoActions.Pos.y, Config.Zones.MecanoActions.Pos.z)
  SetBlipSprite (blip, 446)
  SetBlipDisplay(blip, 4)
  SetBlipScale  (blip, 0.9)
  SetBlipColour (blip, 5)
  SetBlipAsShortRange(blip, true)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentString("Warsztat")
  EndTextCommandSetBlipName(blip)
end)

-- Display markers
Citizen.CreateThread(function()
  while true do
    Wait(5)
    if PlayerData.job ~= nil and PlayerData.job.name == 'mecano' then

      local coords = GetEntityCoords(GetPlayerPed(-1))

      for k,v in pairs(Config.Zones) do
        if(v.Type ~= -1 and GetDistanceBetweenCoords(coords, v.Pos.x, v.Pos.y, v.Pos.z, true) < Config.DrawDistance) then
          DrawMarker(v.Type, v.Pos.x, v.Pos.y, v.Pos.z, 0.0, 0.0, 0.0, 0, 0.0, 0.0, v.Size.x, v.Size.y, v.Size.z, v.Color.r, v.Color.g, v.Color.b, 100, false, true, 2, false, false, false, false)
        end
      end
    end
  end
end)

-- Enter / Exit marker events
Citizen.CreateThread(function()
  while true do
    Wait(10)
    if PlayerData.job ~= nil and PlayerData.job.name == 'mecano' then
      local coords      = GetEntityCoords(GetPlayerPed(-1))
      local isInMarker  = false
      local currentZone = nil
      for k,v in pairs(Config.Zones) do
        if(GetDistanceBetweenCoords(coords, v.Pos.x, v.Pos.y, v.Pos.z, true) < v.Size.x) then
          isInMarker  = true
          currentZone = k
        end
      end
      if (isInMarker and not HasAlreadyEnteredMarker) or (isInMarker and LastZone ~= currentZone) then
        HasAlreadyEnteredMarker = true
        LastZone                = currentZone
        TriggerEvent('esx_mecanojob:hasEnteredMarker', currentZone)
      end
      if not isInMarker and HasAlreadyEnteredMarker then
        HasAlreadyEnteredMarker = false
        TriggerEvent('esx_mecanojob:hasExitedMarker', LastZone)
      end
    end
  end
end)

Citizen.CreateThread(function()

  local trackedEntities = {
      'prop_roadcone02a',
      'prop_toolchest_01'
  }

  while true do

    Citizen.Wait(10)

    local playerPed = GetPlayerPed(-1)
    local coords    = GetEntityCoords(playerPed)

    local closestDistance = -1
    local closestEntity   = nil

    for i=1, #trackedEntities, 1 do

      local object = GetClosestObjectOfType(coords.x,  coords.y,  coords.z,  3.0,  GetHashKey(trackedEntities[i]), false, false, false)

      if DoesEntityExist(object) then

        local objCoords = GetEntityCoords(object)
        local distance  = GetDistanceBetweenCoords(coords.x,  coords.y,  coords.z,  objCoords.x,  objCoords.y,  objCoords.z,  true)

        if closestDistance == -1 or closestDistance > distance then
          closestDistance = distance
          closestEntity   = object
        end

      end

    end

    if closestDistance ~= -1 and closestDistance <= 3.0 then

      if LastEntity ~= closestEntity then
        TriggerEvent('esx_mecanojob:hasEnteredEntityZone', closestEntity)
        LastEntity = closestEntity
      end

    else

      if LastEntity ~= nil then
        TriggerEvent('esx_mecanojob:hasExitedEntityZone', LastEntity)
        LastEntity = nil
      end

    end

  end
end)

-- Key Controls
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5)

        if CurrentAction ~= nil then

          SetTextComponentFormat('STRING')
          AddTextComponentString(CurrentActionMsg)
          DisplayHelpTextFromStringLabel(0, 0, 1, -1)

          if IsControlJustReleased(0, 38) and PlayerData.job ~= nil and PlayerData.job.name == 'mecano' then

            if CurrentAction == 'mecano_actions_menu' then
                OpenMecanoActionsMenu()
            end

            if CurrentAction == 'mecano_harvest_menu' then
                OpenMecanoHarvestMenu()
            end

            if CurrentAction == 'mecano_craft_menu' then
                OpenMecanoCraftMenu()
            end

            if CurrentAction == 'delete_vehicle' then

              if Config.EnableSocietyOwnedVehicles then

                local vehicleProps = ESX.Game.GetVehicleProperties(CurrentActionData.vehicle)
                TriggerServerEvent('esx_society:putVehicleInGarage', 'mecano', vehicleProps)

              else

                if
                  GetEntityModel(vehicle) == GetHashKey('flatbed')   or
                  GetEntityModel(vehicle) == GetHashKey('towtruck2') or
                  GetEntityModel(vehicle) == GetHashKey('towtruck')
                then
                  TriggerServerEvent('esx_service:disableService', 'mecano')
                end

              end

              ESX.Game.DeleteVehicle(CurrentActionData.vehicle)
            end

            if CurrentAction == 'remove_entity' then
              DeleteEntity(CurrentActionData.entity)
            end

            CurrentAction = nil
          end
        end

        if IsControlJustReleased(0, Keys['F6']) and not IsDead and PlayerData.job ~= nil and PlayerData.job.name == 'mecano' then
			--if(OnDuty or PlayerData.job.grade_name == "boss" or PlayerData.job.grade_name == "chief") then
			--	OpenMobileMecanoActionsMenu()
			--else
			--	ESX.ShowNotification("~r~Aby korzystać z narzędzi musisz być na służbie (Robocze ubrania)")
			--end
			
			OpenMobileMecanoActionsMenu()
        end

        -- if IsControlJustReleased(0, Keys['DELETE']) and not IsDead and PlayerData.job ~= nil and PlayerData.job.name == 'mecano' then

          -- if NPCOnJob then

            -- if GetGameTimer() - NPCLastCancel > 5 * 60000 then
              -- StopNPCJob(true)
              -- NPCLastCancel = GetGameTimer()
            -- else
              -- ESX.ShowNotification(_U('wait_five'))
            -- end

          -- else

            -- local playerPed = GetPlayerPed(-1)

            -- if IsPedInAnyVehicle(playerPed,  false) and IsVehicleModel(GetVehiclePedIsIn(playerPed,  false), GetHashKey("flatbed")) then
              -- StartNPCJob()
            -- else
              -- ESX.ShowNotification(_U('must_in_flatbed'))
            -- end

          -- end

        -- end

    end
end)

AddEventHandler('esx:onPlayerDeath', function()
	IsDead = true
end)

AddEventHandler('playerSpawned', function(spawn)
	IsDead = false
end)

RegisterCommand("odholuj",function(source, args)
    if  PlayerData.job ~= nil and (PlayerData.job.name == 'police' or PlayerData.job.name == 'mecano') then
        local coords    = GetEntityCoords(PlayerPedId())
        local vehicle   = GetClosestVehicle(coords.x,  coords.y,  coords.z,  3.0,  0,  71)
        if vehicle == nil then return end
        DeleteEntity(vehicle)
    end
end, false)

RegisterNetEvent('esx_mecanojob:autonaprawka')
AddEventHandler('esx_mecanojob:autonaprawka', function(currentStore)

end)

local Naprawia = false 
local OdliczaneSekundy = 0

Citizen.CreateThread(function(kwota)
	while true do
		Citizen.Wait(0)
			local playerPed = PlayerPedId()
			local coords123    = GetEntityCoords(playerPed)
			local vehicle = GetVehiclePedIsIn(playerPed, false)
			local damage = GetVehicleEngineHealth(vehicle)
			local kwota = 0

			if damage <= 200.0 then
				kwota = 1500.0
			elseif damage <= 500.0 then
				kwota = math.floor(1000-(damage*0.5))
			elseif damage > 500.0 then
				kwota = math.floor(1000-(damage*0.3))
			end
      local cena = math.floor(kwota / 2)

      if(GetDistanceBetweenCoords(coords123, 937.11, -962.95, 39.30, true) < 15) then
			--DrawMarker(1, -324.4, -132.19, 38.05, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 5.0, 5.0, 0.2, 255, 255, 0, 100, false, true, 2, false, false, false, false)
			if(GetDistanceBetweenCoords(coords123, 937.11, -962.95, 39.30, true) < 6) then
				--TriggerServerEvent('esx_mecanojob:pokazmarker')
				if damage < 1000 then
          local SellPos = {
	            ["x"] = 937.11,
	            ["y"] = -962.95,
	            ["z"] = 39.30 + 1
	          }
			  if not Naprawia then
				ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby naprawić pojazd za $~p~"..cena.."~w~. Płatność jedynie ~p~gotówką~s~!", 0.8)
			elseif Naprawia then
			  ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby ~p~anulować~s~ naprawę~n~Pozostało: ~p~"..OdliczaneSekundy.."~s~ sekund...", 0.8)
			end
					if IsControlJustReleased(0, Keys['E']) then
						if not Naprawia then
							autonaprawa()
						elseif Naprawia then
							anulujNaprawe()
						end
					end
				else
          local SellPos = {
	            ["x"] = 937.11,
	            ["y"] = -962.95,
	            ["z"] = 39.30 + 1
	          }
          ESX.Game.Utils.DrawText3D(SellPos, 'Pojazd ~p~nie~s~ jest uszkodzony!', 0.8)
				end
			end
      end
      if(GetDistanceBetweenCoords(coords123, -211.84, -1323.67, 30.40, true) < 15) then
			--DrawMarker(1, 1185.91, 2650.25, 36.9, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 5.0, 5.0, 0.2, 255, 255, 0, 100, false, true, 2, false, false, false, false)
			if(GetDistanceBetweenCoords(coords123, -211.84, -1323.67, 30.40, true) < 6) then
				--TriggerServerEvent('esx_mecanojob:pokazmarker')
				if damage < 1000 then
					local SellPos = {
	            ["x"] = -211.84,
	            ["y"] = -1323.67,
	            ["z"] = 30.40 + 1
	          }
			  if not Naprawia then
				ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby naprawić pojazd za $~p~"..cena.."~w~. Płatność jedynie ~p~gotówką~s~!", 0.8)
			elseif Naprawia then
			  ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby ~p~anulować~s~ naprawę~n~Pozostało: ~p~"..OdliczaneSekundy.."~s~ sekund...", 0.8)
			end
					if IsControlJustReleased(0, Keys['E']) then
						if not Naprawia then
							autonaprawa()
						elseif Naprawia then
							anulujNaprawe()
						end
					end
				else
          local SellPos = {
	            ["x"] = -211.84,
	            ["y"] = -1323.67,
	            ["z"] = 30.40 + 1
	          }
          ESX.Game.Utils.DrawText3D(SellPos, 'Pojazd ~p~nie~s~ jest uszkodzony!', 0.8)
				end
			end
      end
      if(GetDistanceBetweenCoords(coords123, -339.57, -137.98, 38.70, true) < 15) then
			--DrawMarker(1, 110.46, 6606.45, 30.95, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 5.0, 5.0, 0.2, 255, 255, 0, 100, false, true, 2, false, false, false, false)
			if(GetDistanceBetweenCoords(coords123, -339.57, -137.98, 38.70, true) < 6) then
				--TriggerServerEvent('esx_mecanojob:pokazmarker')
				if damage < 1000 then
          local SellPos = {
	            ["x"] = -339.57,
	            ["y"] = -137.98,
	            ["z"] = 38.70 + 1
			  }
			  if not Naprawia then
				  ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby naprawić pojazd za $~p~"..cena.."~w~. Płatność jedynie ~p~gotówką~s~!", 0.8)
			  elseif Naprawia then
				ESX.Game.Utils.DrawText3D(SellPos, "Naciśnij [~p~E~s~] aby ~p~anulować~s~ naprawę~n~Pozostało: ~p~"..OdliczaneSekundy.."~s~ sekund...", 0.8)
			  end
					if IsControlJustReleased(0, Keys['E']) then
						if not Naprawia then
							autonaprawa()
						elseif Naprawia then
							anulujNaprawe()
						end
					end
				else
          local SellPos = {
	            ["x"] = -339.57,
	            ["y"] = -137.98,
	            ["z"] = 38.70 + 1
	          }
            ESX.Game.Utils.DrawText3D(SellPos, 'Pojazd ~p~nie~s~ jest uszkodzony!', 0.8)
				end
			end
	end
  end
end)

function anulujNaprawe()
	local playerPed = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(playerPed, false)
	SetVehicleEngineOn( vehicle, true, true )
	FreezeEntityPosition(vehicle, false)
	Naprawia = false
	TriggerEvent("pNotify:SendNotification", {text = 'Anulowano Naprawę!'})
end

function autonaprawa(kwota)
	local playerPed = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(playerPed, false)
	local damage = GetVehicleEngineHealth(vehicle)
	local kwota = 0
	local czas = 0
	local czekanie = 0

	if damage <= 200.0 then
		kwota = 1500.0
		czas = 900
		czekanie = math.floor(czas*100)
	elseif damage <= 500.0 then
		kwota = math.floor(1000-(damage*0.2))
		czas = math.floor(1000-(damage*0.5))
		czekanie = math.floor(czas*100)
	elseif damage > 500.0 then
		kwota = math.floor(1000-(damage*0.3))
		czas = math.floor(1000-(damage*1))
		czekanie = math.floor(czas*100)
	end
  local cena = math.floor(kwota/2)

	if damage ~= 1000.0 then
		TriggerServerEvent('esx_mecanojob:pokazmarker', cena)
	else
		TriggerEvent("pNotify:SendNotification", {text = 'Silnik nie jest ~p~Uszkodzony!'})
		SetVehicleFixed(vehicle)
	end
end

RegisterNetEvent("esx_mecanojob:faktycznanaprawa")
AddEventHandler("esx_mecanojob:faktycznanaprawa", function(odliczanie)
	Naprawia = true
	local playerPed = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(playerPed, false)
	local damage = GetVehicleEngineHealth(vehicle)
	local kwota = 0
	local czas = 0
	local czekanie = 0
	local sekundy = 0
	local odliczanie = 0
	--local vehicle

	if IsPedInAnyVehicle(playerPed, false) then
		vehicle = GetVehiclePedIsIn(playerPed, false)
	else
		vehicle = GetClosestVehicle(coords, 8.0, 0, 70)
	end

	if damage <= 200.0 then
		kwota = 1500.0
		czas = 900
		czekanie = math.floor(czas*100)
	elseif damage <= 500.0 then
		kwota = math.floor(1000-(damage*0.2))
		czas = math.floor(1000-(damage*0.5))
		czekanie = math.floor(czas*100)
	elseif damage > 500.0 then
		kwota = math.floor(1000-(damage*0.3))
		czas = math.floor(1000-(damage*1))
		czekanie = math.floor(czas*400)
	end

	if IsPedInAnyVehicle(playerPed, false) then
		FreezeEntityPosition(vehicle, true)
		sekundy = math.floor(czekanie*0.001)
		OdliczaneSekundy = sekundy
	else
		FreezeEntityPosition(vehicle, false)
	end
end)

function odliczanie2()
	local playerPed = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(playerPed, false)
	local damage = GetVehicleEngineHealth(vehicle)
	local czas = 0
	local czekanie = 0
	local sekundy = 0
	local odliczanie = 0

	if damage <= 200.0 then
		czas = 900
		czekanie = math.floor(czas*100)
	elseif damage <= 500.0 then
		czas = math.floor(1000-(damage*0.5))
		czekanie = math.floor(czas*100)
	elseif damage > 500.0 then
		czas = math.floor(1000-(damage*1))
		czekanie = math.floor(czas*400)
	end

	sekundy = math.floor(czekanie*0.001)

	OdliczaneSekundy = sekundy
	Citizen.Wait(sekundy)

	--[[if sekundy >= 10 then
		repeat
			Citizen.Wait(10000)
			sekundy = math.floor(sekundy - 10)
			odliczanie = sekundy
			TriggerEvent("pNotify:SendNotification", {text = 'Pozostało '..odliczanie..' sekund...'})
		until(odliczanie <= 10)
		Citizen.Wait(odliczanie)
	end]]
end

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(1000)
		if Naprawia then
			OdliczaneSekundy = OdliczaneSekundy - 1
			if OdliczaneSekundy == 0 then
				Naprawia = false
				NaprawAuto()
			end
		end
	end
end)

function NaprawAuto()
	local playerPed = PlayerPedId()
	local vehicle = GetVehiclePedIsIn(playerPed, false)
	FreezeEntityPosition(vehicle, false)
	SetVehicleFixed(vehicle)
	SetVehicleEngineOn( vehicle, true, true )
	TriggerEvent("pNotify:SendNotification", {text = 'Pojazd Naprawiony!'})
	Naprawia = false
end

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(1)
		if ESX.PlayerData.job ~= nil and ESX.PlayerData.job.name == 'mecano' and not IsDead then
		 exports["rp-radio"]:GivePlayerAccessToFrequencies(1)
		elseif ESX.PlayerData.job ~= nil then
			exports["rp-radio"]:RemovePlayerAccessToFrequencies(1)
		end
	end
end)