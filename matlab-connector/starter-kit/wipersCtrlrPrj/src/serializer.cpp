// Copyright (c) 2025 Eclipse Foundation.
// 
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

#include <cstring>
#include <stdexcept>
#include <iostream>  // Add this for debugging output
#include <arpa/inet.h>  // For ntohl and network functions

#include "serializer.hpp"

void serializeFields(float set_torque, uint8_t *buffer) {
    // Prepare CAN frame
    CANFrame canFrame;

    std::size_t offset = 0;
    
    // Set CAN ID (0x20)
    canFrame.id = 0x20;
    
    // Set Data Length Code (DLC) = 8
    canFrame.dlc = 8;
    
    // Set the data field (first byte of data after DLC should be packet.set_torque)
    // Assuming set_torque is a float
    std::memcpy(canFrame.data, &set_torque, sizeof(set_torque));
    
    // Copy CAN frame to the buffer
    // Copy CAN ID (4 bytes)
    std::memcpy(buffer + offset, &canFrame.id, sizeof(canFrame.id));
    offset += sizeof(canFrame.id);

    // Copy Data Length Code (DLC) (1 byte)
    std::memcpy(buffer + offset, &canFrame.dlc, sizeof(canFrame.dlc));
    offset += sizeof(canFrame.dlc);

    // Copy data payload (8 bytes)
    std::memcpy(buffer + offset, canFrame.data, sizeof(canFrame.data));
    offset += sizeof(canFrame.data);
}

bool deserializeFields(int buffersize, const uint8_t *buffer, float* motor_angle) {
    // Start at the beginning of the buffer
    std::size_t offset = 0;
    
    // Extract CAN ID (4 bytes)
    uint32_t canId;
    std::memcpy(&canId, buffer + offset, sizeof(canId));

    canId = ntohl(canId);  // Convert from network byte order (big-endian) to host byte order (little-endian)

    offset += sizeof(canId);  // Increment offset after reading CAN ID
  
    // Extract Data Length Code (DLC) (1 byte)
    uint8_t dlc;
    std::memcpy(&dlc, buffer + offset, sizeof(dlc));
    offset += sizeof(dlc);  // Increment offset after reading DLC
    
    // If CAN ID is 0x21, extract the payload
    if (canId == 0x21) {
        // Check if there's enough space for motor_angle in the payload
        if (dlc >= sizeof(*motor_angle)) {
            // Copy the data payload (motor_angle) into the packet's motor_angle field
            std::memcpy(motor_angle, buffer + offset, sizeof(*motor_angle));
            offset += sizeof(*motor_angle);  // Move offset after copying motor_angle
            return true;

          //  std::cout << "deserializeFields called! motor angle:" << packet.motor_angle << std::endl;  // Debug message

        } else {
            // Handle error if DLC is too small to contain the required data (optional)
        }
    }
    return false;
}