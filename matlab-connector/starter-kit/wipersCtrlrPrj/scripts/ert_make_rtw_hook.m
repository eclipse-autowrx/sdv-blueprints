/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */
 function ert_make_rtw_hook(hookMethod,modelName,rtwroot,templateMakefile,buildOpts,buildArgs, buildInfo)

switch hookMethod
 case 'after_tlc'
    % Called just after invoking TLC Compiler (actual code generation.)
    % Valid arguments at this stage are hookMethod, Name, and buildArgs, buildInfo
    setTargetProvidesMain(buildInfo, true);
    removeSourceFiles(buildInfo, 'ert_main.cpp');
    % create custom main ert_custom_main.cpp based on ert_main_base.cpp
    % path relative to work\codegen\model1_ert_rtw
    ertMainStr = fileread('..\..\..\src\ert_main_base.cpp');
    % replace '%MODELNAME%' name with actual model name in ert_main_base.cpp
    ertMainStr = regexprep(ertMainStr, '%MODELNAME%', modelName);
    % set step size in nano seconds
    cs = getActiveConfigSet(modelName);
    ertMainStr = regexprep(ertMainStr, '%PERIOD_NS_MODEL%', sprintf('%d', str2double(cs.get_param('FixedStep'))*1e9));
    % write custom main file
    fid = fopen('ert_custom_main.cpp', 'w');
    fwrite(fid, ertMainStr);
    fclose(fid);
    % add additional source file
    addSourceFiles(buildInfo, 'ert_custom_main.cpp');
    sldiagviewer.reportInfo('### ert_main.cpp replaced with ert_custom_main.cpp');
end