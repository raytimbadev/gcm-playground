// Copyright Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit

class ViewController: UIViewController {

  @IBOutlet weak var registrationStatus: UITextView!
  @IBOutlet weak var registrationToken: UITextView!

  @IBOutlet weak var senderIdField: UITextField!
  @IBOutlet weak var appServerHostField: UITextField!
  @IBOutlet weak var stringIdentifierField: UITextField!

  @IBOutlet weak var registerButton: UIButton!
  @IBOutlet weak var unregisterButton: UIButton!

  var apnsToken: NSData!
  var token: String = ""
  var appDelegate: AppDelegate!

  var gcmSenderID: String?
  var appServerHost: String?
  var stringIdentifier: String?

  var registrationOptions = [String: AnyObject]()

  override func viewDidLoad() {
    super.viewDidLoad()

    senderIdField.keyboardType = UIKeyboardType.NumberPad
    registrationToken.textContainer.lineBreakMode = NSLineBreakMode.ByClipping
    unregisterButton.enabled = false

    appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate

    // iOS registered the device and sent a token
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "saveApnsToken:",
      name: appDelegate.apnsRegisteredKey, object: nil)
    // Got a new GCM reg token
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "updateRegistrationStatus:",
      name: appDelegate.registrationKey, object: nil)
    // GCM Token needs to be refreshed
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "onTokenRefresh:",
      name: appDelegate.tokenRefreshKey, object: nil)
    // New message received
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "showReceivedMessage:",
      name: appDelegate.messageKey, object: nil)

    // TODO(karangoel): Remove this, only for development
    senderIdField.text = "1015367374593"
    appServerHostField.text = "751cebd0.ngrok.io"
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }

  // Click handler for register button
  @IBAction func registerClient(sender: UIButton) {
    // Get the fields values
    gcmSenderID = senderIdField.text
    appServerHost = appServerHostField.text
    stringIdentifier = stringIdentifierField.text

    // Validate field values
    if (gcmSenderID == "" || appServerHost == "") {
      showAlert("Invalid input", message: "Sender ID and host cannot be empty.")
      return
    }

    // Register with GCM and get token
    var instanceIDConfig = GGLInstanceIDConfig.defaultConfig()
    instanceIDConfig.delegate = appDelegate
    GGLInstanceID.sharedInstance().startWithConfig(instanceIDConfig)
    registrationOptions = [kGGLInstanceIDRegisterAPNSOption:apnsToken,
      kGGLInstanceIDAPNSServerTypeSandboxOption:true]
    GGLInstanceID.sharedInstance().tokenWithAuthorizedEntity(gcmSenderID,
      scope: kGGLInstanceIDScopeGCM, options: registrationOptions, handler: registrationHandler)
  }

  // Click handler for unregister button
  @IBAction func unregisterFromAppServer(sender: UIButton) {
    // TODO(karangoel): This will actually be sent over GCM instead of HTTP
    let url = NSURL(string: "http://" + appServerHostField.text + "/clients/" + token)
    var request = NSMutableURLRequest(URL: url!)
    var session = NSURLSession.sharedSession()
    request.HTTPMethod = "DELETE"

    var err: NSError?
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    var task = session.dataTaskWithRequest(request, completionHandler: {data, response, error -> Void in
      println("Response: \(response)")
      var httpResponse = response as! NSHTTPURLResponse
      if httpResponse.statusCode != 204 {
        // Move to the UI thread
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
          self.updateUI("Unregistration with app server FAILED", registered: true)
        })
      } else {
        // Move to the UI thread
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
          self.token = ""
          self.updateUI("Unregistration COMPLETE!", registered: false)
        })
      }
    })

    task.resume()
  }

  // Got a new GCM registration token
  func updateRegistrationStatus(notification: NSNotification) {
    if let info = notification.userInfo as? Dictionary<String,String> {
      if let error = info["error"] {
        registrationError(error)
      } else if let regToken = info["registrationToken"] {
        updateUI("Registration SUCCEEDED", registered: true)
      }
    } else {
      println("Software failure.")
    }
  }

  // Show the passed error message on the UI
  func registrationError(error: String) {
    updateUI("Registration FAILED", registered: false)
    showAlert("Error registering with GCM", message: error)
  }

  // Save the iOS APNS token
  func saveApnsToken(notification: NSNotification) {
    if let info = notification.userInfo as? Dictionary<String,NSData> {
      if let deviceToken = info["deviceToken"] {
        apnsToken = deviceToken
      } else {
        println("Could not decode the NSNotification that contains APNS token.")
      }
    } else {
      println("Could not decode the NSNotification userInfo that contains APNS token.")
    }
  }

  // GCM token should be refreshed
  func onTokenRefresh() {
    // A rotation of the registration tokens is happening, so the app needs to request a new token.
    println("The GCM registration token needs to be changed.")
    GGLInstanceID.sharedInstance().tokenWithAuthorizedEntity(gcmSenderID,
      scope: kGGLInstanceIDScopeGCM, options: registrationOptions, handler: registrationHandler)
  }

  // Callback for GCM registration
  func registrationHandler(registrationToken: String!, error: NSError!) {
    if (registrationToken != nil) {
      token = registrationToken
      println("Registration Token: \(registrationToken)")
      registerWithAppServer()
    } else {
      println("Registration to GCM failed with error: \(error.localizedDescription)")
      registrationError(error.localizedDescription)
    }
  }

  // TODO(karangoel): Test this. Show notification content in the UI.
  func showReceivedMessage(notification: NSNotification) {
    if let info = notification.userInfo as? Dictionary<String,AnyObject> {
      if let aps = info["aps"] as? Dictionary<String, String> {
        showAlert("Message received", message: aps["alert"]!)
      }
    } else {
      println("Software failure. Guru meditation.")
    }
  }

  // Call the app server and register the current reg token
  func registerWithAppServer() {
    // TODO(karangoel): This will move to GCM instead of HTTP
    let url = NSURL(string: "http://" + appServerHostField.text + "/clients")
    var request = NSMutableURLRequest(URL: url!)
    var session = NSURLSession.sharedSession()
    request.HTTPMethod = "POST"

    var params = ["registration_token": token, "string_identifier": stringIdentifierField.text] as Dictionary<String, String>

    var err: NSError?
    request.HTTPBody = NSJSONSerialization.dataWithJSONObject(params, options: nil, error: &err)
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("application/json", forHTTPHeaderField: "Accept")

    var task = session.dataTaskWithRequest(request, completionHandler: {data, response, error -> Void in
      println("Response: \(response)")
      var httpResponse = response as! NSHTTPURLResponse
      if httpResponse.statusCode != 201 {
        // Move to the UI thread
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
          self.updateUI("Registration with app server FAILED", registered: false)
        })
      } else {
        // Move to the UI thread
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
          self.updateUI("Registration COMPLETE!", registered: true)
        })
      }
    })

    task.resume()
  }

  func updateUI(status: String, registered: Bool) {
    // Set status and token text
    registrationStatus.text = status
    registrationToken.text = token

    // Button enabling
    registerButton.enabled = !registered;
    unregisterButton.enabled = registered;
  }

  func showAlert(title:String, message:String) {
    let alert = UIAlertController(title: title,
      message: message, preferredStyle: .Alert)
    let dismissAction = UIAlertAction(title: "Dismiss", style: .Destructive, handler: nil)
    alert.addAction(dismissAction)
    self.presentViewController(alert, animated: true, completion: nil)
  }

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

}

