// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

% this script checks the connections to the different hosts and checks if
% the port for local forwarding is free
fprintf("\n### Info: Checking connections...\n");
cfg = jsondecode(fileread('config.json'));
checkLocalPort(cfg);
checkTargetConnection(cfg);

% function to check if the configured port for local port forwarding is free
function checkLocalPort(cfg)
    portLocal = cfg.PortLocal;
    cmd = ['netstat -an | findstr /C:":' portLocal ' "'];
    [status, out] = system(cmd);
    if ~isempty(out)
        errFlag = true;
        fprintf("### Error: local forwarding port localhost:%s not free\n", portLocal);
    else
        errFlag = false;
        fprintf("### Info: Local forwarding port is free\n");
    end
end

% check connection to jump host and target - note: connection to build host
function checkTargetConnection(cfg)
    if strcmp(cfg.IPBuildHost, cfg.IPJumpHost)
        system(['echo JumpHost: && '...
            'ssh -o "PasswordAuthentication no" -t -i ' cfg.PrivateKey ' ' cfg.UserJumpHost '@' cfg.IPJumpHost ' uname -a && ' ...
            'echo --- && echo BuildHost: Skipped - same as JumpHost && '...
            'echo --- && echo Target: && '...
            'ssh -o "PasswordAuthentication no" -t -i ' cfg.PrivateKey ' -J ' cfg.UserJumpHost '@' cfg.IPJumpHost ' '...
                cfg.UserTarget '@' cfg.IPTarget ' uname -a && ' ...
            ' timeout 4 && exit &']);
    else
        system(['echo JumpHost: && '...
            'ssh -o "PasswordAuthentication no" -t -i ' cfg.PrivateKey ' ' cfg.UserJumpHost '@' cfg.IPJumpHost ' uname -a && ' ...
            'echo --- && echo BuildHost: && '...
            'ssh -o "PasswordAuthentication no" -t -i ' cfg.PrivateKey ' ' cfg.UserBuildHost '@' cfg.IPBuildHost ' uname -a && ' ...
            'echo --- && echo Target: && '...
            'ssh -o "PasswordAuthentication no" -t -i ' cfg.PrivateKey ' -J ' cfg.UserJumpHost '@' cfg.IPJumpHost ' '...
                cfg.UserTarget '@' cfg.IPTarget ' uname -a && ' ...
            ' timeout 4 && exit &']);
    end
end