#
# Be sure to run `pod lib lint HandlerIAP.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'HandlerIAP'
  s.version          = '0.3.6'
  s.summary          = 'In App Purchase Handler for iOS app'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
  HandlerIAP helps developers to easily handle in app purchases...
                       DESC

  s.homepage         = 'https://github.com/Viyatek/iap'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Viyatek' => 'viyateknoloji@gmail.com' }
  s.source           = { :git => 'https://github.com/Viyatek/iap.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.0'
  #s.source_files = 'HandlerIAP/Classes/***/**/*'
  s.source_files = 'HandlerIAP/Classes/**/*'
  #s.source_files = 'HandlerIAP/Classes/Internal/**/*'
  #s.subspec 'Internal' do |ss|
  #  ss.source_files = 'HandlerIAP/Classes/Internal/**/*'
  #end
  s.dependency 'SwiftyJSON'
  s.dependency 'SVProgressHUD'
  s.dependency 'Adjust'

  
  s.static_framework = true
  # s.resource_bundles = {
  #   'HandlerIAP' => ['HandlerIAP/Assets/*.png']
  # }
end

