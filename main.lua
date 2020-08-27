-- START CLASSIC
local Object = {}
Object.__index = Object


function Object:new()
end


function Object:extend()
    local cls = {}
    for k, v in pairs(self) do
        if sub(k, 1, 2) == "__" then
            cls[k] = v
        end
    end
    cls.__index = cls
    cls.super = self
    setmetatable(cls, self)
    return cls
end


function Object:implement(...)
    for _, cls in pairs({...}) do
        for k, v in pairs(cls) do
            if self[k] == nil and type(v) == "function" then
                self[k] = v
            end
        end
    end
end


function Object:is(T)
    local mt = getmetatable(self)
    while mt do
        if mt == T then
            return true
        end
        mt = getmetatable(mt)
    end
    return false
end


function Object:__tostring()
    return "Object"
end


function Object:__call(...)
    local obj = setmetatable({}, self)
    obj:new(...)
    return obj
end
-- END CLASSIC

-- START STATE MANAGEMENT
local STATES = {
    GAME = "GAME",
    TITLE = "TITLE",
}
local currentState

-- END STATE MANAGEMENT

-- START GAME
local function drawBox(x, y, width, height)
    -- Shadow
    rectfill(
        x, y,
        x + width, y + height + 1,
        5
    )
    -- White outline
    rectfill(
        x, y,
        x + width, y + height,
        7
    )
    -- Black box
    rectfill(
        x + 1, y + 1,
        x + 1 + width - 2, y + 1 + height - 2,
        0
    )
end

-- START PHYSICS
local WALL_TILES = {
    3, 4, 5,
    19, 21,
    35, 36, 37,
    6, 7, 8,
    22,
}


local WATER_TILES = {
    48, 49, 50,
    64, 65,
    80, 81, 82,
}


local RAMPS = {
    WEST = 51,
    NORTH = 52,
    EAST = 67,
    SOUTH = 68,
}


local function isInTileset(tile, tileset)
    for _, candidateTile in ipairs(tileset) do
        if tile == candidateTile then
            return true
        end
    end
    return false
end

local function checkMove(x, y, newX, newY, width, height)
    -- Simulates a movement from (x, y) to (newX, newY).
    -- x and y movements are calculated separately to provide
    -- accurate collision information. No bouncing is applied;
    -- if a wall is struck, the movement simply stops for that
    -- axis.
    local resultX, resultY
    local collidedX = false
    local collidedY = false

    local xStep = 0
    local yStep = 0
    if newX ~= x then
        xStep = 0.01 * (newX - x)/abs(newX - x)
    end
    if newY ~= y then
        yStep = 0.01 * (newY - y)/abs(newY - y)
    end

    local tile
    if xStep ~= 0 then
        for xi = x, newX, xStep do
            -- If the ball is travelling to the right,
            -- include the width in the calculation so
            -- the correct edge is checked for collision.
            local xToCheck = xi
            if xStep > 0 then
                xToCheck = xi + (width - 1)
            end
            tile = mget(
                flr(xToCheck/8),
                flr(y/8)
            )
            if isInTileset(tile, WALL_TILES) then
                resultX = xi - xStep
                collidedX = true
                break
            end
        end
    end
    if not resultX then
        resultX = newX
    end

    if yStep ~= 0 then
        for yi = y, newY, yStep do
            -- If the ball is travelling down,
            -- include the height in the calculation so
            -- the correct edge is checked for collision.
            local yToCheck = yi
            if yStep > 0 then
                yToCheck = yi + (height - 1)
            end
            tile = mget(
                flr(resultX/8),
                flr(yToCheck/8)
            )
            if isInTileset(tile, WALL_TILES) then
                resultY = yi - yStep
                collidedY = true
                break
            end
        end
    end
    if not resultY then
        resultY = newY
    end

    return resultX, resultY, collidedX, collidedY
end


local function collides(x1, y1, w1, h1, x2, y2, w2, h2)
    return (
        x1 <= x2 + w2 and
        x1 + w1 >= x2 and
        y1 <= y2 + h2 and
        y1 + h1 >= y2
    )
end


local function containsPoint(px, py, x, y, w, h)
    return (
        px >= x and px <= x + w and
        py >= y and py <= y + h
    )
end
-- END PHYSICS

local SFX = {
    SPLASH = 63,
    BOUNCE = 62,
    STROKE = 61,
    SINK = 60,
    SKIM = 58,
    SELECT = 59,
}

local pin
local sparks
local SPARK_LIFE_MAX = 60

local function resetSparks(x, y)
    for i, spark in ipairs(sparks) do
        spark.x = x
        spark.y = y
        local angle = i/#sparks
        spark.velX = cos(angle) * 0.75
        spark.velY = sin(angle) * 0.75
        spark.t = SPARK_LIFE_MAX
    end
end

local Ball = Object:extend()

Ball.MAX_SPEED = 8
Ball.FRICTION = 0.98
Ball.SIZE = 4
Ball.RAMP_SPEED_CHANGE_RATE = 0.05

function Ball:new(x, y)
    self.x = x
    self.y = y
    self.velX = 0
    self.velY = 0
    self.isStopped = true
    self.isSunk = false
end

function Ball:reset(x, y)
    self.isSunk = false
    self.isStopped = true
    self.velX = 0
    self.velY = 0
    self.x = x
    self.y = y
end

function Ball:hit(angle, power)
    if not self.isStopped then
        return
    end
    self.velX = power * Ball.MAX_SPEED * cos(angle)
    self.velY = power * Ball.MAX_SPEED * sin(angle)
    self.isStopped = false
    sfx(SFX.STROKE)
end

function Ball:applyRamp(direction)
    if direction == 'NORTH' then
        self.velY = self.velY - Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'SOUTH' then
        self.velY = self.velY + Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'WEST' then
        self.velX = self.velX - Ball.RAMP_SPEED_CHANGE_RATE
    elseif direction == 'EAST' then
        self.velX = self.velX + Ball.RAMP_SPEED_CHANGE_RATE
    end
end

function Ball:canSink()
    -- Ball can only sink in hole if it is going slow enough.
end

function Ball:update()
    if not self.isStopped then
        local newX, newY = self.x, self.y

        newX = self.x + self.velX
        newX, _, collidedX, _ = checkMove(self.x, self.y, newX, newY, Ball.SIZE, Ball.SIZE)
        if collidedX then
            self.velX = self.velX * -1
        end

        newY = self.y + self.velY
        _, newY, _, collidedY = checkMove(newX, self.y, newX, newY, Ball.SIZE, Ball.SIZE)
        if collidedY then
            self.velY = self.velY * -1
        end

        self.x = newX
        self.y = newY

        -- Check for ramps
        local onRamp = false
        local currentTile = mget(
            flr((self.x + Ball.SIZE/2)/8),
            flr((self.y + Ball.SIZE/2)/8)
        )
        for direction, tile in pairs(RAMPS) do
            if tile == currentTile then
                onRamp = true
                -- self:applyRamp(direction)
                break
            end
        end

        self.velX = self.velX * Ball.FRICTION
        self.velY = self.velY * Ball.FRICTION
        local speed = sqrt(self.velX * self.velX + self.velY * self.velY)
        -- Ball cannot stop on a ramp.
        if not onRamp and speed < 0.1 then
            self.velX = 0
            self.velY = 0
            self.isStopped = true
        end

        if collidedX or collidedY then
            sfx(SFX.BOUNCE)
        end

        if containsPoint(
            self.x + Ball.SIZE/2, self.y + Ball.SIZE/2,
            pin.x + 2, pin.y + 2, 4, 4
        ) then
            if speed < 3 then
                self.isSunk = true
                self.isStopped = true
                sfx(SFX.SINK)
                resetSparks(pin.x + 4, pin.y + 4)
            else
                sfx(SFX.SKIM)
            end
        end
    end
end

function Ball:draw()
    spr(17, self.x - (8 - Ball.SIZE)/2, self.y - (8 - Ball.SIZE)/2)
end

-- Distance from ball where the line should start.
local ANGLE_INDICATOR_BUFFER = 4
local ANGLE_INDICATOR_LENGTH = 24
local ANGLE_CHANGE_RATE = 0.0025

local POWER_BAR_WIDTH = 48
local POWER_BAR_HEIGHT = 8
local POWER_BAR_MARGIN = 1
local POWER_BAR_X = 128 - POWER_BAR_WIDTH - POWER_BAR_MARGIN - 3
local POWER_BAR_Y = POWER_BAR_MARGIN
local POWER_CHANGE_RATE = 0.02

local NEXT_HOLE_TIMER_MAX = 120
local WATER_TIMER_MAX = 60

local ball
local ballOrigin
local currentHole
local scores
local angle
local power
local powerIncreasing
local holeCompleted
local nextHoleTimer
local waterTimer
-- Timer preventing user input straight after scene change.
local gameStartTimer
local showingScore
local roundOver


local function getHolePosition(holeNumber)
    -- Overflow from final hole to first hole.
    if holeNumber > 16 then
        holeNumber = 1
    end
    local holeY = 0
    local holeX = holeNumber - 1
    if holeNumber > 8 then
        holeY = 1
        holeX = (16 - holeNumber)
    end
    return holeX, holeY
end


function initHole(holeNumber)
    holeCompleted = false
    showingScore = false
    roundOver = false
    nextHoleTimer = 0
    waterTimer = 0
    scores[holeNumber] = 0

    local holeX, holeY = getHolePosition(holeNumber)

    for x = holeX * 16, holeX * 16 + 16 do 
        for y = holeY * 16, holeY * 16 + 16 do
            local tile = mget(x, y)
            if tile == 18 then
                pin = {
                    x = x * 8,
                    y = y * 8,
                }
            elseif tile == 16 then
                ballOrigin = {
                    x = x * 8,
                    y = y * 8,
                }
                ball:reset(x * 8 + 2, y * 8 + 2)
            end
        end
    end

    angle = flr(atan2(pin.x - ball.x, pin.y - ball.y) * 8) * 0.125
end


function initGame()
    gameStartTimer = 60
    power = 0
    powerIncreasing = true
    angle = 0.25
    ball = Ball(32, 32)
    scores = {}
    currentHole = 1
    -- Sparks are used to celebrate the ball going in the hole.
    sparks = {}
    for i=1,8 do
        add(
            sparks,
            {
                x = 0,
                y = 0,
                velX = 0,
                velY = 0,
                t = 0,
            }
        )
    end
    initHole(currentHole)
end


function updateGame()
    if gameStartTimer > 0 then
        gameStartTimer = gameStartTimer - 1
        return
    end

    if nextHoleTimer > 0 then
        nextHoleTimer = nextHoleTimer - 1
        if nextHoleTimer == 0 then
            if currentHole < 15 then
                currentHole = currentHole + 1
                initHole(currentHole)
            else
                roundOver = true
            end
        end
    end

    if roundOver then
        if btn(5) then
            initGame()
        end
    end


    if waterTimer > 0 then
        waterTimer = waterTimer - 1
        if waterTimer == 0 then
            ball:reset(
                ballOrigin.x + 2,
                ballOrigin.y + 2
            )
        end
    end

    -- Update sparks that fly up when ball skims the hole.
    for _, spark in ipairs(sparks) do
        if spark.t > 0 then
            spark.t = spark.t - 1
            spark.x = spark.x + spark.velX
            spark.y = spark.y + spark.velY
            spark.velX = spark.velX * 0.99
            spark.velY = spark.velY * 0.99
        end
    end

    if not holeCompleted and waterTimer == 0 then
        if btn(0) then
            angle = angle + ANGLE_CHANGE_RATE
        elseif btn(1) then
            angle = angle - ANGLE_CHANGE_RATE
        end

        if btn(5) then
            if powerIncreasing then
                power = power + POWER_CHANGE_RATE
            else
                power = power - POWER_CHANGE_RATE
            end
            if power > 1 then
                power = 1
                powerIncreasing = false
            elseif power < 0 then
                power = 0
                powerIncreasing = true
            end
        elseif power > 0 then
            ball:hit(angle, power)
            power = 0
            powerIncreasing = true

            scores[currentHole] = scores[currentHole] + 1
        end
        ball:update()

        if ball.isSunk then
            holeCompleted = true
            showingScore = true
        end

        -- Check for water. sploosh
        local currentTile = mget(
            flr((ball.x + Ball.SIZE/2)/8),
            flr((ball.y + Ball.SIZE/2)/8)
        )
        if isInTileset(currentTile, WATER_TILES) then
            waterTimer = WATER_TIMER_MAX
            sfx(SFX.SPLASH)
        end
    else
        if showingScore and btnp(5) then
            showingScore = false
            nextHoleTimer = NEXT_HOLE_TIMER_MAX
            sfx(SFX.SELECT)
        end
    end
end

function drawHud()
    if roundOver then
        drawBox(8, 8, 112, 12)
        drawBox(8, 20, 112, 100)
        print('scorecard', (128 - 9 * 4)/2, 12, 7)

        local x = 0
        local y = 0
        rectfill(20, 40 + 6, 108, 40 + 6, 7)
        rectfill(20, 72 + 6, 108, 72 + 6, 7)
        for holeNumber, score in pairs(scores) do
            print(
                holeNumber,
                22 + x * 10,
                40 + y * 32,
                7
            )
            print(
                score,
                22 + x * 10,
                40 + y * 32 + 8,
                7
            )
            x = x + 1
            if x >= 8 then
                x = 0
                y = y + 1
            end
        end
        -- Add scores onto the ends of rows
        local firstHalfScore = 0
        local secondHalfScore = 0
        for i=1,8 do
            firstHalfScore = firstHalfScore + scores[i]
        end
        for i=9,16 do
            secondHalfScore = secondHalfScore + scores[i]
        end
        print(firstHalfScore, 102, 48, 7)
        print(secondHalfScore, 102, 80, 7)

        -- Final score
        print('SCORE', (128 - 5 * 4)/2, 92, 7)
        local finalScore = tostring(firstHalfScore + secondHalfScore)
        print(finalScore, (128 - #finalScore * 4)/2, 98, 7)

        drawBox(16, 108, 96, 16)
        local text = "press \x97 to play again"
        print(text, (128 - #text * 4)/2, 114, 7)
    else
        -- Shadow
        rectfill(
            POWER_BAR_X, POWER_BAR_Y,
            POWER_BAR_X + POWER_BAR_WIDTH + 2, POWER_BAR_Y + POWER_BAR_HEIGHT + 3,
            5
        )
        -- White outline
        rectfill(
            POWER_BAR_X, POWER_BAR_Y,
            POWER_BAR_X + POWER_BAR_WIDTH + 2, POWER_BAR_Y + POWER_BAR_HEIGHT + 2,
            7
        )
        -- Red power bar
        rectfill(
            POWER_BAR_X + 1, POWER_BAR_Y + 1,
            POWER_BAR_X + 1 + POWER_BAR_WIDTH * power, POWER_BAR_Y + 1 + POWER_BAR_HEIGHT,
            8
        )
        -- Black unpowered section
        rectfill(
            POWER_BAR_X + 1 + POWER_BAR_WIDTH * power, POWER_BAR_Y + 1,
            POWER_BAR_X + 1 + POWER_BAR_WIDTH, POWER_BAR_Y + 1 + POWER_BAR_HEIGHT,
            0
        )
        -- Shadow text
        print('power', POWER_BAR_X + 1 + (POWER_BAR_WIDTH - 20)/2, POWER_BAR_Y + 2 + (POWER_BAR_HEIGHT - 4)/2, 5)
        -- Actual text
        print('power', POWER_BAR_X + 1 + (POWER_BAR_WIDTH - 20)/2, POWER_BAR_Y + 1 + (POWER_BAR_HEIGHT - 4)/2, 7)

        -- Hole Number
        -- Shadow
        drawBox(POWER_BAR_MARGIN, POWER_BAR_MARGIN, 32, 10)
        -- Hole number text
        print(
            'Hole '..tostring(currentHole),
            POWER_BAR_MARGIN + 3,
            POWER_BAR_MARGIN + 3,
            7
        )

        -- Show score after completing hole
        if showingScore then
            drawBox(57, 57, 14, 14)
            print(scores[currentHole], 63, 62, 7)

            drawBox(20, 82, 88, 16)
            print('press X to continue', (128 - 19 * 4)/2, 88, 7)
        end
    end
end


function drawGame()
    local holeX, holeY = getHolePosition(currentHole)

    local cameraX = holeX * 128
    local cameraY = holeY * 128
    if holeCompleted and not showingScore then
        local nextHoleX, nextHoleY = getHolePosition(currentHole + 1)
        cameraX = holeX * 128 + (nextHoleX - holeX) * 128 * (1 - nextHoleTimer/NEXT_HOLE_TIMER_MAX)
        cameraY = holeY * 128 + (nextHoleY - holeY) * 128 * (1 - nextHoleTimer/NEXT_HOLE_TIMER_MAX)
    end

    camera(cameraX, cameraY)
    map(0, 0, 0, 0, 128, 32)

    if gameStartTimer == 0 and not holeCompleted and waterTimer == 0 then
        ball:draw()
        if ball.isStopped then
            line(
                ball.x + Ball.SIZE/2 + ANGLE_INDICATOR_BUFFER * cos(angle),
                ball.y + Ball.SIZE/2 + ANGLE_INDICATOR_BUFFER * sin(angle),
                ball.x + Ball.SIZE/2 + (ANGLE_INDICATOR_BUFFER + ANGLE_INDICATOR_LENGTH) * cos(angle),
                ball.y + Ball.SIZE/2 + (ANGLE_INDICATOR_BUFFER + ANGLE_INDICATOR_LENGTH) * sin(angle),
                7
            )
        end
    end

    for _, spark in ipairs(sparks) do
        if spark.t > 0 then
            local y = spark.y + 16 * sin(0.5 * spark.t/SPARK_LIFE_MAX)
            rectfill(spark.x, y, spark.x + 1, y + 1, flr(rnd(16)))
        end
    end

    -- Hud drawing; only show hud when game is active
    -- i.e. not under menus or titles.
    camera(0, 0)
    if currentState == STATES.GAME then
        drawHud()
    end
end
-- END GAME

-- START TITLES

local function createTransitionPixels()
    local result = {}
    for x=0,15 do
        for y=0,15 do
            add(result, { x = x, y = y })
        end
    end
    for i = #result, 2, -1 do
        local j = ceil(rnd(i))
        result[i], result[j] = result[j], result[i]
    end
    return result
end

local sceneTransitionPixels = createTransitionPixels()

local titleTimer = 0
local function updateTitles()
    titleTimer = titleTimer + 1
    if titleTimer > 120 then
        if btn(5) then
            currentState = STATES.GAME
            sfx(SFX.SELECT)
        end
    end
end

local function drawTitles()
    if titleTimer < 90 then
        cls()
    end
    if titleTimer < 60 then
        local logoText = 'ruairi made this'
        print(
            logoText,
            (128 - #logoText * 4)/2,
            62,
            7
        )
    elseif titleTimer >= 90 then
        drawBox(12, 32, 104, 32)
        spr(
            96,
            (128 - 9 * 8)/2,
            40,
            9,
            2
        )

        drawBox(20, 80, 88, 16)
        if titleTimer > 120 and (titleTimer/45) % 2 < 1 then
            local text = "press \x97 to tee off"
            print(text, (128 - #text * 4)/2, 86, 7)
        end

        if titleTimer < 120 then
            -- Cool pixelate effect when changing scenes
            local pixelCount = (16 * 16) * (1 - ((titleTimer - 90)/30))
            for i=1,pixelCount do
                rectfill(
                    sceneTransitionPixels[i].x * 8,
                    sceneTransitionPixels[i].y * 8,
                    sceneTransitionPixels[i].x * 8 + 8,
                    sceneTransitionPixels[i].y * 8 + 8,
                    0
                )
            end
        end
    end
end

-- END TITLES

-- START MAIN

function _init()
    palt(0, false)
    palt(14, true)
    currentState = STATES.TITLE
    initGame()
end

function _update60()
    if currentState == STATES.GAME then
        updateGame()
    elseif currentState == STATES.TITLE then
        updateTitles()
    end
end

function _draw()
    cls()
    drawGame()
    if currentState == STATES.TITLE then
        drawTitles()
    end
end
-- END MAIN
