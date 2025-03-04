//
//  FlightController.swift
//  DummyDronie
//
//  Created by Yeralin, Daniyar on 4/9/23.
//

import Foundation
import DJISDK

/// FlightController class to manage flight control state and to send virtual stick commands
class FlightController: NSObject, ObservableObject, DJIBatteryDelegate, DJIFlightControllerDelegate {
    
    /// Declared properties for batteryPercentage, altitude and distance
    @Published private(set) var batteryPercentage: Int = 0
    @Published private(set) var altitude: Double = 0
    @Published private(set) var distance: Double = 0
    // Timer used to continuously send virtual sticks command for the vertical takeoff
    @Published private(set) var verticalTakeoffJob: Timer?
    
    /// Setup  the delegates upon drone connection
    func setupDelegates(retry: Int = 5, delay: Double = 5) {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard retry > 0 else {
                    log.error("Failed to setup delegates after multiple attempts")
                    return
                }
                self.setupDelegates(retry: retry - 1)
            }
            return
        }
        // Set up battery and flightController delegates
        aircraft.battery?.delegate = self
        aircraft.flightController?.delegate = self
        log.info("Successfully set flight controller delegates")
    }
    
    /// Prepares the drone for vertical takeoff
    func startVerticalTakeoff() {
        self.enableAircraftVirtualSticksMode() {
            guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
                log.error("Aircraft is not found")
                return
            }
            if aircraft.flightController?.isVirtualStickAdvancedModeEnabled == false {
                log.error("Cannot start vertical takeoff while virtual sticks are disabled")
                return
            }
            aircraft.flightController?.rollPitchCoordinateSystem = .body
            aircraft.flightController?.rollPitchControlMode = .velocity
            aircraft.flightController?.verticalControlMode = .velocity
            aircraft.flightController?.yawControlMode = .angularVelocity
            self.verticalTakeoffJob = Timer.scheduledTimer(timeInterval: 0.05, target: self, selector: #selector(self.verticalTakeoff), userInfo: nil, repeats: true)
        }
    }
    
    /// Sends the virtual stick command to start vertical takeoff
    @objc func verticalTakeoff() {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            self.stopVerticalTakeoff()
            return
        }
        var controlData = DJIVirtualStickFlightControlData()
        // negation (-) required because the drone is moving backwards
        controlData.roll = -Float(Settings.loadSetting(.rollVelocityKey))
        controlData.verticalThrottle = Float(Settings.loadSetting(.throttleVelocityKey))
        
        aircraft.flightController?.send(controlData, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to send virtual sticks command: \(error.localizedDescription)")
                self.stopVerticalTakeoff()
                return
            }
            log.verbose("Virtual sticks command sent successfully")
            return
        })
    }
    
    /// Enable virtual stick mode parameters for the flight controller
    private func enableAircraftVirtualSticksMode(completion: @escaping () -> Void) {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        if aircraft.flightController?.isVirtualStickAdvancedModeEnabled == true {
            log.error("Virtual sticks are already enabled")
            self.disableAircraftVirtualSticksMode()
            return
        }
        
        aircraft.flightController?.setVirtualStickModeEnabled(true, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to enable virtual sticks: \(error.localizedDescription)")
                return
            }
            log.info("Virtual sticks enabled")
            aircraft.flightController?.rollPitchCoordinateSystem = DJIVirtualStickFlightCoordinateSystem.body
            aircraft.flightController?.verticalControlMode = DJIVirtualStickVerticalControlMode.position
            aircraft.flightController?.rollPitchControlMode = DJIVirtualStickRollPitchControlMode.angle
            aircraft.flightController?.isVirtualStickAdvancedModeEnabled = true
            completion()
        })
    }
    
    /// Sends the virtual stick command to stop vertical takeoff
    func stopVerticalTakeoff() {
        self.verticalTakeoffJob?.invalidate() // Stop the job if scheduled
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        if  aircraft.flightController?.isVirtualStickAdvancedModeEnabled == false {
            log.error("Cannot stop vertical takeoff while virtual sticks are disabled")
            return
        }
        
        // Set all control values to 0 to stop movement
        let pitch: Float = 0.0
        let roll: Float = 0.0
        let yaw: Float = 0.0
        let throttle: Float = 0.0
        let controlData = DJIVirtualStickFlightControlData(pitch: pitch, roll: roll, yaw: yaw, verticalThrottle: throttle)
        
        aircraft.flightController?.send(controlData, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to send stop virtual sticks command: \(error.localizedDescription)")
            } else {
                log.info("Vertical takeoff is stopped")
            }
            // Force disable virtual sticks
            self.disableAircraftVirtualSticksMode()
        })
    }
    
    // Disable virtual stick mode for the flight controller
    private func disableAircraftVirtualSticksMode(retry: Int = 5, delay: Double = 1) {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        if aircraft.flightController?.isVirtualStickAdvancedModeEnabled == false {
            log.error("Virtual sticks are already disabled")
            return
        }
        aircraft.flightController?.setVirtualStickModeEnabled(false, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to disable virtual sticks: \(error.localizedDescription)")
                // Very important to disable virtual sticks, otherwise you lose control of your drone
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard retry > 0 else {
                        log.error("Failed to disable virtual sticks mode after multiple attempts")
                        return
                    }
                    self.disableAircraftVirtualSticksMode(retry: retry - 1)
                }
                return
            }
            log.info("Virtual sticks disabled")
            aircraft.flightController?.isVirtualStickAdvancedModeEnabled = false
        })
    }
    
    // MARK: - DJIFlightControllerDelegate
    // All methods below called through the delegate
    
    /// didUpdate delegate method for DJIFlightControllerDelegate, updates altitude and distance
    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        altitude = state.altitude
        guard let aircraftLocation = state.aircraftLocation, let homelocation = state.homeLocation else {
            // Cannot fetch location coordinates until the drone is flying
            log.verbose("Unable to fetch aircraft/homelocation coordinates")
            return
        }
        // Compute distance
        distance = CLLocation(latitude: aircraftLocation.coordinate.latitude, longitude: aircraftLocation.coordinate.longitude)
            .distance(from: CLLocation(latitude: homelocation.coordinate.latitude, longitude: homelocation.coordinate.longitude))
    }
    
    // MARK: - DJIBatteryDelegate
    // All methods below called through the delegate
    
    /// didUpdate delegate method for DJIBatteryDelegate, updates battery percentage
    func battery(_ battery: DJIBattery, didUpdate state: DJIBatteryState) {
        batteryPercentage = Int(state.chargeRemainingInPercent)
    }
    
    /// Sends virtual stick commands based on joystick inputs
    func sendVirtualStickCommands(throttle: Float, yaw: Float, pitch: Float, roll: Float) {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found")
            return
        }
        
        // Enable virtual sticks if not already enabled
        if aircraft.flightController?.isVirtualStickAdvancedModeEnabled == false {
            self.enableVirtualSticksForJoystick()
            return
        }
        
        // Create control data with joystick inputs
        let controlData = DJIVirtualStickFlightControlData(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            verticalThrottle: throttle
        )
        
        // Send the control command
        aircraft.flightController?.send(controlData, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to send virtual sticks command: \(error.localizedDescription)")
                return
            }
            log.verbose("Joystick virtual sticks command sent")
        })
    }
    
    /// Enables virtual sticks mode specifically for joystick control
    private func enableVirtualSticksForJoystick() {
        guard let aircraft = DJISDKManager.product() as? DJIAircraft else {
            log.error("Aircraft is not found for joystick control")
            return
        }
        
        aircraft.flightController?.setVirtualStickModeEnabled(true, withCompletion: { (error) in
            if let error = error {
                log.error("Failed to enable virtual sticks for joystick: \(error.localizedDescription)")
                return
            }
            
            log.info("Virtual sticks enabled for joystick")
            aircraft.flightController?.rollPitchCoordinateSystem = .body
            aircraft.flightController?.rollPitchControlMode = .velocity
            aircraft.flightController?.verticalControlMode = .velocity
            aircraft.flightController?.yawControlMode = .angularVelocity
            aircraft.flightController?.isVirtualStickAdvancedModeEnabled = true
        })
    }
    
}
