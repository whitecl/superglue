babel_config = Rails.root.join("babel.config.js")

def add_member_methods
  inject_into_file "app/models/application_record.rb", after: "class ApplicationRecord < ActiveRecord::Base\n" do
    <<-RUBY
  def self.member_at(index)
    offset(index).limit(1).first
  end

  def self.member_by(attr, value)
    find_by(Hash[attr, value])
  end
    RUBY
  end
end

# say "Copying module-resolver preset to your babel.config.js"
# resolver_snippet = <<~JAVASCRIPT
#   [
#     require('babel-plugin-module-resolver').default, {
#       "root": ["./app"],
#       "alias": {
#         "views": "./app/views",
#         "components": "./app/components",
#         "javascript": "./app/javascript"
#       }
#     }
#   ],
# JAVASCRIPT
# insert_into_file "babel.config.js", resolver_snippet, after: /plugins: \[\n/

## presumption: the user is using the jsbundling-rails + webpack default application bundle of app/javascript/
WEBPACK_ROOT = "#{__dir__}/app/javascript"

say "Copying application.js file to #{WEBPACK_ROOT}"
copy_file "#{__dir__}/templates/web/application.js", "#{WEBPACK_ROOT}/application.js"

say "Copying reducer.js file to #{WEBPACK_ROOT}"
copy_file "#{__dir__}/templates/web/reducer.js", "#{WEBPACK_ROOT}/reducer.js"

say "Copying action_creators.js file to #{WEBPACK_ROOT}"
copy_file "#{__dir__}/templates/web/action_creators.js", "#{WEBPACK_ROOT}/action_creators.js"

say "Copying actions.js file to #{WEBPACK_ROOT}"
copy_file "#{__dir__}/templates/web/actions.js", "#{WEBPACK_ROOT}/actions.js"

say "Copying application_visit.js file to #{WEBPACK_ROOT}"
copy_file "#{__dir__}/templates/web/application_visit.js", "#{WEBPACK_ROOT}/application_visit.js"

say "Copying Superglue initializer"
copy_file "#{__dir__}/templates/web/initializer.rb", "config/initializers/superglue.rb"

say "Copying application.json.props"
copy_file "#{__dir__}/templates/web/application.json.props", "app/views/layouts/application.json.props"

say "Adding required member methods to ApplicationRecord"
add_member_methods

say "Installing React, Redux, and Superglue"
run "yarn add babel-plugin-module-resolver history html-react-parser react-redux redux-thunk redux redux-persist reduce-reducers immer @thoughtbot/superglue --save"

# TODO
# For newer webpacker
# insert_into_file __dir__, "'app/views', 'app/components'", after: /additional_paths: \[/
# For older webpacker
# insert_into_file __dir__, "'app/views', 'app/components'", after: /resolved_paths: \[/

say "superglue.js installed for jsbundling + webpack 🎉", :green
