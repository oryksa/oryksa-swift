Pod::Spec.new do |s|
  s.name             = 'Oryksa'
  s.version          = '1.1.1'
  s.summary          = 'Official iOS SDK for ORYKSA AI Employees: in-app AI chat and API v1 client.'
  s.description      = 'A ready SwiftUI and UIKit chat with the look of the ORYKSA website chat (name and photo of the AI from the ORYKSA account), and a client for the ORYKSA API v1 that uses short-lived session tokens.'
  s.homepage         = 'https://developer.oryksa.com/en/sdks'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ORYKSA AI Employees' => 'info@oryksa.com' }
  s.source           = { :git => 'https://github.com/oryksa/oryksa-swift.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version    = '5.7'
  s.source_files     = 'Sources/Oryksa/**/*.swift'
end
