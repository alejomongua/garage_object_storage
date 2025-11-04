# Garage configuration file (template)
# This template uses environment variable placeholders (e.g. ${RPC_SECRET}).
# Copy or render this to config/garage.toml and ensure the real file is gitignored.
# Generate secrets with:
#   openssl rand -hex 32      # rpc_secret (64 hex chars)
#   openssl rand -base64 32   # tokens (base64)

metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"

# Use LMDB for better performance in production, or sqlite for simplicity
db_engine = "lmdb"

# Replication factor must be 1 for single-node deployments
replication_factor = 1

# RPC settings
# Secrets may be provided via environment variables (e.g. in a .env file loaded by Docker Compose).
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "${RPC_SECRET}"

# S3 API configuration
[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

# S3 Web configuration
[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"
index = "index.html"

# K2V API configuration (optional key-value store)
[k2v_api]
api_bind_addr = "[::]:3904"

# Admin API configuration
[admin]
api_bind_addr = "[::]:3903"
admin_token = "${ADMIN_TOKEN}"
metrics_token = "${METRICS_TOKEN}"