// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

function result = setupModelForExtModeProject(file)
    result = "Undefined error.";
    project = currentProject;
    projectFile = findFile(project, file);
    [~, modelName, ext] = fileparts(projectFile.Path);
    fprintf(modelName);
    stepSize = inputdlg({'Enter step size [s]:'},'Input',[1 45],{'0.1'});
    stepSize = str2double(stepSize{1});
    if ismember(ext, {'.slx'})
        % Do not change the order of the following commands. There are dependencies between the parameters.
        cs = getActiveConfigSet(modelName);
        cs.set_param('Name', 'Configuration'); % Name
        cs.set_param('Description', ''); % Description
    
        % Original configuration set target is ert.tlc
        cs.switchTarget('ert.tlc','');
        cs.set_param('HardwareBoard', 'Example SSH Board');   % Hardware board
    
        cs.set_param('TargetLang', 'C++');   % Language
        cs.set_param('CodeInterfacePackaging', 'Nonreusable function');   % Code interface packaging
        cs.set_param('GenerateAllocFcn', 'off');   % Use dynamic memory allocation for model initialization
        cs.set_param('Solver', 'FixedStepDiscrete');   % Solver
        
        % Solver
        cs.set_param('StartTime', '0.0');   % Start time
        cs.set_param('StopTime', 'inf');   % Stop time
        cs.set_param('SolverName', 'FixedStepDiscrete');   % Solver
        cs.set_param('SolverType', 'Fixed-step');   % Type
        cs.set_param('FixedStep', sprintf("%d", stepSize));   % Fixed-step size (fundamental sample time)
    
        % Data Import/Export
        cs.set_param('SaveFinalState', 'off');   % Save final state
        cs.set_param('LimitDataPoints', 'off');   % Limit data points
        cs.set_param('SaveFormat', 'Dataset');   % Save format
        cs.set_param('SaveOutput', 'on');   % Save output
        cs.set_param('SaveState', 'off');   % Save states
        cs.set_param('SignalLogging', 'on');   % Signal logging
        cs.set_param('DSMLogging', 'off');   % Data stores
        cs.set_param('SaveTime', 'off');   % Save time
        cs.set_param('ReturnWorkspaceOutputs', 'off');   % Single simulation output
        cs.set_param('OutputSaveName', 'yout');   % Output variable
        cs.set_param('SignalLoggingName', 'logsout');   % Signal logging name
        cs.set_param('LoggingToFile', 'off');   % Log data to file
        cs.set_param('DatasetSignalFormat', 'timeseries');   % Dataset signal format
    
        % Optimization
        cs.set_param('DefaultParameterBehavior', 'Tunable');   % Default parameter behavior
    
        % Code Generation
        cs.set_param('ExtMode', 'on');   % External mode
        cs.set_param('ExtModeAutomaticAllocSize', 'on');   % Automatically allocate static memory
        cs.set_param('CustomCodeUndefinedFunction', 'Use interface only');
        cs.set_param('CustomInclude', '..\src');   % Include directories
        cs.set_param('CustomDefine', 'EXTMODE_SAMPLING_RATE_HZ=100');   % measurement sampling rate - definition used in ert_main_base.cpp file
        cs.set_param('SimTargetLang', 'C++');
        cs.set_param('RTWUseSimCustomCode', 'off');
        cs.set_param('SimUserIncludeDirs', '..\src');   % Include directories
        result = "Settings successfully applied.";
    else
        result = "File extension is not '.slx'.";
    end
end