import socket
import sys
import os


def get_current_state(socket_path: str, timeout: float = 2.0):
    """Connect to UDS, read current state, and exit."""
    
    # Create the Unix Domain Socket client
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    
    try:
        print(f"Connecting to Unix Domain Socket: {socket_path}")
        sock.connect(socket_path)
        print(f"Connection established")
        
        # Read the first message (current state)
        data = sock.recv(1024)
        if data:
            message = data.decode('utf-8')
            print(f"{message}", end='')
            
            # Extract just the mode if it's in the expected format
            if "Current wiper mode:" in message:
                mode = message.split("Current wiper mode:")[-1].strip()
                print(f"\nMode: {mode}")
        else:
            print("No data received")
            
    except socket.timeout:
        sys.stderr.write("ERROR: Timeout connecting to server\n")
    except FileNotFoundError:
        sys.stderr.write(f"ERROR: Socket not found at {socket_path}\n")
        sys.stderr.write("Make sure wiper_listener.py is running\n")
    except Exception as e:
        sys.stderr.write(f"ERROR: {e}\n")
    finally:
        sock.close()
        print("\nDisconnected")


if __name__ == "__main__":
    # Use socket path in /tmp
    socket_path = "/tmp/wiper_status.sock"
    
    print(f"Using socket path: {socket_path}")
    
    get_current_state(socket_path)
