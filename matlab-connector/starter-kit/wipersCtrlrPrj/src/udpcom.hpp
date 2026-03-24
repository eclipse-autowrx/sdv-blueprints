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

int ini_udp_socket();

void udpsend(int sockfd, const char* address_server, uint16_t port_server, const uint8_t* buffer, int buffersize);

int udpreceive(int sockfd, uint8_t* buffer, int buffersize);
