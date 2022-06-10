namespace :superglue do
  desc "Verifies if any version of Yarn is installed"
  task :verify_yarn do
    begin
      yarn_version = `yarn --version`
      raise Errno::ENOENT if yarn_version.blank?
    rescue Errno::ENOENT
      $stderr.puts "Yarn not installed. Please download and install Yarn from https://yarnpkg.com/lang/en/docs/install/"
      $stderr.puts "Exiting!" && exit!
    end
  end

  desc "Verifies if any version of react is in package.json"
  task :verify_react do
    package_json = JSON.parse(File.read(Rails.root.join("package.json")))

    if package_json['dependencies']['react'].nil?
      $stderr.puts "React not installed. Did you install React? https://github.com/rails/webpacker#react"
      $stderr.puts "Exiting!" && exit!
    end
  end

  namespace :install do
    desc "Install everything needed for superglue web"
    task 'webpacker' => ["superglue:verify_react"] do
      template = File.expand_path("../install/web.rb", __dir__)
      exec "#{RbConfig.ruby} ./bin/rails app:template LOCATION=#{template}"
    end

    task 'jsbundling_webpack' => ["superglue:verify_react"] do
      template = File.expand_path("../install/jsbundling_webpack.rb", __dir__)
      exec "#{RbConfig.ruby} ./bin/rails app:template LOCATION=#{template}"
    end
  end
end

