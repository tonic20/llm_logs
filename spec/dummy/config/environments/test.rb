require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false
  config.cache_classes = true
  config.active_support.deprecation = :stderr
  config.active_support.disallowed_deprecation = :raise
end
