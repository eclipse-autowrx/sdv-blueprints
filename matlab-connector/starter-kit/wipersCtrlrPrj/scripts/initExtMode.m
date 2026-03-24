/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */
 % this script registers the target configuration for external mode
fprintf("\n### Info: Initialize target configuration...\n");
% load configuration
cfg = jsondecode(fileread('config.json'));

[board, toolchain, targetConnection] = createExtModeBoard('Example SSH Board', cfg.PortLocal);

% board, toolchain and connection need to be removed if script has already been executed during current Matlab session
target.remove([toolchain, targetConnection, board], 'IncludeAssociations', true);
target.add([board, toolchain, targetConnection]);

% Open connection for SSH ExecutionContext of toolchain
target.connection.close(board.Name);
target.connection.open(board.Name, IPAddress=cfg.IPBuildHost, Username=cfg.UserBuildHost, AuthenticationMode='IdentityFile', IdentityFilePath=cfg.PrivateKey, Port=22)

fprintf("Set up script for external mode successfully executed.\n");