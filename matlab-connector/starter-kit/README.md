# MATLAB External Mode - Haptic Force Controller Starter Kit

## Overview
- This example demonstrates the implementation of the control of smart actuators (SW on the Central Computer) in Simulink as a variant of the haptic force controller based on the "MiX / Digital.auto StarterKit Demonstrator" (see https://github.boschdevcloud.com/bios-integration-of-xDomain-systems).
- The motor position setpoint for the right motor is provided as a parameter. The left motor is synchronized with the actual position of the right motor.
- The Central Computer, on which the application is deployed using the MATLAB external mode, communicates with the zone microcontrollers using UDP/IP. The SW runs in a cyclic 1 ms process.
- The serializer and deserializer are taken over from https://github.boschdevcloud.com/bios-integration-of-xDomain-systems/ros2_haptic_force_controller and are integrated in Simulink using the "C Caller" block, the UDP/IP communication is implemented in C++ and integrated in Simulink using the "C Caller" block as well (see source and header files in ./src directory of the project).


## Run the Example
- 0. Prerequesit: "MiX / Digital.auto StarterKit Demonstrator" set-up deployed on hardware.
- 1. Open the project and update the external mode configuration.
- 2. Click on the shortcut "Open Model" and start the external mode in Simulink (HARDWARE Tab -> Monitor & Tune).
- 3. Enable the controllers by setting the parameter "flag_enable_controller" to 1. Change the motor angle setpoint by setting the parameter "Angle_setpoint_right". Tune the parameters of the 2DOF PID controllers during runtime.
