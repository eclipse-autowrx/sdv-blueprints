// Copyright (c) 2025 Eclipse Foundation.
//
// This program and the accompanying materials are made available under the
// terms of the MIT License which is available at
// https://opensource.org/licenses/MIT.
//
// SPDX-License-Identifier: MIT

#include "da_connector.h"
#include <stdio.h>

#ifdef _WIN32
// Windows stub implementations
double da_get_pothole_left() {
    fprintf(stderr, "ERROR: DA connector not supported on Windows\n");
    return 0.0;
}

double da_get_pothole_center() {
    fprintf(stderr, "ERROR: DA connector not supported on Windows\n");
    return 0.0;
}

double da_get_pothole_right() {
    fprintf(stderr, "ERROR: DA connector not supported on Windows\n");
    return 0.0;
}

double da_get_steering_angle() {
    fprintf(stderr, "ERROR: DA connector not supported on Windows\n");
    return 0.0;
}

void da_set_hazard_signal(bool value) {
    fprintf(stderr, "ERROR: DA connector not supported on Windows\n");
}

#else

#include <time.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>

// Helper function to read from UDS socket with timeout
static int uds_read(const char *socket_path, char *buffer, size_t buffer_size) {
    int sock_fd;
    struct sockaddr_un addr;
    ssize_t bytes_received;
    struct timeval timeout;

    sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock_fd == -1) {
        fprintf(stderr, "Failed to create socket for %s\n", socket_path);
        return -1;
    }

    // Set socket timeout to 100ms (must be fast to not stall model step)
    timeout.tv_sec = 0;
    timeout.tv_usec = 100000;
    if (setsockopt(sock_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
        fprintf(stderr, "Failed to set socket timeout for %s\n", socket_path);
        close(sock_fd);
        return -1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    if (connect(sock_fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        fprintf(stderr, "Failed to connect to socket: %s\n", socket_path);
        close(sock_fd);
        return -1;
    }

    bytes_received = recv(sock_fd, buffer, buffer_size - 1, 0);
    if (bytes_received > 0) {
        buffer[bytes_received] = '\0';
        // Strip trailing newline if present
        if (bytes_received > 0 && buffer[bytes_received - 1] == '\n') {
            buffer[bytes_received - 1] = '\0';
        }
    } else {
        close(sock_fd);
        return -1;
    }

    close(sock_fd);
    return bytes_received;
}

// Helper function to write to UDS socket (non-blocking connect)
static int uds_write(const char *socket_path, const char *message) {
    int sock_fd;
    struct sockaddr_un addr;
    ssize_t bytes_sent;

    sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock_fd == -1) {
        fprintf(stderr, "Failed to create socket for %s\n", socket_path);
        return -1;
    }

    // Set non-blocking to avoid stalling the model step on failed connect
    int flags = fcntl(sock_fd, F_GETFL, 0);
    fcntl(sock_fd, F_SETFL, flags | O_NONBLOCK);

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    if (connect(sock_fd, (struct sockaddr *)&addr, sizeof(addr)) == -1) {
        if (errno != EINPROGRESS) {
            close(sock_fd);
            return -1;
        }
        // Wait briefly (50ms) for connection with select
        fd_set wfds;
        struct timeval tv;
        FD_ZERO(&wfds);
        FD_SET(sock_fd, &wfds);
        tv.tv_sec = 0;
        tv.tv_usec = 50000; // 50ms timeout
        if (select(sock_fd + 1, NULL, &wfds, NULL, &tv) <= 0) {
            close(sock_fd);
            return -1;
        }
    }

    // Restore blocking for send
    fcntl(sock_fd, F_SETFL, flags);

    bytes_sent = send(sock_fd, message, strlen(message), 0);
    close(sock_fd);
    
    return (bytes_sent > 0) ? 0 : -1;
}

// Read pothole detection from left lane (zones 1, 4, 7)
double da_get_pothole_left() {
    char buffer[1024];
    const char *socket_path = "/tmp/kuksa_pothole_left.sock";
    int bytes = uds_read(socket_path, buffer, sizeof(buffer));
    
    if (bytes > 0) {
        fprintf(stderr, "[DEBUG] Left pothole received: '%s'\n", buffer);
        // Parse boolean or numeric value
        if (strcmp(buffer, "true") == 0 || strcmp(buffer, "1") == 0) {
            return 1.0;
        }
    } else {
        fprintf(stderr, "[DEBUG] Left pothole read failed (bytes=%d)\n", bytes);
    }
    return 0.0;
}

// Read pothole detection from center lane (zones 2, 5, 8)
double da_get_pothole_center() {
    char buffer[1024];
    const char *socket_path = "/tmp/kuksa_pothole_center.sock";
    int bytes = uds_read(socket_path, buffer, sizeof(buffer));
    
    if (bytes > 0) {
        fprintf(stderr, "[DEBUG] Center pothole received: '%s'\n", buffer);
        if (strcmp(buffer, "true") == 0 || strcmp(buffer, "1") == 0) {
            return 1.0;
        }
    } else {
        fprintf(stderr, "[DEBUG] Center pothole read failed (bytes=%d)\n", bytes);
    }
    return 0.0;
}

// Read pothole detection from right lane (zones 3, 6, 9)
double da_get_pothole_right() {
    char buffer[1024];
    const char *socket_path = "/tmp/kuksa_pothole_right.sock";
    int bytes = uds_read(socket_path, buffer, sizeof(buffer));
    
    if (bytes > 0) {
        fprintf(stderr, "[DEBUG] Right pothole received: '%s'\n", buffer);
        if (strcmp(buffer, "true") == 0 || strcmp(buffer, "1") == 0) {
            return 1.0;
        }
    } else {
        fprintf(stderr, "[DEBUG] Right pothole read failed (bytes=%d)\n", bytes);
    }
    return 0.0;
}

// Read steering wheel angle
double da_get_steering_angle() {
    char buffer[1024];
    const char *socket_path = "/tmp/kuksa_steering_angle.sock";
    int bytes = uds_read(socket_path, buffer, sizeof(buffer));
    
    if (bytes > 0) {
        double angle = atof(buffer);
        fprintf(stderr, "[DEBUG] Steering angle received: '%s' (%.2f degrees)\n", buffer, angle);
        return angle;
    } else {
        fprintf(stderr, "[DEBUG] Steering angle read failed (bytes=%d)\n", bytes);
    }
    return 0.0;
}

// Write hazard signal status
void da_set_hazard_signal(bool value) {
    const char *socket_path = "/tmp/kuksa_hazard_signal.sock";
    char message[64];
    
    // Convert to boolean string
    snprintf(message, sizeof(message), "%s", value ? "true" : "false");
    
    int result = uds_write(socket_path, message);
    if (result == 0) {
        fprintf(stderr, "[DEBUG] Hazard signal sent: '%s'\n", message);
    } else {
        fprintf(stderr, "[DEBUG] Failed to send hazard signal\n");
    }
}

#endif // _WIN32
