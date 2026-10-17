import Config

# No port here: Francis binds to the PORT environment variable, which the
# Dockerfile sets to 4000.
config :francis, dev: false
