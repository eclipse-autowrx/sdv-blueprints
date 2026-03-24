/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */

classdef SSHExecutionTool < target.ExecutionTool
   %SSHEXECUTIONTOOL Execution tool over SSH
   %   Execution tool that uses SSH to deploy and start an application
   %   to a remote server.
   %   The file assumes that the ssh command is already configured so that
   %   the connection is established without needed authentication.
   %   For external mode, the connection should also forward the
   %   appropriate port.

   properties
      Exe;
      ConnectionManager;
      DeploymentManager;
      ChmodOut = '';
      ExecutionManager;
      jumpHost;
      targetHost;
      deploymentPath;
      portLocal;
      portTarget;
      id;
   end

   methods
      % Open the application harness.
      function errFlag = open(this)
         sldiagviewer.reportInfo("### open()");
         
         % load configuration settings
         this.loadConfig();

         % check target port configuration
         if this.checkTargetPort()
             errFlag = true;
             return
         end
         sldiagviewer.reportInfo("### Info: target port checked");

         exeFullPath  = char(this.Application);
         [~,name,ext] = fileparts(exeFullPath);
         this.Exe = strcat(name, ext);

         % Create ssh command to ensure connection to target is established
         connectExecutionTool = this.createHostProcessExecutionTool('Command Line SSH Execution', 'ssh', {'-i', this.id, '-J', this.jumpHost, this.targetHost, 'echo ConnectionEstablished'});
         this.ConnectionManager = targetframework.services.appexecution.createAndRunExecutionManager('', connectExecutionTool.Inner);
         this.ConnectionManager.join();

         errFlag = ~contains(this.ConnectionManager.getStandardOutput(), 'ConnectionEstablished');
      end
      
      % Check if the port on the target is free to be used for the external mode
      function errFlag = checkTargetPort(this)
          sshCmd = sprintf('ssh -i %s -J %s %s "ss -tlnp | grep %s"', this.id, this.jumpHost, this.targetHost, sprintf("':%s '", this.portTarget));
          [status, out] = system(sshCmd);
          if ~isempty(out)
              errFlag = true;
              sldiagviewer.reportInfo(sprintf("### Error: target port localhost:%s not free", this.portTarget));
          else
              errFlag = false;
          end
      end
      
      % load configuration
      function loadConfig(this)
          cfg = jsondecode(fileread('config.json'));
          this.deploymentPath = cfg.DeploymentPath;
          this.jumpHost = [cfg.UserJumpHost '@' cfg.IPJumpHost];
          this.targetHost = [cfg.UserTarget '@' cfg.IPTarget];
          this.portLocal = cfg.PortLocal;
          this.portTarget = cfg.PortTarget;
          this.id = cfg.PrivateKey;
          sldiagviewer.reportInfo(sprintf("### config - localforward: %s:localhost:%s jumphost: %s target: %s", this.portLocal, this.portTarget, this.jumpHost, this.targetHost));
      end

      function errFlag = loadApplication(this)
         sldiagviewer.reportInfo("### loadApplication()");
         remoteExePath = [this.deploymentPath '/' this.Exe];
         % create remote directory if required
         if this.checkDeploymentPath()
             errFlag = true;
             return
         end

         % create and run SSH Deployment Manager
         scpCmd = {'-i', this.id, '-J', this.jumpHost, char(this.Application), [this.targetHost ':' remoteExePath]};
         cmdlineDeploymentTool = this.createHostProcessExecutionTool('Command Line SSH Deployment', 'scp', scpCmd);

         this.DeploymentManager = targetframework.services.appexecution.createAndRunExecutionManager('', cmdlineDeploymentTool.Inner);
         this.DeploymentManager.join();
         this.DeploymentManager.unload();
         this.DeploymentManager.close();

         sshChmodCmd = ['ssh ' '-i ' this.id ' -J ' this.jumpHost ' ' this.targetHost ' "chmod +x ' remoteExePath '"'];
         [status, this.ChmodOut] = system(sshChmodCmd);
         if status ~= 0
            errFlag = true;
            return;
         end
         % create SSH Execution Manager with local port forwarding active
         sshCmd = {'-i', this.id, '-L', sprintf('%s:localhost:%s', this.portLocal, this.portTarget), '-J', this.jumpHost, this.targetHost, ['"' remoteExePath '"'], '-port', this.portTarget};
         cmdlineExecutionTool = this.createHostProcessExecutionTool('Command Line SSH Execution', 'ssh', sshCmd);         

         this.ExecutionManager = targetframework.services.appexecution.createExecutionManager(remoteExePath, cmdlineExecutionTool.Inner);

         errFlag = false;
      end

      function exeTool = createHostProcessExecutionTool(this, name, cmd, cmdArg) %#ok<INUSD>
         exeCmd = target.create('Command', cmd, cmdArg);
         exeTool = target.create('HostProcessExecutionTool', ...
            'Name', name, ...
            'StartCommand', exeCmd, ...
            'OpenTimeout', 10000);
      end

      % Check if the deployment directory exists and create the directory
      % if it does not exist
      function errFlag = checkDeploymentPath(this)
          sshCmd = sprintf('ssh -i %s -J %s %s "if test -d %s; then echo PathExists; else echo PathMissing; fi"', this.id, this.jumpHost, this.targetHost, this.deploymentPath);
          [status, out] = system(sshCmd);
          if contains(out, 'PathExists')
            errFlag = false;
            sldiagviewer.reportInfo(sprintf("### Info: deployment directory exists"));
          elseif contains(out, 'PathMissing')
            sshCmd = sprintf('ssh -i %s -J %s %s "mkdir -p %s"', this.id, this.jumpHost, this.targetHost, this.deploymentPath);
            [status, out] = system(sshCmd);
            if status>0
                errFlag = true;
                sldiagviewer.reportInfo(sprintf("### Info: failed to create directory %s", this.deploymentPath));
            else
                errFlag = false;
                sldiagviewer.reportInfo(sprintf("### Info: created deployment directory %s", this.deploymentPath));
            end
          else
            errFlag = true;
            sldiagviewer.reportInfo(sprintf("### Info: failed to check deployment path %s", this.deploymentPath));
          end
      end


      % Close the application harness.
      function errFlag = close(this)
         this.ExecutionManager.close;
         errFlag = false;
      end


      % Start executing the application on the target.
      function errFlag = startApplication(this)
         sldiagviewer.reportInfo("### startApplication()");
         this.ExecutionManager.open();
         this.ExecutionManager.load();
         this.ExecutionManager.start();
         sldiagviewer.reportInfo("### startApplication() - pause...");
         pause(2); % wait for 2 seconds after starting before connecting to application
         errFlag = false;
      end


      % Stop execution of the application on the target.
      function errFlag = stopApplication(this)
         sldiagviewer.reportInfo("### stopApplication()");
         this.ExecutionManager.stop();
         errFlag = false;
      end

      % Get the status of the application running on the target.
      function [status, errFlag] = getApplicationStatus(this)
         if isempty(this.ExecutionManager)
            status = target.ApplicationStatus.Stopped;
         else
            status = this.ExecutionManager.ApplicationStatus;
         end
         errFlag = false;
      end


      % Get output captured from the applications standard output stream
      function [out, errFlag] = getStandardOutput(this)
         out = '';
         if ~isempty(this.ConnectionManager), out = [out, this.ConnectionManager.getStandardOutput()]; end
         if ~isempty(this.DeploymentManager), out = [out, this.DeploymentManager.getStandardOutput()]; end
         if ~isempty(this.ChmodOut),          out = [out, this.ChmodOut];                              end
         if ~isempty(this.ExecutionManager),  out = [out, this.ExecutionManager.getStandardOutput()];  end
         errFlag = false;
      end

      % Get output captured from the applications standard error stream
      function [err, errFlag] = getStandardError(this)
         err = '';
         if ~isempty(this.ConnectionManager), err = [err, this.ConnectionManager.getStandardError()]; end
         if ~isempty(this.DeploymentManager), err = [err, this.DeploymentManager.getStandardError()]; end
         if ~isempty(this.ExecutionManager),  err = [err, this.ExecutionManager.getStandardError()];  end
         errFlag = false;
      end

   end
end
