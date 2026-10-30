local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local scriptActive = false -- เริ่มต้นเป็น false (กดเปิดในเมนูก่อนใช้งาน)
local isRightClicking = false
local isEngaging = false

local requiredZombieCount = 3 -- ต้องเห็นซอมบี้พร้อมกัน 5 ตัวขึ้นไปถึงเริ่มยิง
local lastShootTime = 0
local shootCooldown = 0.9     -- หน่วงเวลารอ 0.4 วินาที ยิงทีละ 1 นัดไม่เปลืองกระสุน
local currentTarget = nil     -- เช็กเป้าหมายปัจจุบันเพื่อยิงนัดแรกทันที

-- ==========================================
-- 1. UI ปุ่มเปิด / ปิด สคริปต์
-- ==========================================
local guiParent = LocalPlayer:WaitForChild("PlayerGui")
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZombieFarmUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = guiParent

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 130, 0, 45)
ToggleBtn.Position = UDim2.new(0, 20, 0, 20)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50) -- สีแดง (OFF)
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Text = "สคริปต์: OFF"
ToggleBtn.Font = Enum.Font.SourceSansBold
ToggleBtn.TextSize = 18
ToggleBtn.Parent = ScreenGui

local function toggleScript()
    scriptActive = not scriptActive
    if scriptActive then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 50) -- สีเขียว (ON)
        ToggleBtn.Text = "สคริปต์: ON"
    else
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        ToggleBtn.Text = "สคริปต์: OFF"
        isEngaging = false
        currentTarget = nil
        if isRightClicking then
            isRightClicking = false
            local mousePos = UserInputService:GetMouseLocation()
            VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 1, false, game, 0)
        end
    end
end

ToggleBtn.MouseButton1Click:Connect(toggleScript)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        toggleScript()
    end
end)

-- ==========================================
-- 2. ระบบเช็กสิ่งกีดขวาง (Wall Check)
-- ==========================================
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function isTargetVisible(targetHead)
    if not targetHead then return false end
    if LocalPlayer.Character then
        raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    end

    local origin = Camera.CFrame.Position
    local direction = targetHead.Position - origin
    local result = Workspace:Raycast(origin, direction, raycastParams)
    
    if not result or result.Instance:IsDescendantOf(targetHead.Parent) then
        return true
    end
    return false
end

-- ==========================================
-- 3. ค้นหาซอมบี้ที่มองเห็นได้ในจอ
-- ==========================================
local function getVisibleNPCs()
    local visibleList = {}

    for _, obj in pairs(Workspace:GetChildren()) do
        local modelCandidates = {}
        if obj:IsA("Model") then
            table.insert(modelCandidates, obj)
        elseif obj:IsA("Folder") then
            for _, child in pairs(obj:GetChildren()) do
                if child:IsA("Model") then table.insert(modelCandidates, child) end
            end
        end

        for _, model in pairs(modelCandidates) do
            local head = model:FindFirstChild("Head")
            local humanoid = model:FindFirstChild("Humanoid")
            
            if head and humanoid and humanoid.Health > 0 then
                if not Players:GetPlayerFromCharacter(model) and model ~= LocalPlayer.Character then
                    local headPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                    if onScreen and isTargetVisible(head) then
                        table.insert(visibleList, model)
                    end
                end
            end
        end
    end
    return visibleList
end

-- ==========================================
-- 4. Loop หลัก (ใช้ Heartbeat ทำงานเบื้องหลังได้)
-- ==========================================
RunService.Heartbeat:Connect(function()
    if not scriptActive then return end

    local visibleZombies = getVisibleNPCs()
    local mousePos = UserInputService:GetMouseLocation()

    -- เช็กซอมบี้ครบ 5 ตัวเพื่อเปิดฉากยิง
    if not isEngaging then
        if #visibleZombies >= requiredZombieCount then
            isEngaging = true
        end
    end

    if isEngaging then
        if #visibleZombies > 0 then
            local target = nil
            local shortestDistance = math.huge

            for _, zombie in pairs(visibleZombies) do
                local headPos = Camera:WorldToViewportPoint(zombie.Head.Position)
                local dist = (Vector2.new(headPos.X, headPos.Y) - mousePos).Magnitude
                if dist < shortestDistance then
                    target = zombie
                    shortestDistance = dist
                end
            end

            if target and target:FindFirstChild("Head") then
                -- ถ้าเปลี่ยนเป้าหมาย ยิงนัดแรกทันที
                if currentTarget ~= target then
                    currentTarget = target
                    lastShootTime = 0 
                end

                -- หมุนกล้องล็อกหัว
                Camera.CFrame = CFrame.new(Camera.CFrame.Position, target.Head.Position)

                -- กดคลิกขวาเล็ง
                if not isRightClicking then
                    isRightClicking = true
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 1, true, game, 0)
                end

                -- สั่งยิงทีละ 1 นัดตามคูลดาวน์
                if tick() - lastShootTime >= shootCooldown then
                    lastShootTime = tick()
                    VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)
                    task.delay(0.02, function()
                        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
                    end)
                end
            end
        else
            -- ซอมบี้หมดฝูงแล้ว ปลดโหมดการยิง
            isEngaging = false
            currentTarget = nil
            if isRightClicking then
                isRightClicking = false
                VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 1, false, game, 0)
            end
        end
    else
        if isRightClicking then
            isRightClicking = false
            VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 1, false, game, 0)
        end
    end
end)

-- ==========================================
-- 5. ระบบกด E อัตโนมัติวนลูป
-- ==========================================
task.spawn(function()
    while task.wait(0.1) do
        if scriptActive then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end
    end
end)
