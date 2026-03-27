<!--
  Copyright (c) 2025 Eclipse Foundation.

  This program and the accompanying materials are made available under the
  terms of the MIT License which is available at
  https://opensource.org/licenses/MIT.

  SPDX-License-Identifier: MIT
-->

# Dreamkit – Pothole Alert Demo

This folder contains a **playground prototype** that demonstrates how a
MATLAB/Simulink control algorithm can be integrated with digital.auto
components running on a dreamkit target (e.g. NVIDIA Jetson Orin).

---

## Demo Overview

The demo implements a **Pothole Alert** system:

1. A **simulation script** (`simulate_pothole.py`) running on the Jetson
   generates synthetic pothole data and publishes it to
   [Eclipse KUKSA](https://github.com/eclipse-kuksa) via the
   Vehicle Signal Specification (VSS). This simulates the output of a
   real camera-based perception system.
2. A **Logitech steering wheel** connected to the Jetson provides steering
   angle input via scripts that bridge the hardware to KUKSA, making the
   steering data available as VSS signals.
3. Three Python **bridge services** bridge data between KUKSA and the Simulink
   model via Unix Domain Sockets (UDS):
   - `pothole_feeder.py` — subscribes to KUKSA pothole data and exposes it over UDS
   - `steering_feeder.py` — subscribes to KUKSA steering data and exposes it over UDS
   - `hazard_listener.py` — listens for hazard signals on UDS and publishes them back to KUKSA
4. The **Simulink model** (`PotholeAlertModel.slx`) running in External Mode
   reads pothole and steering data from the UDS sockets at each model step,
   evaluates whether the vehicle is steering towards a lane with a detected
   pothole, and outputs a hazard signal if true.
5. The hazard signal from Simulink is then written back to KUKSA via
   `hazard_listener.py`, closing the loop.

---

## Repository Structure

```
dreamkit/
├── README.md                  # This file
├── c_caller/
│   ├── da_connector.h         # C header – function declarations for Simulink C Caller blocks
│   ├── da_connector.c         # C implementation – reads/writes UDS sockets from Simulink
│   ├── pothole_feeder.py      # KUKSA → UDS bridge for pothole zone data (left/right)
│   ├── steering_feeder.py     # KUKSA → UDS bridge for steering wheel angle
│   └── hazard_listener.py     # UDS → KUKSA bridge for hazard signal output from Simulink
└── model/
    ├── PotholeAlertModel.slx  # Simulink model (open in MATLAB to view/edit)
```

### Key Files

| File | Purpose |
|------|---------|
| `c_caller/da_connector.c` | C functions called by Simulink *C Caller* blocks at each model step. Reads pothole/steering data from UDS sockets and writes the hazard signal back. |
| `c_caller/da_connector.h` | Header exposing the C API used by the Simulink model's custom code settings. |
| `c_caller/pothole_feeder.py` | Subscribes to `Vehicle.ADAS.PotholeView` in KUKSA and serves the latest left/right pothole state on two UDS sockets. |
| `c_caller/steering_feeder.py` | Subscribes to `Vehicle.Chassis.SteeringWheel.Angle` in KUKSA and serves the latest angle on a UDS socket. |
| `c_caller/hazard_listener.py` | Listens on a UDS socket for the hazard boolean from Simulink and publishes value changes to `Vehicle.Body.Lights.Hazard.IsSignaling` in KUKSA. Includes change-detection to avoid flooding KUKSA with redundant writes. |
| `model/PotholeAlertModel.slx` | The Simulink model. Uses *C Caller* blocks that invoke functions from `da_connector.c`. Configured for NVIDIA Jetson hardware and Embedded Coder deployment. |

> **Note:** The `PotholeAlert.m` script that was previously used to
> programmatically generate the Simulink model has been removed. The
> canonical model is now `PotholeAlertModel.slx` — open it directly in
> MATLAB/Simulink to view or modify the block diagram.

---

## Prerequisites

### Target Machine (Linux / NVIDIA Jetson)

- Python 3.8+
- [kuksa-client](https://pypi.org/project/kuksa-client/) – `pip install kuksa-client`
- A running [KUKSA Databroker](https://github.com/eclipse-kuksa/kuksa-databroker) instance with custom VSS file
  - Download the custom VSS file from the [Eclipse SDV Playground model](https://playground.digital.auto/model/6875ec635430c81ab197d7bf/api/covesa/Vehicle)

### Host Machine (Windows / MATLAB)

- MATLAB R2023b or later with:
  - Simulink
  - Simulink Coder
  - MATLAB Coder
  - MATLAB Coder Support Package for NVIDIA Jetson and NVIDIA DRIVE Platforms
- SSH access to the target machine

---

## How to Run the Demo

### 1. Start KUKSA Databroker on the Target

Make sure the KUKSA Databroker is running and accessible on port 55555.

### 2. Deploy and Start the Bridge Services

Copy the `c_caller/` folder to the target, then start all three services:

```bash
python3 pothole_feeder.py &
python3 steering_feeder.py &
python3 hazard_listener.py &
```

### 3. Open and Run the Simulink Model

1. Open `model/PotholeAlertModel.slx` in MATLAB/Simulink.
2. Ensure the model's hardware board is set to **NVIDIA Jetson** and the
   target IP matches your device.
3. Build and deploy using **External Mode** to run the model on the target
   while streaming signals back to Simulink for visualization.

### 4. Observe the Results

- The Simulink Data Inspector will show live pothole detection, steering
  angle, and hazard signal traces.
- In KUKSA, `Vehicle.Body.Lights.Hazard.IsSignaling` will toggle based on
  the model's output.

---

## Architecture Notes

### UDS Socket Communication

Each bridge service exposes a Unix Domain Socket. The Simulink-generated
code (via `da_connector.c`) connects to these sockets at every model step
to read inputs and write outputs. The sockets used are:

| Socket Path | Direction | Data |
|---|---|---|
| `/tmp/kuksa_pothole_left.sock` | KUKSA → Simulink | `"true"` / `"false"` |
| `/tmp/kuksa_pothole_right.sock` | KUKSA → Simulink | `"true"` / `"false"` |
| `/tmp/kuksa_steering_angle.sock` | KUKSA → Simulink | Numeric string (e.g. `"-15.5"`) |
| `/tmp/kuksa_hazard_signal.sock` | Simulink → KUKSA | `"true"` / `"false"` |

### Steering Angle Convention

The demo uses the following steering angle convention (based on Logitech
steering wheel input):

- **Positive values:** Vehicle steering wheel turned **right**
- **Negative values:** Vehicle steering wheel turned **left**
- **Zero:** Straight ahead

Example:
- `+25.0°` → steering right by 25 degrees
- `-15.5°` → steering left by 15.5 degrees
- `0.0°` → steering straight

This convention aligns with the VSS standard for
`Vehicle.Chassis.SteeringWheel.Angle`.

---

## Current Work: SDV Runtime Integration

The next evolution of this demo is to replace the KUKSA Databroker and UDS
socket bridge services with a direct integration to the **Eclipse SDV
Runtime**. This aligns with the broader Eclipse SDV strategy and provides a
more robust, scalable, and standardized architecture.

**Status:** In Progress  
**Target:** Integrate MATLAB/Simulink with Eclipse SDV Runtime for Pothole Alert demo

### Target Architecture (Demo v2 – SDV Runtime)

**Detailed architecture diagram:** See [mathwork.drawio](docs/mathwork.drawio) for the complete system design visualization.

### Key References for Integration

-   [MATLAB Coder Support Package for NVIDIA Jetson and NVIDIA DRIVE Platforms](https://www.mathworks.com/help/coder/nvidia.html)
-   [Eclipse SDV Runtime Documentation](https://docs.digital.auto/)
-   [Eclipse SDV Playground Model](https://playground.digital.auto/model/6875ec635430c81ab197d7bf/library/prototype/68edcf3fd327158aa967d7ff/dashboard?search=steeringw)
    -   Model ID: `Runtime-dreamKIT-c028e76a`
-   [Pothole Alert Prototype](https://playground.digital.auto/model/69a686b45ee0670962b69bb2/library/prototype/69c623b738bb8e98f0a9d41d/view)

---

## License

Copyright (c) 2025 Eclipse Foundation.

This program and the accompanying materials are made available under the
terms of the [MIT License](https://opensource.org/licenses/MIT).

SPDX-License-Identifier: MIT
