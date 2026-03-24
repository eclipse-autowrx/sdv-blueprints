// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

#ifndef STEPTHREAD_H
#define STEPTHREAD_H

#include "RTthreads.hpp"

class StepThread : public CyclicRTthread {
	public:
	  StepThread(int priority, int policy, std::vector<int> cores, int period_ns,  void (*stepFunc)())
	    : CyclicRTthread(priority, policy, cores, period_ns), stepFunc_(stepFunc) {}
	 
	  inline bool loop() override {
		  if (stop_flag_) {
			  return true;
		  }
		  else {
			  stepFunc_();
		  	  return false;
		  }
	  }
	 
	  void shutdown() {
		  stop_flag_ = true;
	  }	
	 
	private:
	  void (*stepFunc_)();
	  volatile bool stop_flag_ = false;
};

#endif // STEPTHREAD_H