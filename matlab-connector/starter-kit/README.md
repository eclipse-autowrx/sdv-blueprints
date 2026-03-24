# digital.auto MATLAB Simulink Connector: Smart Wipers

## Use Case
This project bridges MATLAB/Simulink vehicle models with digital.auto playground, specifically targeting the **Smart Wipers with digital.auto Starter Kit** prototype. It allows Simulink-generated C++ code to run natively on target hardware and communicate live with standardized vehicle signals via digital.auto, enabling seamless Software-Defined Vehicle (SDV) prototyping.

## Architecture
* **Logic Layer (Simulink):** Generates standard C++ code from the `.slx` model.
* **Connector Layer (Custom Code):** Utilizes `da_connector` to interface the Simulink execution step with the digital.auto framework.
* **Runtime:** On the hardware runs `sdv-runtime` which takes the vehicle signals coming from digital.auto playground and feeds to the matlab generated code to collectively control the wiper motor operation.

## Getting Started

### Prerequisites
1. **Hardware:** The use case is tested on the E/E starter KIT hardware detailed [here](https://github.com/eclipse-autowrx/SDV4EE-demo).
2. **Host Software:** digital.auto playground and MATLAB (Tested on R2025a).

### Clone the Repository
Clone this repository to your local host machine. 

### digital.auto Playgrounds Runtime Setup
To execute the **Smart Wipers with Starter Kit** prototype and enable the physical motor control, you must run the initialization script on the Pi hardware.

1. Copy the repository contents to the guest folder `$HOME/digital.auto` on the Raspberry Pi.
2. Execute the setup script to initialize the Kuksa databroker and the motor control runtime: `$HOME/digital.auto/scripts/setup_rpi.sh`

### Build and Deploy
1. Open the project (`wipersCtrlr.prj`) in MATLAB.
1. Open the simulink model (`models\hapticForceCtrlr.slx`)
1. Click **Monitor & Tune**. The build process will compile the executable for the Pi. Then transfer and execute on target.
1. Launch the digital.auto prototype from this [link](https://playground.digital.auto/model/69a686b45ee0670962b69bb2)
1. Add/select the runtime and click the `RUN` button.

## Demo
![Smart Wipers Demo](images/smart_wipers.gif)
