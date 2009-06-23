# Include hook code here
require 'rsocial'
ActionController::Base.send(:include, RSocial)
ApplicationHelper.send(:include, RSocial)
yamlFile = YAML.load_file("#{RAILS_ROOT}/config/social.yml")
RSocial::SNCONFIG =  yamlFile[RAILS_ENV]