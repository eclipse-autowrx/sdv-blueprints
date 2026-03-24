/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */

//
// File: ert_main.cpp
//
// Code generated for Simulink model '%MODELNAME%'.
//
// Model version                  : 1.4
// Simulink Coder version         : 25.1 (R2025a) 21-Nov-2024
// C/C++ source code generated on : Mon Sep 15 15:28:19 2025
//
// Target selection: ert.tlc
// Embedded hardware selection: Intel->x86-64 (Windows64)
// Code generation objectives: Unspecified
// Validation result: Not run
//
#include <stdio.h>              // This example main program uses printf/fflush
#include "%MODELNAME%.h"                 // Model header file
#include "ext_mode.h"                  // External mode header file
#include "StepThread.hpp" // RT-Thread

//
// Associating rt_OneStep with a real-time clock or interrupt service routine
// is what makes the generated code "real-time".  The function rt_OneStep is
// always associated with the base rate of the model.  Subrates are managed
// by the base rate from inside the generated code.  Enabling/disabling
// interrupts and floating point context switches are target specific.  This
// example code indicates where these should take place relative to executing
// the generated code step function.  Overrun behavior should be tailored to
// your application needs.  This example simply sets an error status in the
// real-time model and returns from rt_OneStep.
//

void rt_OneStep(void);
void rt_OneStep(void)
{
  extmodeSimulationTime_T extmodeTime = (extmodeSimulationTime_T)0;
  extmodeErrorCode_T extmodeError = EXTMODE_SUCCESS;
  static boolean_T OverrunFlag{ false };

  // Disable interrupts here

  // Check for overrun
  if (OverrunFlag) {
    rtmSetErrorStatus(%MODELNAME%_M, "Overrun");
    return;
  }

  OverrunFlag = true;

  // Save FPU context here (if necessary)
  // Re-enable timer or interrupt here
  // Set model inputs here
  extmodeTime = (extmodeSimulationTime_T)(%MODELNAME%_M->Timing.taskTime0);

  // Step the model
  %MODELNAME%_step();

  // Get model outputs here
  extmodeError = extmodeEvent((extmodeEventId_T)(0), extmodeTime);
  if (extmodeError != EXTMODE_SUCCESS) {
    // Code to handle external mode event errors may be added here
  }

  // Indicate task complete
  OverrunFlag = false;

  // Disable interrupts here
  // Restore FPU context here (if necessary)
  // Enable interrupts here
}

//
// The example main function illustrates what is required by your
// application code to initialize, execute, and terminate the generated code.
// Attaching rt_OneStep to a real-time clock is target specific. This example
// illustrates how you do this relative to initializing the model.
//
int_T main(int_T argc, const char *argv[])
{
  extmodeErrorCode_T errorCode = EXTMODE_SUCCESS;

  // Parse External Mode command line arguments
  errorCode = extmodeParseArgs(argc, (const char**)argv);
  if (errorCode != EXTMODE_SUCCESS) {
    return (errorCode);
  }

  // Initialize model
  %MODELNAME%_initialize();

  // External Mode initialization
  errorCode = extmodeInit(%MODELNAME%_M->extModeInfo, &rtmGetTFinal(%MODELNAME%_M));
  if (errorCode != EXTMODE_SUCCESS) {
    // Code to handle External Mode initialization errors
    // may be added here
  }

  if (errorCode == EXTMODE_SUCCESS) {
    // Wait until a Start or Stop Request has been received from the Host
    extmodeWaitForHostRequest(EXTMODE_WAIT_FOREVER);
    if (extmodeStopRequested()) {
      rtmSetStopRequested(%MODELNAME%_M, true);
    }
  }

  // Create thread rt_OneStep_thread for rt_OneStep function
  int priority = 80;
  int policy = SCHED_FIFO;
  std::vector<int> cores = {1,2,3,4,5,6,7};
  
  StepThread rt_OneStep_thread(priority, policy, cores, %PERIOD_NS_MODEL%, rt_OneStep);
  rt_OneStep_thread.start();

  while (!extmodeSimulationComplete()&& !extmodeStopRequested()&&
         !rtmGetStopRequested(%MODELNAME%_M)) {
    // Run External Mode background activities
    errorCode = extmodeBackgroundRun();
    if (errorCode != EXTMODE_SUCCESS && errorCode != EXTMODE_EMPTY) {
      // Code to handle External Mode background task errors
      // may be added here
    }

    std::this_thread::sleep_for(std::chrono::nanoseconds(1000000000/EXTMODE_SAMPLING_RATE_HZ));
  }
  
  // Stop thread rt_OneStep_thread
  rt_OneStep_thread.shutdown();
  rt_OneStep_thread.join();

  // Terminate model
  %MODELNAME%_terminate();

  // External Mode reset
  extmodeReset();
  return 0;
}

//
// File trailer for generated code.
//
// [EOF]
//
