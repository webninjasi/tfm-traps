pshy.require("pshy.events")

local newgame = pshy.require("pshy.rotations.newgame")


--- Contants
local TRAP_DURATION = 5000
local TRAP_RELOAD = 5000


--- Aliases
local TFM, ROOM, ui, system = tfm.exec, tfm.get.room, ui, system
local tonumber, pairs, ipairs = tonumber, pairs, ipairs
local unpack = table.unpack
local random, max, floor, ceil, abs = math.random, math.max, math.floor, math.ceil, math.abs
local lshift, btest = bit32.lshift, bit32.btest
local os_time = os.time


--- Ground System
do
  local _grounds = {}
  local _imgIds = {}

  function saveGround(options)
    local id = options.lua

    _grounds[id] = options

    if options.hide then
      if _imgIds[id] then
        TFM.removeImage(_imgIds[id])
        _imgIds[id] = nil
      end

      TFM.removePhysicObject(id)

      return
    end

    TFM.addPhysicObject(id, options.x, options.y, options)

    if options.move then
      TFM.movePhysicObject(id, unpack(options.move))
    end

    if options.image then
      if _imgIds[id] then
        TFM.removeImage(_imgIds[id])
        _imgIds[id] = nil
      end

      local img = options.image

      _imgIds[id] = TFM.addImage(
        img[1],
        "+" .. id,
        img[2] or 0, img[3] or 0,
        nil,
        img[4] or 1, img[5] or 1,
        (options.dynamic and 0 or math.rad(options.angle or 0)) + (img[6] or 0), img[7] or 1,
        img[8] or 0.5, img[9] or 0.5,
        img[10]
      )
    end
  end

  function reloadGrounds()
    for id, ground in next, _grounds do
      if not ground.dynamic or (ground.mass and ground.mass < 0) or ground.hide then
        if ground.hide then
          TFM.removePhysicObject(id)
        else
          saveGround(ground)
        end
      end
    end
  end

  function resetGrounds()
    _grounds = {}
  end
end


--- Trap Group System
do
  local groups = {}
  local lastId = 1000

  TrapGroupSystem = {
    ENABLE_ALWAYS = 0,
    ENABLE_RANDOM = 1,
    ENABLE_RANDOM_SINGLE = 2,

    reset = function(self)
      groups = {}
      lastId = 1000
    end,

    add = function(self, trap, groupName, behaviour)
      local group = groups[groupName]

      if not group then
        lastId = 1 + lastId
        group = {
          id = lastId,
          _len = 0,
          _behaviour = {},
        }
        groups[groupName] = group
      end

      group._len = 1 + group._len
      group[group._len] = trap.id
      group._behaviour[trap.id] = behaviour
    end,

    register = function(self)
      local info, duration, reload

      for groupName, group in pairs(groups) do
        if group._len > 0 then
          duration, reload = 0, 0
        else
          duration, reload = TRAP_DURATION, TRAP_RELOAD
        end

        for i=1, group._len do
          info = TrapSystem:get(group[i])

          if duration ~= -1 then
            if info.duration < 0 then
              duration = -1
            else
              duration = max(duration, info.duration)
            end
          end

          reload = max(reload, info.reload)
        end

        TrapSystem:register({
          onactivate = {
            _len = 1,
            {
              enable = function(_, player)
                local randomTraps = { _len = 0 }
                local randomSingleTraps = { _len = 0 }
                local behaviour

                for i=1,group._len do
                  behaviour = group._behaviour[group[i]]

                  if behaviour == self.ENABLE_ALWAYS then
                    TrapSystem:activate(group[i], player)
                  elseif behaviour == self.ENABLE_RANDOM then
                    randomTraps._len = 1 + randomTraps._len
                    randomTraps[randomTraps._len] = group[i]
                  elseif behaviour == self.ENABLE_RANDOM_SINGLE then
                    randomSingleTraps._len = 1 + randomSingleTraps._len
                    randomSingleTraps[randomSingleTraps._len] = group[i]
                  end
                end

                if randomTraps._len > 0 then
                  local enabledmask = random(lshift(1, randomTraps._len - 1))

                  for i=1,randomTraps._len do
                    if btest(enabledmask, lshift(1, i - 1)) then
                      TrapSystem:activate(randomTraps[i], player)
                    end
                  end
                end

                if randomSingleTraps._len > 0 then
                  local idx = random(1, randomSingleTraps._len)

                  TrapSystem:activate(randomSingleTraps[idx], player)
                end
              end,

              disable = function(_, player)
                for i=group._len, 1, -1 do
                  TrapSystem:deactivate(group[i], player)
                end
              end,
            }
          },
          name = "#" .. groupName,
          id = group.id,
          reload = reload,
          duration = duration,
        })
      end
    end,
  }
end


local commands

--- Trap Parser
do
  local function getTrap(trapName)
    if not trapName then
      return
    end

    local sym = trapName:sub(1, 1)
    local trap

    if sym == '@' then
      trap = TrapSystem:get(trapName:sub(2))
    elseif sym == '#' then
      trap = TrapSystem:get(trapName)
    end

    if trap then
      return trap
    end
  end

  local function getCoords(strx, stry)
    local x, y = tonumber(strx), tonumber(stry)
    if x or y then
      return x, y
    end

    local trap = getTrap(strx)
    if trap then
      return trap.x, y or trap.y
    end
  end

  local function tobool(value, default)
    if value == nil or value == "" then
      return default
    end

    value = value:lower()

    return value == "yes" or value == "true" or value == "1"
  end

  commands = {
    type = function(value) -- change type
      local _prev
      value = tonumber(value)
      return {
        enable = function(ground)
          _prev = ground.type
          ground.type = value
          return true
        end,

        disable = function(ground)
          ground.type = _prev
          return true
        end,
      }
    end,

    dynamic = function(enabled) -- change dynamic
      local _prev
      enabled = tobool(enabled, true)
      return {
        enable = function(ground)
          _prev = ground.dynamic
          ground.dynamic = enabled
          return true
        end,

        disable = function(ground)
          ground.dynamic = _prev
          return true
        end,
      }
    end,

    angle = function(value) -- change angle
      local _prev
      value = tonumber(value)
      return {
        enable = function(ground)
          _prev = ground.angle
          ground.angle = value
          return true
        end,

        disable = function(ground)
          ground.angle = _prev
          return true
        end,
      }
    end,

    collision = function(miceCol, groundCol) -- change collision
      local _prevMiceCol, _prevGroundCol

      miceCol = tobool(miceCol, nil)
      groundCol = tobool(groundCol, nil)

      return {
        enable = function(ground)
          if miceCol ~= nil then
            _prevMiceCol = ground.miceCollision
            ground.miceCollision = miceCol
          end

          if groundCol ~= nil then
            _prevGroundCol = ground.groundCollision
            ground.groundCollision = groundCol
          end

          return miceCol ~= nil or groundCol ~= nil
        end,

        disable = function(ground)
          if miceCol ~= nil then
            ground.miceCollision = _prevMiceCol
          end

          if groundCol ~= nil then
            ground.groundCollision = _prevGroundCol
          end

          return miceCol ~= nil or groundCol ~= nil
        end,
      }
    end,

    kill = function() -- kill on touch
      return {
        contact = function(name, contact)
          TFM.killPlayer(name)
        end,
      }
    end,

    freeze = function(enabled, displayIce) -- freeze on touch
      enabled = tobool(enabled, true)
      displayIce = tobool(displayIce, true)

      return {
        contact = function(name, contact)
          TFM.freezePlayer(name, enabled, displayIce)
        end,
      }
    end,

    friction = function(value) -- change friction
      local _prev
      value = tonumber(value)
      return {
        enable = function(ground)
          _prev = ground.friction
          ground.friction = value
          return true
        end,

        disable = function(ground)
          ground.friction = _prev
          return true
        end,
      }
    end,

    restitution = function(value) -- change restitution
      local _prev
      value = tonumber(value)
      return {
        enable = function(ground)
          _prev = ground.restitution
          ground.restitution = value
          return true
        end,

        disable = function(ground)
          ground.restitution = _prev
          return true
        end,
      }
    end,

    mass = function(value) -- change mass
      local _prev
      value = tonumber(value)
      return {
        enable = function(ground)
          _prev = ground.mass
          ground.mass = value
          return true
        end,

        disable = function(ground)
          ground.mass = _prev
          return true
        end,
      }
    end,

    fixed = function(enabled) -- change fixed rotation
      local _prev
      enabled = tobool(enabled, true)
      return {
        enable = function(ground)
          _prev = ground.fixedRotation
          ground.fixedRotation = enabled
          return true
        end,

        disable = function(ground)
          ground.fixedRotation = _prev
          return true
        end,
      }
    end,

    foreground = function(enabled) -- change foreground
      local _prev
      enabled = tobool(enabled, true)
      return {
        enable = function(ground)
          _prev = ground.foreground
          ground.foreground = enabled
          return true
        end,

        disable = function(ground)
          ground.foreground = _prev
          return true
        end,
      }
    end,

    color = function(value) -- change color
      local _prev
      value = tonumber(value, 16)
      return {
        enable = function(ground)
          _prev = ground.color
          ground.color = value
          return true
        end,

        disable = function(ground)
          ground.color = _prev
          return true
        end,
      }
    end,

    damping = function(linear, angular) -- change linear/angular damping
      local _prevLinear, _prevAngular

      linear = tonumber(linear)
      angular = tonumber(angular)

      return {
        enable = function(ground)
          if linear then
            _prevLinear = ground.linearDamping
            ground.linearDamping = linear
          end

          if angular then
            _prevAngular = ground.angularDamping
            ground.angularDamping = angular
          end

          return linear or angular
        end,

        disable = function(ground)
          if linear then
            ground.linearDamping = _prevLinear
          end

          if angular then
            ground.angularDamping = _prevAngular
          end

          return linear or angular
        end,
      }
    end,

    width = function(value) -- change width
      local _prev
      value = tonumber(value) or 10
      return {
        enable = function(ground)
          _prev = ground.width
          ground.width = value
          return true
        end,

        disable = function(ground)
          ground.width = _prev
          return true
        end,
      }
    end,

    height = function(value) -- change height
      local _prev
      value = tonumber(value) or 10
      return {
        enable = function(ground)
          _prev = ground.height
          ground.height = value
          return true
        end,

        disable = function(ground)
          ground.height = _prev
          return true
        end,
      }
    end,

    teleport = function(tx, ty, relative, indirect) -- teleport: x,y,relative,indirect (default x,y,false)
      local x, y, ready

      relative = tobool(relative, false)
      indirect = tobool(indirect, false)

      if indirect then
        return {
          enable = function(ground, player)
            if not ready then
              x, y = getCoords(tx, ty)
              x = x or (relative and 0)
              y = y or (relative and 0)
              ready = true
            end

            if player then
              TFM.movePlayer(player, x or 0, y or 0, relative)
            end
          end,
        }
      else
        return {
          contact = function(name, contact)
            if not ready then
              x, y = getCoords(tx, ty)
              x = x or (relative and 0)
              y = y or (relative and 0)
              ready = true
            end
    
            if x or y then
              TFM.movePlayer(name, x or contact.playerX, y or contact.playerY, relative)
            end
          end,
        }
      end
    end,

    speed = function(x, y, relative, indirect) -- speed/velocity: x,y,relative,indirect (default: 0,0,true,false)
      x, y = tonumber(x) or 0, tonumber(y) or 0
      relative = tobool(relative, true)
      indirect = tobool(indirect, false)

      if indirect then
        return {
          enable = function(ground, player)
            if player then
              TFM.movePlayer(player, 0, 0, true, x, y, relative)
            end
          end,
        }
      else
        return {
          contact = function(name, contact)
            TFM.movePlayer(name, 0, 0, true, x, y, relative)
          end,
        }
      end
    end,

    move = function(cx, cy, prel, vx, vy, vrel, a, arel) -- move ground: x,y,rel,xs,ys,rels,a,rela (default: 0,0,true,0,0,true,0,true)
      prel = tobool(prel, true)
      vx, vy = tonumber(vx) or 0, tonumber(vy) or 0
      vrel = tobool(vrel, true)
      a = tonumber(a) or 0
      arel = tobool(arel, true)

      local x, y, ready
      local _prev

      return {
        enable = function(ground)
          if not ready then
            x, y = getCoords(cx, cy)
            x, y = x or 0, y or 0
            ready = true
          end

          _prev = ground.move
          ground.move = { x, y, prel, vx, vy, vrel, a, arel }
          return true
        end,
        disable = function(ground)
          ground.move = _prev
          return true
        end,
      }
    end,

    hide = function() -- hide/remove the ground
      local _prev

      return {
        enable = function(ground)
          _prev = ground.hide
          ground.hide = true
          return true
        end,
        disable = function(ground)
          ground.hide = _prev
          return true
        end,
      }
    end,

    show = function() -- show the ground
      local _prev

      return {
        enable = function(ground)
          _prev = ground.hide
          ground.hide = nil
          return true
        end,
        disable = function(ground)
          ground.hide = _prev
          return true
        end,
      }
    end,

    toggle = function() -- toggle the ground
      local _prev

      return {
        enable = function(ground)
          _prev = ground.hide
          ground.hide = not ground.hide
          return true
        end,
        disable = function(ground)
          ground.hide = _prev
          return true
        end,
      }
    end,

    object = function(typ, ox, oy, ghost, angle, vx, vy, fx, fy) -- create shaman object: typ,x,y,ghost,angle,vx,vy,fx,fy (default: 1,0,0,false,0,0,0,,)
      typ = tonumber(type) or 1
      ghost = tobool(ghost, false)
      angle = tonumber(angle) or 0
      vx = tonumber(vx) or 0
      vy = tonumber(vy) or 0

      local options = (fx or fy) and {
        fixedXSpeed = tonumber(fx) or 0,
        fixedYSpeed = tonumber(fy) or 0
      } or nil
      local lastObjId
      local x, y, ready

      return {
        enable = function(ground)
          if not ready then
            x, y = getCoords(ox, oy)
            x, y = x or 0, y or 0
            ready = true
          end

          lastObjId = TFM.addShamanObject(typ, x, y, angle, vx, vy, ghost, options)
        end,
        disable = function(ground)
          TFM.removeObject(lastObjId)
        end,
      }
    end,

    cheese = function(give) -- give/take cheese: give (default: 1)
      local give = tobool(give, true)

      return {
        contact = function(name, contact)
          if give then
            TFM.giveCheese(name)
          else
            TFM.removeCheese(name)
          end
        end,
      }
    end,

    aie = function(enable, sensitivity) -- enable/disable aie mode: enable,sensitivity (default: 1,1)
      enable = tobool(enable, true)
      sensitivity = tonumber(sensitivity) or 1

      return {
        contact = function(name, contact)
          TFM.setAieMode(enable, sensitivity, name)
        end,
      }
    end,

    gravitywind = function(gravity, wind) -- set gravity and wind scale: gravity,wind (default: 1,1)
      gravity = tonumber(gravity) or 1
      wind = tonumber(wind) or 1

      return {
        contact = function(name, contact)
          TFM.setPlayerGravityScale(name, gravity, wind)
        end,
      }
    end,

    activate = function(target) -- activate a trap or a group: @trap/#group
      local trapId, ready

      return {
        enable = function(ground, player, trap)
          if not ready then
            if target ~= "" then
              local targetTrap = getTrap(target)

              if targetTrap then
                trapId = targetTrap.id
              end
            else
              trapId = trap.id
            end

            ready = true
          end

          if trapId then
            TrapSystem:activate(trapId, player)
          end
        end,
      }
    end,

    image = function(image, x, y, scalex, scaley, rotation, alpha, anchorx, anchory, fadeIn) -- change ground image
      x = tonumber(x) or 0
      y = tonumber(y) or 0
      scalex = tonumber(scalex) or 1
      scaley = tonumber(scaley) or 1
      rotation = tonumber(rotation) or 0
      alpha = tonumber(alpha) or 1
      anchorx = tonumber(anchorx) or 0.5
      anchory = tonumber(anchory) or 0.5
      fadeIn = tobool(fadeIn, false)

      local img = {
        image,
        x, y,
        scalex, scaley,
        rotation, alpha,
        anchorx, anchory,
        fadeIn
      }
      local _prevImage

      return {
        enable = function(ground)
          _prevImage = ground.image
          ground.image = img
          return true
        end,
        disable = function(ground)
          ground.image = _prevImage
          return true
        end,
      }
    end,

    sound = function(url, volume, sx, sy) -- play a sound
      volume = tonumber(volume)

      local x, y, ready

      x = tonumber(sx)
      y = tonumber(sy)

      local function play(player, contact, obj)
        if not ready then
          if obj then
            if sx == '-' then
              x = obj.x
            end

            if sy == '-' then
              y = obj.y
            end
          end

          ready = true
        end

        tfm.exec.playSound(url, volume, x, y, player)
      end

      return {
        enable = function(ground, player, trap)
          play(player, nil, trap)
        end,
        contact = play,
      }
    end,

    music = function(channel, url, volume, loop, fade) -- play a music
      url = url ~= '' and url
      volume = tonumber(volume)
      loop = tobool(loop, false)
      fade = tobool(fade, true)

      local function play(ground, player)
        if url then
          tfm.exec.playMusic(url, channel, volume, loop, fade, player)
        else
          tfm.exec.stopMusic(channel, player)
        end
      end

      return {
        enable = play,
        contact = function(name, contact)
          play(nil, name)
        end,
      }
    end,
  }
end


--- Trap System
do
  local _traps = {}
  local _active = {}
  local _timed = {}
  local _deactivatetime = {}
  local _reloadtime = {}
  local nameMapping = {}
  local timerTick = 0

  local function scanCallback(arr, name)
    local ret = { _len=0 }

    if arr then
      for i=1, #arr do
        if arr[i][name] then
          ret._len = 1 + ret._len
          ret[ret._len] = arr[i][name]
        end
      end
    end

    return ret
  end

  function TrapSystem_eventContactListener(name, id, contact)
    local trap = _traps[id]

    if not trap then
      return
    end

    local activateContact = trap.callbacks.activateContact
    local deactivateContact = trap.callbacks.deactivateContact
    local timerContact = trap.callbacks.timerContact
    local active = _active[id] and true or false
    local ground = trap.ground

    if active then
      for i=1, activateContact._len do
        activateContact[i](name, contact, ground)
      end
    else
      for i=1, deactivateContact._len do
        deactivateContact[i](name, contact, ground)
      end
    end

    if timerContact and _active[2000 + id] then
      for i=1, timerContact._len do
        timerContact[i](name, contact, ground)
      end
    end
  end

  TrapSystem = {
    reset = function()
      _traps = {}
      _active = {}
      _timed = {}
      _deactivatetime = {}
      _reloadtime = {}
      nameMapping = {}
      timerTick = 0
    end,

    register = function(self, trap)
      local id = trap.id
      local group

      _deactivatetime[id] = 0
      _reloadtime[id] = 0
      _traps[id] = trap

      if trap.name then
        nameMapping[trap.name] = id
      end

      local initCallbacks = not trap.callbacks

      if initCallbacks then
        trap.callbacks = {
          activateContact = scanCallback(trap.onactivate, "contact"),
          activateEnable = scanCallback(trap.onactivate, "enable"),
          activateDisable = scanCallback(trap.onactivate, "disable"),

          deactivateContact = scanCallback(trap.ondeactivate, "contact"),
          deactivateEnable = scanCallback(trap.ondeactivate, "enable"),
          deactivateDisable = scanCallback(trap.ondeactivate, "disable"),

          touchContact = scanCallback(trap.ontouch, "contact"),
          touchEnable = scanCallback(trap.ontouch, "enable"),
          touchDisable = scanCallback(trap.ontouch, "disable"),

          timerContact = scanCallback(trap.ontimer, "contact"),
          timerEnable = scanCallback(trap.ontimer, "enable"),
          timerDisable = scanCallback(trap.ontimer, "disable"),
        }
      end

      if trap.groups then
        for i=1, #trap.groups do
          group = trap.groups[i]
          local behaviour = TrapGroupSystem.ENABLE_ALWAYS

          if group.behaviour == 'random' then
            behaviour = TrapGroupSystem.ENABLE_RANDOM
          elseif group.behaviour == 'randomone' then
            behaviour = TrapGroupSystem.ENABLE_RANDOM_SINGLE
          elseif group.behaviour == 'always' then
            behaviour = TrapGroupSystem.ENABLE_ALWAYS
          end

          TrapGroupSystem:add(trap, group.name, behaviour)
        end
      end

      local ground

      if trap.getGround then
        ground = trap.getGround()
        trap.ground = ground
      end

      if trap.ontimer and #trap.ontimer > 0 then
        _timed[id] = trap.delay or 0

        -- shadow trap
        TrapSystem:register({
          onactivate = {
            _len = 1,
            {
              enable = function(_, player)
                local timerEnable = trap.callbacks.timerEnable
                local shouldUpdate = false

                for i=1, timerEnable._len do
                  shouldUpdate = timerEnable[i](ground, player, trap) or shouldUpdate
                end

                if shouldUpdate and ground then
                  saveGround(ground)
                end
              end,

              disable = function(_, player)
                local timerDisable = trap.callbacks.timerDisable
                local shouldUpdate = false

                -- Disable commands in reverse order to remove effects in correct order
                for i=timerDisable._len, 1, -1 do
                  shouldUpdate = timerDisable[i](ground, player) or shouldUpdate
                end

                if shouldUpdate and ground then
                  saveGround(ground)
                end
              end,
            }
          },
          name = "__" .. trap.id,
          id = 2000 + trap.id,
          reload = trap.timerReload or 0,
          duration = trap.timerDuration or (trap.interval * 1000 - 400),
        })
      end

      if ground then
        local activateContact = trap.callbacks.activateContact
        local deactivateContact = trap.callbacks.deactivateContact
        local timerContact = trap.callbacks.timerContact

        if timerContact then
          timerContact._len = #timerContact
        end

        ground.lua = id
        ground.id = id
        ground.contactListener = true

        if trap.ontouch and initCallbacks then
          local touchEnable = trap.callbacks.touchEnable
          local touchContact = trap.callbacks.touchContact

          local function callback(name, contact)
            local shouldUpdate = false

            for i=1, touchContact._len do
              touchContact[i](name, contact, ground)
            end

            for i=1, touchEnable._len do
              shouldUpdate = touchEnable[i](ground, name, trap) or shouldUpdate
            end

            if shouldUpdate and ground then
              saveGround(ground)
            end
          end

          activateContact._len = 1 + activateContact._len
          activateContact[activateContact._len] = callback

          deactivateContact._len = 1 + deactivateContact._len
          deactivateContact[deactivateContact._len] = callback
        end

        saveGround(ground)
      end

      local deactivateEnable = trap.callbacks.deactivateEnable
      local shouldUpdate = false

      for i=1, deactivateEnable._len do
        shouldUpdate = deactivateEnable[i](ground, nil, trap) or shouldUpdate
      end

      if shouldUpdate and ground then
        saveGround(ground)
      end
    end,

    get = function(self, identifier)
      local trap = _traps[identifier] or _traps[nameMapping[identifier]]

      if not trap then
        return
      end

      return {
        id = trap.id,
        active = _active[trap.id],
        deactivateTime = _deactivatetime[trap.id],
        reloadTime = _reloadtime[trap.id],
        duration = trap.duration,
        reload = trap.reload,
        timerDuration = trap.timerDuration,
        timerReload = trap.timerReload,
        x = trap.ground and trap.ground.x,
        y = trap.ground and trap.ground.y,
      }
    end,

    tick = function(self, trapId)
      local trap = _traps[trapId]

      if not trap then
        return
      end

      self:activate(2000 + trapId, nil)

      _timed[trapId] = _timed[trapId] + trap.interval
    end,

    activate = function(self, trapId, player)
      if _active[trapId] then
        return
      end

      local trap = _traps[trapId]

      if not trap then
        print(('Attempt to activate unregistered trap: %s'):format(tostring(trapId)))
        return
      end

      if os_time() - _reloadtime[trapId] < 0 then
        return
      end

      _deactivatetime[trapId] = os_time() + trap.duration
      _reloadtime[trapId] = _deactivatetime[trapId] + trap.reload
      _active[trapId] = true

      local activateEnable = trap.callbacks.activateEnable
      local deactivateDisable = trap.callbacks.deactivateDisable
      local touchDisable = trap.callbacks.touchDisable
      local shouldUpdate = false
      local ground = trap.ground

      -- Disable commands in reverse order to remove effects in correct order
      for i=touchDisable._len, 1, -1 do
        shouldUpdate = touchDisable[i](ground, player, trap) or shouldUpdate
      end

      for i=deactivateDisable._len, 1, -1 do
        shouldUpdate = deactivateDisable[i](ground, player, trap) or shouldUpdate
      end

      for i=1, activateEnable._len do
        shouldUpdate = activateEnable[i](ground, player, trap) or shouldUpdate
      end

      if shouldUpdate and ground then
        saveGround(ground)
      end
    end,

    deactivate = function(self, trapId, player)
      if not _active[trapId] then
        return
      end

      local trap = _traps[trapId]

      if not trap then
        print(('Attempt to deactivate unregistered trap: %s'):format(tostring(trapId)))
        return
      end

      if trap.duration < 0 or os_time() - _deactivatetime[trapId] < 0 then
        return
      end

      _active[trapId] = false

      local trap = _traps[trapId]

      if trap then
        local activateDisable = trap.callbacks.activateDisable
        local deactivateEnable = trap.callbacks.deactivateEnable
        local touchDisable = trap.callbacks.touchDisable
        local shouldUpdate = false
        local ground = trap.ground

        -- Disable commands in reverse order to remove effects in correct order
        for i=touchDisable._len, 1, -1 do
          shouldUpdate = touchDisable[i](ground, player, trap) or shouldUpdate
        end

        for i=activateDisable._len, 1, -1 do
          shouldUpdate = activateDisable[i](ground, player, trap) or shouldUpdate
        end

        for i=1, deactivateEnable._len do
          shouldUpdate = deactivateEnable[i](ground, player, trap) or shouldUpdate
        end

        if shouldUpdate and ground then
          saveGround(ground)
        end
      end
    end,
  }

  function TrapSystem_eventLoop(elapsed, remaining)
    for trapId in next, _active do
      TrapSystem:deactivate(trapId)
    end

    for trapId, tick in next, _timed do
      if timerTick == tick then
        TrapSystem:tick(trapId)
      end
    end

    timerTick = 0.5 + timerTick
  end
end


--- Events
function eventNewGame()
  local map = newgame.current_map

  TrapGroupSystem:reset()
  TrapSystem:reset()
  resetGrounds()

	if map and map.traps then
    local trapList = map.traps

    for i=1, #trapList do
      TrapSystem:register(trapList[i])
    end
	end

  TrapGroupSystem:register()
end

eventLoop = TrapSystem_eventLoop
eventNewPlayer = reloadGrounds
eventContactListener = TrapSystem_eventContactListener

return {
  TRAP_DURATION = TRAP_DURATION,
  TRAP_RELOAD = TRAP_DURATION,

  commands = commands,
}
