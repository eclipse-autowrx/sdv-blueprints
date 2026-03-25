// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

% function for generating a key pair and copying the public key to the hosts
function setupKeys(action)
    switch action
        case 'generateKey'
            system('ssh-keygen -t rsa && pause && exit &');
        case 'copyPublicKeyToHosts'
            cfg = jsondecode(fileread('config.json'));
            system(['.\scripts\copy-key.bat '...
                cfg.UserJumpHost '@' cfg.IPJumpHost ' '...
                cfg.UserBuildHost '@' cfg.IPBuildHost ' '...
                cfg.UserTarget '@' cfg.IPTarget ' '...
                cfg.PrivateKey...
                ' &']);
        otherwise
    end
end