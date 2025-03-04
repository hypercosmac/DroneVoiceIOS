# droneAI

> *Deploying and tasking a drone is as simple as issuing a voice or text command, and the drone understands the intent and carries it out autonomously.*

This prototype builds upon the original DummyDronie repository, evolving it into a platform for Drones as Natural Language AI Agents.

## Vision

### Natural Language Tasking
Instead of programming flight paths or manually piloting, an operator can simply tell the drone what goal to achieve. For example, "Drone, fly over to the east ridge and survey the area for any sign of wildfire" or "Find the red truck in the parking lot and circle it".

### Human-Machine Collaboration
Drones operate as part of a seamless human-machine team, enhancing safety and productivity in various environments. Rather than replacing humans, these AI drones collaborate with people and other machines to accomplish goals more efficiently.

## Features

- Connect and manage DJI drone devices
- Control the drone using voice commands
- Voice command recognition for takeoff and landing
- Monitor drone's battery percentage, altitude, and distance
- Start and stop video recording
- Virtual joystick controls for manual flight

## Requirements

- Compatible DJI drone (e.g., DJI Phantom, Mavic or Inspire series)
- Compatible iOS device (iOS >=16.2)
- Xcode

## Setup

1. Clone the repository to your local machine.
2. Obtain a DJI Mobile SDK App Key from the [DJI Developer Portal](https://developer.dji.com/user/apps/).
3. Add the App Key to the project's `Info.plist` file, associating it with the `SDK_APP_KEY_INFO_PLIST_KEY` key.
4. Ensure that the application has required permissions in the `Info.plist` file, such as `NSLocationWhenInUseUsageDescription`, `NSBluetoothAlwaysUsageDescription`, and `NSSpeechRecognitionUsageDescription`.
5. Build and run the project on a supported iOS device.

## Usage

1. Turn on your DJI drone and connect your iOS device to the drone's remote controller.
2. Run the app on the iOS device.
3. The app will automatically detect and connect to the drone.
4. Once connected, you can control the drone using voice commands or virtual joysticks.
5. Press and hold the microphone button to issue voice commands like "take off" or "land".

## Contributing

Feel free to contribute to this project by submitting issues or pull requests.

## License

This project is licensed under the MIT License.
