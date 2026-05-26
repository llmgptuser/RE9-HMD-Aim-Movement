if reframework:get_game_name() ~= "re9" then return end

local cfg = {
    snap_turn_enabled = true,
    snap_turn_back_enabled = true,
    snap_turn_angle = 45.0,
    tilt_threshold = 0.8,
    recenter_threshold = 0.4,
    smooth_turn_speed = 5.0,
}

local cfg_path = "re9_vr/re9_vr_hmd_aim_movement_config.json"

local function load_cfg()
    local loaded_cfg = json.load_file(cfg_path)

    if loaded_cfg == nil then
        json.dump_file(cfg_path, cfg)
        return
    end

    for k, v in pairs(loaded_cfg) do
        cfg[k] = v
    end
end

load_cfg()

re.on_config_save(function()
    json.dump_file(cfg_path, cfg)
end)

local gamepad_singleton_t = sdk.find_type_definition("via.hid.GamePad")

local function get_right_input_axis()
    if vrmod:is_using_controllers() then
        local axis = vrmod:get_right_stick_axis()
        return axis
    end

    local gamepad_singleton = sdk.get_native_singleton("via.hid.GamePad")
    if not gamepad_singleton then return Vector2f.new(0, 0) end

    local pad = sdk.call_native_func(gamepad_singleton, gamepad_singleton_t, "get_LastInputDevice")
    if not pad then return Vector2f.new(0, 0) end

    return pad:get_AxisR()
end

local function math_sign(x)
    if x > 0 then
        return 1
    elseif x < 0 then
        return -1
    else
        return 0
    end
end

local is_stick_centered = true
local is_stick_centered_y = true
local snap_turn = false
local snap_turn_sign = 0
local snap_turn_back = false

local function get_current_character()
    local character_manager = sdk.get_managed_singleton("app.CharacterManager")
    if not character_manager then 
        return "Unknown" 
    end

    local player_context = character_manager:call("getPlayerContextRef") 
    if not player_context then 
        player_context = character_manager:call("get_PlayerContextFast")
    end
    
    if not player_context then 
        return "Unknown" 
    end

    local ok_leon, is_leon = pcall(function() 
        return player_context:call("get_IsCp_A0Character") 
    end)
    if ok_leon and is_leon then 
        return "Leon" 
    end

    local ok_grace, is_grace = pcall(function() 
        return player_context:call("get_IsCp_A1Character") 
    end)
    if ok_grace and is_grace then 
        return "Grace" 
    end

    return "Other"
end

local is_crouch = false
sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("PlayerInputMediator")):get_method("getCrouchState"),
    function(args)
    end,
    function(retval)
        is_crouch = ((sdk.to_int64(retval) & 1) == 1)
        return retval
    end
)

local function get_pivot_adjustment(yaw_radians, pitch_radians)
    local pitch_degrees = math.deg(pitch_radians)
    local char = get_current_character()
    if is_crouch then
        if char == "Grace" then
            local pivot_radius = 0.2485
            local pivot_h_radius = (90.0 + pitch_degrees * 1.5) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -math.sin(pitch_radians) * pivot_radius * 0.75
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y - 0.02, z + 0.27)
            return origin
        elseif char == "Leon" then
            local pivot_radius = 0.349
            local pivot_h_radius = (90.0 + pitch_degrees * 0.40) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -math.sin(pitch_radians) * pivot_radius * 0.33
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y - 0.02, z + 0.32)
            return origin
        else
            local pivot_radius = 0.20
            local pivot_h_radius = (90.0 + pitch_degrees * (-0.8)) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -math.sin(pitch_radians) * pivot_radius * 0.2
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y, z + 0.27)
            return origin
        end
    else
        if char == "Grace" then
            local pivot_radius = 0.098
            local pivot_h_radius = (90.0 + pitch_degrees * 2.0) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -(math.sin(pitch_radians) - math.cos(pitch_radians)) * pivot_radius * 0.5
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y - 0.07, z + 0.1)
            return origin
        elseif char == "Leon" then
            local pivot_radius = 0.083
            local pivot_h_radius = (90.0 + pitch_degrees * 3.0) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -(math.sin(pitch_radians) - 1.5 * math.cos(pitch_radians)) * pivot_radius * 0.5
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y - 0.07, z + 0.1)
            return origin
        else
            local pivot_radius = 0.098
            local pivot_h_radius = (90.0 + pitch_degrees * (-0.8)) / 90.0 * pivot_radius
            local x = -math.sin(yaw_radians) * pivot_h_radius
            local y = -(math.sin(pitch_radians) - 0 * math.cos(pitch_radians)) * pivot_radius * 0.5
            local z = -math.cos(yaw_radians) * pivot_h_radius
            local origin = Vector3f.new(x, y, z + 0.1)
            return origin          
        end
    end
end

local turn_yaw_degrees = 0
sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("CameraUtillty")):get_method("setYawDeg"),
    function(args)
    end,
    function(retval)
        if not vrmod:is_hmd_active() then
            return retval
        end
        local quat = vrmod:get_rotation(0):to_quat()
        local forward = quat * Vector3f.new(0, 0, 1)
        local yaw_radians = math.atan(forward.x, forward.z)
        local yaw_degrees = math.deg(yaw_radians)
        local pitch_radians = math.atan(forward.y, math.sqrt(forward.x * forward.x + forward.z * forward.z))
        local pitch_degrees = math.deg(pitch_radians)

        local origin = get_pivot_adjustment(yaw_radians, pitch_radians)
        vrmod:set_standing_origin(origin)
        vrmod:recenter_view()

        local right_stick_axis = get_right_input_axis()
        local x_axis = right_stick_axis.x
        local y_axis = right_stick_axis.y
        if cfg.snap_turn_enabled then
            if is_stick_centered then
                if math.abs(x_axis) > cfg.tilt_threshold then
                    is_stick_centered = false
                    snap_turn_sign = math_sign(x_axis)
                    turn_yaw_degrees = turn_yaw_degrees - snap_turn_sign * cfg.snap_turn_angle
                end
            elseif math.abs(x_axis) < cfg.recenter_threshold then
                is_stick_centered = true
            end
            if cfg.snap_turn_back_enabled and is_stick_centered then
                if is_stick_centered_y then
                    if y_axis < -cfg.tilt_threshold then
                        is_stick_centered_y = false
                        turn_yaw_degrees = turn_yaw_degrees + 180.0
                    end
                elseif math.abs(y_axis) < cfg.recenter_threshold then
                    is_stick_centered_y = true
                end
            end
        else
            turn_yaw_degrees = turn_yaw_degrees - x_axis * cfg.smooth_turn_speed
        end
        return sdk.float_to_ptr(yaw_degrees + turn_yaw_degrees)
    end
)

sdk.hook(
    sdk.find_type_definition(sdk.game_namespace("CameraUtillty")):get_method("setPitchDeg"),
    function(args)
    end,
    function(retval)
        if not vrmod:is_hmd_active() then
            return retval
        end
        local quat = vrmod:get_rotation(0):to_quat()
        local forward = quat * Vector3f.new(0, 0, 1)
        local pitch_radians = math.atan(forward.y, math.sqrt(forward.x * forward.x + forward.z * forward.z))
        local pitch_degrees = math.deg(pitch_radians)
        vrmod:recenter_view()
        return sdk.float_to_ptr(-pitch_degrees)
    end
)

re.on_draw_ui(function()
    local changed = false
    if imgui.tree_node("HMD Aim and Enhanced Movement") then
        changed, cfg.snap_turn_enabled = imgui.checkbox("Snap Turn Enabled", cfg.snap_turn_enabled)
        if cfg.snap_turn_enabled then
            changed, cfg.snap_turn_angle = imgui.drag_float("Snap Turn Angle", cfg.snap_turn_angle, 15.0, 15.0, 90.0)
            changed, cfg.tilt_threshold = imgui.drag_float("Snap Turn Tilt Threshold", cfg.tilt_threshold, 0.05, 0.1, 1.0)
            changed, cfg.recenter_threshold = imgui.drag_float("Snap Turn Recenter Threshold", cfg.recenter_threshold, 0.05, 0.1, 1.0)
            changed, cfg.snap_turn_back_enabled = imgui.checkbox("Tild Down to Turn Back Enabled", cfg.snap_turn_back_enabled)
        else
            changed, cfg.smooth_turn_speed = imgui.drag_float("Smooth Turn Speed", cfg.smooth_turn_speed, 1.0, 1.0, 50.0)
        end
        imgui.tree_pop()
    end
end)
