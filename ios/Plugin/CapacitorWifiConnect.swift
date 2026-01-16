import Foundation

import NetworkExtension
import SystemConfiguration.CaptiveNetwork
import CoreLocation

public typealias PluginResultData = [String: Any]

@objc public class CapacitorWifiConnect: NSObject, CLLocationManagerDelegate {
    
    static let sharedInstance = CapacitorWifiConnect()
    private var locationManager = CLLocationManager()
    private let operationQueue = OperationQueue()
    private let operationQueueForRequest = OperationQueue()
    private var status: CLAuthorizationStatus = CLAuthorizationStatus.notDetermined;
    private var resolve: ((PluginResultData) -> Void)?
    
    override init(){
        super.init()
        //Pause the operation queue because
        // we don't know if we have location permissions yet
        resolve = nil;
        operationQueue.isSuspended = true
        operationQueueForRequest.isSuspended = true
        locationManager.delegate = self
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        
        self.status = status;
        //If we're authorized to use location services, run all operations in the queue
        // otherwise if we were denied access, cancel the operations
        if(status == .authorizedAlways || status == .authorizedWhenInUse){
            self.operationQueue.isSuspended = false
            self.operationQueueForRequest.isSuspended = false
        }else if(status == .denied){
            self.operationQueue.cancelAllOperations()
            self.operationQueueForRequest.isSuspended = false
            if(self.resolve != nil) {
                self.resolve!(["value": -5]);
                self.resolve = nil;
            }
        }
    }
    
    func runLocationBlock(callback: @escaping () -> ()){
        
        // Get the current authorization status
        let authState = locationManager.authorizationStatus

        // If we have permissions, start executing the commands immediately
        // otherwise request permission
        if authState == .authorizedAlways || authState == .authorizedWhenInUse {
          self.operationQueue.isSuspended = false
        } else {
          // Request permission
          locationManager.requestWhenInUseAuthorization()
        }
        
        //Create a closure with the callback function so we can add it to the operationQueue
        let block = { callback() }
        
        //Add block to the queue to be executed asynchronously
        self.operationQueue.addOperation(block)
    }
    
    func runLocationBlockRequest(callback: @escaping () -> ()){
        
        //Get the current authorization status
        let authState = locationManager.authorizationStatus

        if authState == .authorizedAlways || authState == .authorizedWhenInUse {
          self.operationQueueForRequest.isSuspended = false
        } else {
          locationManager.requestWhenInUseAuthorization()
        }
        
        //Create a closure with the callback function so we can add it to the operationQueue
        let block = { callback() }
        
        //Add block to the queue to be executed asynchronously
        self.operationQueueForRequest.addOperation(block)
    }
    
    private func mapStatus(status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return "granted"
        case .denied:
            return "denied"
        case .notDetermined:
            return "prompt"
        default:
            return "prompt"
        }
    }
    
    @objc public func checkPermission(resolve: @escaping (PluginResultData) -> Void) -> Void {
        resolve(["value": mapStatus(status: status)])
    }
    
    @objc public func requestPermission(resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlockRequest {
            resolve(["value": self.mapStatus(status: self.status)])
        }
    }
    
    @objc public func disconnect(resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlock {
          self._getSSID { ssid in
            guard let ssid = ssid, !ssid.isEmpty else {
              resolve(["value": false])
              return
            }

            NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
            resolve(["value": true])
          }
        }
    }
    
    
    @objc public func getAppSSID(resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if (self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": "", "status": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlock {
            self._getSSID { ssid in
                resolve(["value": ssid ?? "", "status": 0])
            }
        }
    }
    
    @objc public func getDeviceSSID(resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": "", "status": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlock {
            NEHotspotNetwork.fetchCurrent(){ currentNetwork in
                if (currentNetwork == nil) {
                    return resolve(["value": "", "status": -3])
                }
                resolve(["value": currentNetwork?.ssid, "status": 0])
            }
            
        }
    }
    
    private func _getSSID(completion: @escaping (String?) -> Void) {
        NEHotspotNetwork.fetchCurrent { network in
            let ssid = network?.ssid
            completion((ssid?.isEmpty == false) ? ssid : nil)
        }
    }
    

    @objc public func connect(ssid: String, saveNetwork: Bool, resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlock {
            let hotspotConfig = NEHotspotConfiguration.init(ssid: ssid)
            // hotspotConfig.joinOnce = !saveNetwork;
            return self.execConnect(hotspotConfig: hotspotConfig, resolve: resolve);
        }
    }
    
    @objc public func prefixConnect(ssid: String, saveNetwork: Bool, resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": -5])
        }
        
        
        self.resolve = resolve;
        
        
        self.runLocationBlock {
            let hotspotConfig = NEHotspotConfiguration.init(ssidPrefix: ssid)
            // hotspotConfig.joinOnce = !saveNetwork;
            return self.execConnect(hotspotConfig: hotspotConfig, resolve: resolve);
        }
        
    }
    
    @objc public func secureConnect(ssid: String, password: String, saveNetwork: Bool, isWep: Bool, resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        self.resolve = resolve;
        
        runLocationBlock {
            if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
                return resolve(["value": -5])
            }
            
            let hotspotConfig = NEHotspotConfiguration.init(ssid: ssid, passphrase: password, isWEP: isWep)
            // hotspotConfig.joinOnce = !saveNetwork;
            return self.execConnect(hotspotConfig: hotspotConfig, resolve: resolve);
        }
    }
    
    @objc public func securePrefixConnect(ssid: String, password: String, saveNetwork: Bool, isWep: Bool, resolve: @escaping (PluginResultData) -> Void, reject: @escaping (_ message: String, _ code: String? , _ error: Error? , _ data: PluginResultData? ) -> Void) -> Void {
        
        if(self.status != .notDetermined && self.status != .authorizedAlways && self.status != .authorizedWhenInUse) {
            return resolve(["value": -5])
        }
        
        self.resolve = resolve;
        
        runLocationBlock {
            let hotspotConfig = NEHotspotConfiguration.init(ssidPrefix: ssid, passphrase: password, isWEP: isWep)
            // hotspotConfig.joinOnce = !saveNetwork;
            return self.execConnect(hotspotConfig: hotspotConfig, resolve: resolve);
        }
    }
    
    private func execConnect(hotspotConfig: NEHotspotConfiguration, resolve: @escaping (PluginResultData) -> Void) {
      NEHotspotConfigurationManager.shared.getConfiguredSSIDs { wifiList in
        wifiList.forEach {
          NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: $0)
        }

        NEHotspotConfigurationManager.shared.apply(hotspotConfig) { [weak self] error in
          if let error = error as NSError? {
            switch error.code {
            case NEHotspotConfigurationError.alreadyAssociated.rawValue:
              resolve(["value": 0]) // success
            case NEHotspotConfigurationError.userDenied.rawValue:
              resolve(["value": -1]) // user denied
            default:
              resolve(["value": -2]) // no connection
            }
            return
          }

          guard let self = self else {
            resolve(["value": -3])
            return
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self else {
              resolve(["value": -3])
              return
            }

            self._getSSID { currentSsid in
              if let currentSsid = currentSsid,
                 currentSsid.hasPrefix(hotspotConfig.ssid) {
                resolve(["value": 0])
              } else {
                resolve(["value": -2])
              }
            }
          }
      }
    }
  }
}
