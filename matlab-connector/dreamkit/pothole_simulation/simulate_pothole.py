#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Pothole Detection Simulator for KUKSA VSS

Simulates a car driving at ~50 km/h encountering potholes on left and right lanes.
Pattern:
  - Left lane:  Zone 1 (far) -> Zone 4 (middle) -> Zone 7 (near) -> clear
  - Right lane: Zone 3 (far) -> Zone 6 (middle) -> Zone 9 (near) -> clear

Zone Layout:
  +------+-----+------+
  | 1    | 2   | 3    |  <- FAR (row 0)
  +------+-----+------+
  | 4    | 5   | 6    |  <- MIDDLE (row 1)
  +------+-----+------+
  | 7    | 8   | 9    |  <- NEAR (row 2)
  +------+-----+------+
         [Car]

Usage:
  python3 simulate_pothole.py [--kuksa-address 127.0.0.1] [--kuksa-port 55555]
                               [--speed 50] [--interval 2.0] [--loops 0]
"""

import argparse
import logging
import signal
import sys
import threading
import time

try:
    from kuksa_client.grpc import VSSClient
    from kuksa_client.grpc import Datapoint
except ImportError:
    print("[ERROR] kuksa_client not found. Install with: pip install kuksa-client")
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("PotholeSim")

# VSS signal paths
VSS_POTHOLE_VIEW = "Vehicle.ADAS.PotholeView"
VSS_VEHICLE_SPEED = "Vehicle.Speed"
VSS_IGNITION_ON = "Vehicle.Powertrain.IsIgnitionOn"
VSS_ENGINE_SPEED = "Vehicle.Powertrain.CombustionEngine.Speed"

# Default zone state (all clear)
ZONES_CLEAR = {'1': False, '2': False, '3': False,
               '4': False, '5': False, '6': False,
               '7': False, '8': False, '9': False}


def build_pothole_string(active_zones: list) -> str:
    """
    Build PotholeView string value.

    Args:
        active_zones: List of zone IDs (1-9) that have potholes detected.

    Returns:
        String like "{'1': false, '2': false, '3': true, ...}"
    """
    zones = dict(ZONES_CLEAR)
    for z in active_zones:
        zones[str(z)] = True
    # Format to match the expected VSS string format
    parts = []
    for k in sorted(zones.keys(), key=int):
        val = 'true' if zones[k] else 'false'
        parts.append(f"'{k}': {val}")
    return "{" + ", ".join(parts) + "}"


def set_pothole_view(client: VSSClient, active_zones: list):
    """Set PotholeView VSS signal with given active zones.
    Always sends the value to KUKSA, even for clear (all false).
    """
    pothole_str = build_pothole_string(active_zones)
    # Always send to KUKSA - even for clear state
    client.set_current_values({
        VSS_POTHOLE_VIEW: Datapoint(pothole_str)
    })
    if active_zones:
        logger.info(f"PotholeView set -> zones {active_zones} active | {pothole_str}")
    else:
        # Verify the clear was actually written by reading it back
        try:
            readback = client.get_current_values([VSS_POTHOLE_VIEW])
            for path, dp in readback.items():
                logger.info(f"PotholeView CLEAR sent & verified -> {dp.value}")
        except Exception:
            logger.info(f"PotholeView CLEAR sent -> {pothole_str}")


def set_vehicle_speed(client: VSSClient, speed: float):
    """Set vehicle speed VSS signal."""
    client.set_current_values({
        VSS_VEHICLE_SPEED: Datapoint(speed)
    })
    logger.info(f"Vehicle.Speed set -> {speed} km/h")


def setup_vehicle_signals(client: VSSClient, speed: float, engine_rpm: float = 1500.0):
    """Set initial vehicle signals: ignition, engine RPM, speed."""
    client.set_current_values({
        VSS_IGNITION_ON: Datapoint(True),
        VSS_ENGINE_SPEED: Datapoint(engine_rpm),
        VSS_VEHICLE_SPEED: Datapoint(speed),
    })
    logger.info(f"Vehicle signals set -> Ignition=ON, EngineRPM={engine_rpm}, Speed={speed} km/h")


def run_simulation(client: VSSClient, speed: float, interval: float, loops: int,
                   stop_event: threading.Event):
    """
    Run the pothole simulation loop.

    Sequence per loop:
      1. LEFT lane approach:  Zone 1 -> Zone 4 -> Zone 7 -> Clear (all zones false)
      2. RIGHT lane approach: Zone 3 -> Zone 6 -> Zone 9 -> Clear (all zones false)

    Args:
        client: Connected KUKSA VSSClient
        speed: Vehicle speed in km/h
        interval: Time in seconds between each zone step
        loops: Number of loops (0 = infinite)
        stop_event: Threading event to signal stop (for Ctrl+C)
    """
    # Left lane sequence: pothole approaching from far to near
    left_sequence = [
        ([1],       "LEFT lane - FAR (zone 1)"),
        ([4],       "LEFT lane - MIDDLE (zone 4)"),
        ([7],       "LEFT lane - NEAR only (zone 7)"),
        # ([],        "LEFT lane - CLEAR (all zones false)"),
    ]

    # Right lane sequence: pothole approaching from far to near
    right_sequence = [
        ([3],       "RIGHT lane - FAR (zone 3)"),
        ([6],       "RIGHT lane - MIDDLE (zone 6)"),
        ([9],       "RIGHT lane - NEAR only (zone 9)"),
        # ([],        "RIGHT lane - CLEAR (all zones false)"),
    ]

    # Set vehicle signals (ignition, RPM, speed)
    setup_vehicle_signals(client, speed)

    loop_count = 0
    while not stop_event.is_set() and (loops == 0 or loop_count < loops):
        loop_count += 1
        logger.info(f"=== Loop {loop_count} {'(infinite)' if loops == 0 else f'of {loops}'} ===")

        # --- Left lane pothole approach ---
        logger.info("--- LEFT lane pothole approaching ---")
        for zones, description in left_sequence:
            if stop_event.is_set():
                break
            set_pothole_view(client, zones)
            logger.info(f"  {description}")
            if stop_event.wait(interval):  # Returns True if event is set (stop)
                break

        if stop_event.is_set():
            break

        # Brief pause between sequences
        if stop_event.wait(interval):
            break

        # --- Right lane pothole approach ---
        logger.info("--- RIGHT lane pothole approaching ---")
        for zones, description in right_sequence:
            if stop_event.is_set():
                break
            set_pothole_view(client, zones)
            logger.info(f"  {description}")
            if stop_event.wait(interval):
                break

        if stop_event.is_set():
            break

        # Pause before next loop
        if stop_event.wait(interval):
            break

    if stop_event.is_set():
        logger.info("Simulation stopped by user.")
    else:
        logger.info("Simulation complete.")


def main():
    parser = argparse.ArgumentParser(
        description='Pothole Detection Simulator - simulates potholes on left and right lanes'
    )
    parser.add_argument('--kuksa-address', default='127.0.0.1',
                        help='KUKSA databroker address (default: 127.0.0.1)')
    parser.add_argument('--kuksa-port', type=int, default=55555,
                        help='KUKSA databroker port (default: 55555)')
    parser.add_argument('--speed', type=float, default=50.0,
                        help='Simulated vehicle speed in km/h (default: 50)')
    parser.add_argument('--interval', type=float, default=1.0,
                        help='Time between zone transitions in seconds (default: 1.0)')
    parser.add_argument('--loops', type=int, default=0,
                        help='Number of simulation loops, 0=infinite (default: 0)')
    parser.add_argument('--debug', action='store_true',
                        help='Enable debug logging')

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    # Graceful shutdown via threading.Event (interruptible sleep)
    stop_event = threading.Event()

    def signal_handler(sig, frame):
        logger.info("Shutdown signal received, stopping...")
        stop_event.set()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Connect to KUKSA
    logger.info(f"Connecting to KUKSA at {args.kuksa_address}:{args.kuksa_port}...")
    try:
        client = VSSClient(args.kuksa_address, args.kuksa_port)
        client.connect()
        logger.info("Connected to KUKSA databroker")
    except Exception as e:
        logger.error(f"Failed to connect to KUKSA: {e}")
        sys.exit(1)

    try:
        run_simulation(client, args.speed, args.interval, args.loops, stop_event)
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        # Clear pothole view on exit
        try:
            set_pothole_view(client, [])
            logger.info("Cleared PotholeView on exit")
        except Exception:
            pass
        client.disconnect()
        logger.info("Disconnected from KUKSA")

    return 0


if __name__ == '__main__':
    sys.exit(main())
