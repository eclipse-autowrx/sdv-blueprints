#include "da_connector.h"
#include <stdio.h>

#ifdef _WIN32
// Windows-specific includes and dummy implementation
double da_connector()
{
  fprintf(stderr, "ERROR: da_connector() is not supported on Windows\n");
  return 0.0;
}
#else

#include <time.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

// Static buffer to track the last logged message
static char last_message[256] = "";

void log_message(const char *message)
{
  // Skip if this exact message was already logged
  if (strcmp(last_message, message) == 0)
  {
    return;
  }

  // Write directly to /tmp without creating subdirectories
  const char *file_path = "/tmp/mathworks.log";

  // Open file for writing
  FILE *log_file = fopen(file_path, "a");
  if (log_file == NULL)
  {
    fprintf(stderr, "Failed to open log file: %s\n", file_path);
    return;
  }

  // Get current timestamp
  time_t now = time(NULL);
  struct tm *tm_info = localtime(&now);
  char timestamp[64];
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);

  // Write message with timestamp
  fprintf(log_file, "[%s] %s\n", timestamp, message);

  // Close the file
  fclose(log_file);

  // Save this message as the last logged message
  strncpy(last_message, message, sizeof(last_message) - 1);
  last_message[sizeof(last_message) - 1] = '\0';
}

int uds_listen(char *buffer, size_t buffer_size)
{
  int sock_fd;
  struct sockaddr_un addr;
  ssize_t bytes_received;
  const char *socket_path = "/tmp/wiper_status.sock";

  // Create socket file descriptor (client endpoint)
  sock_fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (sock_fd == -1)
  {
    fprintf(stderr, "Failed to create socket file descriptor\n");
    return -1;
  }

  // Setup socket address
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

  // Connect to the socket
  if (connect(sock_fd, (struct sockaddr *)&addr, sizeof(addr)) == -1)
  {
    fprintf(stderr, "Failed to connect to socket: %s\n", socket_path);
    close(sock_fd);
    return -1;
  }

  // Read the message (one-shot read)
  bytes_received = recv(sock_fd, buffer, buffer_size - 1, 0);
  if (bytes_received > 0)
  {
    buffer[bytes_received] = '\0'; // Null-terminate the string

    // Remove trailing newline if present
    if (bytes_received > 0 && buffer[bytes_received - 1] == '\n')
    {
      buffer[bytes_received - 1] = '\0';
    }
  }
  else if (bytes_received == 0)
  {
    fprintf(stderr, "No data received from socket\n");
    close(sock_fd);
    return 0;
  }
  else
  {
    fprintf(stderr, "Error receiving data from socket\n");
    close(sock_fd);
    return -1;
  }

  // Close the socket
  close(sock_fd);

  return bytes_received;
}

double da_connector()
{
  char buffer[1024];
  int result = uds_listen(buffer, sizeof(buffer));

  if (result > 0)
  {
    log_message(buffer);

    // Map wiper mode to return value
    if (strcmp(buffer, "OFF") == 0)
    {
      return 0;
    }
    else if (strcmp(buffer, "SLOW") == 0)
    {
      return 500;
    }
    else if (strcmp(buffer, "MEDIUM") == 0)
    {
      return 750;
    }
    else if (strcmp(buffer, "FAST") == 0)
    {
      return 1000;
    }
  }

  // Default return if no valid mode received
  return 0;
}

#endif // win
