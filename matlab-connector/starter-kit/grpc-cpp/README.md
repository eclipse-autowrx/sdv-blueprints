Here is the complete Markdown code for your `README.md` file. You can copy this entire block and paste it directly into your file:

```markdown
# digital.auto MATLAB Simulink Connector: Smart Wipers

## Use Case
This project bridges MATLAB/Simulink vehicle models with the Eclipse Kuksa.val databroker, specifically targeting the **Matlab Blueprint / Smart Wipers with Starter Kit** prototype on digital.auto playgrounds. It allows Simulink-generated C++ code to run natively on target hardware and communicate in real-time with standardized vehicle signals via gRPC, enabling seamless Software-Defined Vehicle (SDV) prototyping.

## Architecture
* **Logic Layer (Simulink):** Generates standard C++ code from the `.slx` model.
* **Connector Layer (Custom Code):** Utilizes `da_connector.c` and `client.cpp` to interface the Simulink execution step with the gRPC framework.
* **Transport Layer (gRPC/Protobuf):** Communicates with the Kuksa Databroker using standard VSS (Vehicle Signal Specification) protobuf definitions.
* **Dependencies:** Uses pre-compiled, portable Raspberry Pi binaries (`rpi_libs`) linked dynamically via Simulink's `$(START_DIR)` token, ensuring the project builds immediately upon cloning without complex path configuration.

## Getting Started

### Prerequisites
1. **Hardware:** The use case is tested on a **Raspberry Pi 5** running the Legacy OS.
2. **Host Software:** MATLAB (Tested on R2025b) with the **Simulink Support Package for Raspberry Pi Hardware** installed.

### 1. Clone the Repository
Clone this repository to your local host machine. Because the project utilizes relative paths, you can place the cloned folder anywhere on your system.

### 2. Sync Protobuf Headers to the Target (Crucial Step)
MATLAB's automatic file sync mechanism deploys `.cpp` files but often ignores directory structures containing header (`.h`) files. Before building, you must manually sync the `local/protogen` directory to the target Raspberry Pi.

Open a terminal or PowerShell on your host machine and run the following command (replace `<pi_username>`, `<pi_ip_address>`, and `<Path_To_Your_Cloned_Repo>` with your actual details):

```bash
scp -r .\local <pi_username>@<pi_ip_address>:/home/<pi_username>/MATLAB_ws/R2025b/C/<Path_To_Your_Cloned_Repo>/matlab-connector/
```
*(Example: `scp -r .\local mseti@192.168.88.17:/home/mseti/MATLAB_ws/R2025b/C/Users/GXC2KOR/Desktop/check/sdv-blueprints-fork/matlab-connector/`)*

### 3. Build and Deploy
1. Open the Simulink model (`hapticForceCtrlr_hack.slx`) in MATLAB.
2. Navigate to **Hardware** -> **Hardware Settings** and verify the Raspberry Pi IP address and credentials.
3. Click **Build, Deploy & Start**. The build process will automatically link the provided `rpi_libs` and compile the executable on the Pi.

## digital.auto Playgrounds Runtime Setup
To execute the **Smart Wipers with Starter Kit** prototype and enable the physical motor control runtime on the Raspberry Pi, you must run the initialization script on the Pi hardware.

1. Copy the repository contents to the guest folder `$HOME/digital.auto` on the Raspberry Pi.
2. Execute the setup script to initialize the Kuksa databroker and the motor control runtime:
```bash
$HOME/digital.auto/scripts/setup_rpi.sh
```

## Trial build for host machine
If you wish to compile or test the gRPC components locally on a Debian/Ubuntu host machine rather than deploying via Simulink, install the standard development packages:

```bash
sudo apt install -y libgrpc++-dev libprotobuf-dev protobuf-compiler protobuf-compiler-grpc pkg-config
```
```