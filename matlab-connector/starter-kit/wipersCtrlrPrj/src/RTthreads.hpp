// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

#ifndef RTTHREAD_H
#define RTTHREAD_H

#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>
#include <unistd.h>  // For sysconf

#include <chrono>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

class RTthread {
   public:
    RTthread(int priority, int policy, std::vector<int> cores)
        : priority_(priority), policy_(policy), cores_(cores) {}

    virtual ~RTthread() = default;

    void start() {
        pthread_attr_t attr;
        int ret = pthread_attr_init(&attr);
        if (ret) {
            throw std::runtime_error("error in pthread_attr_init: " + std::string(std::strerror(ret)));
        }

        // Validate scheduler policy
        if (policy_ != SCHED_FIFO && policy_ != SCHED_RR && policy_ != SCHED_OTHER) {
            throw std::runtime_error("Error: Unsupported scheduling policy!");
        }

        // Set the scheduler policy
        ret = pthread_attr_setschedpolicy(&attr, policy_);
        if (ret) {
            throw std::runtime_error("error in pthread_attr_setschedpolicy: " + std::string(std::strerror(ret)));
        }

        // Validate and set priority
        int min_prio = sched_get_priority_min(policy_);
        int max_prio = sched_get_priority_max(policy_);
        std::cout << "[DEBUG] Scheduler Policy: " << policy_ << " | Min Prio: " << min_prio << " | Max Prio: " << max_prio << "\n";

        if (priority_ < min_prio || priority_ > max_prio) {
            throw std::runtime_error("Error: Priority must be between " + std::to_string(min_prio) + " and " + std::to_string(max_prio));
        }

        struct sched_param param;
        param.sched_priority = priority_;
        ret = pthread_attr_setschedparam(&attr, &param);
        if (ret) {
            throw std::runtime_error("error in pthread_attr_setschedparam: " + std::string(std::strerror(ret)));
        }

        // Explicitly use the scheduling attributes
        ret = pthread_attr_setinheritsched(&attr, PTHREAD_EXPLICIT_SCHED);
        if (ret) {
            throw std::runtime_error("error in pthread_attr_setinheritsched: " + std::string(std::strerror(ret)));
        }

        struct sched_param check_param;
        int check_policy;
        pthread_getschedparam(pthread_self(), &check_policy, &check_param);
        std::cout << "[DEBUG] Applied Policy: " << check_policy
                  << " | Applied Priority: " << check_param.sched_priority << std::endl;


        // Create the thread
        ret = pthread_create(&thread_, &attr, &RTthread::runThread, this);
        if (ret) {
            throw std::runtime_error("error in pthread_create: " + std::string(std::strerror(ret)));
        }

        pthread_attr_destroy(&attr);  // Cleanup
    }

    int join() { return pthread_join(thread_, NULL); }

    virtual void run() noexcept = 0;

   protected:
    int priority_;
    int policy_;
    std::vector<int> cores_;
    pthread_t thread_;

    static void* runThread(void* data) {
        RTthread* thread = static_cast<RTthread*>(data);

        // Print scheduling parameters in the new thread
        int policy;
        struct sched_param param;
        pthread_getschedparam(pthread_self(), &policy, &param);
        std::cout << "[DEBUG THREAD] Scheduler Policy: " << policy
                << " | Priority: " << param.sched_priority << std::endl;

        try {
            thread->setAffinity();
            thread->run();
        } catch (const std::exception& e) {
            std::cerr << "[ERROR] Exception in thread: " << e.what() << std::endl;
        }
        return nullptr;
    }

    void setAffinity() {
        cpu_set_t cpuset;
        CPU_ZERO(&cpuset);

        int available_cores = sysconf(_SC_NPROCESSORS_ONLN);
        std::cout << "[DEBUG] Available CPU Cores: " << available_cores << std::endl;

        bool valid_core_found = false;
        for (int core : cores_) {
            if (core < available_cores) {
                CPU_SET(core, &cpuset);
                valid_core_found = true;
            } else {
                std::cerr << "[WARNING] Core " << core << " is out of range! Ignoring..." << std::endl;
            }
        }

        if (!valid_core_found) {
            throw std::runtime_error("[ERROR] No valid CPU core selected for thread.");
        }

        int ret = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
        if (ret) {
            throw std::runtime_error("error in pthread_setaffinity_np: " + std::string(std::strerror(ret)));
        }
    }
};

// =================== CyclicRTthread ===================
class CyclicRTthread : public RTthread {
   public:
    CyclicRTthread(int priority, int policy, std::vector<int> cores, int period_ns)
        : RTthread(priority, policy, cores), period_ns_(period_ns) {}

    void changePeriod(int period_new) { period_ns_ = period_new; }

    void run() noexcept override {
        auto nexttime = std::chrono::steady_clock::now();
        while (true) {
            while (nexttime > std::chrono::steady_clock::now()) {
                // Busy-wait loop (not ideal but needed for real-time constraints)
            }

            auto start = std::chrono::steady_clock::now();
            if (loop()) break;

            auto end = std::chrono::steady_clock::now();
            nexttime = start + std::chrono::nanoseconds(period_ns_);

            std::chrono::duration<double, std::nano> elapsed = end - start;
            int sleep_time_ns = period_ns_ - static_cast<int>(elapsed.count()) - 140000;

            if (sleep_time_ns > 0) {
                std::this_thread::sleep_for(std::chrono::nanoseconds(sleep_time_ns));
            }
        }
    }

    virtual bool loop() = 0;

   private:
    int period_ns_;
};

#endif  // RTTHREAD_H