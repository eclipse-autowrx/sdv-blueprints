#!/usr/bin/env python3
# Copyright (c) 2025 Eclipse Foundation.
#
# This program and the accompanying materials are made available under the
# terms of the MIT License which is available at
# https://opensource.org/licenses/MIT.
#
# SPDX-License-Identifier: MIT

"""
KUKSA Hazard Listener - Bridges UDS socket from Simulink to KUKSA

Listens on /tmp/kuksa_hazard_signal.sock for hazard signal from Simulink
and sets Vehicle.Body.Lights.Hazard.IsSignaling in KUKSA
"""

import asyncio
import socket
import os
import sys
import signal

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
        self.socket_path = '/tmp/kuksa_hazard_signal.sock'
        self.client = None
        self._shutdown_event = asyncio.Event()
        # Track last published value so we only call KUKSA on actual changes.
        # Simulink sends the hazard value every model step (many times/sec),
        # but the boolean only changes rarely.
        self._last_hazard = None
        self._pending_value = None        # latest value received from socket
        self._value_changed = asyncio.Event()  # signals the publisher task
    
    async def connect_kuksa(self):
        """Connect to KUKSA"""
        self.client = VSSClient(self.kuksa_address, self.kuksa_port)
        await self.client.connect()
        print(f"[INFO] Connected to KUKSA at {self.kuksa_address}:{self.kuksa_port}")
    
    async def _kuksa_publisher(self):
        """Publish hazard value to KUKSA only when it changes.

        Runs as a separate task so the socket accept loop is never
        blocked by a slow KUKSA gRPC round-trip.
        """
        while not self._shutdown_event.is_set():
            # Wait until a new value arrives or shutdown is requested
            changed = asyncio.create_task(self._value_changed.wait())
            shutdown = asyncio.create_task(self._shutdown_event.wait())
            done, pending = await asyncio.wait(
                {changed, shutdown}, return_when=asyncio.FIRST_COMPLETED
            )
            for t in pending:
                t.cancel()
            if self._shutdown_event.is_set():
                break

            self._value_changed.clear()
            is_hazard = self._pending_value
            if is_hazard == self._last_hazard:
                continue  # no real change, skip KUKSA call

            try:
                await self.client.set_target_values({
                    VSS_HAZARD_SIGNAL: Datapoint(is_hazard)
                })
                self._last_hazard = is_hazard
                print(f"[UPDATE] Set {VSS_HAZARD_SIGNAL} = {is_hazard}")
            except Exception as e:
                print(f"[ERROR] Failed to set hazard signal: {e}")
    
    async def _handle_client(self, conn):
        """Handle client connection — fast read only, no KUKSA call here."""
        loop = asyncio.get_event_loop()
        try:
            data = await asyncio.wait_for(loop.sock_recv(conn, 1024), timeout=0.1)
            if data:
                value = data.decode('utf-8').strip()
                is_hazard = (value.lower() == 'true' or value == '1')
                # Store latest value and wake the publisher (non-blocking)
                self._pending_value = is_hazard
                self._value_changed.set()
        except asyncio.TimeoutError:
            pass
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
        server_sock.listen(64)  # larger backlog for bursty Simulink steps
        server_sock.setblocking(False)
        
        print(f"[INFO] Listening for hazard signals on: {self.socket_path}")
        print()
        
        loop = asyncio.get_event_loop()
        
        try:
            while not self._shutdown_event.is_set():
                try:
                    # Timeout lets us periodically check for shutdown
                    conn, _ = await asyncio.wait_for(
                        loop.sock_accept(server_sock),
                        timeout=0.5
                    )
                    # Fire-and-forget: handle_client only does a fast recv + store
                    asyncio.create_task(self._handle_client(conn))
                except asyncio.TimeoutError:
                    continue
                except asyncio.CancelledError:
                    break
                except Exception as e:
                    if not self._shutdown_event.is_set():
                        print(f"[WARN] Socket accept error: {e}")
                        await asyncio.sleep(0.1)
        finally:
            server_sock.close()
            try:
                os.unlink(self.socket_path)
            except:
                pass
    
    async def start(self):
        """Start the listener"""
        print("=" * 60)
        print("KUKSA Hazard Listener from Simulink")
        print("=" * 60)
        
        # Connect to KUKSA
        await self.connect_kuksa()
        
        # Start KUKSA publisher as a background task
        publisher = asyncio.create_task(self._kuksa_publisher())
        
        try:
            # Listen on socket (blocks until shutdown)
            await self.listen_socket()
        finally:
            publisher.cancel()
            try:
                await publisher
            except asyncio.CancelledError:
                pass
    
    async def stop(self):
        """Stop the listener"""
        self._shutdown_event.set()
        self._value_changed.set()  # wake publisher so it can exit
        
        if self.client:
            try:
                await self.client.disconnect()
            except Exception:
                pass
        
        try:
            os.unlink(self.socket_path)
        except:
            pass


async def main():
    listener = HazardListener()

    async def shutdown():
        print("\n[INFO] Shutting down...")
        await listener.stop()

    loop = asyncio.get_event_loop()
    try:
        # Unix: register signals directly with the event loop so
        # the shutdown coroutine is scheduled properly
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(
                sig, lambda: asyncio.create_task(shutdown())
            )
    except NotImplementedError:
        # Windows: add_signal_handler is not supported, fall back
        # to KeyboardInterrupt which is caught below
        pass

    try:
        await listener.start()
    except asyncio.CancelledError:
        pass
    finally:
        await listener.stop()
        print("[INFO] Shutdown complete")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[INFO] Shutdown complete")
