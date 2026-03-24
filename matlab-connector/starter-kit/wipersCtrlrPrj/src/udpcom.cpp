/**
 * Copyright (c) 2025 Robert Bosch GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the MIT License which is available at
 * https://opensource.org/licenses/MIT.
 *
 * SPDX-License-Identifier: MIT
 */

#include <bits/stdc++.h> 
#include <stdlib.h> 
#include <unistd.h> 
#include <sys/types.h> 
#include <sys/socket.h> 
#include <arpa/inet.h> 
#include <netinet/in.h>
#include <iostream>
#include <fcntl.h>

#include "udpcom.hpp"

int ini_udp_socket() {
	int sockfd;
    
	if ( (sockfd = socket(AF_INET, SOCK_DGRAM, 0)) < 0 ) { 
			std::cout << "[DEBUG] UDP socket creation failed" << std::endl; 
	}
	else {
			fcntl(sockfd, F_SETFL, O_NONBLOCK);
			std::cout << "[DEBUG] UDP socket successfully initialized: " << sockfd << std::endl;
	}
	return sockfd;
}

void udpsend(int sockfd, const char* address_server, uint16_t port_server, const uint8_t* buffer, int buffersize) {
	if (sockfd >= 0) {
		struct sockaddr_in address;
		address.sin_family = AF_INET;
		address.sin_port = htons(port_server);
		address.sin_addr.s_addr = inet_addr(address_server);
		sendto(sockfd, buffer, buffersize, 0, reinterpret_cast<sockaddr*>(&address), sizeof(address));
	}
}

#define UDPRECVBUFFERSIZE 128

int udpreceive(int sockfd, uint8_t* buffer, int buffersize) {
	int len_data = 0;
    static uint8_t recvBuffer[UDPRECVBUFFERSIZE];

	if (sockfd >= 0) {
		len_data = recv(sockfd, recvBuffer, UDPRECVBUFFERSIZE, 0);
        if (len_data>0){
            len_data = len_data < buffersize ? len_data : buffersize;
            std:memcpy(buffer, recvBuffer, len_data);
        }
	}
	return len_data;
}