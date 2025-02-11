require 'rails/generators/named_base'
require 'rails/generators/resource_helpers'

module Rails
  module Generators
    class SuperglueGenerator < NamedBase # :nodoc:
      include Rails::Generators::ResourceHelpers

      source_root File.expand_path('../templates', __FILE__)

      argument :attributes, type: :array, default: [], banner: 'field:type field:type'

      def create_root_folder
        path = File.join('app/views', controller_file_path)
        empty_directory path unless File.directory?(path)
      end

      def copy_view_files
        %w(index show new edit).each do |view|
          @action_name = view
          filename = filename_with_extensions(view)
          template filename, File.join('app/views', controller_file_path, filename)
        end
        template '_form.json.props', File.join('app/views', controller_file_path, '_form.json.props')

        %w(index show new edit).each do |view|
          @action_name = view
          filename = filename_with_js_extensions(view)
          template 'web/' + filename, File.join('app/views', controller_file_path, filename)
        end

        %w(index show new edit).each do |view|
          @action_name = view
          filename = filename_with_html_extensions(view)
          template 'web/' + filename, File.join('app/views', controller_file_path, filename)
        end

        %w(index show new edit).each do |view|
          append_mapping(view)
        end
      end


      protected
        def append_mapping(action)
          app_js = 'app/javascript/packs/application.js'

          component_name = [plural_table_name, action].map(&:camelcase).join

          inject_into_file app_js, after: "from '@thoughtbot/superglue'" do
            "\nimport #{component_name} from 'views/#{controller_file_path}/#{action}'"
          end

          inject_into_file app_js, after: 'identifierToComponentMapping = {' do
            "\n      '#{[controller_file_path, action].join('/')}': #{component_name},"
          end
        end

        def action_name
          @action_name
        end

        def attributes_names
          [:id] + super
        end

        def filename_with_extensions(name)
          [name, :json, :props] * '.'
        end

        def filename_with_js_extensions(name)
          [name, :js] * '.'
        end

        def filename_with_html_extensions(name)
          [name, :html, :erb] * '.'
        end

        def attributes_list_with_timestamps
          attributes_list(attributes_names + %w(created_at updated_at))
        end

        def attributes_list(attributes = attributes_names)
          if self.attributes.any? {|attr| attr.name == 'password' && attr.type == :digest}
            attributes = attributes.reject {|name| %w(password password_confirmation).include? name}
          end

          attributes
        end
    end
  end
end
