#!/usr/bin/env python3
"""
KUKSA Pothole Feeder - Bridges KUKSA PotholeView to UDS sockets for Simulink

Subscribes to Vehicle.ADAS.PotholeView and publishes to separate UDS sockets:
  - /tmp/kuksa_pothole_left.sock   (zones 1, 4, 7)
  - /tmp/kuksa_pothole_center.sock (zones 2, 5, 8)
  - /tmp/kuksa_pothole_right.sock  (zones 3, 6, 9)

Each socket publishes "true" or "false" based on pothole detection.
"""

import asyncio
import socket
import os
import sys
import threading
import ast

try:
    from kuksa_client.grpc.aio import VSSClient
except ImportError:
    print("[ERROR] kuksa_client not found. Install with: pip install kuksa-client")
    sys.exit(1)

VSS_POTHOLE_VIEW = "Vehicle.ADAS.PotholeView"

LEFT_LANE_ZONES = ['1', '4', '7']
CENTER_LANE_ZONES = ['2', '5', '8']
RIGHT_LANE_ZONES = ['3', '6', '9']

class PotholeFeeder:
    def __init__(self, kuksa_address="localhost", kuksa_port=55555):
        self.kuksa_address = kuksa_address
        self.kuksa_port = kuksa_port
        self.running = False
        
        # Socket paths
        self.sockets = {
            'left': '/tmp/kuksa_pothole_left.sock',
            'center': '/tmp/kuksa_pothole_center.sock',
            'right': '/tmp/kuksa_pothole_right.sock'
        }
        
        # Server sockets
        self.servers = {}
        
        # Latest values
        self.values = {
            'left': False,
            'center': False,
            'right': False
        }
        self.lock = threading.Lock()
    
    def _parse_pothole_view(self, value_str):
        """Parse PotholeView string to dict"""
        if not value_str or value_str == 'None':
            return {}
        try:
            normalized = value_str.replace('true', 'True').replace('false', 'False')
            parsed = ast.literal_eval(normalized)
            return {str(k): bool(v) for k, v in parsed.items()}
        except Exception as e:
            print(f"[WARNING] Failed to parse PotholeView: {e}")
            return {}
    
    def _lane_has_pothole(self, zones, pothole_dict):
        """Check if any zone in lane has pothole"""
        return any(pothole_dict.get(z, False) for z in zones)
    
    def _handle_client(self, conn, lane):
        """Send latest value to connected client"""
        try:
            with self.lock:
                value = "true" if self.values[lane] else "false"
            conn.sendall((value + '\n').encode('utf-8'))
        except Exception as e:
            print(f"[ERROR] Failed to send to client ({lane}): {e}")
        finally:
            try:
                conn.close()
            except:
                pass
    
    def _accept_connections(self, server_sock, lane):
        """Accept incoming connections for a lane"""
        while self.running:
            try:
                conn, _ = server_sock.accept()
                client_thread = threading.Thread(
                    target=self._handle_client,
                    args=(conn, lane)
                )
                client_thread.daemon = True
                client_thread.start()
            except Exception:
                break
    
    def _create_socket_server(self, lane):
        """Create UDS server for a lane"""
        socket_path = self.sockets[lane]
        
        # Remove existing socket
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass
        
        # Create server socket
        server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_sock.bind(socket_path)
        server_sock.listen(10)
        
        print(f"[INFO] Broadcasting {lane} lane on: {socket_path}")
        
        # Start acceptor thread
        acceptor = threading.Thread(
            target=self._accept_connections,
            args=(server_sock, lane)
        )
        acceptor.daemon = True
        acceptor.start()
        
        return server_sock
    
    async def subscribe_pothole_view(self):
        """Subscribe to KUKSA PotholeView"""
        client = VSSClient(self.kuksa_address, self.kuksa_port)
        await client.connect()
        print(f"[INFO] Connected to KUKSA at {self.kuksa_address}:{self.kuksa_port}")
        print(f"[INFO] Subscribing to: {VSS_POTHOLE_VIEW}")
        
        try:
            async for update in client.subscribe_current_values([VSS_POTHOLE_VIEW]):
                if not self.running:
                    break
                
                dp = update.get(VSS_POTHOLE_VIEW)
                if dp is None or dp.value is None:
                    continue
                
                # Parse pothole view
                pothole_dict = self._parse_pothole_view(str(dp.value))
                
                # Update lane values
                with self.lock:
                    self.values['left'] = self._lane_has_pothole(LEFT_LANE_ZONES, pothole_dict)
                    self.values['center'] = self._lane_has_pothole(CENTER_LANE_ZONES, pothole_dict)
                    self.values['right'] = self._lane_has_pothole(RIGHT_LANE_ZONES, pothole_dict)
                
                # Log changes
                active_lanes = [k for k, v in self.values.items() if v]
                if active_lanes:
                    print(f"[UPDATE] Pothole detected in lanes: {active_lanes}")
                
        except asyncio.CancelledError:
            pass
        finally:
            await client.close()
            print("[INFO] Disconnected from KUKSA")
    
    async def start(self):
        """Start the feeder"""
        self.running = True
        
        print("=" * 60)
        print("KUKSA Pothole Feeder for Simulink")
        print("=" * 60)
        
        # Create socket servers
        for lane in ['left', 'center', 'right']:
            self.servers[lane] = self._create_socket_server(lane)
        
        print()
        
        # Subscribe to KUKSA
        await self.subscribe_pothole_view()
    
    def stop(self):
        """Stop the feeder"""
        self.running = False
        
        # Close servers
        for server_sock in self.servers.values():
            try:
                server_sock.close()
            except:
                pass
        
        # Remove sockets
        for socket_path in self.sockets.values():
            try:
                os.unlink(socket_path)
            except:
                pass

if __name__ == "__main__":
    import signal
    
    feeder = PotholeFeeder()
    
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
