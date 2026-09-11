#!/usr/bin/env ruby
# Requires the existing xcodeproj gem and Muses installed on the specified simulator.
require 'xcodeproj'
require 'tmpdir'

simulator = ARGV.fetch(0) { abort 'Usage: ruby checks/run-tabbar-ui-checks.rb SIMULATOR_UDID' }
Dir.mktmpdir('muses-tabbar-ui-') do |directory|
  project = Xcodeproj::Project.new(File.join(directory, 'TabBarChecks.xcodeproj'))
  target = project.new_target(:ui_test_bundle, 'TabBarChecks', :ios, '17.0')
  source = project.main_group.new_file(File.expand_path('TabBarUITests.swift', __dir__))
  target.source_build_phase.add_file_reference(source)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.ordoeden.muses.tabbarchecks',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'SWIFT_VERSION' => '6.0',
      'TARGETED_DEVICE_FAMILY' => '1',
      'CODE_SIGNING_ALLOWED' => 'NO'
    })
  end
  project.save
  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.add_test_target(target)
  scheme.save_as(project.path, 'TabBarChecks')
  success = system('xcodebuild', '-project', project.path.to_s, '-scheme', 'TabBarChecks',
                  '-destination', "platform=iOS Simulator,id=#{simulator}",
                  '-derivedDataPath', '/tmp/muses-tabbar-ui-derived',
                  '-parallel-testing-enabled', 'NO', 'CODE_SIGNING_ALLOWED=NO', 'test')
  abort 'Tabbar UI checks failed' unless success
end
