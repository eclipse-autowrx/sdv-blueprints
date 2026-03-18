import asyncio

from kuksa_client.grpc.aio import VSSClient
from kuksa_client.grpc import Datapoint

WIPER_MODE_PATH = "Vehicle.Body.Windshield.Front.Wiping.Mode"

# Common wiper mode options based on VSS specification
WIPER_MODES = [
    "OFF",
    "SLOW",
    "MEDIUM",
    "FAST",
    "INTERVAL",
    "RAIN_SENSOR"
]


def display_menu():
    """Display the wiper mode selection menu."""
    print("\n" + "="*50)
    print("Wiper Mode Controller")
    print("="*50)
    print("\nAvailable wiper modes:")
    for idx, mode in enumerate(WIPER_MODES, 1):
        print(f"  {idx}. {mode}")
    print("  0. Exit")
    print("="*50)


def get_user_choice() -> str:
    """Prompt user for input and return the selected mode."""
    while True:
        try:
            choice = input("\nEnter your choice (0-{}): ".format(len(WIPER_MODES))).strip()
            choice_num = int(choice)
            
            if choice_num == 0:
                return None  # Exit signal
            elif 1 <= choice_num <= len(WIPER_MODES):
                return WIPER_MODES[choice_num - 1]
            else:
                print(f"❌ Invalid choice. Please enter a number between 0 and {len(WIPER_MODES)}.")
        except ValueError:
            print("❌ Invalid input. Please enter a number.")
        except KeyboardInterrupt:
            print("\n\nExiting...")
            return None


async def set_wiper_mode(mode: str, host: str = "localhost", port: int = 55555):
    """Connect to KUKSA and set the wiper mode."""
    client = VSSClient(host, port)
    
    try:
        await client.connect()
        print(f"✓ Connected to KUKSA at {host}:{port}")
        
        # Set the wiper mode - create a Datapoint with the string value
        datapoint = Datapoint(value=mode)
        await client.set_current_values({WIPER_MODE_PATH: datapoint})
        print(f"✓ Successfully set wiper mode to: {mode}")
        
    except Exception as e:
        print(f"❌ Error setting wiper mode: {e}")
    finally:
        await client.disconnect()


async def main_loop(host: str = "localhost", port: int = 55555):
    """Main interactive loop for setting wiper modes."""
    print(f"\nConnecting to KUKSA server at {host}:{port}...")
    
    while True:
        display_menu()
        selected_mode = get_user_choice()
        
        if selected_mode is None:
            print("\nExiting. Goodbye!")
            break
        
        print(f"\nSetting wiper mode to: {selected_mode}")
        await set_wiper_mode(selected_mode, host, port)


if __name__ == "__main__":
    try:
        asyncio.run(main_loop("localhost", 55555))
    except KeyboardInterrupt:
        print("\n\nInterrupted by user. Exiting...")
