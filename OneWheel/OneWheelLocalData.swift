//
//  OneWheelPrefs.swift
//  OneWheel
//
//  Created by David Brodsky on 3/10/18.
//  Copyright © 2018 David Brodsky. All rights reserved.
//

import Foundation

class OneWheelLocalData {
    
    private let keyOnboarded = "ow_onboarded"
    
    private let keyUuid = "ow_uuid"
    private let keyAudioAlerts = "ow_audio_alerts"
    
    // Surfaced in Settings.bundle
    private let keyAutoLights = "ow_auto_lights"
    private let keyFootAlerts = "ow_alerts_foot_sensor"
    private let keySpeedAlerts = "ow_alerts_speed"
    private let keyBatteryAlerts = "ow_alerts_battery"
    private let keyMileageAlerts = "ow_alerts_mileage"
    private let keyConnectionAlerts = "ow_alerts_connection"
    private let keyAlertsRequiresHeadphones = "ow_alerts_requires_headphones"
    private let keyAlertsDuckAudio = "ow_alerts_duck_audio"
    private let keyAlertsVolume = "ow_alerts_volume"
    private let keyGoofy = "ow_foot_sensor_goofy"
    private let keyMetric = "ow_metric"
    private let keyChartSpeed = "ow_chart_speed"
    private let keyChartBattPercentage = "ow_chart_battery_percentage"
    private let keyChartBattVoltage = "ow_chart_battery_voltage"
    
    private let data = UserDefaults.standard
    
    init() {
        data.register(defaults: [keyOnboarded : false])
        data.register(defaults: [keyAudioAlerts : true])
        data.register(defaults: [keyAutoLights : false])
        data.register(defaults: [keyFootAlerts : true])
        data.register(defaults: [keySpeedAlerts : true])
        data.register(defaults: [keyBatteryAlerts : true])
        data.register(defaults: [keyMileageAlerts : true])
        data.register(defaults: [keyConnectionAlerts : true])
        data.register(defaults: [keyAlertsRequiresHeadphones : true])
        data.register(defaults: [keyAlertsDuckAudio : false])
        data.register(defaults: [keyAlertsVolume : 1.0])
        data.register(defaults: [keyGoofy : false])
        data.register(defaults: [keyMetric : false])
        data.register(defaults: [keyChartSpeed : true])
        data.register(defaults: [keyChartBattPercentage : true])
        data.register(defaults: [keyChartBattVoltage : false])
    }
    
    func clearPrimaryDeviceUUID() {
        data.removeObject(forKey: keyUuid)
    }
    
    func setPrimaryDeviceUUID(_ uuid: UUID) {
        data.setValue(uuid.uuidString, forKeyPath: keyUuid)
    }
    
    func getPrimaryDeviceUUID() -> UUID? {
        if let stringUuid = data.string(forKey: keyUuid) {
            return UUID.init(uuidString: stringUuid)
        } else {
            return nil
        }
    }
    
    func setAudioAlertsEnabled(_ enabled: Bool) {
        data.setValue(enabled, forKeyPath: keyAudioAlerts)
    }
    
    func getAudioAlertsEnabled() -> Bool {
        return data.bool(forKey: keyAudioAlerts)
    }
    
    func getAutoLightsEnabled() -> Bool {
        return data.bool(forKey: keyAutoLights)
    }
    
    func getFootAlertsEnabled() -> Bool {
        return data.bool(forKey: keyFootAlerts)
    }
    
    func getSpeedAlertsEnabled() -> Bool {
        return data.bool(forKey: keySpeedAlerts)
    }
    
    func getBatteryAlertsEnabled() -> Bool {
        return data.bool(forKey: keyBatteryAlerts)
    }
    
    func getMileageAlertsEnabled() -> Bool {
        return data.bool(forKey: keyMileageAlerts)
    }
    
    func getConnectionAlertsEnabled() -> Bool {
        return data.bool(forKey: keyConnectionAlerts)
    }
    
    func getAlertsDuckAudio() -> Bool {
        return data.bool(forKey: keyAlertsDuckAudio)
    }
    
    func getAlertsRequireHeadphones() -> Bool {
        return data.bool(forKey: keyAlertsRequiresHeadphones)
    }
    
    func getAlertsVolume() -> Float {
        return data.float(forKey: keyAlertsVolume)
    }
    
    func setOnboarded(_ onboarded: Bool) {
        data.setValue(onboarded, forKeyPath: keyOnboarded)
    }
    
    func getOnboarded() -> Bool {
        return data.bool(forKey: keyOnboarded)
    }
    
    func getIsGoofy() -> Bool {
        return data.bool(forKey: keyGoofy)
    }
    
    func getIsMetric() -> Bool {
        return data.bool(forKey: keyMetric)
    }
    
    func getShowChartSpeed() -> Bool {
        return data.bool(forKey: keyChartSpeed)
    }
    
    func getShowChartBatteryPercentage() -> Bool {
        return data.bool(forKey: keyChartBattPercentage)
    }
    
    func getShowChartBatteryVoltage() -> Bool {
        return data.bool(forKey: keyChartBattVoltage)
    }
}
