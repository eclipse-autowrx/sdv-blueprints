<!--
  Copyright (c) 2025 Eclipse Foundation.

  This program and the accompanying materials are made available under the
  terms of the MIT License which is available at
  https://opensource.org/licenses/MIT.

  SPDX-License-Identifier: MIT
-->

# Dreamkit – Pothole Alert Demo

This folder contains a **playground prototype** that demonstrates how a
MATLAB/Simulink control algorithm can be integrated with Eclipse SDV
components running on an embedded Linux target (e.g. NVIDIA Jetson Orin).

> **Note:** The dreamkit folder is the designated area for experimental and
> prototype work. Anything new that is still under active development or
> exploration should go here before being promoted into a more stable
> location.

---

## Demo Overview

The demo implements a **Pothole Alert** system:

1. A camera-based pothole detection pipeline publishes pothole zone data to
   [Eclipse KUKSA](https://github.com/eclipse-kuksa) via the
   Vehicle Signal Specification (VSS).
2. Steering wheel angle is also available in KUKSA.
3. Three Python **bridge services** subscribe to KUKSA and expose the data
   over Unix Domain Sockets (UDS) so that a Simulink model running in
   External Mode can read them at each model step.
4. The **Simulink model** (`PotholeAlertModel.slx`) evaluates whether the
   vehicle is steering towards a lane that has a detected pothole and, if
   so, asserts a hazard signal.
5. A fourth Python service picks up the hazard signal from Simulink and
   writes it back to KUKSA, closing the loop.

### Data Flow

```
KUKSA (VSS)                   Simulink (External Mode)
┌──────────┐   subscribe      ┌──────────────────────┐
│ Pothole  ├──────────────►   │                      │
│ View     │  pothole_feeder  │  PotholeAlertModel   │
├──────────┤                  │                      │
│ Steering ├──────────────►   │  Logic:              │
│ Angle    │ steering_feeder  │   steer_towards_lane │
└──────────┘       (UDS)      │     AND pothole_in   │
                              │       => hazard ON   │
┌──────────┐   set_target     │                      │
│ Hazard   │◄──────────────   │                      │
│ Signaling│ hazard_listener  └──────────────────────┘
└──────────┘       (UDS)
```

---

## Repository Structure

```
dreamkit/
├── README.md                  # This file
├── c_caller/
│   ├── da_connector.h         # C header – function declarations for Simulink C Caller blocks
│   ├── da_connector.c         # C implementation – reads/writes UDS sockets from Simulink
│   ├── pothole_feeder.py      # KUKSA → UDS bridge for pothole zone data (left/center/right)
│   ├── steering_feeder.py     # KUKSA → UDS bridge for steering wheel angle
│   └── hazard_listener.py     # UDS → KUKSA bridge for hazard signal output from Simulink
└── model/
    ├── PotholeAlertModel.slx  # Simulink model (open in MATLAB to view/edit)
    └── PotholeAlertModel_ert_rtw/  # Auto-generated C code from Embedded Coder (do not edit manually)
```

### Key Files

| File | Purpose |
|------|---------|
| `c_caller/da_connector.c` | C functions called by Simulink *C Caller* blocks at each model step. Reads pothole/steering data from UDS sockets and writes the hazard signal back. |
| `c_caller/da_connector.h` | Header exposing the C API used by the Simulink model's custom code settings. |
| `c_caller/pothole_feeder.py` | Subscribes to `Vehicle.ADAS.PotholeView` in KUKSA and serves the latest left/center/right pothole state on three UDS sockets. |
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
- A running [KUKSA Databroker](https://github.com/eclipse-kuksa/kuksa-databroker) instance (default port 55555)

### Host Machine (Windows / MATLAB)

- MATLAB R2023b or later with:
  - Simulink
  - Embedded Coder
  - Simulink Coder
  - MATLAB Coder
  - NVIDIA Jetson hardware support package
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
| `/tmp/kuksa_pothole_center.sock` | KUKSA → Simulink | `"true"` / `"false"` |
| `/tmp/kuksa_pothole_right.sock` | KUKSA → Simulink | `"true"` / `"false"` |
| `/tmp/kuksa_steering_angle.sock` | KUKSA → Simulink | Numeric string (e.g. `"-15.5"`) |
| `/tmp/kuksa_hazard_signal.sock` | Simulink → KUKSA | `"true"` / `"false"` |

### Performance Considerations

The hazard listener uses a **change-detection** pattern: although Simulink
sends the hazard value at every model step (potentially 50–100 Hz), the
listener only forwards it to KUKSA when the boolean actually changes. This
prevents the gRPC round-trip from blocking the socket accept loop and
stalling the Simulink model step, which would cause XCP External Mode
timeouts.

---

## License

Copyright (c) 2025 Eclipse Foundation.

This program and the accompanying materials are made available under the
terms of the [MIT License](https://opensource.org/licenses/MIT).

SPDX-License-Identifier: MIT
