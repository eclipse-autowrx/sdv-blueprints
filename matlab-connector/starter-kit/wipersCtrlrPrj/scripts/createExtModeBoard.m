/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */
 
 % function to create board, toolchain and target connection
function [board, toolchain, targetConnection] = createExtModeBoard(boardName, localForwardPort)
    % Define target processor
    processor = target.get("Processor",Id='ARM Compatible-ARM Cortex-A (64-bit)');
    board     = target.create('Board', 'Name', boardName, 'Processors', processor);

    % Set up toolchain for cross-compilation for ARM64 target
    toolchain                                        = target.create("Toolchain");
    toolchain.Name                                   = "Remote SSH Build Toolchain";
    toolchain.Builder                                = target.create("CMakeBuilder");
    toolchain.Builder.Generator                      = "Unix Makefiles";
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_C_COMPILER', 'Value', 'aarch64-linux-gnu-gcc');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_CXX_COMPILER', 'Value', 'aarch64-linux-gnu-g++');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_SYSTEM_NAME', 'Value', 'Linux');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_FIND_ROOT_PATH', 'Value', '/usr/aarch64-linux-gnu');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_FIND_ROOT_PATH_MODE_PROGRAM', 'Value', 'NEVER');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_FIND_ROOT_PATH_MODE_LIBRARY', 'Value', 'ONLY');
    toolchain.Builder.CommandLineCacheEntries(end+1) = target.create('CMakeCacheEntry', 'Name', 'CMAKE_FIND_ROOT_PATH_MODE_INCLUDE', 'Value', 'ONLY');
    toolchain.RunsOn                                 = target.ExecutionContext.SSH;
    toolchain.SupportedHardware                      = target.create("HardwareComponentSupport", Component=board);

    % Execution tool
    matlabExecution                                             = target.create('ExecutionService',  'Name', 'SSH Deploy and Launcher');
    matlabExecution.APIImplementation                           = target.create('APIImplementation', 'Name', 'MyServiceImplementation');
    matlabExecution.APIImplementation.BuildDependencies         = target.create('MATLABDependencies');
    matlabExecution.APIImplementation.BuildDependencies.Classes = {'SSHExecutionTool'};
    matlabExecution.APIImplementation.API                       = target.get('API', 'ExecutionTool');
    board.Tools.ExecutionTools                                  = matlabExecution;

    % rtIOStream
    buildDependencies = target.create('BuildDependencies', 'SourceFiles', {fullfile('$(MATLAB_ROOT)','toolbox','coder','rtiostream','src','rtiostreamtcpip','rtiostream_tcpip.c')});
    apiImplementation = target.create('APIImplementation', 'Name', 'TCP ARM64 RTIOStream Implementation', 'API', target.get('API','rtiostream'), 'BuildDependencies', buildDependencies);
    tcpComms          = target.create('CommunicationInterface', 'Name', 'Windows TCP Interface', 'Channel', 'TCPChannel', 'APIImplementations', apiImplementation);
    board.CommunicationInterfaces = tcpComms;

    % ExtMode
    externalMode                      = target.create('ExternalMode', 'Name', 'External Mode', 'XCPTransportLayer', 'TCP');
    board.CommunicationProtocolStacks = externalMode;

    % Set up connection between development computer and target hardware - usage of local port forwarding
    tcpChannel                            = target.create('TCPChannel', 'Name', 'External Process TCPCommunicationChannel');
    tcpChannel.IPAddress                  = 'localhost';
    tcpChannel.Port                       = localForwardPort;
    targetConnection                      = target.create('TargetConnection', 'Name', 'Host Process Connection');
    targetConnection.CommunicationChannel = tcpChannel;
    targetConnection.Target               = board;
end