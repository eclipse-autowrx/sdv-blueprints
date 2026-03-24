#  Copyright (c) 2025 Eclipse Foundation.
#  
#  This program and the accompanying materials are made available under the
#  terms of the MIT License which is available at
#  https://opensource.org/licenses/MIT.
# 
#  SPDX-License-Identifier: MIT

import socket
import sys
import os
import asyncio
import threading

from kuksa_client.grpc.aio import VSSClient

WIPER_MODE_PATH = "Vehicle.Body.Windshield.Front.Wiping.Mode"

# Global variable to store the latest message
latest_message = "No message yet"
message_lock = threading.Lock()


def handle_client(conn):
    """Send the latest message to a connected client."""
    try:
        with message_lock:
            msg = latest_message
        conn.sendall((msg + '\n').encode('utf-8'))
    except Exception as e:
        print(f"[ERROR] Failed to send to client: {e}")
    finally:
        try:
            conn.close()
        except:
            pass


def accept_connections(server_sock):
    """Accept incoming connections and send them the latest message."""
    while True:
        try:
            conn, _ = server_sock.accept()
            # Handle each client in a separate thread
            client_thread = threading.Thread(target=handle_client, args=(conn,))
            client_thread.daemon = True
            client_thread.start()
        except Exception as e:
            break


async def subscribe_wiper_mode(host: str = "localhost", port: int = 55555):
    """Subscribe to KUKSA wiper mode and update the latest message."""
    global latest_message
    
    client = VSSClient(host, port)
    await client.connect()
    print(f"[INFO] Connected to KUKSA at {host}:{port}")
    print(f"[INFO] Subscribing to: {WIPER_MODE_PATH}")
    
    current_wiper_mode = None
    
    try:
        async for update in client.subscribe_current_values([WIPER_MODE_PATH]):
            dp = update.get(WIPER_MODE_PATH)
            if dp is None:
                continue

            new_mode = dp.value
            
            # Update message only on change
            if new_mode != current_wiper_mode:
                current_wiper_mode = new_mode
                with message_lock:
                    latest_message = str(new_mode)
                print(f"[UPDATE] Wiper mode changed: {new_mode}")
                print(f"[INFO] Broadcasting to UDS listeners")

    except asyncio.CancelledError:
        pass
    finally:
        await client.close()
        print("[INFO] Disconnected from KUKSA")


async def broadcast_server(socket_path: str):
    """
    Create a UDS server that broadcasts KUKSA wiper mode changes.
    Listeners can connect at any time and receive the current message.
    Only the latest message is retained (no queuing).
    """
    
    # Remove socket file if it already exists
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass
    
    # Create the Unix Domain Socket server
    server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    
    try:
        print(f"[INFO] Creating broadcast socket at: {socket_path}")
        server_sock.bind(socket_path)
        server_sock.listen(10)
        print(f"[INFO] Broadcasting on: {socket_path}")
        print("[INFO] Listeners can connect anytime to read the latest wiper mode\n")
        
        # Start connection acceptor thread
        acceptor_thread = threading.Thread(target=accept_connections, args=(server_sock,))
        acceptor_thread.daemon = True
        acceptor_thread.start()
        
        # Subscribe to KUKSA in the main async loop
        await subscribe_wiper_mode("localhost", 55555)
                
    except Exception as e:
        sys.stderr.write(f"ERROR: {e}\n")
        return False
    finally:
        server_sock.close()
        try:
            os.unlink(socket_path)
            print("[INFO] Socket cleaned up")
        except:
            pass
    
    return True


if __name__ == "__main__":
    # Use socket path in /tmp
    socket_path = "/tmp/wiper_status.sock"
    
    print("=" * 60)
    print("UDS Publisher (KUKSA Wiper Mode Broadcaster)")
    print("=" * 60)
    print(f"Socket path: {socket_path}")
    print("Latest message only - no queuing")
    print("Subscribes to KUKSA wiper mode and broadcasts to UDS")
    print("=" * 60)
    print()
    
    try:
        asyncio.run(broadcast_server(socket_path))
    except KeyboardInterrupt:
        print("\n[INFO] Received Ctrl+C, shutting down gracefully...")
    finally:
        print("[INFO] Shutdown complete.")
