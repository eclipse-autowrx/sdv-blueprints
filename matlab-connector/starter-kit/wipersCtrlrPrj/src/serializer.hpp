// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

struct CANFrame {
    uint32_t id;       // CAN ID (11-bit or 29-bit)
    uint8_t dlc;       // Data length code (0-8 bytes)
    uint8_t data[8];   // Data payload
};

// transmit data struct
struct ControlData_Tx {
    uint64_t time_stamp;
    float set_torque;
};

struct MotorData_Rx {
    uint64_t time_stamp;
    uint32_t can_frame_id;
    float motor_angle;
    uint16_t can_latency;
    uint16_t eth_latency;
};

void serializeFields(float set_torque, uint8_t *buffer);

bool deserializeFields(int buffersize, const uint8_t *buffer, float* motor_angle);