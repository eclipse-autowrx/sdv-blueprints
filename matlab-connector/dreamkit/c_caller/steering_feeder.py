#!/usr/bin/env python3
# Copyright (c) 2025 Eclipse Foundation.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License which is available at
# https://opensource.org/licenses/MIT.
#
# SPDX-License-Identifier: MIT

"""
KUKSA Steering Angle Feeder - Bridges KUKSA steering angle to UDS socket for Simulink

Subscribes to Vehicle.Chassis.SteeringWheel.Angle and publishes to:
  - /tmp/kuksa_steering_angle.sock

Publishes numeric angle value (e.g., "-15.5" or "23.0")
"""

import asyncio
import socket
import os
import sys
import threading

try:
    from kuksa_client.grpc.aio import VSSClient
except ImportError:
    print("[ERROR] kuksa_client not found. Install with: pip install kuksa-client")
    sys.exit(1)

VSS_STEERING_ANGLE = "Vehicle.Chassis.SteeringWheel.Angle"

class SteeringFeeder:
    def __init__(self, kuksa_address="localhost", kuksa_port=55555):
        self.kuksa_address = kuksa_address
        self.kuksa_port = kuksa_port
        self.running = False
        
        self.socket_path = '/tmp/kuksa_steering_angle.sock'
        self.server_sock = None
        
        self.steering_angle = 0.0
        self.lock = threading.Lock()
    
    def _handle_client(self, conn):
        """Send latest steering angle to connected client"""
        try:
            with self.lock:
                value = str(self.steering_angle)
            conn.sendall((value + '\n').encode('utf-8'))
        except Exception as e:
            print(f"[ERROR] Failed to send to client: {e}")
        finally:
            try:
                conn.close()
            except:
                pass
    
    def _accept_connections(self):
        """Accept incoming connections"""
        while self.running:
            try:
                conn, _ = self.server_sock.accept()
                client_thread = threading.Thread(
                    target=self._handle_client,
                    args=(conn,)
                )
                client_thread.daemon = True
                client_thread.start()
            except Exception:
                break
    
    def _create_socket_server(self):
        """Create UDS server"""
        # Remove existing socket
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass
        
        # Create server socket
        self.server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_sock.bind(self.socket_path)
        self.server_sock.listen(10)
        
        print(f"[INFO] Broadcasting steering angle on: {self.socket_path}")
        
        # Start acceptor thread
        acceptor = threading.Thread(target=self._accept_connections)
        acceptor.daemon = True
        acceptor.start()
    
    async def subscribe_steering_angle(self):
        """Subscribe to KUKSA steering angle"""
        client = VSSClient(self.kuksa_address, self.kuksa_port)
        await client.connect()
        print(f"[INFO] Connected to KUKSA at {self.kuksa_address}:{self.kuksa_port}")
        print(f"[INFO] Subscribing to: {VSS_STEERING_ANGLE}")
        
        try:
            async for update in client.subscribe_current_values([VSS_STEERING_ANGLE]):
                if not self.running:
                    break
                
                dp = update.get(VSS_STEERING_ANGLE)
                if dp is None or dp.value is None:
                    continue
                
                # Update steering angle
                angle = float(dp.value)
                with self.lock:
                    self.steering_angle = angle
                
                print(f"[UPDATE] Steering angle: {angle:.1f}°")
                
        except asyncio.CancelledError:
            pass
        finally:
            await client.close()
            print("[INFO] Disconnected from KUKSA")
    
    async def start(self):
        """Start the feeder"""
        self.running = True
        
        print("=" * 60)
        print("KUKSA Steering Angle Feeder for Simulink")
        print("=" * 60)
        
        # Create socket server
        self._create_socket_server()
        print()
        
        # Subscribe to KUKSA
        await self.subscribe_steering_angle()
    
    def stop(self):
        """Stop the feeder"""
        self.running = False
        
        # Close server
        if self.server_sock:
            try:
                self.server_sock.close()
            except:
                pass
        
        # Remove socket
        try:
            os.unlink(self.socket_path)
        except:
            pass

if __name__ == "__main__":
    import signal
    
    feeder = SteeringFeeder()
    
    def signal_handler(sig, frame):
        print("\n[INFO] Shutting down...")
        feeder.stop()
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        asyncio.run(feeder.start())
    except KeyboardInterrupt:
        pass
    finally:
        feeder.stop()
        print("[INFO] Shutdown complete")
