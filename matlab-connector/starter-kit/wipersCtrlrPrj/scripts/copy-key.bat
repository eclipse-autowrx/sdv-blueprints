@echo off
setlocal

:: Input Arguments
:: JUMPHOST: userJumpHost@IPAddressJumpHost
set JUMPHOST=%~1
:: BUILDHOST: userBuildHost@IPAddressBuildHost
set BUILDHOST=%~2
:: TARGETHOST: userTargetHost@IPAddressTargetHost
set TARGETHOST=%~3
:: KEY: Path to private key file
set KEY=%~4

:: JUMP HOST
echo --- JUMP HOST ---
echo Attempting to connect to jump host %JUMPHOST%...
ssh -o "PasswordAuthentication no" -i %KEY% -t %JUMPHOST% "echo ConnectionEstablished"
if %errorlevel% equ 0 (
    echo SUCCESS: Connection established to %JUMPHOST% without copying public key.
) else (
	echo Failed to connect. Copying public key "%KEY%.pub" to host %JUMPHOST%...
	type %KEY%.pub | ssh -t %JUMPHOST% "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod -R go= ~/.ssh && cat >> ~/.ssh/authorized_keys"
)
echo.

:: BUILD HOST
echo --- BUILD HOST ---
if "%JUMPHOST%" neq "%BUILDHOST%" (
	echo Attempting to connect to build host %BUILDHOST%...
	ssh -o "PasswordAuthentication no" -i %KEY% -t %BUILDHOST% "echo ConnectionEstablished"
	if %errorlevel% equ 0 (
		echo SUCCESS: Connection established to %BUILDHOST% without copying public key.
	) else (
		echo Failed to connect. Copying public key "%KEY%.pub" to host %BUILDHOST%...
		type %KEY%.pub | ssh -t %BUILDHOST% "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod -R go= ~/.ssh && cat >> ~/.ssh/authorized_keys"
	)
) else (
	echo Build host %BUILDHOST% equal to jump host %JUMPHOST% - Skipped.
)
echo.

:: TARGET HOST 
echo --- TARGET HOST ---
echo Attempting to connect to target %TARGETHOST% via jump host %JUMPHOST%...
ssh -o "PasswordAuthentication no" -i %KEY% -t -J %JUMPHOST% %TARGETHOST% "echo ConnectionEstablished"
if %errorlevel% equ 0 (
    echo SUCCESS: Connection established to %TARGETHOST% without copying public key.
) else (
	echo Failed to connect. Copying public key "%KEY%.pub" to host %TARGETHOST%...
	type %KEY%.pub | ssh -t -J %JUMPHOST% %TARGETHOST% "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod -R go= ~/.ssh && cat >> ~/.ssh/authorized_keys"
)

endlocal

pause
exit