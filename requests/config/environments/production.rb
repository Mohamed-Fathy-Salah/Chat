require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = true
  config.log_level = :info
  config.log_tags = [ :request_id ]
  config.action_controller.perform_caching = true
  
  config.cache_store = :redis_cache_store, { 
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1")
  }

  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end
