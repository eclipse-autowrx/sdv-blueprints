%% model name (use different name to avoid shadowing the script)
model = "PotholeAlertModel";

%% create model
if bdIsLoaded(model)
    close_system(model, 0);
end
if exist(model + ".slx", 'file')
    delete(model + ".slx");
end
new_system(model)
open_system(model)

%% Configuration: Set USE_DA to true when running on Linux with DA feeders
USE_DA = true;  % Set to true for DA integration, false for test signals

%% Add signal sources
if USE_DA
    fprintf('Using DA C Caller integration...\n');

    % Path to the c_caller folder (sibling of the model folder)
    script_dir = fileparts(mfilename('fullpath'));
    c_caller_dir = fullfile(fileparts(script_dir), 'c_caller');
    if ~isfolder(c_caller_dir)
        error('C caller folder not found: %s', c_caller_dir);
    end

    % Configure Simulation Target so C Caller can import and simulate custom code
    set_param(model, 'SimCustomHeaderCode', '#include "da_connector.h"');
    set_param(model, 'SimUserIncludeDirs', c_caller_dir);
    set_param(model, 'SimUserSources', 'da_connector.c');

    % Configure code generation custom code as well
    set_param(model, 'CustomHeaderCode', '#include "da_connector.h"');
    set_param(model, 'CustomInclude', c_caller_dir);
    set_param(model, 'CustomSource', 'da_connector.c');

    % C Caller blocks use the imported function list from Simulation Target
    % Set discrete sample time (0.01 s) for all C Caller blocks
    SAMPLE_TIME = '0.01';
    
    add_block('simulink/User-Defined Functions/C Caller', model + "/pothole_right");
    set_param(model + "/pothole_right", 'FunctionName', 'da_get_pothole_right', 'SampleTime', SAMPLE_TIME);

    add_block('simulink/User-Defined Functions/C Caller', model + "/pothole_left");
    set_param(model + "/pothole_left", 'FunctionName', 'da_get_pothole_left', 'SampleTime', SAMPLE_TIME);

    add_block('simulink/User-Defined Functions/C Caller', model + "/steering_angle");
    set_param(model + "/steering_angle", 'FunctionName', 'da_get_steering_angle', 'SampleTime', SAMPLE_TIME);

    add_block('simulink/User-Defined Functions/C Caller', model + "/hazard_signal");
    set_param(model + "/hazard_signal", 'FunctionName', 'da_set_hazard_signal', 'SampleTime', SAMPLE_TIME);

    % Refresh block interfaces so input/output ports exist before wiring
    set_param(model, 'SimulationCommand', 'update');
else
    fprintf('Using test signal sources for simulation...\n');
    
    % Test signal sources for simulation
    % Sine wave: 25*sin(0.5*t), period = 4*pi = 12.57s
    % RIGHT peak (steering = +25) at t = 3.14s
    % LEFT peak (steering = -25) at t = 9.42s
    
    % Pothole right - pulse at t=2s to t=4s (covers RIGHT peak)
    add_block("simulink/Sources/Pulse Generator", model + "/pothole_right");
    set_param(model + "/pothole_right","Period","20","PulseWidth","10","PhaseDelay","2","Amplitude","1");
    
    % Pothole left - pulse at t=8.5s to t=10.5s (covers LEFT peak)
    add_block("simulink/Sources/Pulse Generator", model + "/pothole_left");
    set_param(model + "/pothole_left","Period","20","PulseWidth","10","PhaseDelay","8.5","Amplitude","1");
    
    % Steering angle - sine wave sweeping left and right
    add_block("simulink/Sources/Sine Wave", model + "/steering_angle");
    set_param(model + "/steering_angle","Amplitude","25","Frequency","0.5","SampleTime","0");
    
    % Hazard signal output (terminator for test mode)
    add_block("simulink/Sinks/Terminator", model + "/hazard_signal");
end

% Output port for monitoring
add_block("simulink/Sinks/Out1", model + "/hazard_out_port")

%% steering compare
add_block("simulink/Logic and Bit Operations/Compare To Constant", model + "/steer_left")
set_param(model + "/steer_left","const","-5","relop","<")

add_block("simulink/Logic and Bit Operations/Compare To Constant", model + "/steer_right")
set_param(model + "/steer_right","const","5","relop",">")


%% AND blocks
add_block("simulink/Logic and Bit Operations/Logical Operator", model + "/and_left")
set_param(model + "/and_left","Operator","AND")

add_block("simulink/Logic and Bit Operations/Logical Operator", model + "/and_right")
set_param(model + "/and_right","Operator","AND")

%% OR (only left and right lanes trigger hazard)
add_block("simulink/Logic and Bit Operations/Logical Operator", model + "/or")
set_param(model + "/or","Operator","OR","Inputs","2")

%% connections
add_line(model,"steering_angle/1","steer_left/1")
add_line(model,"steering_angle/1","steer_right/1")

add_line(model,"pothole_left/1","and_left/1")
add_line(model,"steer_left/1","and_left/2")

add_line(model,"pothole_right/1","and_right/1")
add_line(model,"steer_right/1","and_right/2")

% Connect only left and right to OR (center lanes ignored per Python logic)
add_line(model,"and_left/1","or/1")
add_line(model,"and_right/1","or/2")

add_line(model,"or/1","hazard_signal/1")
add_line(model,"or/1","hazard_out_port/1")

%% log all signals

add_block("simulink/Sinks/To Workspace", model + "/log_pothole_left")
set_param(model + "/log_pothole_left","VariableName","pothole_left_out")
add_line(model,"pothole_left/1","log_pothole_left/1")

add_block("simulink/Sinks/To Workspace", model + "/log_pothole_right")
set_param(model + "/log_pothole_right","VariableName","pothole_right_out")
add_line(model,"pothole_right/1","log_pothole_right/1")

add_block("simulink/Sinks/To Workspace", model + "/log_steering")
set_param(model + "/log_steering","VariableName","steering_out")
add_line(model,"steering_angle/1","log_steering/1")

add_block("simulink/Sinks/To Workspace", model + "/hazard_log")
set_param(model + "/hazard_log","VariableName","hazard_out")
add_line(model,"or/1","hazard_log/1")

%% Enable signal logging for External Mode / Data Inspector
set_param(model, 'SignalLogging', 'on');
set_param(model, 'SignalLoggingName', 'logsout');

% Mark output signals for logging so they appear in Data Inspector
blocks_to_log = {'/pothole_left', '/pothole_right', '/steering_angle', '/or'};
log_names = {'pothole_left_logged', 'pothole_right_logged', 'steering_angle_logged', 'hazard_output_logged'};
for i = 1:length(blocks_to_log)
    try
        ph = get_param(model + blocks_to_log{i}, 'PortHandles');
        set_param(ph.Outport(1), 'DataLogging', 'on');
        set_param(ph.Outport(1), 'DataLoggingNameMode', 'Custom');
        set_param(ph.Outport(1), 'DataLoggingName', log_names{i});
    catch ME
        fprintf('Warning: Could not set logging for %s. Error: %s\n', blocks_to_log{i}, ME.message);
    end
end

%% arrange full model
Simulink.BlockDiagram.arrangeSystem(model)

%% Configure hardware implementation
set_param(model, 'HardwareBoard', 'NVIDIA Jetson');

%% save
save_system(model)

%% run simulation
set_param(model,"StopTime","inf")
% simOut = sim(model);
