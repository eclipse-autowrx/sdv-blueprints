import asyncio
import socket
import os
import sys
import argparse
import signal

from kuksa_client.grpc.aio import VSSClient

WIPER_MODE_PATH = "Vehicle.Body.Windshield.Front.Wiping.Mode"
VERBOSE = False
current_wiper_mode = None  # Track current mode globally
shutdown_event = None  # Global shutdown event


def log_verbose(message: str):
    """Print verbose message if verbose mode is enabled."""
    if VERBOSE:
        sys.stderr.write(f"[VERBOSE] {message}\n")


def send_to_clients(connections, message: str):
    """Send a message to all connected clients via Unix Domain Socket."""
    log_verbose(f"Sending to {len(connections)} clients: {message.strip()}")
    disconnected = []
    for conn in connections:
        try:
            conn.sendall(message.encode('utf-8'))
        except Exception as e:
            sys.stderr.write(f"ERROR: Failed to send message to client: {e}\n")
            disconnected.append(conn)
    
    # Remove disconnected clients
    for conn in disconnected:
        connections.remove(conn)
        log_verbose(f"Removed disconnected client. Remaining: {len(connections)}")
        try:
            conn.close()
        except:
            pass


async def subscribe_wiper_mode(connections, host: str = "localhost", port: int = 55555):
    global current_wiper_mode, shutdown_event
    
    log_verbose(f"Connecting to KUKSA at {host}:{port}")
    client = VSSClient(host, port)
    await client.connect()
    log_verbose("Successfully connected to KUKSA")

    send_to_clients(connections, f"Connected to KUKSA at {host}:{port}\n")
    send_to_clients(connections, f"Subscribing to: {WIPER_MODE_PATH}\n")

    try:
        log_verbose(f"Starting subscription to {WIPER_MODE_PATH}")
        async for update in client.subscribe_current_values([WIPER_MODE_PATH]):
            # Check for shutdown signal
            if shutdown_event.is_set():
                log_verbose("Shutdown signal received, stopping subscription")
                break
                
            log_verbose(f"Received update: {update}")
            dp = update.get(WIPER_MODE_PATH)
            if dp is None:
                log_verbose("Update does not contain wiper mode data")
                continue

            new_mode = (
                dp.value
            )  # Expected to be a mode string like 'OFF', 'SLOW', 'MEDIUM', 'FAST', 'INTERVAL', 'RAIN_SENSOR'

            log_verbose(f"New mode: {new_mode}, Current mode: {current_wiper_mode}")
            # Send only on change
            if new_mode != current_wiper_mode:
                current_wiper_mode = new_mode
                send_to_clients(connections, f"Wiper mode changed: {current_wiper_mode}\n")
            else:
                log_verbose("Mode unchanged, skipping notification")

    except asyncio.CancelledError:
        # Graceful shutdown
        log_verbose("Subscription cancelled")
        pass
    finally:
        log_verbose("Closing KUKSA connection")
        await client.close()
        send_to_clients(connections, "Disconnected\n")


async def accept_connections(server_sock, connections):
    """Accept incoming client connections in the background."""
    global current_wiper_mode, shutdown_event
    
    loop = asyncio.get_event_loop()
    log_verbose("Starting to accept connections")
    while not shutdown_event.is_set():
        try:
            log_verbose("Waiting for client connection...")
            # Use run_in_executor to make accept() non-blocking
            conn, _ = await loop.run_in_executor(None, server_sock.accept)
            connections.append(conn)
            sys.stderr.write(f"Client connected. Total clients: {len(connections)}\n")
            
            # Send current state immediately to new client
            if current_wiper_mode is not None:
                try:
                    welcome_msg = f"Current wiper mode: {current_wiper_mode}\n"
                    conn.sendall(welcome_msg.encode('utf-8'))
                    log_verbose(f"Sent current state to new client: {current_wiper_mode}")
                except Exception as e:
                    sys.stderr.write(f"ERROR sending welcome message: {e}\n")
            else:
                log_verbose("No current wiper mode available yet")
                
        except socket.timeout:
            # Timeout is expected, just continue
            log_verbose("Accept timeout (expected), continuing...")
            await asyncio.sleep(0.1)  # Small delay to prevent busy loop
            continue
        except Exception as e:
            log_verbose(f"Accept loop exception: {e}")
            # Don't break on timeout, only on real errors
            if "timed out" not in str(e).lower():
                sys.stderr.write(f"ERROR accepting connection: {e}\n")
                break
            await asyncio.sleep(0.1)


async def main(socket_path):
    """Main async function to run server and KUKSA subscription."""
    global shutdown_event
    
    shutdown_event = asyncio.Event()
    
    log_verbose(f"Starting main with socket path: {socket_path}")
    # Create the Unix Domain Socket server
    server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    # Don't set timeout - let it block until connection arrives
    # server_sock.settimeout(1.0)  # Removed to prevent timeout issues
    
    # Remove the socket file if it already exists
    if os.path.exists(socket_path):
        log_verbose(f"Removing existing socket file: {socket_path}")
        os.remove(socket_path)
    
    try:
        server_sock.bind(socket_path)
        server_sock.listen(5)
        sys.stderr.write(f"Listening on Unix Domain Socket: {socket_path}\n")
        
        # List to track all connected clients
        connections = []
        
        # Start accepting connections in background
        accept_task = asyncio.create_task(accept_connections(server_sock, connections))
        
        # Start KUKSA subscription
        try:
            await subscribe_wiper_mode(connections, "localhost", 55555)
        except KeyboardInterrupt:
            log_verbose("Received KeyboardInterrupt")
            shutdown_event.set()
        finally:
            log_verbose("Shutting down accept task")
            shutdown_event.set()  # Signal shutdown
            accept_task.cancel()
            try:
                await accept_task
            except asyncio.CancelledError:
                pass
            
            # Close all client connections
            log_verbose(f"Closing {len(connections)} client connections")
            for conn in connections:
                try:
                    conn.close()
                except:
                    pass
            
    finally:
        log_verbose("Closing server socket")
        server_sock.close()
        # Clean up the socket file
        if os.path.exists(socket_path):
            log_verbose(f"Removing socket file: {socket_path}")
            os.remove(socket_path)


if __name__ == "__main__":
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='KUKSA Wiper Mode Listener')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose output')
    args = parser.parse_args()
    
    # Set verbose mode
    VERBOSE = args.verbose
    
    # Use socket path in /tmp
    socket_path = "/tmp/wiper_status.sock"
    
    sys.stderr.write(f"Using socket path: {socket_path}\n")
    
    if VERBOSE:
        sys.stderr.write("Verbose mode enabled\n")
    
    try:
        asyncio.run(main(socket_path))
    except KeyboardInterrupt:
        sys.stderr.write("\n[INFO] Received Ctrl+C, shutting down gracefully...\n")
    finally:
        sys.stderr.write("[INFO] Shutdown complete.\n")
