#!/usr/bin/env python3
"""
KUKSA Hazard Listener - Bridges UDS socket from Simulink to KUKSA

Listens on /tmp/kuksa_hazard_signal.sock for hazard signal from Simulink
and sets Vehicle.Body.Lights.Hazard.IsSignaling in KUKSA
"""

import asyncio
import socket
import os
import sys

try:
    from kuksa_client.grpc.aio import VSSClient
    from kuksa_client.grpc import Datapoint
except ImportError:
    print("[ERROR] kuksa_client not found. Install with: pip install kuksa-client")
    sys.exit(1)

VSS_HAZARD_SIGNAL = "Vehicle.Body.Lights.Hazard.IsSignaling"

class HazardListener:
    def __init__(self, kuksa_address="localhost", kuksa_port=55555):
        self.kuksa_address = kuksa_address
        self.kuksa_port = kuksa_port
        self.running = False
        self.socket_path = '/tmp/kuksa_hazard_signal.sock'
        self.client = None
    
    async def connect_kuksa(self):
        """Connect to KUKSA"""
        self.client = VSSClient(self.kuksa_address, self.kuksa_port)
        await self.client.connect()
        print(f"[INFO] Connected to KUKSA at {self.kuksa_address}:{self.kuksa_port}")
    
    async def set_hazard(self, value):
        """Set hazard signal in KUKSA"""
        try:
            is_hazard = (value.lower() == 'true' or value == '1')
            await self.client.set_target_values({
                VSS_HAZARD_SIGNAL: Datapoint(is_hazard)
            })
            print(f"[UPDATE] Set {VSS_HAZARD_SIGNAL} = {is_hazard}")
        except Exception as e:
            print(f"[ERROR] Failed to set hazard signal: {e}")
    
    def _handle_client(self, conn):
        """Handle client connection"""
        try:
            data = conn.recv(1024)
            if data:
                value = data.decode('utf-8').strip()
                # Schedule async task
                asyncio.create_task(self.set_hazard(value))
        except Exception as e:
            print(f"[ERROR] Failed to receive from client: {e}")
        finally:
            try:
                conn.close()
            except:
                pass
    
    async def listen_socket(self):
        """Listen on UDS socket for hazard signals from Simulink"""
        # Remove existing socket
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass
        
        # Create server socket
        server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_sock.bind(self.socket_path)
        server_sock.listen(10)
        server_sock.setblocking(False)
        
        print(f"[INFO] Listening for hazard signals on: {self.socket_path}")
        print()
        
        loop = asyncio.get_event_loop()
        
        try:
            while self.running:
                # Accept connections asynchronously
                try:
                    conn, _ = await loop.sock_accept(server_sock)
                    self._handle_client(conn)
                except Exception as e:
                    if self.running:
                        await asyncio.sleep(0.1)
        finally:
            server_sock.close()
            try:
                os.unlink(self.socket_path)
            except:
                pass
    
    async def start(self):
        """Start the listener"""
        self.running = True
        
        print("=" * 60)
        print("KUKSA Hazard Listener from Simulink")
        print("=" * 60)
        
        # Connect to KUKSA
        await self.connect_kuksa()
        
        # Listen on socket
        await self.listen_socket()
    
    async def stop(self):
        """Stop the listener"""
        self.running = False
        
        if self.client:
            await self.client.disconnect()
        
        try:
            os.unlink(self.socket_path)
        except:
            pass

if __name__ == "__main__":
    import signal
    
    listener = HazardListener()
    
    def signal_handler(sig, frame):
        print("\n[INFO] Shutting down...")
        asyncio.create_task(listener.stop())
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        asyncio.run(listener.start())
    except KeyboardInterrupt:
        pass
    finally:
        print("[INFO] Shutdown complete")
