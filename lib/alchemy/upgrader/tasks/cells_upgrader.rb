require 'alchemy/upgrader'
require 'rails/generators'

module Alchemy::Upgrader::Tasks
  class CellsUpgrader < Thor
    include Thor::Actions

    no_tasks do
      def convert_cells
        if File.exist?(page_layouts_config_file)
          backup_config
          convert_page_layouts_config
        else
          puts "\nNo page layouts config found. Skipping."
        end
        if File.exist?(cells_config_file)
          convert_cell_config
          delete_cells_config
        else
          puts "\nNo cells config found. Skipping."
        end
        update_cell_views
        update_render_cell_calls
        move_cell_views
        generate_editor_partials
        puts 'Done ✔'
      end
    end

    private

    def backup_config
      print "-- Copy existing config file to `config/alchemy/page_layouts.yml.old` ... "

      FileUtils.copy Rails.root.join('config', 'alchemy', 'page_layouts.yml'),
                     Rails.root.join('config', 'alchemy', 'page_layouts.yml.old')

      puts "done ✔\n"
    end

    def write_config(config)
      print '-- Writing new `config/alchemy/page_layouts.yml` ... '

      File.open(Rails.root.join('config', 'alchemy', 'page_layouts.yml'), "w") do |f|
        f.write config.to_yaml.sub("---\n", "").gsub("\n-", "\n\n-")
      end

      puts "done ✔\n"
    end

    def convert_page_layouts_config
      print '-- Moving `cells` from page layouts definition into autogenerated `elements` ... '
      page_layouts = YAML.load_file(page_layouts_config_file)
      page_layouts.select { |p| p['cells'].present? }.map do |page_layout|
        elements = page_layout['elements'] || []
        autogenerate_elements = page_layout['autogenerate'] || []
        cell_elements = page_layout.delete('cells')
        page_layout['elements'] = (elements + cell_elements).uniq
        page_layout['autogenerate'] = (autogenerate_elements + cell_elements).uniq
      end
      puts "done ✔\n"
      write_config(page_layouts)
    end

    def page_layouts_config_file
      Rails.root.join('config', 'alchemy', 'page_layouts.yml')
    end

    def cells_config_file
      Rails.root.join('config', 'alchemy', 'cells.yml')
    end

    def convert_cell_config
      puts '-- Converting cells into unique fixed nestable elements.'
      fixed_element_name_finder = FixedElementNameFinder.new

      YAML.load_file(cells_config_file).each do |cell|
        append_to_file Rails.root.join('config', 'alchemy', 'elements.yml') do
          <<-CELL.strip_heredoc

            - name: #{fixed_element_name_finder.call(cell['name'])}
              fixed: true
              unique: true
              nestable_elements: [#{cell['elements'].join(', ')}]
          CELL
        end
      end
    end

    def delete_cells_config
      puts '-- Deleting cells config file.'
      FileUtils.rm(cells_config_file)
    end

    def move_cell_views
      if Dir.exist? cells_view_folder
        puts "-- Move cell views into elements view folder"
        Dir.glob("#{cells_view_folder}/*").each do |view|
          filename = File.basename(view).gsub(/(_\w+)\.(\w*\.)?(erb|haml|slim)/, '\1_view.\2\3')
          FileUtils.mv(view, "#{elements_view_folder}/#{filename}")
          puts "   Moved #{File.basename(view)} into `app/views/alchemy/elements/` folder"
        end
        FileUtils.rm_rf(cells_view_folder)
      else
        puts "No cell views found. Skip"
      end
    end

    def generate_editor_partials
      puts "-- Generate editor partials"
      Rails::Generators.invoke('alchemy:elements', ['--skip'])
    end

    def update_cell_views
      if Dir.exist? cells_view_folder
        puts "-- Update cell views"
        Dir.glob("#{cells_view_folder}/*").each do |view|
          gsub_file(view, /elements\.published/, 'elements')
          gsub_file(view, /cell\.elements(.+)/, 'element.nested_elements\1')
          gsub_file(view, /render_elements[\(\s]?:?from_cell:?\s?(=>)?\s?cell\)?/, 'render element.nested_elements')
          gsub_file(view, /cell/, 'element')
        end
      else
        puts "No cell views found. Skip"
      end
    end

    def update_render_cell_calls
      puts "-- Update render_cell calls"
      Dir.glob("#{alchemy_views_folder}/**/*").each do |view|
        next if File.directory?(view)
        # <%= render_cell 'test' %>
        # <%= render_cell('test') %>
        # <%= render_cell("test", options: true) %>
        content = File.binread(view)
        content.gsub!(/render_cell([\s(]+)(['":])(\w+)([^\w])(.*?)/) do
          element_name = CellNameMigrator.call($3)
          "render_elements#{$1}only: #{$2}#{element_name}#{$4}, fixed: true#{$5}"
        end
        
        # <%= render_elements from_cell: 'page_intro' %>
        # <%= render_elements testing: 'blubb',     from_cell: :page_intro %>
        # <%= render_elements from_cell: "page_intro", testing: 'blubb' %>
        # <%= render_elements(from_cell: "page_intro", testing: 'blubb') %>
        # <%= render_elements(testing: 'blubb', from_cell: "page_intro") %>
        content.gsub!(/render_elements(.*?)from_cell[:\s=>]+([:'"])(\w+)(['"]?)(.*)/) do
          element_name = CellNameMigrator.call($3)
          "render_elements#{$1}only: #{$2}#{element_name}#{$4}, fixed: true#{$5}"
        end
        File.open(view, "wb") { |file| file.write(content) }
      end
    end

    def elements_view_folder
      Rails.root.join('app', 'views', 'alchemy', 'elements')
    end

    def cells_view_folder
      Rails.root.join('app', 'views', 'alchemy', 'cells')
    end

    def alchemy_views_folder
      Rails.root.join('app', 'views', 'alchemy')
    end
  end
end
